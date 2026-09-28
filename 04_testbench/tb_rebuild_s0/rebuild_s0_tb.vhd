library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.ENV.ALL;

entity rebuild_s0_tb is
end entity rebuild_s0_tb;

architecture simulation of rebuild_s0_tb is
    constant C_NUM_SAMPLES : positive := 512;
    constant C_DATA_WIDTH  : positive := 32;
    constant C_ADDR_WIDTH  : positive := 9;
    constant C_CLK_PERIOD  : time := 10 ns;
    constant C_TIMEOUT     : positive := 1000000;

    signal clk            : std_logic := '0';
    signal rst_n          : std_logic := '0';
    signal start          : std_logic := '0';
    signal data_in_valid  : std_logic := '0';
    signal done           : std_logic;
    signal data_q00       : std_logic_vector(C_DATA_WIDTH - 1 downto 0) :=
                            (others => '0');
    signal data_q01       : std_logic_vector(C_DATA_WIDTH - 1 downto 0) :=
                            (others => '0');
    signal data_w1        : std_logic_vector(C_DATA_WIDTH - 1 downto 0) :=
                            (others => '0');
    signal data_h0        : std_logic_vector(C_NUM_SAMPLES - 1 downto 0) :=
                            (others => '0');
    signal data_out       : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal data_out_valid : std_logic;
    signal error          : std_logic;

    function h0_test_1(index : natural) return std_logic is
    begin
        if (index mod 3) = 0 or (index mod 11) = 0 then
            return '1';
        end if;
        return '0';
    end function;

    function h0_test_2(index : natural) return std_logic is
    begin
        if (index mod 2) = 1 or (index mod 13) = 0 then
            return '1';
        end if;
        return '0';
    end function;
