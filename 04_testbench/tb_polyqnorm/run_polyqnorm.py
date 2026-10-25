"""Validate Algorithm 19 using direct polynomial evaluation and Xilinx IP.

The project is only read. Files/logs are generated in a temporary directory.
"""
import argparse
from pathlib import Path
import random
import re
import sys
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
N = 512


def evaluate(a, root, p):
    value = 0
    for coefficient in reversed(a):
        value = (value*root+coefficient) % p
    return value


def reference(polys, p, g):
    # Sum over ALL odd roots in natural order. No RTL NTT, index reversal,
    # or Fermat exponentiation is reused. pow(...,-1,p) uses modular inverse.
    gamma = pow(g, (p-1)//(2*N), p)
    total = 0
    for i in range(N):
        root = pow(gamma, 2*i+1, p)
        inverse_root = pow(root, -1, p)
        q, b, x, y = [evaluate(a, root, p) for a in polys]
        qi, bi, xi, yi = [evaluate(a, inverse_root, p) for a in polys]
        if q == 0 or qi == 0:
            return 1, 0
        d, di = y*pow(q,-1,p) % p, yi*pow(qi,-1,p) % p
        e, ei = (x+d*b) % p, (xi+di*bi) % p
        total = (total + q*e*ei + d*yi) % p
    return 0, total


def make_vectors(path, p, g):
    def impulse(x, index=0):
        a=[0]*N; a[index]=x % p; return a
    rng=random.Random(20261011)
    q=impulse(2000); q[1]=3; q[-1]=p-3; q[7]=p-2; q[-7]=2
    dense=[q]+[[rng.randint(-50,50)%p for _ in range(N)] for _ in range(3)]
    gamma=pow(g,(p-1)//(2*N),p)
    # Zero at a noninitial spectral position (17 in the DUT ordering).
    rev=int(f'{17:09b}'[::-1],2)
    singular=impulse(-pow(gamma,2*rev+1,p)); singular[1]=1
    invalid=[impulse(1),[0]*N,[0]*N,[0]*N]; invalid[1][-1]=p
    recovery=[a.copy() for a in dense]; recovery[3]=[(-x)%p for x in recovery[3]]
    cases=[
        [impulse(1),[0]*N,[0]*N,[0]*N],
        [impulse(3),[0]*N,impulse(-1,511),[0]*N],
        [impulse(7),[0]*N,[0]*N,impulse(19,31)],
        dense,
        [impulse(11)]+[[rng.randrange(p) for _ in range(N)] for _ in range(3)],
        [singular,impulse(2),impulse(3),impulse(4)],
        invalid,
        recovery,
    ]
    with path.open('w') as file:
        for index,polys in enumerate(cases):
            err,value=(1,0) if index==6 else reference(polys,p,g)
            assert err == (index in (5,6))
            if index==1: assert value == N*3 % p
            if index==2: assert value == N*19*19*pow(7,-1,p) % p
            file.write(f'{err} {value}\n')
            for row in zip(*polys): file.write(' '.join(map(str,row))+'\n')
            print(f'{p}: case {index}, error={err}, result={value}',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,default=ROOT/'02_project/hawk_acc')
    parser.add_argument('--vivado-bin',type=Path,default=Path('C:/Xilinx/Vivado/2022.1/bin'))
    parser.add_argument('--models', action='store_true', help='Use behavioral RAM/ROM with 1024-word Gamma tables')
    parser.add_argument('--vectors-only',action='store_true')
    args=parser.parse_args()
    work=HERE if args.vectors_only else Path(tempfile.mkdtemp(prefix='hawk-polyqnorm-'))
    print(work,flush=True)
    for name,p,g in [('p1',2147473409,3),('p2',2147389441,11)]:
        make_vectors(work/f'polyqnorm_{name}.txt',p,g)
    if args.vectors_only: return
    def run(tool,*params):
        subprocess.run([str(args.vivado_bin/(tool+'.bat')),*map(str,params)],cwd=work,check=True)
    if args.models:
        sys.path.insert(0, str(HERE.parent/'tb_rebuild_s0'))
        from run_standalone import MODELS, HEADER
        models = MODELS
        for name, component in [('p1','blk_mem_gen_3'),('p2','blk_mem_gen_4')]:
            coe=(ROOT/f'05_software/rom/gamma_{name}_n1024.coe').read_text()
            words=re.findall(r'[0-9a-fA-F]{8}',coe.split('memory_initialization_vector=')[1])
            assert len(words)==1024
            models += HEADER + f"""
entity {component} is
port(clka,ena: in std_logic; addra: in std_logic_vector(9 downto 0);
douta: out std_logic_vector(31 downto 0)); end;
architecture model of {component} is
type rom_t is array(0 to 1023) of std_logic_vector(31 downto 0);
constant rom: rom_t := (""" + ','.join(f'x"{w}"' for w in words) + """);
signal q: std_logic_vector(31 downto 0);
begin
process(clka) begin
if rising_edge(clka) then
if ena='1' then q<=rom(to_integer(unsigned(addra))); douta<=q; end if;
end if;
end process; end;
"""
        (work/'models.vhd').write_text(models)
        run('xvhdl','--2008',work/'models.vhd')
    else:
        ip_root=args.project/(args.project.name+'.gen')/'sources_1/ip'
        if not (ip_root/'blk_mem_gen_1/sim/blk_mem_gen_1.v').is_file():
            ip_root = args.project/(args.project.name+'.gen')/'sources_1/bd/hawk_acc/ip/hawk_acc_hawk_acc_0_0/src'
        sources=[]
        for ip in ('blk_mem_gen_1','blk_mem_gen_3','blk_mem_gen_4'):
            sources.append(ip_root/ip/'sim'/f'{ip}.v')
            for mif in (ip_root/ip).rglob('*.mif'):
                shutil.copyfile(mif,work/mif.name)
        run('xvlog','--work','work',*sources)
    run('xvhdl','--2008',ROOT/'03_design/hawk_pkg.vhd',ROOT/'03_design/mod_reducer.vhd',ROOT/'03_design/ntt.vhd',ROOT/'03_design/polyqnorm.vhd',HERE/'polyqnorm_tb.vhd')
    run('xelab','--relax','-L','blk_mem_gen_v8_4_5','work.polyqnorm_tb','-s','polyqnorm_test')
    (work/'run.tcl').write_text('run 500 ms\nquit\n')
    run('xsim','polyqnorm_test','-tclbatch','run.tcl')
    log=(work/'xsim.log').read_text()
    if 'PolyQnorm: P1 y P2 superados' not in log or 'Failure:' in log or 'Fatal:' in log:
        raise RuntimeError(f'Validation failed: {work}')
    print('PASS: 16 cases, both primes; ' + ('behavioral memory models' if args.models else 'Xilinx memory IP'),flush=True)


if __name__=='__main__': main()
