library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity poly_mul_mod2 is
    generic (
        g_num_samples : integer := 512;
        g_num_phases : integer := 1
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        start : in std_logic;
        done : out std_logic;
        data_a : in std_logic_vector(g_num_samples - 1 downto 0);
        data_b : in std_logic_vector(g_num_samples - 1 downto 0);
        result : out std_logic_vector(g_num_samples - 1 downto 0)
    );
end entity poly_mul_mod2;

architecture rtl of poly_mul_mod2 is

signal temp_result : std_logic_vector(g_num_samples - 1 downto 0);
signal i : integer range 0 to g_num_samples;
signal j : integer range 0 to g_num_samples;
signal acc : std_logic;
signal done_d : std_logic;
signal enable : std_logic;

attribute MARK_DEBUG : string;
-- attribute MARK_DEBUG of temp_result : signal is "true";
attribute MARK_DEBUG of i : signal is "true";
attribute MARK_DEBUG of j : signal is "true";
attribute MARK_DEBUG of acc : signal is "true";
attribute MARK_DEBUG of done_d : signal is "true";
attribute MARK_DEBUG of enable : signal is "true";

begin
    and_parallel_process : process(clk, rst_n)
    variable group_xor : std_logic;
    begin
        if rst_n = '0' then
            temp_result <= (others => '0');
            i <= 0;
            j <= 0;
            done_d <= '0';
            acc <= '0';
            group_xor := '0';
            enable <= '0';
        elsif rising_edge(clk) then
            -- AND operation for each bit pair
            group_xor := '0';
            done_d <= '0';
            if start = '1' then
              i <= 0;
              j <= 0;
              acc <= '0';
              enable <= '1';
              group_xor := '0';
              temp_result <= (others => '0');
            elsif enable = '1' then
                if i < g_num_samples then
                    for parallel_counter in 0 to g_num_phases-1 loop
                        if (i - (j + parallel_counter)) >= 0 then
                            group_xor := group_xor xor (data_a(j+parallel_counter) and data_b(i-(j+parallel_counter)));
                        else
                            group_xor := group_xor xor (data_a(j+parallel_counter) and data_b(i-(j+parallel_counter)+g_num_samples));
                        end if;
                    end loop;
                end if;

                if j + g_num_phases >= g_num_samples then
                    j <= 0;
                    i <= i + 1;
                    acc <= '0';
                    temp_result(i) <= acc xor group_xor;
                    if i >= g_num_samples - 1 then
                        done_d <= '1';
                        i <= 0;
                        enable <= '0';
                    end if;
                else
                    j <= j + g_num_phases;
                    acc <= acc xor group_xor;
                end if;
            end if;
        end if;
    end process and_parallel_process;

    result <= temp_result;
    done <= done_d;
    -- Multiplication logic here
end architecture rtl;