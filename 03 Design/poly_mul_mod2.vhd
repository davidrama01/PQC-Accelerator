library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity poly_mul_mod2 is
    generic (
        N : integer := 32;
        P : integer := 8
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        start : in std_logic;
        done : out std_logic;
        data_a : in std_logic_vector(N-1 downto 0);
        data_b : in std_logic_vector(N-1 downto 0);
        result : out std_logic_vector(N-1 downto 0)
    );
end entity poly_mul_mod2;

architecture rtl of poly_mul_mod2 is

signal temp_result : std_logic_vector(N-1 downto 0);
signal i : integer range 0 to N;
signal j : integer range 0 to N;
signal acc : std_logic;
signal done_d : std_logic;
signal enable : std_logic;

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
            elsif enable = '1' then
                if i < N then
                    for parallel_counter in 0 to P-1 loop
                        if (i - (j + parallel_counter)) >= 0 then
                            group_xor := group_xor xor (data_a(j+parallel_counter) and data_b(i-(j+parallel_counter)));
                        else
                            group_xor := group_xor xor (data_a(j+parallel_counter) and data_b(i-(j+parallel_counter)+N));
                        end if;
                    end loop;
                end if;

                if j + P >= N then
                    j <= 0;
                    i <= i + 1;
                    acc <= '0';
                    temp_result(i) <= acc xor group_xor;
                    if i >= N - 1 then
                        done_d <= '1';
                        i <= 0;
                        enable <= '0';
                    end if;
                else
                    j <= j + P;
                    acc <= acc xor group_xor;
                end if;
            end if;
        end if;
    end process and_parallel_process;

    result <= temp_result;
    done <= done_d;
    -- Multiplication logic here
end architecture rtl;