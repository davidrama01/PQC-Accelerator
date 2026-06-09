library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

-- Testbench entity
entity tb_poly_mul_mod2 is
end entity tb_poly_mul_mod2;

architecture rtl of tb_poly_mul_mod2 is

    -- Component declaration
    component poly_mul_mod2
        generic (
            g_num_samples : integer := 32;
            g_num_phases : integer := 8
        );
        port (
            clk : in std_logic;
            rst_n : in std_logic;
            start : in std_logic;
            done : out std_logic;
            data_a : in std_logic_vector(g_num_samples - 1 downto 0);
            data_b : in std_logic_vector(g_num_samples - 1 downto 0);
            result : out std_logic_vector(g_num_samples - 1 downto 0)
        );
    end component;

    constant N : integer := 32;
    -- Signals
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal start : std_logic := '0';
    signal done : std_logic;
    signal data_a : std_logic_vector(31 downto 0) := (others => '0');
    signal data_b : std_logic_vector(31 downto 0) := (others => '0');
    signal result : std_logic_vector(31 downto 0);
    
    -- CSV reading function
function read_vector_from_csv(line_str : string; field : integer)
return std_logic_vector is

    variable v : std_logic_vector(N-1 downto 0) := (others => '0');
    variable field_idx : integer := 0;
    variable bit_idx   : integer := 0;

begin

    for i in line_str'range loop

        if line_str(i) = ',' then
            field_idx := field_idx + 1;
            bit_idx := 0;

        elsif field_idx = field then

            if line_str(i) = '0' or line_str(i) = '1' then

                if bit_idx < N then
                    -- IMPORTANTE: MSB a la izquierda
                    if line_str(i) = '0' then
                        v(N-1 - bit_idx) := '0';
                    elsif line_str(i) = '1' then
                        v(N-1 - bit_idx) := '1';
                    end if;
                    bit_idx := bit_idx + 1;
                end if;

            end if;

        end if;

    end loop;

    return v;

end function;

begin
    -- Instantiate UUT
    dut: poly_mul_mod2
        generic map (
            g_num_samples => 32, 
            g_num_phases => 8
        ) port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            done => done,
            data_a => data_a,
            data_b => data_b,
            result => result
        );

    -- Clock generation
    clk_process : process
    begin
        clk <= '0';
        wait for 5 ns;
        clk <= '1';
        wait for 5 ns;
    end process;

    -- Stimulus process
    stimulus_process : process
        file test_file : text;
        variable line_in : line;
        variable line_str : string(1 to 2048);
        variable line_len : integer;
        variable a_vec : std_logic_vector(N-1 downto 0);
        variable b_vec : std_logic_vector(N-1 downto 0);
        variable exp_result : std_logic_vector(N-1 downto 0);
        variable test_count : integer := 0;
        variable pass_count : integer := 0;
        variable fail_count : integer := 0;
    begin
        -- Reset
        rst_n <= '0';
        start <= '0';
        wait for 20 ns;
        rst_n <= '1';
        wait for 20 ns;

        -- Open test vector file
        file_open(test_file, "polymulmod2_vectors_N32.csv", read_mode);

        -- Read test vectors from CSV
        while not endfile(test_file) loop
            readline(test_file, line_in);
            line_str(1 to line_in'length) := line_in.all;
            line_len := line_in'length;

            -- Skip empty lines or comments
            if line_len > 0 and line_str(1) /= '#' then
                test_count := test_count + 1;

                -- Parse fields: a, b, expected_result
                a_vec := read_vector_from_csv(line_str(1 to line_len), 0);
                b_vec := read_vector_from_csv(line_str(1 to line_len), 1);
                exp_result := read_vector_from_csv(line_str(1 to line_len), 2);

                -- Load inputs into DUT
                data_a <= a_vec;
                data_b <= b_vec;
                wait for 10 ns;

                -- Activate start signal
                start <= '1';
                wait for 100 ns;
                start <= '0';

                -- Wait for done signal to be activated
                wait until done = '1';
                wait for 100 ns;

                -- Verify result
                if result = exp_result then
                    report "Test " & integer'image(test_count) & " PASSED" severity note;
                    pass_count := pass_count + 1;
                else
                    report "Test " & integer'image(test_count) & " FAILED: result mismatch" severity error;
                    fail_count := fail_count + 1;
                end if;

                -- Wait before next test
                wait for 20 ns;
            end if;
        end loop;

        file_close(test_file);

        -- Print summary
        report "Test Summary: " & integer'image(pass_count) & " passed, " &
               integer'image(fail_count) & " failed out of " &
               integer'image(test_count) & " tests" severity note;

        wait;
    end process;
end architecture rtl;