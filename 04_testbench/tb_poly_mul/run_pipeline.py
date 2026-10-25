"""Compare poly_mul and calculate_w1 against independent negacyclic convolution."""
from pathlib import Path
import random, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
BIN=Path('C:/Xilinx/Vivado/2022.1/bin')
rng=random.Random(20261025)
lanes=[]
for width in (16,32):
    declarations=[]; tests=[]
    cases=[]
    for n in (256,512,1024,256):
        a=[rng.randint(-20,20) for _ in range(n)]
        b=[rng.randint(-20,20) for _ in range(n)]
        cases.append((n,a,b))
    cases.append((256,[0]*255+[1],[0,1]+[0]*254))
    cases.append((256,[-(1<<(width-1))]+[0]*255,[-(1<<(width-1))]+[0]*255))
    for case,(n,a,b) in enumerate(cases):
        expected=[]
        for i in range(n):
            value=sum(a[j]*b[(i-j)%n]*(1 if j<=i else -1) for j in range(n))
            value %= 1<<(2*width)
            # numeric_std.resize(signed): sign plus the low width-1 bits.
            expected.append(((value>>(2*width-1))<<(width-1)) | (value&((1<<(width-1))-1)))
        for name,values in [('a',a),('b',b),('e',expected)]:
            declarations.append(f"constant {name}{case}: vec_t(0 to {n-1}) := ("+','.join('"'+format(x% (1<<width),f'0{width}b')+'"' for x in values)+');')
        tests.append(f'''n<={n};
for k in 0 to {n-1} loop mem_a(k)<=a{case}(k); mem_b(k)<=b{case}(k); end loop;
wait until falling_edge(clk); start<='1';
wait until falling_edge(clk); start<='0'; count:=0; count_w:=0;
for cycle in 1 to {n*(n+4)+8} loop
    wait until falling_edge(clk);
    if done='1' then
        assert count<{n} report "Extra coefficient" severity failure;
        assert result=e{case}(count) report "poly_mul mismatch width={width} case={case}" severity failure;
        count:=count+1;
    end if;
    if done_w='1' then
        assert count_w<{n} and w1=e{case}(count_w) report "calculate_w1 mismatch" severity failure;
        count_w:=count_w+1;
    end if;
end loop;
assert count={n} and count_w={n} report "Missing coefficients" severity failure;
report "PASS width={width} n={n} case={case}";
''')
    lanes.append(f'''lane{width}: block
constant W: positive := {width};
type vec_t is array(natural range <>) of std_logic_vector(W-1 downto 0);
'''+''.join(declarations)+f'''
signal mem_a,mem_b: vec_t(0 to 1023) := (others=>(others=>'0'));
signal clk: std_logic := '0';
signal rst_n,start,done,done_w: std_logic := '0';
signal n: integer range 256 to 1024 := 256;
signal aa,ab,af,ag,ax0,ax1: std_logic_vector(9 downto 0);
signal da,db,f,g,x1,result,w1: std_logic_vector(W-1 downto 0);
signal da_q,db_q,f_q,g_q,x1_q: std_logic_vector(W-1 downto 0);
begin
clk<=not clk after 5 ns;
process(clk) begin if rising_edge(clk) then
 da_q<=mem_a(to_integer(unsigned(aa))); db_q<=mem_b(to_integer(unsigned(ab)));
 f_q<=mem_a(to_integer(unsigned(af))); g_q<=mem_a(to_integer(unsigned(ag)));
 x1_q<=mem_b(to_integer(unsigned(ax1)));
 da<=da_q; db<=db_q; f<=f_q; g<=g_q; x1<=x1_q;
end if; end process;
dut: entity work.poly_mul generic map(W,10) port map(n,clk,rst_n,start,done,da,db,aa,ab,result);
composition: entity work.calculate_w1 generic map(W,10)
port map(num_samples=>n,clk=>clk,rst_n=>rst_n,start=>start,done=>done_w,
f_regen=>f,g_regen=>g,x0=>(others=>'0'),x1=>x1,
addr_f=>af,addr_g=>ag,addr_x0=>ax0,addr_x1=>ax1,w1=>w1);
process
variable count,count_w: natural;
begin
wait until falling_edge(clk); rst_n<='1'; start<='1';
wait until falling_edge(clk); start<='0';
for k in 1 to 10 loop wait until falling_edge(clk); end loop;
rst_n<='0'; wait until falling_edge(clk);
assert done='0' and unsigned(result)=0 report "Reset failed" severity failure;
rst_n<='1';
-- Restart while products are already in flight; the first case flushes them.
start<='1'; wait until falling_edge(clk); start<='0';
for k in 1 to 10 loop wait until falling_edge(clk); end loop;
'''+''.join(tests)+f"passed({int(width==32)})<=true; wait; end process; end block;")
source='''library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity poly_pipeline_tb is end;
architecture tb of poly_pipeline_tb is
signal passed: boolean_vector(0 to 1) := (others=>false);
begin
'''+''.join(lanes)+'''
process begin
wait until passed=(passed'range=>true);
report "PASS: poly_mul and calculate_w1 pipelines";
std.env.stop; wait;
end process; end;
'''
work=Path(tempfile.mkdtemp(prefix='hawk-poly-pipeline-'));print(work,flush=True)
(work/'tb.vhd').write_text(source)
def run(tool,*args): subprocess.run([str(BIN/(tool+'.bat')),*map(str,args)],cwd=work,check=True)
run('xvhdl','--2008',*[ROOT/'03_design'/f'{name}.vhd' for name in ('hawk_pkg','poly_mul','calculate_w1')],work/'tb.vhd')
run('xelab','work.poly_pipeline_tb','-s','poly_pipeline')
(work/'run.tcl').write_text('run 100 ms\nquit\n')
run('xsim','poly_pipeline','-tclbatch','run.tcl')
log=(work/'xsim.log').read_text()
assert 'PASS: poly_mul and calculate_w1 pipelines' in log and 'Failure:' not in log and 'Fatal:' not in log
