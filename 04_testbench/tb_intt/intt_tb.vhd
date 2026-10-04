library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity intt_tb is
end entity;

architecture simulation of intt_tb is
    signal clk : std_logic := '0';
    type modulus_array_t is array (0 to 1) of positive;
    constant MODULI : modulus_array_t := (2147473409, 2147389441);
    signal tests_passed : boolean_vector(0 to 3) := (others => false);
begin
    clk <= not clk after 5 ns;
    modules : for lane in 0 to 3 generate
        constant g_modulus : positive := MODULI(lane mod 2);
        constant MODULE_NAME : string := "Lane " & integer'image(lane);
    function vector_filename return string is
    begin
        if g_modulus = 2147473409 then
            return "vectors_p1_" & integer'image(lane / 2) & ".txt";
        elsif g_modulus = 2147389441 then
            return "vectors_p2_" & integer'image(lane / 2) & ".txt";
        end if;
        assert false report MODULE_NAME & ": " & "g_modulus debe ser P1 o P2" severity failure;
        return "";
    end function;
    constant N : positive := 512;
    signal rst_n, start, data_in_valid : std_logic := '0';
    signal data_in : std_logic_vector(31 downto 0) := (others => '0');
    signal data_out : std_logic_vector(31 downto 0);
    signal done, data_out_valid : std_logic;
    signal inverse_input : std_logic_vector(31 downto 0);
    signal inverse_valid : std_logic;
    begin
        direct_inverse : if lane < 2 generate
            inverse_input <= data_in;
            inverse_valid <= data_in_valid;
        end generate;
        roundtrip : if lane >= 2 generate
            forward_dut : entity work.ntt(rtl)
                generic map (g_modulus => g_modulus)
                port map (clk => clk, rst_n => rst_n, start => start,
                          data_in_valid => data_in_valid, data_in => data_in,
                          data_out => inverse_input, data_out_valid => inverse_valid, done => open);
        end generate;
        dut : entity work.intt(rtl)
            generic map (g_modulus => g_modulus)
            port map (clk => clk, rst_n => rst_n, start => start,
                      data_in_valid => inverse_valid, data_in => inverse_input,
                      data_out => data_out, data_out_valid => data_out_valid, done => done);

    stimulus : process
        file vectors : text open read_mode is vector_filename;
        type samples_t is array(0 to N-1) of integer;
        variable inputs, expected : samples_t;
        variable row : line;
        variable count : natural;
        variable finished : boolean;

        procedure reset_dut is
        begin
            wait until falling_edge(clk);
            rst_n <= '0';
            start <= '0';
            data_in_valid <= '0';
            for k in 1 to 3 loop
                wait until rising_edge(clk);
                wait for 1 ns;
                assert data_out_valid = '0' and done = '0'
                    report MODULE_NAME & ": " & "Salida activa durante reset" severity failure;
            end loop;
            wait until falling_edge(clk);
            rst_n <= '1';
            wait until falling_edge(clk);
        end procedure;

        procedure launch is
        begin
            start <= '1';
            wait until falling_edge(clk);
            start <= '0';
        end procedure;
    begin
        reset_dut;
        -- Aborta una carga parcial y verifica recuperacion tras reset.
        launch;
        data_in_valid <= '1';
        data_in <= std_logic_vector(to_unsigned(g_modulus-1, 32));
        for k in 1 to 19 loop wait until falling_edge(clk); end loop;
        reset_dut;
        -- Aborta tambien una operacion que ya esta calculando mariposas.
        launch;
        data_in_valid <= '1';
        for k in 1 to N loop wait until falling_edge(clk); end loop;
        data_in_valid <= '0';
        for k in 1 to 37 loop wait until falling_edge(clk); end loop;
        reset_dut;

        -- Seis vectores consecutivos, sin reset entre ellos.
        for test in 0 to 5 loop
            for k in 0 to N-1 loop
                readline(vectors, row);
                read(row, inputs(k)); read(row, expected(k));
            end loop;
            launch;
            for k in 0 to N-1 loop
                if test mod 2 = 1 and (k mod 17 = 0 or k mod 31 = 0) then
                    data_in_valid <= '0';
                    -- Mantiene el dato anterior durante la pausa de carga.
                    wait until rising_edge(clk);
                    wait for 1 ns;
                    assert done = '0' and data_out_valid = '0'
                        report MODULE_NAME & ": " & "Salida durante pausa de carga" severity failure;
                    wait until falling_edge(clk);
                end if;
                data_in_valid <= '1';
                data_in <= std_logic_vector(to_unsigned(inputs(k), 32));
                wait until rising_edge(clk);
                wait for 1 ns;
                assert done = '0' and data_out_valid = '0'
                    report MODULE_NAME & ": " & "Salida prematura" severity failure;
                wait until falling_edge(clk);
            end loop;
            data_in_valid <= '0';
            count := 0; finished := false;
            for cycle in 0 to 100000 loop
                wait until rising_edge(clk);
                wait for 1 ns;
                assert not is_x(done) and not is_x(data_out_valid)
                    report MODULE_NAME & ": " & "Control desconocido" severity failure;
                if data_out_valid = '1' then
                    assert count < N report MODULE_NAME & ": " & "Demasiadas salidas" severity failure;
                    assert not is_x(data_out) report MODULE_NAME & ": " & "Dato desconocido" severity failure;
                    assert unsigned(data_out) < to_unsigned(g_modulus, 32)
                        report MODULE_NAME & ": " & "Residuo fuera de rango" severity failure;
                    assert to_integer(unsigned(data_out)) = expected(count)
                        report MODULE_NAME & ": " & "INTT prueba " & integer'image(test) &
                               ", indice " & integer'image(count) &
                               ": esperado=" & integer'image(expected(count)) &
                               ", obtenido=" & integer'image(to_integer(unsigned(data_out)))
                        severity failure;
                    count := count + 1;
                elsif count > 0 and count < N then
                    assert false report MODULE_NAME & ": " & "Hueco en la salida secuencial" severity failure;
                end if;
                if done = '1' then
                    assert count = N and data_out_valid = '1'
                        report MODULE_NAME & ": " & "done no coincide con la ultima salida" severity failure;
                    finished := true;
                    exit;
                end if;
            end loop;
            assert finished report MODULE_NAME & ": " & "Timeout INTT" severity failure;
            for k in 1 to 3 loop
                wait until rising_edge(clk); wait for 1 ns;
                assert done = '0' and data_out_valid = '0'
                    report MODULE_NAME & ": " & "Salida extra despues de done" severity failure;
            end loop;
            report MODULE_NAME & ": " & "INTT prueba " & integer'image(test) & ": 512 resultados correctos" severity note;
            wait until falling_edge(clk);
        end loop;
        assert endfile(vectors) report MODULE_NAME & ": " & "Vectores sin consumir" severity failure;
        report MODULE_NAME & ": todas las pruebas superadas" severity note;
        tests_passed(lane) <= true;
        wait;
    end process;
    end generate modules;

    completion : process
    begin
        wait until tests_passed(0) and tests_passed(1) and tests_passed(2) and tests_passed(3);
        report "INTT: P1 y P2, todas las pruebas superadas" severity note;
        stop;
        wait;
    end process;
end architecture;
