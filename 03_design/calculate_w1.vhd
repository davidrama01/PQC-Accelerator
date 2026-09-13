library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity calculate_w1 is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 16;
        g_addr_width  : integer := 9
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        x0          : in std_logic_vector(g_data_width - 1 downto 0);
        x1          : in std_logic_vector(g_data_width - 1 downto 0);
        f_regen     : in std_logic_vector(g_data_width - 1 downto 0);
        g_regen     : in std_logic_vector(g_data_width - 1 downto 0);
        addr_f      : out std_logic_vector(g_addr_width - 1 downto 0);
        addr_g      : out std_logic_vector(g_addr_width - 1 downto 0);
        addr_x0     : out std_logic_vector(g_addr_width - 1 downto 0);
        addr_x1     : out std_logic_vector(g_addr_width - 1 downto 0);
        w1          : out std_logic_vector(g_data_width - 1 downto 0)
    );
end entity calculate_w1;

architecture rtl of calculate_w1 is

signal mul0_result : std_logic_vector(g_data_width - 1 downto 0);
signal mul1_result : std_logic_vector(g_data_width - 1 downto 0);
signal w1_internal : signed(g_data_width - 1 downto 0);
signal mul0_done : std_logic;
signal mul1_done : std_logic;
signal done_d : std_logic;
signal addr_f_int : std_logic_vector(g_addr_width - 1 downto 0);
signal addr_g_int : std_logic_vector(g_addr_width - 1 downto 0);
signal addr_x0_int : std_logic_vector(g_addr_width - 1 downto 0);
signal addr_x1_int : std_logic_vector(g_addr_width - 1 downto 0);

component poly_mul
    generic (
        g_num_samples   : integer := 512;
        g_data_width    : integer := 16;
        g_addr_width    : integer := 9 -- Log2(g_num_samples)
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        data_a      : in std_logic_vector(g_data_width - 1 downto 0);
        data_b      : in std_logic_vector(g_data_width - 1 downto 0);
        addr_a      : out std_logic_vector(g_addr_width - 1 downto 0);
        addr_b      : out std_logic_vector(g_addr_width - 1 downto 0);
        result      : out std_logic_vector(g_data_width - 1 downto 0)
    );
end component;

begin

    calculate_process: process(clk, rst_n) begin
        if rst_n = '0' then
            w1_internal <= (others => '0');
            done_d <= '0';
        elsif rising_edge(clk) then
            if mul0_done = '1' and mul1_done = '1' then
                w1_internal <= signed(mul0_result) - signed(mul1_result);
                done_d <= '1';
            else
                done_d <= '0';
            end if; 
        end if;
    end process;

    w1 <= std_logic_vector(w1_internal);
    done <= done_d;
    addr_f <= addr_f_int;
    addr_g <= addr_g_int;
    addr_x0 <= addr_x0_int;
    addr_x1 <= addr_x1_int;

    mul_x0_inst: poly_mul
        generic map (
            g_num_samples => g_num_samples,
            g_data_width => g_data_width,
            g_addr_width => g_addr_width
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            done => mul0_done,
            addr_a => addr_f_int,
            addr_b => addr_x1_int,
            data_a => f_regen,
            data_b => x1,
            result => mul0_result
        );

    mul_x1_inst: poly_mul
        generic map (
            g_num_samples => g_num_samples,
            g_data_width => g_data_width,
            g_addr_width => g_addr_width
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            done => mul1_done,
            addr_a => addr_g_int,
            addr_b => addr_x0_int,
            data_a => g_regen,
            data_b => x0,
            result => mul1_result
        );
    
    -- Multiplication logic here
end architecture rtl;