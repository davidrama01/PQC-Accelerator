library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity sym_break_w1 is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 16
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        valid       : in std_logic;
        ready       : out std_logic;
        sym_break   : out std_logic;
        w1          : in std_logic_vector(g_data_width - 1 downto 0)
    );
end entity sym_break_w1;

architecture rtl of sym_break_w1 is


signal ready_d      : std_logic;
signal sym_break_int: std_logic;
signal cnt_w1       : integer range 0 to g_num_samples - 1 := 0;
signal nonzero_found: std_logic;

begin

    symbreak_process: process(clk, rst_n) begin
        if rst_n = '0' then
            ready_d         <= '0';
            sym_break_int   <= '0';
            cnt_w1          <= 0;
            nonzero_found   <= '0';
        elsif rising_edge(clk) then
            ready_d <= '0';

            -- start inicializa una nueva operacion, pero no valida w1.
            if start = '1' then
                sym_break_int <= '0';
                nonzero_found <= '0';
                cnt_w1        <= 0;

            elsif valid = '1' then
                -- La condicion depende exclusivamente del primer
                -- coeficiente no nulo, empezando por w1[0].
                if nonzero_found = '0' then
                    if signed(w1) > 0 then
                        sym_break_int <= '1';
                        nonzero_found <= '1';
                    elsif signed(w1) < 0 then
                        sym_break_int <= '0';
                        nonzero_found <= '1';
                    end if;
                end if;

                if cnt_w1 = g_num_samples - 1 then
                    ready_d <= '1';
                    cnt_w1  <= 0;
                else
                    cnt_w1 <= cnt_w1 + 1;
                end if;
            end if;
        end if;
    end process;

    sym_break <= sym_break_int;
    ready   <= ready_d;
    

end architecture rtl;
