"""Deterministic signed-divider regression, including 65-bit boundary cases."""
from pathlib import Path
import random
import run_standalone

rng = random.Random(472)
pairs = [(a,b) for a in (0,1,-1,7,-7,2**64-1,-2**64)
         for b in (0,1,-1,2,-2,2**29-1,-2**32)]
pairs += [(rng.randrange(-2**64,2**64), rng.randrange(-2**32,2**32)) for _ in range(200)]
def bits(x,n): return '"'+format(x % (1<<n),f'0{n}b')+'"'
checks=[]
for a,b in pairs:
    q = (abs(a)//abs(b)) * (-1 if (a<0) != (b<0) else 1) if b else 0
    checks.append(f'''n <= {bits(a,65)}; d <= {bits(b,33)}; start <= '1';
wait until falling_edge(clk); start <= '0';
-- Alter inputs while busy: accepted operands must remain latched.
n <= (others=>'0'); d <= (others=>'0');
for i in 0 to 67 loop
    exit when done='1';
    wait until falling_edge(clk);
end loop;
assert done='1' and busy='0' report "Divider timeout" severity failure;
assert q = {bits(q,65)} and zero='{int(b==0)}' report "Wrong quotient" severity failure;
wait until falling_edge(clk);
assert done='0' report "done must pulse" severity failure;
''')
source = '''library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity divider_tb is end;
architecture tb of divider_tb is
signal clk: std_logic := '0';
signal rst_n,start,busy,done,zero: std_logic := '0';
signal n,q: signed(64 downto 0) := (others=>'0');
signal d: signed(32 downto 0) := (others=>'0');
begin
clk <= not clk after 5 ns;
dut: entity work.signed_divider port map(clk,rst_n,start,n,d,q,busy,done,zero);
process begin
wait until falling_edge(clk); rst_n<='1';
-- Abort an active operation by reset, then exercise back-to-back divisions.
n<=to_signed(123,65); d<=to_signed(3,33); start<='1';
wait until falling_edge(clk); start<='0';
wait until falling_edge(clk); rst_n<='0';
wait until falling_edge(clk);
assert busy='0' and done='0' report "Reset failed" severity failure;
rst_n<='1';
''' + ''.join(checks) + '''
report "Todas las pruebas de RebuildS0 han finalizado correctamente";
std.env.stop; wait;
end process; end;
'''
work=Path(__file__).with_name('.work'); work.mkdir(exist_ok=True)
tb=work/'divider_tb.vhd'; tb.write_text(source)
run_standalone.main(tb.resolve(),'divider_tb','1 ms')
print(f'PASS: {len(pairs)} divider cases and reset during operation')
