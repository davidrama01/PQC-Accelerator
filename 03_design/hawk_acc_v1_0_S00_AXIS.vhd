library ieee;
use ieee.std_logic_1164.all;

entity hawk_acc_v1_0_S00_AXIS is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- AXI4Stream sink: Data Width
		C_S_AXIS_TDATA_WIDTH	: integer	:= 32
	);
	port (

		-- Start of transaction
		sot 			: in std_logic;
		-- End of transaction
		eot 			: out std_logic;
		-- Valid handshake of received data
		valid 			: out std_logic;
		-- Data output
		data_received 	: out std_logic_vector(C_S_AXIS_TDATA_WIDTH-1 downto 0);

		-- AXI4Stream sink: Clock
		S_AXIS_ACLK		: in std_logic;
		-- AXI4Stream sink: Reset
		S_AXIS_ARESETN	: in std_logic;
		-- Ready to accept data in
		S_AXIS_TREADY	: out std_logic;
		-- Data in
		S_AXIS_TDATA	: in std_logic_vector(C_S_AXIS_TDATA_WIDTH-1 downto 0);
		-- Byte qualifier
		S_AXIS_TSTRB	: in std_logic_vector((C_S_AXIS_TDATA_WIDTH/8)-1 downto 0);
		-- Indicates boundary of last packet
		S_AXIS_TLAST	: in std_logic;
		-- Data is in valid
		S_AXIS_TVALID	: in std_logic
	);
end hawk_acc_v1_0_S00_AXIS;

architecture arch_imp of hawk_acc_v1_0_S00_AXIS is

	-- Define the states of state machine
	-- The control state machine oversees the writing of input streaming data into the IP
	type state is ( IDLE,        -- This is the initial/idle state 
	                RECEIVE_WORD); -- In this state ready is enabled
	                             
	signal axis_tready		: std_logic;
	-- State variable
	signal  mst_exec_state 	: state;  
	-- Done register
	signal eot_d 			: std_logic;

begin
	-- I/O Connections assignments

	S_AXIS_TREADY	<= axis_tready;
	data_received 	<= S_AXIS_TDATA;
	eot 			<= eot_d;
	axis_tready 	<= '1' when mst_exec_state = RECEIVE_WORD else '0';

	-- Valid handshake generation
	valid <= S_AXIS_TVALID and axis_tready;

	-- State machine for start and done handling
	process(S_AXIS_ACLK) begin
		if S_AXIS_ARESETN = '0' then
			mst_exec_state 	<= IDLE;
			eot_d 			<= '0';
		elsif rising_edge(S_AXIS_ACLK) then
			eot_d <= '0';
			case mst_exec_state is
				when IDLE =>
					if sot = '1' then
						mst_exec_state <= RECEIVE_WORD;
					end if;
				when RECEIVE_WORD =>
					if S_AXIS_TLAST = '1' then
						mst_exec_state 	<= IDLE;
						eot_d 			<= '1';
					end if;
			end case;
		end if;
	end process;

end arch_imp;
