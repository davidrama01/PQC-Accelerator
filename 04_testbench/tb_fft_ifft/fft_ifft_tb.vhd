library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.ENV.ALL;

entity fft_ifft_tb is
end entity fft_ifft_tb;

architecture simulation of fft_ifft_tb is
    constant C_NUM_SAMPLES : positive := 512;
    constant C_DATA_WIDTH  : positive := 32;
    constant C_ADDR_WIDTH  : positive := 9;
    constant C_CLK_PERIOD  : time := 10 ns;

    type sample_array_t is array (0 to C_NUM_SAMPLES - 1) of
        std_logic_vector(C_DATA_WIDTH - 1 downto 0);

    signal clk   : std_logic := '0';
    signal rst_n : std_logic := '0';

    signal fft_start          : std_logic := '0';
    signal fft_data_in_valid  : std_logic := '0';
    signal fft_done           : std_logic;
    signal fft_data_in        : std_logic_vector(C_DATA_WIDTH - 1 downto 0) :=
                                (others => '0');
    signal fft_data_out       : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal fft_data_out_valid : std_logic;

    signal ifft_start          : std_logic := '0';
    signal ifft_data_in_valid  : std_logic := '0';
    signal ifft_done           : std_logic;
    signal ifft_data_in        : std_logic_vector(C_DATA_WIDTH - 1 downto 0) :=
                                 (others => '0');
    signal ifft_data_out       : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal ifft_data_out_valid : std_logic;

    -- Para n=512, IFFT(FFT(a)) contiene la normalizacion 1/256. Se aplica
    -- esa escala a la entrada de la FFT para recuperar exactamente a[0]=1.
    function fft_input(index : natural) return std_logic_vector is
    begin
        if index = 0 then
            return std_logic_vector(to_signed(256, C_DATA_WIDTH));
        end if;
        return std_logic_vector(to_signed(0, C_DATA_WIDTH));
    end function;

    function expected_output(index : natural) return std_logic_vector is
    begin
        if index = 0 then
            return std_logic_vector(to_signed(1, C_DATA_WIDTH));
        end if;
        return std_logic_vector(to_signed(0, C_DATA_WIDTH));
    end function;

    -- Segundo polinomio: los 512 coeficientes son no nulos, alternan signo
    -- y tienen magnitudes entre 1 y 15.
    function second_original(index : natural) return integer is
        variable magnitude : integer;
    begin
        magnitude := (index mod 15) + 1;
        if (index mod 2) = 0 then
            return magnitude;
        end if;
        return -magnitude;
    end function;

    function second_fft_input(index : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(
            second_original(index) * 256, C_DATA_WIDTH));
    end function;
