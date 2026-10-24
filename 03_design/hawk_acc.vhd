library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hawk_pkg.all;

entity hawk_acc is
    generic (
        C_DATA_WIDTH : integer := 32
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        mode      : in  std_logic;
        data_slv  : in  std_logic_vector(C_DATA_WIDTH - 1 downto 0);
        data_mst  : out std_logic_vector(C_DATA_WIDTH - 1 downto 0);
        ack_slv   : in  std_logic;
        ready_slv : out std_logic;
        valid     : out std_logic;
        ready     : in  std_logic;
        start_mst : out std_logic;
        last_word : out std_logic;
        verify_error : out std_logic;
        verify_done  : out std_logic
    );
end entity hawk_acc;

architecture rtl of hawk_acc is

    component hawk_sign
        generic (
            g_data_width  : integer := 32;
            g_num_samples : integer := 512;
            g_addr_width  : integer := c_addr_width;
            g_size_fifo   : integer := c_size_fifo
        );
        port (
            clk       : in  std_logic;
            rst_n     : in  std_logic;
            data_in   : in  std_logic_vector(g_data_width - 1 downto 0);
            data_out  : out std_logic_vector(g_data_width - 1 downto 0);
            ack_in    : in  std_logic;
            ready     : in  std_logic;
            valid     : out std_logic;
            last_word : out std_logic;
            start_out : out std_logic
        );
    end component;

    component hawk_verify
        generic (
            g_data_width  : integer := 32;
            g_num_samples : integer := 512;
            g_addr_width  : integer := c_addr_width;
            g_size_fifo   : integer := c_size_fifo
        );
        port (
            clk         : in  std_logic;
            rst_n       : in  std_logic;
            data_in     : in  std_logic_vector(g_data_width - 1 downto 0);
            error_out   : out std_logic;
            ack_in      : in  std_logic;
            input_ready : out std_logic;
            ready       : in  std_logic;
            valid       : out std_logic;
            start_out   : out std_logic
        );
    end component;

    signal data_sign : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    signal ack_sign, ack_verify : std_logic;
    signal ready_sign : std_logic;
    signal valid_sign, valid_verify : std_logic;
    signal start_sign : std_logic;
    signal last_sign, input_ready_verify : std_logic;

begin

    -- mode: 0 = firma, 1 = verificacion.
    -- Mantener mode estable desde antes del primer dato hasta aceptar la salida.
    -- Solo el modulo seleccionado recibe transferencias de entrada y salida.
    ack_sign     <= ack_slv when mode = '0' else '0';
    ack_verify   <= ack_slv when mode = '1' else '0';
    ready_sign   <= ready when mode = '0' else '0';
    -- El registro captura el resultado inmediatamente, sin esperar al DMA.
    verify_done <= valid_verify;

    data_mst  <= data_sign when mode = '0' else (others => '0');
    valid     <= valid_sign when mode = '0' else '0';
    start_mst <= start_sign when mode = '0' else '0';
    ready_slv <= rst_n when mode = '0' else input_ready_verify;
    -- AXI-Stream de salida se utiliza exclusivamente para la firma.
    last_word <= last_sign when mode = '0' else '0';

    hawk_sign_inst : hawk_sign
        generic map (
            g_data_width  => C_DATA_WIDTH,
            g_num_samples => c_num_samples,
            g_addr_width  => c_addr_width,
            g_size_fifo   => c_size_fifo
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            data_in   => data_slv,
            data_out  => data_sign,
            ack_in    => ack_sign,
            ready     => ready_sign,
            valid     => valid_sign,
            last_word => last_sign,
            start_out => start_sign
        );

    hawk_verify_inst : hawk_verify
        generic map (
            g_data_width  => C_DATA_WIDTH,
            g_num_samples => c_num_samples,
            g_addr_width  => c_addr_width,
            g_size_fifo   => c_size_fifo
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            data_in     => data_slv,
            error_out   => verify_error,
            ack_in      => ack_verify,
            input_ready => input_ready_verify,
            ready       => '1',
            valid       => valid_verify,
            start_out   => open
        );

end architecture rtl;
