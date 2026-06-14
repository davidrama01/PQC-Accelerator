library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity calculate_s1 is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 16;
        g_addr_width  : integer := 9;
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        ready       : out std_logic;
        h1          : in std_logic_vector(g_num_samples - 1 downto 0);
        w1          : in std_logic_vector(g_data_width - 1 downto 0);
        addr        : out std_logic_vector(g_addr_width - 1 downto 0);
        s1          : out std_logic_vector(g_data_width - 1 downto 0)
    );
end entity calculate_s1;

architecture rtl of calculate_s1 is

signal s1_internal : signed(g_data_width - 1 downto 0);
signal done_d : std_logic;
signal ready_d : std_logic;
signal addr_int : integer range 0 to g_num_samples + 10;

begin

    calculate_s1_process: process(clk, rst_n) begin
        if rst_n = '0' then
            s1_internal <= (others => '0');
            done_d      <= '0';
            ready_d     <= '0';
            addr_int    <= 0;
        elsif rising_edge(clk) then
            done_d  <= '0';
            ready_d <= '0';
            if start = '1' then
                addr_int      <= 0;
                w1_internal   <= (others => '0');
                enable        <= '1';
            elsif enable = '1' then
                if (addr_int >= g_num_samples) then
                    enable   <= '0';
                    addr_int <= 0;
                    done_d   <= '1';
                elsif (addr_int < g_num_samples) then
                    if (h1(addr_int) = '1') then
                        s1_internal <= std_logic_vector(shift_right((to_signed(1, g_data_width) - signed(w1)),1));   
                    else
                        s1_internal <= std_logic_vector(shift_right(-signed(w1),1));
                    end if;
                    addr_int    <= addr_int + 1;
                    ready_d     <= '1';
                end if;
            end if; 
        end if;
    end process;

    s1 <= std_logic_vector(s1_internal);
    done <= done_d;
    addr <= std_logic_vector(to_unsigned(addr_int, g_data_width));
    
    -- Multiplication logic here
end architecture rtl;