library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity poly_mul is
    generic (
        g_num_samples   : integer := 512;
        g_data_width    : integer := 16;
        g_addr_width    : integer := 9 -- Log2(g_num_samples)
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        data_a      : in std_logic_vector(g_data_width - 1 downto 0);
        data_b      : in std_logic_vector(g_data_width - 1 downto 0);
        addr_a      : out std_logic_vector(g_num_samples - 1 downto 0);
        addr_b      : out std_logic_vector(g_num_samples - 1 downto 0);
        addr_result : out std_logic_vector(g_num_samples - 1 downto 0);
        result      : out std_logic_vector(g_data_width - 1 downto 0)
    );
end entity poly_mul;

architecture rtl of poly_mul is

signal temp_result  : signed(2*g_data_width - 1 downto 0);
signal acc          : signed(2*g_data_width - 1 downto 0);
signal i            : integer range 0 to g_num_samples;
signal j            : integer range 0 to g_num_samples;
signal done_d       : std_logic;
signal enable       : std_logic;

begin

    pol_mul_process : process(clk, rst_n)
    begin
        if rst_n = '0' then
            temp_result <= (others => '0');
            acc         <= (others => '0');
            i           <= 0;
            j           <= 0;
            done_d      <= '0';
            enable      <= '0';
        elsif rising_edge(clk) then
            done_d <= '0';
            if start = '1' then
              i             <= 0;
              j             <= 0;
              acc           <= (others => '0');
              enable        <= '1';
              temp_result   <= (others => '0');
            elsif enable = '1' then
                if i < g_num_samples then
                    acc <= acc + (signed(data_a) * signed(data_b));
                end if;

                if j >= g_num_samples - 1 then
                    j           <= 0;
                    i           <= i + 1;
                    acc         <= (others => '0');
                    temp_result <= acc;
                    done_d      <= '1';
                    if i >= g_num_samples - 1 then
                        i       <= 0;
                        enable  <= '0';
                    end if;
                else
                    j <= j + 1;
                end if;
            end if;
        end if;
    end process pol_mul_process;

    addr_a      <= std_logic_vector(to_unsigned(j, g_addr_width));
    addr_result <= std_logic_vector(to_unsigned(i, g_addr_width));
    addr_b      <= std_logic_vector(to_unsigned((i-j+g_num_samples) mod g_num_samples, g_addr_width));

    result <= std_logic_vector(resize(temp_result, g_data_width));
    done <= done_d;

end architecture rtl;