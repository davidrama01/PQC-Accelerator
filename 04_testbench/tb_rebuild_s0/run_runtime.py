"""Simulate RebuildS0 for 256, 512, 1024, then 256 without resetting."""
from pathlib import Path
import random
import math
import generate_vectors as oracle
import run_standalone


def main():
    declarations, tests = [], []
    for case, n in enumerate((256, 512, 1024, 256)):
        oracle.N = n
        rng = random.Random(20261024 + case)
        q00 = [64] + [0] * (n-1)
        q00[1], q00[-1] = 3, -3
        q01 = [rng.randint(-16, 16) for _ in range(n)]
        w1 = [rng.randint(-16, 16) for _ in range(n)]
        h0 = [rng.randrange(2) for _ in range(n)]
        expected = oracle.rebuild(q00, q01, w1, h0)
        for name, values in zip(('q00', 'q01', 'w1', 'h0', 'expected'),
                                (q00, q01, w1, h0, expected)):
            declarations.append(f'constant {name}_{case}: vec_t(0 to {n-1}) := (' +
                                ','.join(map(str, values)) + ');')
        threshold = {256: 2223, 512: 8317, 1024: 20218}[n]
        tests.append(f'''
        assert verify_threshold({n}) = to_unsigned({threshold},32)
            report "Incorrect threshold" severity failure;
        num_samples <= {n};
        h0 <= (others => '0');
        for i in 0 to {n-1} loop
            if h0_{case}(i)=1 then h0(i)<='1'; else h0(i)<='0'; end if;
        end loop;
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        start <= '1';
        wait until falling_edge(clk);
        start <= '0';
        valid <= '1';
        for i in 0 to {n-1} loop
            q00 <= std_logic_vector(to_signed(q00_{case}(i),32));
            q01 <= std_logic_vector(to_signed(q01_{case}(i),32));
            w1 <= std_logic_vector(to_signed(w1_{case}(i),32));
            wait until falling_edge(clk);
        end loop;
        valid <= '0';
        count := 0;
        for cycle in 0 to 300000 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert err='0' report "Rebuild error" severity failure;
            if out_valid='1' then
                assert count < {n} report "Extra output" severity failure;
                assert not is_x(dout) report "Unknown output" severity failure;
                assert to_integer(signed(dout))=expected_{case}(count)
                    report "Mismatch case {case}, index " & integer'image(count)
                    severity failure;
                count := count+1;
            end if;
            exit when done='1';
        end loop;
        assert done='1' and count={n} report "Timeout/count mismatch" severity failure;
        report "PASS runtime RebuildS0 n={n}, case={case}" severity note;
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        ''')
        for delta in (-1, 0, 1):
            remainder, values = threshold + delta, []
            while remainder:
                value = math.isqrt(remainder)
                values.append(value)
                remainder -= value*value
            name = f'norm_{case}_{delta+1}'
            declarations.append(f'constant {name}: vec_t(0 to {n-1}) := (' +
                                ','.join(map(str, values+[0]*(n-len(values)))) + ');')
            tests.append(f'''
        th_start <= '1';
        wait until falling_edge(clk);
        th_start <= '0';
        for i in 0 to {n-1} loop
            x0 <= std_logic_vector(to_signed({name}(i),16));
            wait until falling_edge(clk);
        end loop;
        x0 <= (others=>'0');
        for cycle in 0 to 10 loop
            wait until rising_edge(clk);
            wait for 1 ns;
            exit when th_done='1';
        end loop;
        assert th_done='1' and th_verify='{int(delta <= 0)}'
            report "Threshold boundary failed n={n} delta={delta}" severity failure;
        wait until falling_edge(clk);
        ''')
    source = '''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hawk_pkg.all;
entity rebuild_runtime_tb is end;
architecture simulation of rebuild_runtime_tb is
type vec_t is array(natural range <>) of integer;
''' + '\n'.join(declarations) + '''
signal clk: std_logic := '0';
signal rst_n, start, valid: std_logic := '0';
signal done, err, out_valid: std_logic;
signal num_samples: integer range 256 to 1024 := 512;
signal q00,q01,w1,dout: std_logic_vector(31 downto 0) := (others=>'0');
signal h0: std_logic_vector(1023 downto 0) := (others=>'0');
signal th_start: std_logic := '0';
signal th_done, th_verify: std_logic;
signal x0: std_logic_vector(15 downto 0) := (others=>'0');
begin
clk <= not clk after 5 ns;
th: entity work.threshold port map(num_samples=>num_samples,clk=>clk,
    rst_n=>rst_n,start=>th_start,done=>th_done,x0=>x0,x1=>(others=>'0'),verify=>th_verify);
dut: entity work.rebuild_s0 port map(num_samples=>num_samples,
    clk=>clk,rst_n=>rst_n,start=>start,data_in_valid=>valid,
    done=>done,data_q00=>q00,data_q01=>q01,data_w1=>w1,data_h0=>h0,
    data_out=>dout,data_out_valid=>out_valid,error=>err);
process
variable count: natural;
begin
wait for 40 ns;
wait until falling_edge(clk);
rst_n <= '1';
''' + '\n'.join(tests) + '''
report "Todas las pruebas de RebuildS0 han finalizado correctamente" severity note;
std.env.stop;
wait;
end process;
end;
'''
    work = Path(__file__).with_name('.work')
    work.mkdir(exist_ok=True)
    tb = work / 'rebuild_runtime_tb.vhd'
    tb.write_text(source)
    run_standalone.main(tb.resolve(), 'rebuild_runtime_tb', '10 ms')


if __name__ == '__main__':
    main()
