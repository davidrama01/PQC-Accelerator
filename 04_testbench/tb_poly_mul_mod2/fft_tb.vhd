library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.ENV.ALL;

entity fft_tb is
end entity fft_tb;

architecture simulation of fft_tb is
    constant C_NUM_SAMPLES : positive := 512;
    constant C_DATA_WIDTH  : positive := 32;
    constant C_ADDR_WIDTH  : positive := 9;
    constant C_CLK_PERIOD  : time := 10 ns;

    signal clk            : std_logic := '0';
    signal rst_n          : std_logic := '0';
    signal start          : std_logic := '0';
    signal done           : std_logic;
    signal data_in        : std_logic_vector(C_DATA_WIDTH - 1 downto 0) :=
                            (others => '0');
    signal data_out       : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal data_out_valid : std_logic;
begin
    clk <= not clk after C_CLK_PERIOD / 2;

    -- Se instancia solamente la FFT. Las instancias blk_mem_gen_1 y
    -- blk_mem_gen_2 que contiene el DUT deben proceder del proyecto Vivado.
    dut : entity work.fft(rtl)
        generic map (
            g_num_samples => C_NUM_SAMPLES,
            g_data_width  => C_DATA_WIDTH,
            g_addr_width  => C_ADDR_WIDTH
        )
        port map (
            clk            => clk,
            rst_n          => rst_n,
            start          => start,
            done           => done,
            data_in        => data_in,
            data_out       => data_out,
            data_out_valid => data_out_valid
        );

    stimulus : process
        variable output_count : natural := 0;
        variable nonzero_seen : boolean := false;
    begin
        -- Reset sincrono, activo a nivel bajo.
        rst_n <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        -- Pulso de inicio de un ciclo.
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Vector nulo. Permite comprobar el recorrido completo utilizando
        -- la RAM y la ROM reales: su transformada tambien debe ser nula.
        -- La interfaz actual consume un dato cada dos ciclos, en los estados
        -- ST_INIT_RAM y ST_COMMIT_INIT.
        for i in 0 to C_NUM_SAMPLES - 1 loop
            data_in <= (others => '0');
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end loop;

        -- Cuenta y comprueba las palabras entregadas por la FFT.
        while done = '0' loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if data_out_valid = '1' then
                assert output_count < C_NUM_SAMPLES
                    report "La FFT produjo mas de 512 resultados"
                    severity failure;

                assert data_out = (data_out'range => '0')
                    report "Salida no nula en el indice " &
                           integer'image(output_count) &
                           ": 0x" & to_hstring(data_out)
                    severity error;

                output_count := output_count + 1;
            end if;
        end loop;

        assert output_count = C_NUM_SAMPLES
            report "Se recibieron " & integer'image(output_count) &
                   " resultados nulos; se esperaban 512"
            severity failure;

        report "Prueba 1 finalizada: 512 salidas nulas correctas"
            severity note;

        -- Reinicia el bloque para ejecutar una segunda transformada.
        rst_n <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        output_count := 0;
        nonzero_seen := false;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        -- Patron determinista no nulo con coeficientes positivos y negativos.
        for i in 0 to C_NUM_SAMPLES - 1 loop
            data_in <= std_logic_vector(to_signed(
                ((i * 37 + 11) mod 257) - 128, C_DATA_WIDTH));
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end loop;

        while done = '0' loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if data_out_valid = '1' then
                assert output_count < C_NUM_SAMPLES
                    report "La FFT produjo mas de 512 resultados"
                    severity failure;

                assert not is_x(data_out)
                    report "La salida contiene bits desconocidos en el indice " &
                           integer'image(output_count)
                    severity failure;

                if data_out /= (data_out'range => '0') then
                    nonzero_seen := true;
                end if;

                output_count := output_count + 1;
            end if;
        end loop;

        assert output_count = C_NUM_SAMPLES
            report "Se recibieron " & integer'image(output_count) &
                   " resultados en la segunda prueba; se esperaban 512"
            severity failure;

        assert nonzero_seen
            report "La FFT del patron no nulo produjo solo ceros"
            severity failure;

        report "Prueba 2 finalizada: patron no nulo, 512 salidas validas"
            severity note;

        -- stop;
        wait;
    end process stimulus;

    timeout : process
    begin
        wait for 1 ms;
        assert false
            report "Timeout: la FFT no termino en 1 ms"
            severity failure;
    end process timeout;
end architecture simulation;
