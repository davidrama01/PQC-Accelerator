library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hawk_pkg.all;

entity hawk_acc is
	generic (
		C_DATA_WIDTH : integer := 32
	);
	port (
		clk         : in  std_logic;
		rst_n       : in  std_logic;
		data_slv    : in  std_logic_vector(C_DATA_WIDTH-1 downto 0);
		data_mst    : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
		ack_slv     : in  std_logic;
        ack_mst     : in std_logic;
        start_mst     : out std_logic
	);
end entity hawk_acc;

architecture rtl of hawk_acc is

	component hawk_sign is
		generic (
			C_DATA_WIDTH : integer := 32;
            g_num_samples : integer := 512;
            g_size_fifo : integer := 32
		);
		port (
			clk      : in  std_logic;
			rst_n    : in  std_logic;
			data_in  : in  std_logic_vector(C_DATA_WIDTH-1 downto 0);
			data_out : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
			ack_in   : in  std_logic;
            ack_out  : in std_logic;
            start_out : out std_logic
		);
	end component;

	signal internal_data : std_logic_vector(C_DATA_WIDTH-1 downto 0);
	signal internal_ack  : std_logic;
    signal start_mst_internal : std_logic;

begin

	hawk_sign_inst : hawk_sign
	generic map (
		C_DATA_WIDTH => C_DATA_WIDTH,
		g_num_samples => c_num_samples,
		g_size_fifo => c_size_fifo
	)
	port map (
		clk      => clk,
		rst_n    => rst_n,
		data_in  => data_slv,
		data_out => internal_data,
		ack_in   => ack_slv,
        ack_out  => ack_mst,
        start_out => start_mst_internal
	);

	data_mst <= internal_data;
    start_mst <= start_mst_internal;

end architecture rtl;
