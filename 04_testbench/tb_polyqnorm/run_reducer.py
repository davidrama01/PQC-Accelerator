"""Check sequential reduction against Python integer modulo, including reset."""
from pathlib import Path
import random
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
BIN=Path('C:/Xilinx/Vivado/2022.1/bin')
work=Path(tempfile.mkdtemp(prefix='hawk-reducer-'))
rng=random.Random(20261024)
lanes=[]
for lane,p in enumerate((2147473409,2147389441)):
    values=[0,1,p-1,p,p+1,p*p-1,p*p,2**63,2**64-1]
    values += [rng.randrange(2**64) for _ in range(200)]
    checks=[]
    for x in values:
        checks.append(f'''data_in<=x"{x:016x}"; start<='1';
wait until falling_edge(clk); start<='0'; data_in<=(others=>'0');
for i in 1 to 64 loop
    assert busy='1' and done='0' report "Early completion" severity failure;
    wait until falling_edge(clk);
end loop;
assert done='1' and busy='0' and residue=to_unsigned({x%p},32)
    report "Incorrect reduction" severity failure;
wait until falling_edge(clk);
assert done='0' report "done must pulse" severity failure;
''')
    lanes.append(f'''lane{lane}: block
signal start,busy,done,rst_n: std_logic := '0';
signal data_in: unsigned(63 downto 0) := (others=>'0');
signal residue: unsigned(31 downto 0);
begin
dut: entity work.mod_reducer generic map(g_modulus=>{p})
port map(clk,rst_n,start,data_in,residue,busy,done);
process begin
wait until falling_edge(clk); rst_n<='1'; start<='1';
wait until falling_edge(clk); start<='0';
wait until falling_edge(clk); rst_n<='0';
wait until falling_edge(clk);
assert busy='0' and done='0' report "Reset failed" severity failure;
rst_n<='1';
''' + ''.join(checks)+f"passed({lane})<=true; wait; end process; end block;" )
source='''library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity reducer_tb is end;
architecture tb of reducer_tb is
signal clk: std_logic := '0';
signal passed: boolean_vector(0 to 1) := (others=>false);
begin
clk<=not clk after 5 ns;
''' + ''.join(lanes)+'''
process begin
wait until passed=(passed'range=>true);
report "PASS: 418 reductions, both primes, reset and exact latency";
std.env.stop; wait;
end process; end;
'''
(work/'reducer_tb.vhd').write_text(source)
def run(tool,*args):
    subprocess.run([str(BIN/(tool+'.bat')),*map(str,args)],cwd=work,check=True)
print(work,flush=True)
run('xvhdl','--2008',ROOT/'03_design/mod_reducer.vhd',work/'reducer_tb.vhd')
run('xelab','work.reducer_tb','-s','reducer_test')
(work/'run.tcl').write_text('run 1 ms\nquit\n')
run('xsim','reducer_test','-tclbatch','run.tcl')
log=(work/'xsim.log').read_text()
assert 'PASS: 418 reductions' in log and 'Failure:' not in log and 'Fatal:' not in log
