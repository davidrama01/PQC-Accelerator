library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity calculate_t is
    generic (
        g_num_samples : integer := 512
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        h0          : in std_logic_vector(g_num_samples - 1 downto 0);
        h1          : in std_logic_vector(g_num_samples - 1 downto 0);
        f_regen     : in std_logic_vector(g_num_samples - 1 downto 0);
        f_decoded   : in std_logic_vector(g_num_samples - 1 downto 0);
        t           : out std_logic_vector(g_num_samples - 1 downto 0)
    );
end entity calculate_t;

architecture rtl of calculate_t is

signal regen_result : std_logic_vector(g_num_samples - 1 downto 0);
signal decoded_result : std_logic_vector(g_num_samples - 1 downto 0);
signal t_internal : std_logic_vector(g_num_samples - 1 downto 0);
signal regen_done : std_logic;
signal decoded_done : std_logic;
signal regen_done_r : std_logic;
signal decoded_done_r : std_logic;
signal done_d : std_logic;

component poly_mul_mod2
    generic (
        g_num_samples : integer := 512;
        g_num_phases : integer := 8
    );
    port (
        clk     : in std_logic;
        rst_n   : in std_logic;
        start   : in std_logic;
        done    : out std_logic;
        data_a  : in std_logic_vector(g_num_samples - 1 downto 0);
        data_b  : in std_logic_vector(g_num_samples - 1 downto 0);
        result  : out std_logic_vector(g_num_samples - 1 downto 0)
    );
end component;

begin

    calculate_process: process(clk, rst_n) begin
        if rst_n = '0' then
            t_internal <= (others => '0');
            done_d <= '0';
            regen_done_r <= '0';
            decoded_done_r <= '0';
        elsif rising_edge(clk) then
            if regen_done_r = '1' and decoded_done_r = '1' then
                t_internal <= regen_result xor decoded_result;
                done_d <= '1';
                regen_done_r <= '0';
                decoded_done_r <= '0';
            else
                done_d <= '0';
            end if; 

            if regen_done = '1' then
                regen_done_r <= '1';
            end if;

            if decoded_done = '1' then
                decoded_done_r <= '1';
            end if;
        end if;
    end process;

    t <= t_internal;
    done <= done_d;

    mul_regen: poly_mul_mod2
        generic map (
            g_num_samples => g_num_samples,
            g_num_phases => c_num_phases
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            done => regen_done,
            data_a => h0,
            data_b => f_regen,
            result => regen_result
        );

     mul_decoded: poly_mul_mod2
        generic map (
            g_num_samples => g_num_samples,
            g_num_phases => c_num_phases
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            start => start,
            done => decoded_done,
            data_a => h1,
            data_b => f_decoded,
            result => decoded_result
        );
    
    -- Multiplication logic here
end architecture rtl;