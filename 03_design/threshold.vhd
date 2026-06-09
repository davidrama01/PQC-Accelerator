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
        x0          : in t_poly_coef(g_num_samples - 1 downto 0)(g_data_width - 1 downto 0);
        x1          : in t_poly_coef(g_num_samples - 1 downto 0)(g_data_width - 1 downto 0);
        verify      : out std_logic;
    );
end entity threshold;

architecture rtl of threshold is

signal enable : std_logic;
signal enable_d : std_logic;
signal index_counter : integer range 0 to 1024;
signal y : signed(g_data_width - 1 downto 0);
signal acc0 : signed(g_data_width - 1 downto 0);
signal acc1 : signed(g_data_width - 1 downto 0);
signal flag_end_mul : std_logic;
signal flag_end_sum : std_logic;
signal verify_internal : std_logic;
signal done_d : std_logic;
    
begin

    norm_process: process(clk, rst_n) begin
        if rst_n = '0' then
            enable <= '0';
            enable_d <= '0';
            verify_internal <= '0';
            done_d <= '0';
            flag_end_mul <= '0';
            flag_end_sum <= '0';
            index_counter <= 0;
            y <= (others => '0');
            acc0 <= (others => '0');
            acc1 <= (others => '0');
        elsif rising_edge(clk) then
            enable_d <= enable; -- Registro para detectar el flanco de start
            flag_end_mul <= '0'; -- Reiniciar la bandera al inicio de cada ciclo
            flag_end_sum <= '0'; -- Reiniciar la bandera al inicio de cada ciclo
            verify_internal <= '0'; -- Reiniciar la señal de verificación al inicio de cada ciclo
            done_d <= '0'; -- Reiniciar la señal de done al inicio de cada ciclo
            if start = '1' then
                enable <= '1'; -- Habilitar el proceso de cálculo
                index_counter <= 0; -- Reiniciar el contador de índices
                y <= (others => '0'); -- Reiniciar el resultado
                acc0 <= (others => '0'); -- Reiniciar el acumulador 0
                acc1 <= (others => '0'); -- Reiniciar el acumulador 1
            elsif enable = '1' then
                if index_counter < g_num_samples then
                    acc0 <= acc0 + x0(index_counter) * x0(index_counter);
                    acc1 <= acc1 + x1(index_counter) * x1(index_counter);
                    index_counter <= index_counter + 1;
                end if;
            end if;
            if flag_end_mul = '1' then
                y <= acc0 + acc1;
                flag_end_sum <= '1';
            end if;
            if flag_end_sum = '1' then
                done_d <= '1';
                enable <= '0'; -- Deshabilitar el proceso de cálculo
                y <= (others => '0'); -- Reiniciar el resultado
                acc0 <= (others => '0'); -- Reiniciar el acumulador 0
                acc1 <= (others => '0'); -- Reiniciar el acumulador 1
                index_counter <= 0; -- Reiniciar el contador de índices
                if y <= c_threshold_verify then
                    verify_internal <= '1';
                else
                    verify_internal <= '0';
                end if;
                flag_end_sum <= '0'; -- Reiniciar la bandera para la siguiente operación
            end if;
        end if;
    end process;
    
    verify <= verify_internal;
    done <= done_d;

end architecture rtl;