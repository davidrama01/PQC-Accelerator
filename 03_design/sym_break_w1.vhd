library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity sym_break_w1 is
    generic (
        g_num_samples : integer := 512;
        g_addr_width : integer := 9
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        ready       : out std_logic;
        w1_in       : in std_logic_vector(g_num_samples - 1 downto 0);
        addr_in     : out std_logic_vector(g_num_samples - 1 downto 0);
        w1_out      : out std_logic_vector(g_num_samples - 1 downto 0)
    );
end entity sym_break_w1;

architecture rtl of sym_break_w1 is


signal w1_internal  : signed(g_num_samples - 1 downto 0);
signal addr_int     : integer range 0 to g_num_samples + 10;
signal done_d       : std_logic;
signal ready_d      : std_logic;
signal sym_break    : std_logic;

begin

    symbreak_process: process(clk, rst_n) begin
        if rst_n = '0' then
            w1_internal <= (others => '0');
            done_d      <= '0';
            ready_d     <= '0';
            sym_break   <= '1';
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
                elsif (addr_int < g_num_samples) and (sym_break = '0') then
                    w1_internal <= -signed(w1_in);
                    addr_int    <= addr_int + 1;
                    ready_d     <= '1';
                elsif (addr_int < g_num_samples) and (sym_break = '1') then
                    if (w1_in < (others => '0')) then 
                        sym_break   <= '0';
                        addr_int     <= 0;
                    else
                        sym_break   <= '1';
                        addr_int    <= addr_int + 1;
                    end if;
                end if;
            end if; 
        end if;
    end process;

    w1_out  <= std_logic_vector(w1_internal);
    done    <= done_d;
    ready   <= ready_d;
    addr_in <= std_logic_vector(to_signed(addr_int, g_addr_width));
    

end architecture rtl;