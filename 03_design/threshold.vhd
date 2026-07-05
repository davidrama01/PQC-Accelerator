library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity threshold is
    generic (
        g_num_samples : integer := 512;
        g_data_width : integer := 16
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        x0          : in std_logic_vector(g_data_width - 1 downto 0);
        x1          : in std_logic_vector(g_data_width - 1 downto 0);
        verify      : out std_logic
    );
end entity threshold;

architecture rtl of threshold is

signal enable           : std_logic;
signal flag_end_mul     : std_logic;
signal flag_end_sum     : std_logic;
signal verify_internal  : std_logic;
signal done_d           : std_logic;
signal index_counter    : integer range 0 to 1024;
signal y                : signed(40 downto 0);
signal acc0             : signed(40 downto 0);
signal acc1             : signed(40 downto 0);
    
begin

    norm_process: process(clk, rst_n) begin
        if rst_n = '0' then
            enable          <= '0';
            verify_internal <= '0';
            done_d          <= '0';
            flag_end_mul    <= '0';
            flag_end_sum    <= '0';
            index_counter   <= 0;
            y               <= (others => '0');
            acc0            <= (others => '0');
            acc1            <= (others => '0');
        elsif rising_edge(clk) then
            verify_internal <= '0'; -- Reiniciar la señal de verificación al inicio de cada ciclo
            done_d          <= '0'; -- Reiniciar la señal de done al inicio de cada ciclo
            if start = '1' then
                enable <= '1'; -- Habilitar el proceso de cálculo
                index_counter <= 0; -- Reiniciar el contador de índices
                y <= (others => '0'); -- Reiniciar el resultado
                acc0 <= (others => '0'); -- Reiniciar el acumulador 0
                acc1 <= (others => '0'); -- Reiniciar el acumulador 1
                flag_end_mul <= '0'; -- Reiniciar la bandera de fin de multiplicación
                flag_end_sum <= '0'; -- Reiniciar la bandera de fin de suma
            elsif enable = '1' then
                if index_counter < g_num_samples then
                    acc0 <= acc0 + resize((signed(x0) * signed(x0)),acc0'length);
                    acc1 <= acc1 + resize((signed(x1) * signed(x1)),acc1'length);
                    index_counter <= index_counter + 1;
                    if index_counter = g_num_samples - 1 then
                        flag_end_mul <= '1';
                    end if;
                end if;
                if flag_end_mul = '1' then
                    y <= acc0 + acc1;
                    flag_end_mul <= '0'; -- Reiniciar la bandera de fin de multiplicación
                    flag_end_sum <= '1';
                end if;
                if flag_end_sum = '1' then
                    done_d <= '1';
                    flag_end_sum <= '0'; -- Reiniciar la bandera de fin de suma
                    enable <= '0'; -- Deshabilitar el proceso de cálculo
                    acc0 <= (others => '0'); -- Reiniciar el acumulador 0
                    acc1 <= (others => '0'); -- Reiniciar el acumulador 1
                    index_counter <= 0; -- Reiniciar el contador de índices
                    if y <= c_threshold_verify then
                        verify_internal <= '1';
                    else
                        verify_internal <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    verify <= verify_internal;
    done <= done_d;

end architecture rtl;