begin
    clk <= not clk after C_CLK_PERIOD / 2;

    dut : entity work.rebuild_s0(rtl)
        generic map (
            g_num_samples => C_NUM_SAMPLES,
            g_data_width  => C_DATA_WIDTH,
            g_addr_width  => C_ADDR_WIDTH
        )
        port map (
            clk            => clk,
            rst_n          => rst_n,
            start          => start,
            data_in_valid  => data_in_valid,
            done           => done,
            data_q00       => data_q00,
            data_q01       => data_q01,
            data_w1        => data_w1,
            data_h0        => data_h0,
            data_out       => data_out,
            data_out_valid => data_out_valid,
            error          => error
        );

    stimulus : process
        variable output_count : natural range 0 to C_NUM_SAMPLES := 0;
        variable saw_done     : boolean := false;
        variable h0_values    : std_logic_vector(C_NUM_SAMPLES - 1 downto 0);
        variable expected     : integer;
        variable obtained     : integer;
    begin
        -----------------------------------------------------------------------
        -- Reset
        -----------------------------------------------------------------------
        rst_n <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- Test 1: q00[0]=1, q01=0 and w1=0.
        --
        -- Xre=Xim=0, therefore qhat01=0 and t=IFFT(qhat01)=0.
        -- Since c_s0*h0 is smaller than 2*c_q00, z=0 and w0=h0.
        -----------------------------------------------------------------------
        for i in 0 to C_NUM_SAMPLES - 1 loop
            h0_values(i) := h0_test_1(i);
        end loop;
        data_h0 <= h0_values;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        data_in_valid <= '1';
        for i in 0 to C_NUM_SAMPLES - 1 loop
            if i = 0 then
                data_q00 <= std_logic_vector(to_signed(1, C_DATA_WIDTH));
            else
                data_q00 <= (others => '0');
            end if;
            data_q01 <= (others => '0');
            data_w1  <= (others => '0');
            wait until rising_edge(clk);
        end loop;
        data_in_valid <= '0';

        output_count := 0;
        saw_done := false;
        for cycle in 0 to C_TIMEOUT - 1 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            assert not is_x(data_out_valid)
                report "data_out_valid contiene bits desconocidos"
                severity failure;
            assert not is_x(done)
                report "done contiene bits desconocidos"
                severity failure;
            assert not is_x(error)
                report "error contiene bits desconocidos"
                severity failure;

            if data_out_valid = '1' then
                assert output_count < C_NUM_SAMPLES
                    report "RebuildS0 produjo mas de 512 coeficientes"
                    severity failure;
                assert not is_x(data_out)
                    report "RebuildS0 produjo bits desconocidos en la salida " &
                           integer'image(output_count)
                    severity failure;

                if h0_values(output_count) = '1' then
                    expected := 1;
                else
                    expected := 0;
                end if;
                obtained := to_integer(signed(data_out));

                assert obtained = expected
                    report "Diferencia en prueba 1, indice " &
                           integer'image(output_count) &
                           ": obtenido=" & integer'image(obtained) &
                           ", esperado=" & integer'image(expected)
                    severity error;

                output_count := output_count + 1;
            end if;

            if done = '1' then
                saw_done := true;
                exit;
            end if;
        end loop;

        assert saw_done
            report "Timeout esperando done en la prueba 1"
            severity failure;
        assert error = '0'
            report "RebuildS0 activo error en una entrada valida"
            severity failure;
        assert output_count = C_NUM_SAMPLES
            report "RebuildS0 produjo " & integer'image(output_count) &
                   " salidas; se esperaban 512"
            severity failure;

        report "Prueba 1 superada: salida w0 igual a h0" severity note;

        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- Test 2: q00[0] negativo. Debe terminar con error y sin salida.
        -----------------------------------------------------------------------
        data_h0 <= (others => '0');
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        data_q00 <= std_logic_vector(to_signed(-1, C_DATA_WIDTH));
        data_q01 <= (others => '0');
        data_w1  <= (others => '0');
        data_in_valid <= '1';
        wait until rising_edge(clk);
        data_in_valid <= '0';

        saw_done := false;
        for cycle in 0 to 20 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            assert data_out_valid = '0'
                report "Se produjo una salida valida despues de q00[0] < 0"
                severity failure;

            if done = '1' then
                assert error = '1'
                    report "done se activo sin error para q00[0] < 0"
                    severity failure;
                saw_done := true;
                exit;
            end if;
        end loop;

        assert saw_done
            report "No se recibio done para q00[0] < 0"
            severity failure;

        report "Prueba 2 superada: deteccion de q00[0] negativo" severity note;

        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- Test 3: ejecucion valida despues de ST_ERROR. Incluye huecos en
        -- data_in_valid para comprobar que el contador solo consume validos.
        -----------------------------------------------------------------------
        for i in 0 to C_NUM_SAMPLES - 1 loop
            h0_values(i) := h0_test_2(i);
        end loop;
        data_h0 <= h0_values;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        for i in 0 to C_NUM_SAMPLES - 1 loop
            if (i mod 17) = 0 then
                data_in_valid <= '0';
                wait until rising_edge(clk);
            end if;

            if i = 0 then
                data_q00 <= std_logic_vector(to_signed(1, C_DATA_WIDTH));
            else
                data_q00 <= (others => '0');
            end if;
            data_q01 <= (others => '0');
            data_w1  <= (others => '0');
            data_in_valid <= '1';
            wait until rising_edge(clk);
        end loop;
        data_in_valid <= '0';

        output_count := 0;
        saw_done := false;
        for cycle in 0 to C_TIMEOUT - 1 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if data_out_valid = '1' then
                assert output_count < C_NUM_SAMPLES
                    report "RebuildS0 produjo mas de 512 coeficientes en prueba 3"
                    severity failure;
                assert not is_x(data_out)
                    report "Salida desconocida en prueba 3"
                    severity failure;

                if h0_values(output_count) = '1' then
                    expected := 1;
                else
                    expected := 0;
                end if;
                obtained := to_integer(signed(data_out));

                assert obtained = expected
                    report "Diferencia en prueba 3, indice " &
                           integer'image(output_count) &
                           ": obtenido=" & integer'image(obtained) &
                           ", esperado=" & integer'image(expected)
                    severity error;

                output_count := output_count + 1;
            end if;

            if done = '1' then
                saw_done := true;
                exit;
            end if;
        end loop;

        assert saw_done
            report "Timeout esperando done en la prueba 3"
            severity failure;
        assert error = '0'
            report "Error inesperado en la ejecucion posterior a ST_ERROR"
            severity failure;
        assert output_count = C_NUM_SAMPLES
            report "La prueba 3 produjo " & integer'image(output_count) &
                   " salidas; se esperaban 512"
            severity failure;

        report "Prueba 3 superada: recuperacion despues de ST_ERROR"
            severity note;
        report "Todas las pruebas de RebuildS0 han finalizado correctamente"
            severity note;

        stop;
        wait;
    end process stimulus;
end architecture simulation;
