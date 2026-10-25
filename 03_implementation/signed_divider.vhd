library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Restoring signed division, one dividend bit per clock. Truncates toward zero.
-- start is accepted only while idle. Inputs are latched; done pulses for one
-- cycle and quotient remains stable until completion of the next operation.
-- The minimum signed value divided by -1 wraps to the same minimum value.
-- Zero divisor returns zero with divide_by_zero asserted at completion.
entity signed_divider is
    generic (g_numerator_width : positive := 65;
             g_denominator_width : positive := 33);
    port (clk, rst_n, start : in std_logic;
          numerator : in signed(g_numerator_width-1 downto 0);
          denominator : in signed(g_denominator_width-1 downto 0);
          quotient : out signed(g_numerator_width-1 downto 0);
          busy, done, divide_by_zero : out std_logic);
end entity;

architecture rtl of signed_divider is
    signal active, negative : std_logic := '0';
    signal bits_left : natural range 0 to g_numerator_width := 0;
    signal dividend, result_bits : unsigned(g_numerator_width-1 downto 0);
    signal divisor : unsigned(g_denominator_width-1 downto 0);
    signal remainder_reg : unsigned(g_denominator_width downto 0);
begin
    busy <= active;
    process(clk)
        variable trial, difference : unsigned(g_denominator_width downto 0);
        variable next_result : unsigned(g_numerator_width-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                active <= '0'; negative <= '0'; bits_left <= 0;
                dividend <= (others=>'0'); result_bits <= (others=>'0');
                divisor <= (others=>'0'); remainder_reg <= (others=>'0');
                quotient <= (others=>'0'); done <= '0'; divide_by_zero <= '0';
            else
                done <= '0';
                if active = '0' then
                    if start = '1' then
                        divide_by_zero <= '0';
                        if denominator = 0 then
                            quotient <= (others=>'0');
                            divide_by_zero <= '1'; done <= '1';
                        else
                            -- Unsigned magnitudes also represent the most negative input.
                            dividend <= unsigned(abs(numerator));
                            divisor <= unsigned(abs(denominator));
                            negative <= numerator(numerator'high) xor denominator(denominator'high);
                            remainder_reg <= (others=>'0');
                            result_bits <= (others=>'0');
                            bits_left <= g_numerator_width; active <= '1';
                        end if;
                    end if;
                else
                    trial := shift_left(remainder_reg, 1);
                    trial(0) := dividend(dividend'high);
                    next_result := shift_left(result_bits, 1);
                    -- One subtraction provides both the comparison and new remainder.
                    difference := trial - resize(divisor, trial'length);
                    if trial >= resize(divisor, trial'length) then
                        trial := difference; next_result(0) := '1';
                    end if;
                    remainder_reg <= trial;
                    dividend <= shift_left(dividend, 1);
                    result_bits <= next_result;
                    bits_left <= bits_left - 1;
                    if bits_left = 1 then
                        if negative = '1' then quotient <= -signed(next_result);
                        else quotient <= signed(next_result); end if;
                        active <= '0'; done <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
