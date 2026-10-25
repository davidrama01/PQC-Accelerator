"""Diagnose signing arithmetic against the real generated blk_mem_gen_0 IP.

Production sources are read only. Logs and testbench stay in .work/sign_memory.
"""
from pathlib import Path
import subprocess
import random
import argparse

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'06_test/.work/sign_memory'
BIN=Path('C:/Xilinx/Vivado/2022.1/bin')
IP=ROOT/'02_project/hawk_acc/hawk_acc.gen/sources_1/bd/hawk_acc/ip/hawk_acc_hawk_acc_0_0/src/blk_mem_gen_0/sim/blk_mem_gen_0.v'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--n',type=int,choices=(256,512,1024),default=256)
    args=parser.parse_args()
    work=WORK/f'current_{args.n}'
    work.mkdir(parents=True,exist_ok=True)
    rng=random.Random(20261025)
    n=args.n
    a=[rng.randint(-5,5) for _ in range(n)]
    b=[rng.randint(-4,4) for _ in range(n)]
    expected=[sum(a[j]*b[(i-j)%n]*(1 if j<=i else -1) for j in range(n)) for i in range(n)]
    tb='''library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity sign_memory_tb is end;
architecture tb of sign_memory_tb is
type ints is array(0 to 255) of integer;
'''
    for name,values in [('A',a),('B',b),('E',expected)]:
        tb+=f'constant C_{name}:ints:=('+','.join(map(str,values))+');\n'
    tb=tb.replace('0 to 255',f'0 to {n-1}')
    body='''
component blk_mem_gen_0 is port(clka,ena:in std_logic;wea:in std_logic_vector(0 downto 0);
addra:in std_logic_vector(9 downto 0);dina:in std_logic_vector(31 downto 0);douta:out std_logic_vector(31 downto 0)); end component;
signal clk:std_logic:='0'; signal rst,start:std_logic:='0';
signal loading:boolean:=true;
signal wa:std_logic_vector(0 downto 0):="0";
signal wi:integer range 0 to 255:=0;
signal aa,ab,as1,ma,mb,ms:std_logic_vector(9 downto 0);
signal da,db,ds,qa,qb,qs,result,s1:std_logic_vector(31 downto 0);
signal pd,sd,sv:std_logic;
signal out_ready,sym:std_logic:='0';
signal h1:std_logic_vector(1023 downto 0):=(others=>'0');
begin
clk<=not clk after 5 ns;
ma<=std_logic_vector(to_unsigned(wi,10)) when loading else aa;
mb<=std_logic_vector(to_unsigned(wi,10)) when loading else ab;
ms<=std_logic_vector(to_unsigned(wi,10)) when loading else as1;
da<=std_logic_vector(to_signed(C_A(wi),32)); db<=std_logic_vector(to_signed(C_B(wi),32));
ds<=std_logic_vector(to_signed(2*wi+(wi mod 2),32));
ra:blk_mem_gen_0 port map(clk,'1',wa,ma,da,qa);
rb:blk_mem_gen_0 port map(clk,'1',wa,mb,db,qb);
rs:blk_mem_gen_0 port map(clk,'1',wa,ms,ds,qs);
p:entity work.poly_mul generic map(32,10) port map(256,clk,rst,start,pd,qa,qb,aa,ab,result);
s:entity work.calculate_s1 generic map(32,10)
port map(256,clk,rst,start,out_ready,sd,sv,sym,h1,qs,as1,s1);
process
variable pc,sc,pe,se:integer:=0;
variable expected_s:integer;
variable held:boolean:=false;
variable held_data:std_logic_vector(31 downto 0);
variable held_last:std_logic;
begin
for i in 0 to 255 loop
 wait until falling_edge(clk); wi<=i; wa<="1";
end loop;
wait until falling_edge(clk); wa<="0"; loading<=false;
for i in 0 to 255 loop if i mod 2=1 then h1(i)<='1'; end if; end loop;
wait until falling_edge(clk); rst<='1';
-- Abort an operation while its read/product pipeline is active.
wait until falling_edge(clk); start<='1';
wait until falling_edge(clk); start<='0';
for k in 1 to 8 loop wait until falling_edge(clk); end loop;
rst<='0'; wait until falling_edge(clk);
assert pd='0' and sv='0' and sd='0' report "Reset did not flush output" severity failure;
rst<='1';
-- Run both sign choices back to back without another reset.
for operation in 0 to 1 loop
pc:=0; sc:=0; held:=false;
if operation=0 then sym<='1'; else sym<='0'; end if;
wait until falling_edge(clk); start<='1';
wait until falling_edge(clk); start<='0'; out_ready<='0';
for cycle in 0 to 70000 loop
 wait until rising_edge(clk);
 if held then
  assert sv='1' and s1=held_data and sd=held_last report "Output changed under backpressure" severity failure;
 end if;
 held:=sv='1' and out_ready='0'; held_data:=s1; held_last:=sd;
 if pd='1' then
  assert pc<256 severity failure;
  if signed(result)/=to_signed(C_E(pc),32) then
   pe:=pe+1;
   if pe<=4 then report "POLY mismatch index="&integer'image(pc)&" expected="&integer'image(C_E(pc))&" actual="&integer'image(to_integer(signed(result))); end if;
  end if;
  pc:=pc+1;
 end if;
 if sv='1' and out_ready='1' then
  assert sc<256 severity failure;
  assert (sd='1')=(sc=255) report "Incorrect last flag" severity failure;
  if operation=0 then expected_s:=-sc; else expected_s:=sc+(sc mod 2); end if;
  if signed(s1)/=to_signed(expected_s,32) then
   se:=se+1;
   if se<=4 then report "S1 mismatch index="&integer'image(sc)&" expected="&integer'image(-sc)&" actual="&integer'image(to_integer(signed(s1))); end if;
  end if;
  sc:=sc+1;
 end if;
 exit when pc=256 and sc=256;
 wait until falling_edge(clk);
 -- Include pauses spanning coefficient boundaries and the final word.
 if cycle mod 11<6 then out_ready<='0'; else out_ready<='1'; end if;
end loop;
assert pc=256 and sc=256 report "Missing outputs" severity failure;
wait until falling_edge(clk);
for k in 1 to 4 loop
 wait until falling_edge(clk);
 assert pd='0' and sv='0' and sd='0' report "Extra output after completion" severity failure;
end loop;
end loop;
report "AUDIT COMPLETE poly_errors="&integer'image(pe)&" s1_errors="&integer'image(se);
std.env.stop; wait;
end process;
end;
'''
    tb+=body.replace('255',str(n-1)).replace('256',str(n)).replace('70000',str(n*(n+6)+100))
    (work/'tb.vhd').write_text(tb)
    sources=[]
    for name in ('hawk_pkg','poly_mul','calculate_s1'):
        src=(ROOT/'03_design'/f'{name}.vhd').read_text()
        dest=work/f'{name}.vhd';dest.write_text(src);sources.append(dest)
    def run(tool,*args):
        p=subprocess.run([str(BIN/(tool+'.bat')),*map(str,args)],cwd=work,capture_output=True,text=True)
        (work/(tool+'.log')).write_text(p.stdout+p.stderr)
        if p.returncode: raise RuntimeError(p.stdout+p.stderr)
        print(tool+': OK',flush=True)
    run('xvlog','--work','work',IP)
    run('xvhdl','--2008',*sources,work/'tb.vhd')
    run('xelab','--relax','-L','blk_mem_gen_v8_4_5','work.sign_memory_tb','-s','audit')
    (work/'run.tcl').write_text('run 30 ms\nquit\n')
    run('xsim','audit','-tclbatch','run.tcl')
    log=(work/'xsim.log').read_text()
    assert 'AUDIT COMPLETE' in log and 'Failure:' not in log,log[-3000:]
    print('\n'.join(x for x in log.splitlines() if 'mismatch' in x or 'AUDIT COMPLETE' in x))
    assert 'AUDIT COMPLETE poly_errors=0 s1_errors=0' in log


if __name__=='__main__': main()
