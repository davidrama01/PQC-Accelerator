library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity calculate_s1 is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 16;
        g_addr_width  : integer := 9
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        out_ready   : in std_logic;
        done        : out std_logic;
        ready       : out std_logic;
        sym_break   : in std_logic;
        h1          : in std_logic_vector(g_num_samples - 1 downto 0);
        w1          : in std_logic_vector(g_data_width - 1 downto 0);
        addr        : out std_logic_vector(g_addr_width - 1 downto 0);
        s1          : out std_logic_vector(g_data_width - 1 downto 0)
    );
end entity calculate_s1;

architecture rtl of calculate_s1 is

signal s1_internal : signed(g_data_width - 1 downto 0);
signal done_d : std_logic;
signal ready_d : std_logic;
signal coefficient_index : integer range 0 to g_num_samples - 1;

type state_t is (IDLE, REQUEST_DATA, CAPTURE_DATA, PRESENT_DATA);
signal state : state_t;

begin

    calculate_s1_process: process(clk, rst_n)
        variable h1_ext : signed(g_data_width downto 0);
        variable w1_ext : signed(g_data_width downto 0);
        variable diff   : signed(g_data_width downto 0);
    begin
        if rst_n = '0' then
            s1_internal <= (others => '0');
            done_d      <= '0';
            ready_d     <= '0';
            coefficient_index <= 0;
            state        <= IDLE;
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    done_d  <= '0';
                    ready_d <= '0';

                    if start = '1' then
                        coefficient_index <= 0;
                        state <= REQUEST_DATA;
                    end if;

                -- La BRAM captura la direccion presentada durante este ciclo.
                when REQUEST_DATA =>
                    state <= CAPTURE_DATA;

                -- Un ciclo despues, se registra el coeficiente calculado.
                when CAPTURE_DATA =>
                    h1_ext := (others => '0');
                    if h1(coefficient_index) = '1' then
                        h1_ext := to_signed(1, g_data_width + 1);
                    end if;

                    w1_ext := resize(signed(w1), g_data_width + 1);

                    if sym_break = '1' then
                        diff := h1_ext - w1_ext;
                    else
                        diff := h1_ext + w1_ext;
                    end if;

                    s1_internal <= resize(shift_right(diff, 1), g_data_width);
                    ready_d     <= '1';
                    if coefficient_index = g_num_samples - 1 then
                        done_d <= '1';
                    end if;
                    state <= PRESENT_DATA;

                -- Mantener dato, valid y last hasta que AXI lo acepte.
                when PRESENT_DATA =>
                    if out_ready = '1' then
                        ready_d <= '0';
                        done_d  <= '0';

                        if coefficient_index = g_num_samples - 1 then
                            state <= IDLE;
                            coefficient_index <= 0;
                        else
                            coefficient_index <= coefficient_index + 1;
                            state <= REQUEST_DATA;
                        end if;
                    end if;

                when others =>
                    done_d  <= '0';
                    ready_d <= '0';
                    coefficient_index <= 0;
                    state <= IDLE;
            end case;
        end if;
    end process;

    s1 <= std_logic_vector(s1_internal);
    done <= done_d;
    ready <= ready_d;
    addr <= std_logic_vector(to_unsigned(coefficient_index, g_addr_width));
    
    -- Multiplication logic here
end architecture rtl;
