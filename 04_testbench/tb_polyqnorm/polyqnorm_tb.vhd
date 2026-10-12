library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity polyqnorm_tb is
    generic (
        g_vectors_dir : string := "C:/David/TFM/hawk_fw/04_testbench/tb_polyqnorm/"
    );
end entity;
architecture simulation of polyqnorm_tb is
    signal clk : std_logic := '0';
    type primes_t is array(0 to 1) of positive;
    constant PRIMES : primes_t := (2147473409, 2147389441);
    signal passed : boolean_vector(0 to 1) := (others => false);
begin
    clk <= not clk after 5 ns;
    modules : for lane in 0 to 1 generate
        constant P : positive := PRIMES(lane);
        constant LABEL_P : string := "P" & integer'image(lane+1);
        signal rst_n, start, valid_in : std_logic := '0';
        signal q00, q01, w0, w1 : std_logic_vector(31 downto 0) := (others => '0');
        signal result : std_logic_vector(31 downto 0);
        signal done, valid_out, dut_error : std_logic;
    begin
        dut : entity work.polyqnorm(rtl)
            generic map (g_modulus => P)
            port map (clk => clk, rst_n => rst_n, start => start, data_in_valid => valid_in,
                      data_q00 => q00, data_q01 => q01, data_w0 => w0, data_w1 => w1,
                      data_out => result, data_out_valid => valid_out, done => done, error => dut_error);
        stimulus : process
            constant VECTOR_FILE : string := "polyqnorm_p" & integer'image(lane+1) & ".txt";
            file vectors : text;
            variable open_status : file_open_status;
            variable row : line;
            variable a, b, c, d, expected, expected_error : integer;
            variable outputs : natural;
            variable finished : boolean;
            procedure reset_dut is
            begin
                wait until falling_edge(clk);
                rst_n <= '0'; start <= '0'; valid_in <= '0';
                for cycle in 1 to 3 loop
                    wait until rising_edge(clk); wait for 1 ns;
                    assert done = '0' and valid_out = '0' and dut_error = '0'
                        report LABEL_P & ": salida durante reset" severity failure;
                end loop;
                wait until falling_edge(clk); rst_n <= '1';
                wait until falling_edge(clk);
            end procedure;
            procedure launch is
            begin
                start <= '1'; wait until falling_edge(clk); start <= '0';
            end procedure;
        begin
            -- El script copia los vectores al directorio de simulacion.
            -- En Vivado pueden permanecer junto al testbench: usar la ruta
            -- configurable si no estan en el directorio de trabajo de XSim.
            file_open(open_status, vectors, VECTOR_FILE, read_mode);
            if open_status /= open_ok then
                file_open(open_status, vectors, g_vectors_dir & VECTOR_FILE, read_mode);
            end if;
            if open_status /= open_ok then
                assert false
                    report "No se pudo abrir " & VECTOR_FILE & " ni " &
                           g_vectors_dir & VECTOR_FILE &
                           ". Revisa g_vectors_dir o anade los TXT como Data Files."
                    severity failure;
                wait;
            end if;
            reset_dut;
            -- Reset mientras la inversion modular esta en curso.
            launch;
            valid_in <= '1';
            q01 <= std_logic_vector(to_unsigned(4,32));
            w0 <= std_logic_vector(to_unsigned(2,32));
            w1 <= std_logic_vector(to_unsigned(3,32));
            for i in 0 to 511 loop
                if i=0 then q00 <= std_logic_vector(to_unsigned(1,32));
                else q00 <= (others => '0'); end if;
                wait until falling_edge(clk);
            end loop;
            valid_in <= '0';
            for cycle in 1 to 30000 loop wait until falling_edge(clk); end loop;
            reset_dut;

            for test in 0 to 7 loop
                readline(vectors,row); read(row,expected_error); read(row,expected);
                launch;
                for i in 0 to 511 loop
                    readline(vectors,row); read(row,a); read(row,b); read(row,c); read(row,d);
                    if test mod 2 = 1 and i mod 17 = 0 then
                        valid_in <= '0'; -- Conserva datos durante las pausas.
                        wait until falling_edge(clk);
                    end if;
                    q00 <= std_logic_vector(to_unsigned(a,32));
                    q01 <= std_logic_vector(to_unsigned(b,32));
                    w0 <= std_logic_vector(to_unsigned(c,32));
                    w1 <= std_logic_vector(to_unsigned(d,32));
                    valid_in <= '1';
                    wait until rising_edge(clk); wait for 1 ns;
                    assert done = '0' and valid_out = '0'
                        report LABEL_P & ": terminacion prematura" severity failure;
                    wait until falling_edge(clk);
                end loop;
                valid_in <= '0'; outputs := 0; finished := false;
                for cycle in 0 to 300000 loop
                    wait until rising_edge(clk); wait for 1 ns;
                    assert not is_x(done) and not is_x(valid_out) and not is_x(dut_error)
                        report LABEL_P & ": control desconocido" severity failure;
                    if valid_out = '1' then
                        outputs := outputs+1;
                        assert expected_error = 0 and outputs = 1 and done = '1'
                            report LABEL_P & ": salida inesperada" severity failure;
                        assert not is_x(result)
                            report LABEL_P & ": resultado desconocido" severity failure;
                        assert unsigned(result) = to_unsigned(expected,32)
                            report LABEL_P & " test=" & integer'image(test) &
                                   " esperado=" & integer'image(expected) &
                                   " obtenido=" & integer'image(to_integer(unsigned(result))) severity failure;
                    end if;
                    if done='1' then
                        if expected_error=1 then
                            assert dut_error='1' and outputs=0
                                report LABEL_P & ": error no detectado" severity failure;
                        else
                            assert dut_error='0' and outputs=1
                                report LABEL_P & ": falta resultado" severity failure;
                        end if;
                        finished := true; exit;
                    end if;
                end loop;
                assert finished report LABEL_P & ": timeout" severity failure;
                for cycle in 1 to 3 loop
                    wait until rising_edge(clk); wait for 1 ns;
                    assert done='0' and valid_out='0'
                        report LABEL_P & ": pulsos extra" severity failure;
                end loop;
                report LABEL_P & " PolyQnorm test " & integer'image(test) & " OK" severity note;
                wait until falling_edge(clk);
            end loop;
            assert endfile(vectors) report "Vectores sobrantes" severity failure;
            passed(lane) <= true; wait;
        end process;
    end generate;
    completion : process
    begin
        wait until passed(0) and passed(1);
        report "PolyQnorm: P1 y P2 superados" severity note;
        stop; wait;
    end process;
end architecture;
