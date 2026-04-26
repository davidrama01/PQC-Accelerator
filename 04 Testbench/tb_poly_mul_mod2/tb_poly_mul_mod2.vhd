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
            N : integer := 32;
            P : integer := 8
        );
        port (
            clk : in std_logic;
            rst_n : in std_logic;
            start : in std_logic;
            done : out std_logic;
            data_a : in std_logic_vector(N-1 downto 0);
            data_b : in std_logic_vector(N-1 downto 0);
            result : out std_logic_vector(N-1 downto 0)
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
    function read_vector_from_csv(line_str : string; field : integer) return std_logic_vector is
        variable v : std_logic_vector(N-1 downto 0) := (others => '0');
        variable idx : integer := 0;
        variable field_idx : integer := 0;
        variable bit_idx : integer := 0;
        variable in_field : boolean := false;
    begin
        for i in line_str'range loop
            if line_str(i) = ',' then
                if in_field then
                    field_idx := field_idx + 1;
                    in_field := false;
                    bit_idx := 0;
                end if;
            elsif field_idx = field then
                in_field := true;
                if line_str(i) = '1' then
                    v(bit_idx) := '1';
                elsif line_str(i) = '0' then
                    v(bit_idx) := '0';
                end if;
                bit_idx := bit_idx + 1;
            elsif not in_field and line_str(i) /= ' ' then
                if line_str(i) /= ',' then
                    field_idx := field_idx + 1;
                end if;
            end if;
        end loop;
        return v;
    end function;

begin
    -- Instantiate UUT
    dut: poly_mul_mod2
        generic map (
            N => 32, 
            P => 8
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
        wait for 10 ns;
        clk <= '1';
        wait for 10 ns;
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
        wait for 20 ns;
        rst_n <= '1';
        wait for 20 ns;

        data_a <= "10010000010011101011110000001101"; -- Example 32-bit input vector a
        data_b <= "01101110111101110110101000000111"; -- Example 32-bit input vector b
        start <= '1';
        wait for 100 ns; -- Wait for computation
        start <= '0';
        wait; -- Wait indefinitely for the test to complete

        -- -- Open test vector file
        -- file_open(test_file, "polymulmod2_vectors_N32.csv", read_mode);

        -- -- Read test vectors from CSV
        -- while not endfile(test_file) loop
        --     readline(test_file, line_in);
        --     line_str(1 to line_in'length) := line_in.all;
        --     line_len := line_in'length;

        --     -- Skip empty lines or comments
        --     if line_len > 0 and line_str(1) /= '#' then
        --         test_count := test_count + 1;

        --         -- Parse fields: a, b, expected_result
        --         a_vec := read_vector_from_csv(line_str(1 to line_len), 0);
        --         b_vec := read_vector_from_csv(line_str(1 to line_len), 1);
        --         exp_result := read_vector_from_csv(line_str(1 to line_len), 2);

        --         -- Apply test inputs
        --         data_a <= a_vec;
        --         data_b <= b_vec;
        --         start <= '1';
        --         wait for 10 ns; -- Wait for computation
        --         start <= '0';

        --         -- Assert done signal is activated
        --         if done /= '1' then
        --             report "Test " & integer'image(test_count) & " FAILED: done signal not activated" severity error;
        --             fail_count := fail_count + 1;
        --         elsif result = exp_result then
        --             report "Test " & integer'image(test_count) & " PASSED" severity note;
        --             pass_count := pass_count + 1;
        --         else
        --             report "Test " & integer'image(test_count) & " FAILED: result mismatch" severity error;
        --             fail_count := fail_count + 1;
        --         end if;
        --     end if;
        -- end loop;

        -- file_close(test_file);

        -- -- Print summary
        -- report "Test Summary: " & integer'image(pass_count) & " passed, " &
        --        integer'image(fail_count) & " failed out of " &
        --        integer'image(test_count) & " tests" severity note;

        -- wait;
    end process;
end architecture rtl;