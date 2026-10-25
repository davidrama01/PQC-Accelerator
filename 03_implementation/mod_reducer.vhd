library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Exact unsigned reduction by a constant modulus, one input bit per cycle.
-- Accept start while idle; inputs are latched. done pulses for one cycle.
-- Reset aborts the current operation. The result is held until next completion.
entity mod_reducer is
    generic (g_input_width : positive := 64;
             g_result_width : positive := 32;
             g_modulus : positive := 2147473409);
    port (clk, rst_n, start : in std_logic;
          data_in : in unsigned(g_input_width-1 downto 0);
          residue : out unsigned(g_result_width-1 downto 0);
          busy, done : out std_logic);
end entity;
architecture rtl of mod_reducer is
    constant C_P : unsigned(g_result_width downto 0) := to_unsigned(g_modulus,g_result_width+1);
    signal active : std_logic := '0';
    signal bits_left : natural range 0 to g_input_width := 0;
    signal input_reg : unsigned(g_input_width-1 downto 0);
    signal remainder_reg : unsigned(g_result_width downto 0);
begin
    assert C_P(C_P'high) = '0' report "Modulus must fit result width" severity failure;
    busy <= active;
    process(clk)
        variable trial, difference : unsigned(g_result_width downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                active <= '0'; done <= '0'; bits_left <= 0;
                input_reg <= (others=>'0'); remainder_reg <= (others=>'0');
                residue <= (others=>'0');
            else
                done <= '0';
                if active = '0' then
                    if start = '1' then
                        input_reg <= data_in; remainder_reg <= (others=>'0');
                        bits_left <= g_input_width; active <= '1';
                    end if;
                else
                    trial := shift_left(remainder_reg,1);
                    trial(0) := input_reg(input_reg'high);
                    -- The extra bit exposes unsigned underflow; only one subtractor.
                    difference := trial - C_P;
                    if difference(difference'high) = '0' then trial := difference; end if;
                    remainder_reg <= trial;
                    input_reg <= shift_left(input_reg,1);
                    bits_left <= bits_left-1;
                    if bits_left = 1 then
                        residue <= resize(trial,g_result_width);
                        active <= '0'; done <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
