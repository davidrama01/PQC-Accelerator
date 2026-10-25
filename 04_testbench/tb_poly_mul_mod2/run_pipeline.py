"""Validate banked, pipelined GF(2) cyclic multiplication in XSim."""
from pathlib import Path
import random
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
BIN=Path('C:/Xilinx/Vivado/2022.1/bin')
rng=random.Random(20261024)
cases=[]
for n in (1,2,3,7,31,32,33,256,512,1024,32):
    a=rng.getrandbits(n); b=rng.getrandbits(n)
    mask=(1<<n)-1; expected=0
    for j in range(n):
        if (a>>j)&1:
            expected ^= ((b<<j)|(b>>(n-j))) & mask
    cases.append((n,a,b,expected))
# Explicit wrap-around and zero cases, plus inactive upper input bits.
cases += [(256,1<<255,2,1),(512,0,(1<<1024)-1,0),(3,((1<<1024)-1)^7,7,0)]
checks=[]
for n,a,b,expected in cases:
    checks.append(f'''n<={n}; a<=x"{a:0256x}"; b<=x"{b:0256x}";
start<='1'; wait until falling_edge(clk); start<='0';
for cycle in 1 to {n*n+5} loop
    assert done='0' report "Early done" severity failure;
    wait until falling_edge(clk);
end loop;
assert done='1' and result=x"{expected:0256x}" report "Product mismatch n={n}" severity failure;
wait until falling_edge(clk);
assert done='0' report "done must pulse" severity failure;
if {n}>=256 then
for cycle in 1 to 8 loop
    exit when done_t='1';
    wait until falling_edge(clk);
end loop;
assert done_t='1' and result_t=x"{expected:0256x}" report "calculate_t mismatch" severity failure;
end if;
wait until falling_edge(clk);
report "PASS n={n}";
''')
source='''library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity pipeline_tb is end;
architecture tb of pipeline_tb is
signal clk: std_logic := '0';
signal rst_n,start,done: std_logic := '0';
signal n: integer range 1 to 1024 := 32;
signal done_t,start_t: std_logic;
signal n_t: integer range 256 to 1024 := 256;
signal result_t: std_logic_vector(1023 downto 0);
signal a,b,result: std_logic_vector(1023 downto 0) := (others=>'0');
begin
clk<=not clk after 5 ns;
dut: entity work.poly_mul_mod2 port map(n,clk,rst_n,start,done,a,b,result);
start_t<=start when n>=256 else '0';
n_t<=n when n>=256 else 256;
composition: entity work.calculate_t port map(n_t,clk,rst_n,start_t,done_t,a,b,b,(others=>'0'),result_t);
process begin
wait until falling_edge(clk); rst_n<='1'; start<='1';
wait until falling_edge(clk); start<='0';
for i in 1 to 7 loop wait until falling_edge(clk); end loop;
rst_n<='0'; wait until falling_edge(clk);
assert done='0' and unsigned(result)=0 report "Reset failed" severity failure;
rst_n<='1';
-- Start again during an active multiplication; the first checked case restarts it.
start<='1'; wait until falling_edge(clk); start<='0';
for i in 1 to 5 loop wait until falling_edge(clk); end loop;
''' + ''.join(checks) + '''
report "PASS: pipelined mod2 multiplication, all cases";
std.env.stop; wait;
end process; end;
'''
work=Path(tempfile.mkdtemp(prefix='hawk-mod2-pipeline-'))
print(work,flush=True)
(work/'pipeline_tb.vhd').write_text(source)
def run(tool,*args):
    subprocess.run([str(BIN/(tool+'.bat')),*map(str,args)],cwd=work,check=True)
run('xvhdl','--2008',ROOT/'03_design/hawk_pkg.vhd',ROOT/'03_design/poly_mul_mod2.vhd',ROOT/'03_design/calculate_t.vhd',work/'pipeline_tb.vhd')
run('xelab','work.pipeline_tb','-s','pipeline_test')
(work/'run.tcl').write_text('run 150 ms\nquit\n')
run('xsim','pipeline_test','-tclbatch','run.tcl')
log=(work/'xsim.log').read_text()
assert 'PASS: pipelined mod2 multiplication, all cases' in log and 'Failure:' not in log and 'Fatal:' not in log
