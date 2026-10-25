"""Replay public keys and signatures from a UART log through PS and real-IP RTL.

The RAM write inputs omitted by ntt.vhd are tied low ONLY in a temporary
simulation copy when --tie-rom-write-inputs is supplied. Production is untouched.
"""
import argparse
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '06_test/.work/uart_replay'
IP = ROOT / '02_project/hawk_acc/hawk_acc.gen/sources_1/bd/hawk_acc/ip/hawk_acc_hawk_acc_0_0/src'
BIN = Path('C:/Xilinx/Vivado/2022.1/bin')


def run(command, directory, name):
    p = subprocess.run(list(map(str, command)), cwd=directory, capture_output=True, text=True)
    (directory / (name + '.log')).write_text(p.stdout + p.stderr)
    if p.returncode:
        raise RuntimeError(f'{name} failed: {directory / (name + ".log")}\n{p.stdout[-2500:]}{p.stderr[-1000:]}')
    print(f'{name}: OK', flush=True)
    return p.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--n', type=int, default=512, choices=(256, 512, 1024))
    parser.add_argument('--message', default='Hola HAWK')
    parser.add_argument('--tie-rom-write-inputs', action='store_true')
    parser.add_argument('--ps-only', action='store_true')
    args = parser.parse_args()
    work = WORK / str(args.n)
    work.mkdir(parents=True, exist_ok=True)
    text = args.log.read_text(encoding='utf-8-sig')
    section = next(s for s in re.split(r'(?==== HAWK-)', text) if s.startswith(f'=== HAWK-{args.n}:'))
    pub = bytes.fromhex(re.search(r'public_key = 0x([0-9A-Fa-f]+)', section)[1])
    sig = bytes.fromhex(re.search(r'signature = 0x([0-9A-Fa-f]+)', section)[1])
    headers = ROOT / '05_software/headers'
    for header in headers.glob('*.h'):
        shutil.copyfile(header, work / header.name)
    params = (headers / 'hawk_params.h').read_text()
    params = re.sub(r'^#define HAWK_512$', f'#define HAWK_{args.n}', params, flags=re.M)
    (work / 'hawk_params.h').write_text('#define HAWK_FIXED_PARAMS\n' + params)
    # Reuse the independent mathematical backend, but feed the user's bytes.
    source = (ROOT / '06_test/main_hawk_pipeline_test.c').read_text()
    source = source[:source.index('#ifndef HAWK_HELLOWORLD_TEST')]
    source = source.replace('int HawkFpgaVerify(', 'int ReferenceVerify(')
    source += '''
int HawkFpgaVerify(const uint32_t *h0,const int32_t *q00,const int32_t *q01,
                   const int32_t *w1,uint32_t *error) {
    FILE *f=fopen("packet.txt","w"); assert(f);
    for(size_t i=0;i<HAWK_N_WORDS32;i++) fprintf(f,"%u\\n",h0[i]);
    const int32_t *v[]={q00,q01,w1};
    for(unsigned k=0;k<3;k++) for(size_t i=0;i<HAWK_N;i++) fprintf(f,"%d\\n",v[k][i]);
    fclose(f);
    int r=ReferenceVerify(h0,q00,q01,w1,error);
    printf("reference transport=%d error=%u norm=%llu\\n",r,*error,(unsigned long long)verified_norm);
    return r;
}
int main(void) {
'''
    for name, data in [('pub', pub), ('sig', sig), ('message', args.message.encode())]:
        source += f'const uint8_t {name}[]={{' + ','.join(map(str, data)) + '};\n'
    source += 'int r=hawk_verify(sig,sizeof sig,pub,sizeof pub,message,sizeof message); printf("verify=%d\\n",r); return r>=0?0:1; }\n'
    (work / 'replay.c').write_text(source)
    names = ('keygen','basic','decode','encode','regenerate','fft_transform','ntt_transform','shake256','towersolver','hawk_sign','hawk_verify','sampler_sign')
    sources = [ROOT / '05_software/src' / (n + '.c') for n in names]
    sources += list((ROOT / '05_software/third_party/ntrugen').glob('*.c'))
    run(['C:/MINGW/bin/gcc.exe','-std=c99','-O2','-DNTRUGEN_AVX2=0', '-I'+str(work), '-I'+str(ROOT/'06_test/vitis_mock'), '-I'+str(ROOT/'05_software/third_party/ntrugen'), *sources,work/'replay.c','-lm','-o',work/'replay.exe'],work,'compile_ps')
    reference = run([work/'replay.exe'],work,'reference')
    print(reference, flush=True)
    if args.ps_only:
        return
    expected_error = int(re.search(r'error=(\d+)', reference)[1])
    packet = list(map(int,(work/'packet.txt').read_text().split()))
    n = args.n
    block = '    -- BEGIN GENERATED VECTORS\nconstant C_CASES:positive:=1;\n'
    block += f'type vector_t is array(0 to {n-1}) of integer;\ntype vectors_t is array(0 to 0) of vector_t;\n'
    hcount = n//32
    for k,key in enumerate(('Q00','Q01','W1')):
        values=packet[hcount+k*n:hcount+(k+1)*n]
        block += f'constant C_{key}:vectors_t := (0 => (' + ','.join(f'{i}=>{v}' for i,v in enumerate(values)) + '));\n'
    h = ''.join(f'{v:08X}' for v in reversed(packet[:hcount]))
    block += f'type hashes_t is array(0 to 0) of std_logic_vector({n-1} downto 0);\nconstant C_H0:hashes_t := (0=>x"{h}");\n'
    block += f'constant C_ERROR:std_logic_vector(0 to 0):="{expected_error}";\nfunction case_name(index:natural) return string is begin return "UART replay"; end;\n    -- END GENERATED VECTORS'
    tb=(ROOT/'04_testbench/tb_hawk_verify/hawk_verify_tb.vhd').read_text()
    tb=re.sub(r'    -- BEGIN GENERATED VECTORS.*?    -- END GENERATED VECTORS',lambda _:block,tb,flags=re.S)
    tb=tb.replace('0 to 15 loop',f'0 to {hcount-1} loop').replace('0 to 511 loop',f'0 to {n-1} loop')
    tb=tb.replace('clk         => clk,',f'num_samples => {n},\n            clk         => clk,')
    # Skip synthetic reset cases: replay only the supplied complete operation.
    tb=re.sub(r'        -- Aborta una carga parcial:.*?        -- Todos los casos siguientes', '        -- Todos los casos siguientes',tb,flags=re.S)
    tb=tb.replace('-- stop;','stop;')
    (work/'replay_tb.vhd').write_text(tb)
    ips=('fifo_generator_0','blk_mem_gen_1','blk_mem_gen_2','blk_mem_gen_3','blk_mem_gen_4')
    for ip in ips:
        for mif in (IP/ip).rglob('*.mif'):
            shutil.copyfile(mif,work/mif.name)
    run([BIN/'xvlog.bat','--work','work',*[IP/ip/'sim'/f'{ip}.v' for ip in ips]],work,'xvlog')
    rtl=[]
    for name in ('hawk_pkg','fft','ifft','signed_divider','rebuild_s0','mod_reducer','ntt','polyqnorm','sym_break_w1','hawk_verify'):
        src=(ROOT/'03_design'/f'{name}.vhd').read_text()
        if name=='ntt' and args.tie_rom_write_inputs:
            src=src.replace('component blk_mem_gen_4\n        port (','component blk_mem_gen_4\n        port (\n            wea : in std_logic_vector(0 downto 0);\n            dina : in std_logic_vector(31 downto 0);')
            src=src.replace('rom_gamma_inst : blk_mem_gen_4\n            port map (','rom_gamma_inst : blk_mem_gen_4\n            port map (\n                wea => "0", dina => (others => \'0\'),')
        dest=work/f'{name}.vhd'; dest.write_text(src); rtl.append(dest)
    run([BIN/'xvhdl.bat','--2008',*rtl,work/'replay_tb.vhd'],work,'xvhdl')
    run([BIN/'xelab.bat','--relax','-debug','typical','-L','fifo_generator_v13_2_7','-L','blk_mem_gen_v8_4_5','work.hawk_verify_tb','-s','replay'],work,'xelab')
    (work/'run.tcl').write_text('run 100 ms\nquit\n')
    run([BIN/'xsim.bat','replay','-tclbatch','run.tcl'],work,'xsim')
    log=(work/'xsim.log').read_text()
    assert 'PASS: HawkVerify' in log and 'Failure:' not in log and 'Fatal:' not in log, log[-4000:]
    print(f'PASS UART replay n={n}; logs: {work}',flush=True)


if __name__=='__main__':
    main()