begin
    clk <= not clk after C_CLK_PERIOD / 2;

    fft_dut : entity work.fft(rtl)
        generic map (
            g_num_samples => C_NUM_SAMPLES,
            g_data_width  => C_DATA_WIDTH,
            g_addr_width  => C_ADDR_WIDTH
        )
        port map (
            clk            => clk,
            rst_n          => rst_n,
            start          => fft_start,
            data_in_valid  => fft_data_in_valid,
            done           => fft_done,
            data_in        => fft_data_in,
            data_out       => fft_data_out,
            data_out_valid => fft_data_out_valid
        );

    ifft_dut : entity work.ifft(rtl)
        generic map (
            g_num_samples => C_NUM_SAMPLES,
            g_data_width  => C_DATA_WIDTH,
            g_addr_width  => C_ADDR_WIDTH
        )
        port map (
            clk            => clk,
            rst_n          => rst_n,
            start          => ifft_start,
            data_in_valid  => ifft_data_in_valid,
            done           => ifft_done,
            data_in        => ifft_data_in,
            data_out       => ifft_data_out,
            data_out_valid => ifft_data_out_valid
        );

    stimulus : process
        variable fft_values  : sample_array_t := (others => (others => '0'));
        variable fft_count   : natural range 0 to C_NUM_SAMPLES := 0;
        variable ifft_count  : natural range 0 to C_NUM_SAMPLES := 0;
        variable expected    : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
        variable obtained_integer : integer;
        variable expected_integer : integer;
    begin
        -- Reset comun de ambos bloques.
        rst_n <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        -- Carga de la entrada escalada y ejecucion de la FFT.
        fft_start <= '1';
        wait until rising_edge(clk);
        fft_start <= '0';

        fft_data_in_valid <= '1';
        for i in 0 to C_NUM_SAMPLES - 1 loop
            fft_data_in <= fft_input(i);
            wait until rising_edge(clk);
        end loop;
        fft_data_in_valid <= '0';

        -- Almacena las 512 palabras producidas por la FFT. No se modelan
        -- memorias: el testbench utiliza las IP incluidas en Vivado.
        while fft_done = '0' loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if fft_data_out_valid = '1' then
                assert fft_count < C_NUM_SAMPLES
                    report "La FFT produjo mas de 512 salidas"
                    severity failure;
                assert not is_x(fft_data_out)
                    report "La FFT produjo bits desconocidos en el indice " &
                           integer'image(fft_count)
                    severity failure;

                fft_values(fft_count) := fft_data_out;
                fft_count := fft_count + 1;
            end if;
        end loop;

        assert fft_count = C_NUM_SAMPLES
            report "La FFT produjo " & integer'image(fft_count) &
                   " salidas; se esperaban 512"
            severity failure;

        -- Carga en la IFFT del resultado completo de la FFT.
        ifft_start <= '1';
        wait until rising_edge(clk);
        ifft_start <= '0';

        ifft_data_in_valid <= '1';
        for i in 0 to C_NUM_SAMPLES - 1 loop
            ifft_data_in <= fft_values(i);
            wait until rising_edge(clk);
        end loop;
        ifft_data_in_valid <= '0';

        -- Compara palabra a palabra con el polinomio original no escalado.
        while ifft_done = '0' loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if ifft_data_out_valid = '1' then
                assert ifft_count < C_NUM_SAMPLES
                    report "La IFFT produjo mas de 512 salidas"
                    severity failure;
                assert not is_x(ifft_data_out)
                    report "La IFFT produjo bits desconocidos en el indice " &
                           integer'image(ifft_count)
                    severity failure;

                expected := expected_output(ifft_count);
                assert ifft_data_out = expected
                    report "Diferencia FFT/IFFT en el indice " &
                           integer'image(ifft_count) &
                           ": obtenido=0x" &
                           to_hstring(to_bitvector(ifft_data_out)) &
                           ", esperado=0x" &
                           to_hstring(to_bitvector(expected))
                    severity error;

                ifft_count := ifft_count + 1;
            end if;
        end loop;

        assert ifft_count = C_NUM_SAMPLES
            report "La IFFT produjo " & integer'image(ifft_count) &
                   " salidas; se esperaban 512"
            severity failure;

        report "Prueba 1 FFT -> IFFT superada: impulso exacto"
            severity note;

        -- Segunda ejecucion completa con 512 coeficientes no nulos.
        rst_n <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst_n <= '1';
        wait until rising_edge(clk);

        fft_count := 0;
        ifft_count := 0;
        fft_values := (others => (others => '0'));

        fft_start <= '1';
        wait until rising_edge(clk);
        fft_start <= '0';

        fft_data_in_valid <= '1';
        for i in 0 to C_NUM_SAMPLES - 1 loop
            fft_data_in <= second_fft_input(i);
            wait until rising_edge(clk);
        end loop;
        fft_data_in_valid <= '0';

        while fft_done = '0' loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if fft_data_out_valid = '1' then
                assert fft_count < C_NUM_SAMPLES
                    report "La FFT produjo mas de 512 salidas en la prueba 2"
                    severity failure;
                assert not is_x(fft_data_out)
                    report "La FFT produjo bits desconocidos en la prueba 2"
                    severity failure;
                fft_values(fft_count) := fft_data_out;
                fft_count := fft_count + 1;
            end if;
        end loop;

        assert fft_count = C_NUM_SAMPLES
            report "La FFT no produjo 512 salidas en la prueba 2"
            severity failure;

        ifft_start <= '1';
        wait until rising_edge(clk);
        ifft_start <= '0';

        ifft_data_in_valid <= '1';
        for i in 0 to C_NUM_SAMPLES - 1 loop
            ifft_data_in <= fft_values(i);
            wait until rising_edge(clk);
        end loop;
        ifft_data_in_valid <= '0';

        while ifft_done = '0' loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if ifft_data_out_valid = '1' then
                assert ifft_count < C_NUM_SAMPLES
                    report "La IFFT produjo mas de 512 salidas en la prueba 2"
                    severity failure;
                assert not is_x(ifft_data_out)
                    report "La IFFT produjo bits desconocidos en la prueba 2"
                    severity failure;

                obtained_integer := to_integer(signed(ifft_data_out));
                expected_integer := second_original(ifft_count);

                -- Las ocho etapas de punto fijo truncan hacia menos infinito.
                -- La referencia software presenta un error entre -3 y 0 LSB.
                assert abs(obtained_integer - expected_integer) <= 3
                    report "Diferencia FFT/IFFT en prueba 2, indice " &
                           integer'image(ifft_count) &
                           ": obtenido=" & integer'image(obtained_integer) &
                           ", esperado=" & integer'image(expected_integer)
                    severity error;

                ifft_count := ifft_count + 1;
            end if;
        end loop;

        assert ifft_count = C_NUM_SAMPLES
            report "La IFFT no produjo 512 salidas en la prueba 2"
            severity failure;

        report "Prueba 2 FFT -> IFFT superada: 512 entradas no nulas"
            severity note;
        -- stop;
        wait;
    end process stimulus;

    timeout : process
    begin
        wait for 3 ms;
        assert false
            report "Timeout: la prueba FFT/IFFT no termino en 3 ms"
            severity failure;
    end process timeout;
end architecture simulation;
