"""Replay software-generated valid signatures through complete HawkVerify RTL.

Generate packets with check_pipeline_variants.py --export first. Mathematical
memory models preserve the two-clock BRAM latency; --real-ip uses Xilinx IP.
Extra assertions are added only to a simulation copy of HawkVerify.
"""
from pathlib import Path
import argparse
import importlib.util
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
BIN=Path('C:/Xilinx/Vivado/2022.1/bin')
IP=ROOT/'02_project/hawk_acc/hawk_acc.gen/sources_1/bd/hawk_acc/ip/hawk_acc_hawk_acc_0_0/src'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--real-ip',action='store_true')
    parser.add_argument('--n',type=int,choices=(256,512,1024))
    args=parser.parse_args()
    sizes=(args.n,) if args.n else (256,512,1024)
    work=ROOT/'06_test/.work'/('verify_real' if args.real_ip else 'verify_models')
    if args.n: work=work/str(args.n)
    work.mkdir(parents=True,exist_ok=True)
    decl=[];tests=[]
    for case,n in enumerate(sizes):
        packet=list(map(int,(ROOT/f'06_test/.work/verify_vectors/verify_{n}_0.txt').read_text().split()))
        pn,r1,r2=packet[:3];assert pn==n
        h=packet[3:3+n//32];pos=3+n//32
        q00,q01,w1,w0=[packet[pos+k*n:pos+(k+1)*n] for k in range(4)]
        for name,values in [('INPUT',h+q00+q01+w1)]:
            decl.append(f'constant C_{name}{case}:words(0 to {len(values)-1}):=('+','.join(f'x"{v%2**32:08X}"' for v in values)+');')
        decl.append(f'constant C_W0_{case}:integers(0 to {n-1}):=('+','.join(map(str,w0))+');')
        tests.append(f'''
        n<={n}; expected_r1<=std_logic_vector(to_unsigned({r1},32));
        expected_r2<=std_logic_vector(to_unsigned({r2},32));
        for i in 0 to {n-1} loop expected_w0(i)<=C_W0_{case}(i); end loop;
        wait until falling_edge(clk); load(C_INPUT{case}); finish('0');
        report "PASS valid signature n={n}: all w0 coefficients and r1=r2={r1}";
''')
    package='''library ieee;use ieee.std_logic_1164.all;
package audit_expected is
type integers is array(natural range <>) of integer;
signal expected_w0:integers(0 to 1023):=(others=>0);
signal expected_r1,expected_r2:std_logic_vector(31 downto 0);
end package;
'''
    (work/'expected.vhd').write_text(package)
    tb='''library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use work.audit_expected.all;
entity verify_integration_tb is end;
architecture tb of verify_integration_tb is
type words is array(natural range <>) of std_logic_vector(31 downto 0);
'''+ '\n'.join(decl)+'''
signal clk:std_logic:='0';signal rst,ack,valid,startout,error,input_ready:std_logic:='0';
signal din:std_logic_vector(31 downto 0):=(others=>'0');
signal n:integer range 256 to 1024:=256;
begin
clk<=not clk after 5 ns;
dut:entity work.hawk_verify generic map(32,10)
port map(num_samples=>n,clk=>clk,rst_n=>rst,data_in=>din,error_out=>error,
ack_in=>ack,input_ready=>input_ready,ready=>'1',valid=>valid,start_out=>startout);
process
procedure load(constant data:words) is begin
 for i in data'range loop
  while input_ready/='1' loop wait until falling_edge(clk); end loop;
  ack<='1';din<=data(i);wait until falling_edge(clk);
  if i mod 19=7 then ack<='0';wait until falling_edge(clk);end if;
 end loop;
 ack<='0';din<=(others=>'0');
end;
procedure finish(constant expected_error:std_logic) is
 variable finished:boolean:=false;
begin
 for cycle in 0 to 8000000 loop
  wait until rising_edge(clk);
  if valid='1' then
   assert error=expected_error report "Unexpected verification result" severity failure;
   finished:=true;exit;
  end if;
 end loop;
 assert finished report "Verification timeout" severity failure;
 wait until falling_edge(clk);
 while input_ready/='1' loop wait until falling_edge(clk);end loop;
end;
begin
wait until falling_edge(clk);wait until falling_edge(clk);rst<='1';
wait until falling_edge(clk);
'''+''.join(tests)+'''
report "PASS: software signatures through HawkVerify";
std.env.stop;wait;
end process;end;
'''
    (work/'tb.vhd').write_text(tb)
    def run(tool,*params):
        p=subprocess.run([str(BIN/(tool+'.bat')),*map(str,params)],cwd=work,capture_output=True,text=True)
        (work/(tool+'.log')).write_text(p.stdout+p.stderr)
        if p.returncode:raise RuntimeError(p.stdout+p.stderr)
        print(tool+': OK',flush=True)
    if args.real_ip:
        ips=('fifo_generator_0','blk_mem_gen_1','blk_mem_gen_2','blk_mem_gen_3','blk_mem_gen_4')
        sources=[]
        for ip in ips:
            source=IP/ip/'sim'/f'{ip}.v'
            dest=work/(ip+'.v');shutil.copyfile(source,dest);sources.append(dest)
            for mif in (IP/ip).rglob('*.mif'):shutil.copyfile(mif,work/mif.name)
        run('xvlog','--work','work',*sources)
    else:
        # Import definitions only; run_standalone's CLI uses sys.argv[1].
        old=sys.argv;sys.argv=[old[0]]
        spec=importlib.util.spec_from_file_location('memory_models',ROOT/'04_testbench/tb_rebuild_s0/run_standalone.py')
        model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model);sys.argv=old
        models=model.MODELS
        for component,filename,bits in [('blk_mem_gen_2','delta_rom.coe',64),('blk_mem_gen_3','gamma_p1_n1024.coe',32),('blk_mem_gen_4','gamma_p2_n1024.coe',32)]:
            coe=(ROOT/'05_software/rom'/filename).read_text().split('memory_initialization_vector=')[1]
            values=re.findall(r'[0-9a-fA-F]{'+str(bits//4)+r'}',coe);assert len(values)==1024
            models+=model.HEADER+f'''
entity {component} is port(clka,ena:in std_logic;addra:in std_logic_vector(9 downto 0);douta:out std_logic_vector({bits-1} downto 0));end;
architecture model of {component} is
type words is array(0 to 1023) of std_logic_vector({bits-1} downto 0);
constant rom:words:=('''+','.join(f'x"{x}"' for x in values)+f''');
signal q:std_logic_vector({bits-1} downto 0);
begin process(clka) begin if rising_edge(clka) then if ena='1' then
q<=rom(to_integer(unsigned(addra)));douta<=q;end if;end if;end process;end;
'''
        (work/'models.vhd').write_text(models)
        run('xvhdl','--2008',work/'models.vhd')
    rtl=[]
    for name in ('hawk_pkg','fft','ifft','signed_divider','rebuild_s0','mod_reducer','ntt','polyqnorm','sym_break_w1','hawk_verify'):
        src=(ROOT/'03_design'/f'{name}.vhd').read_text()
        if name=='hawk_verify':
            src=src.replace('architecture rtl of hawk_verify is','use work.audit_expected.all;\narchitecture rtl of hawk_verify is')
            src=src.replace('when POLYQNORM_DONE =>\n                        --', '''when POLYQNORM_DONE =>
                        assert r1=expected_r1 and r2=expected_r2 report "Norm residues differ from software" severity failure;
                        --''')
            marker='end architecture rtl;'
            assert marker in src
            src=src.replace(marker,'''audit_w0:process(clk)
variable index:natural:=0;
begin if rising_edge(clk) then
if core_rst_n='0' or start_rebuild='1' then index:=0;
elsif rebuild_out_valid='1' then
assert index<num_samples severity failure;
assert signed(rebuild_w0)=to_signed(expected_w0(index),32)
report "Rebuild w0 differs from software at "&integer'image(index) severity failure;
index:=index+1;
end if;end if;end process;
'''+marker)
        dest=work/f'{name}.vhd';dest.write_text(src);rtl.append(dest)
    run('xvhdl','--2008',work/'expected.vhd',*rtl,work/'tb.vhd')
    libraries=['-L','fifo_generator_v13_2_7','-L','blk_mem_gen_v8_4_5'] if args.real_ip else []
    run('xelab','--relax',*libraries,'work.verify_integration_tb','-s','verify_integration')
    (work/'run.tcl').write_text('run 200 ms\nquit\n')
    run('xsim','verify_integration','-tclbatch','run.tcl')
    log=(work/'xsim.log').read_text()
    assert 'PASS: software signatures through HawkVerify' in log and 'Failure:' not in log and 'Fatal:' not in log,log[-4000:]
    print('\n'.join(x for x in log.splitlines() if 'PASS' in x))


if __name__=='__main__':main()
