"""Check complete HawkSign stream transactions with the real signing BRAM.

Reference results use direct negacyclic convolution. These are arithmetic
and protocol vectors, not cryptographic signatures or a physical DMA test.
"""
from pathlib import Path
import random
import subprocess

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'06_test/.work/sign_integration'
BIN=Path('C:/Xilinx/Vivado/2022.1/bin')
IP=ROOT/'02_project/hawk_acc/hawk_acc.gen/sources_1/bd/hawk_acc/ip/hawk_acc_hawk_acc_0_0/src/blk_mem_gen_0/sim/blk_mem_gen_0.v'


def conv(a,b):
    n=len(a)
    return [sum(a[j]*b[(i-j)%n]*(1 if j<=i else -1) for j in range(n)) for i in range(n)]


def pack(a):
    return [sum((a[32*i+j]&1)<<j for j in range(32)) for i in range(len(a)//32)]


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    rng=random.Random(20261025)
    decl=[];tests=[]
    for case,n in enumerate((256,512,1024,256)):
        h0=[rng.randrange(2) for _ in range(n)]
        h1=[rng.randrange(2) for _ in range(n)]
        F=[rng.randrange(2) for _ in range(n)];G=[1]+[0]*(n-1)
        f=[2*rng.randint(-3,3) for _ in range(n)];f[0]+=1
        g=[2*rng.randint(-3,3) for _ in range(n)]
        t0=[(v+h0[i])&1 for i,v in enumerate(conv(h1,F))]
        t1=h1[:]
        x0=[2*rng.randint(-2,2)+t for t in t0]
        x1=[2*rng.randint(-2,2)+t for t in t1]
        w=[a-b for a,b in zip(conv(f,x1),conv(g,x0))]
        # Exercise both symmetry branches.
        sign=next(v for v in w if v)
        if (sign>0)!=(case%2==0):
            x0=[-v for v in x0];x1=[-v for v in x1];w=[-v for v in w]
        positive=next(v for v in w if v)>0
        diff=[h1[i]-(v if positive else -v) for i,v in enumerate(w)]
        assert all(v%2==0 for v in diff)
        s=[v//2 for v in diff]
        packet=pack(h0)+pack(h1)+pack(F)+pack(G)+f+g
        for name,values in [('INPUT',packet),('T',pack(t0)+pack(t1)),('X',x0+x1),('S',s)]:
            decl.append(f'constant C_{name}{case}:words(0 to {len(values)-1}):=('+','.join(f'x"{v%2**32:08X}"' for v in values)+');')
        tests.append(f'''
        n<={n}; wait until falling_edge(clk);
        send_packet(C_INPUT{case}); receive_packet(C_T{case},{n*n+10000});
        send_packet(C_X{case}); receive_packet(C_S{case},{n*(n+20)+10000});
        report "PASS HawkSign n={n} case={case} symmetry_positive={positive}";
''')
    tb='''library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;
entity sign_integration_tb is end;
architecture tb of sign_integration_tb is
type words is array(natural range <>) of std_logic_vector(31 downto 0);
'''+ '\n'.join(decl)+'''
signal clk:std_logic:='0';signal rst,ack,ready,valid,last,startout:std_logic:='0';
signal din,dout:std_logic_vector(31 downto 0):=(others=>'0');
signal n:integer range 256 to 1024:=256;
begin
clk<=not clk after 5 ns;
dut:entity work.hawk_sign generic map(32,10)
port map(n,clk,rst,din,dout,ack,ready,valid,last,startout);
process
procedure send_packet(constant data:words) is begin
 for i in data'range loop
  ack<='1';din<=data(i);wait until falling_edge(clk);
 end loop;
 ack<='0';din<=(others=>'0');
end;
procedure receive_packet(constant expected:words;constant timeout:positive) is
 variable count:natural:=0;
 variable stalled:boolean:=false;
 variable held:std_logic_vector(31 downto 0);
 variable held_last:std_logic;
begin
 ready<='0';
 for cycle in 0 to timeout loop
  wait until rising_edge(clk);
  if stalled then
   assert valid='1' and dout=held and last=held_last report "Unstable stream under backpressure" severity failure;
  end if;
  stalled:=valid='1' and ready='0';held:=dout;held_last:=last;
  if valid='1' and ready='1' then
   assert count<expected'length report "Extra stream word" severity failure;
   assert dout=expected(count) report "HawkSign mismatch at word "&integer'image(count)&" expected="&to_hstring(expected(count))&" actual="&to_hstring(dout) severity failure;
   assert (last='1')=(count=expected'length-1) report "Incorrect TLAST" severity failure;
   count:=count+1;
  end if;
  wait until falling_edge(clk);
  if count=expected'length then ready<='0';return;end if;
  if cycle mod 13<7 then ready<='0';else ready<='1';end if;
 end loop;
 assert false report "HawkSign transaction timed out" severity failure;
end;
begin
wait until falling_edge(clk);wait until falling_edge(clk);rst<='1';
wait until falling_edge(clk);
'''+''.join(tests)+'''
report "PASS: complete signing integration";
std.env.stop;wait;
end process;end;
'''
    (WORK/'tb.vhd').write_text(tb)
    def run(tool,*args):
        p=subprocess.run([str(BIN/(tool+'.bat')),*map(str,args)],cwd=WORK,capture_output=True,text=True)
        (WORK/(tool+'.log')).write_text(p.stdout+p.stderr)
        if p.returncode:raise RuntimeError(p.stdout+p.stderr)
        print(tool+': OK',flush=True)
    run('xvlog','--work','work',IP)
    run('xvhdl','--2008',*[ROOT/'03_design'/f'{s}.vhd' for s in ('hawk_pkg','poly_mul_mod2','calculate_t','poly_mul','calculate_w1','sym_break_w1','calculate_s1','hawk_sign')],WORK/'tb.vhd')
    run('xelab','--relax','-L','blk_mem_gen_v8_4_5','work.sign_integration_tb','-s','sign_integration')
    (WORK/'run.tcl').write_text('run 50 ms\nquit\n')
    run('xsim','sign_integration','-tclbatch','run.tcl')
    log=(WORK/'xsim.log').read_text()
    assert 'PASS: complete signing integration' in log and 'Failure:' not in log and 'Fatal:' not in log,log[-4000:]
    print('\n'.join(x for x in log.splitlines() if 'PASS' in x))


if __name__=='__main__':main()
