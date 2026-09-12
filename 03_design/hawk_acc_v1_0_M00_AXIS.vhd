library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hawk_acc_v1_0_M00_AXIS is
	generic (

		-- Width of S_AXIS address bus. The slave accepts the read and write addresses of width C_M_AXIS_TDATA_WIDTH.
		C_M_AXIS_TDATA_WIDTH	: integer	:= 32
	);
	port (
		-- Start of transaction
		sot 			: in std_logic;
		-- End of transaction
		eot 			: out std_logic;
		-- Last word of the transaction
		last_word 		: in std_logic;
		-- Valid handshake of received data
		valid    		: in std_logic;
		-- Data output
		data_mst 		: in std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
		-- Do not modify the ports beyond this line

		-- Global ports
		M_AXIS_ACLK	: in std_logic;
		-- 
		M_AXIS_ARESETN	: in std_logic;
		-- Master Stream Ports. TVALID indicates that the master is driving a valid transfer, A transfer takes place when both TVALID and TREADY are asserted. 
		M_AXIS_TVALID	: out std_logic;
		-- TDATA is the primary payload that is used to provide the data that is passing across the interface from the master.
		M_AXIS_TDATA	: out std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
		-- TSTRB is the byte qualifier that indicates whether the content of the associated byte of TDATA is processed as a data byte or a position byte.
		M_AXIS_TSTRB	: out std_logic_vector((C_M_AXIS_TDATA_WIDTH/8)-1 downto 0);
		-- TLAST indicates the boundary of a packet.
		M_AXIS_TLAST	: out std_logic;
		-- TREADY indicates that the slave can accept a transfer in the current cycle.
		M_AXIS_TREADY	: in std_logic
	);
end hawk_acc_v1_0_M00_AXIS;

architecture implementation of hawk_acc_v1_0_M00_AXIS is                                                                                                      
	                                                                                  
	-- Define the states of state machine                                             
	-- The control state machine oversees the data transfer 
	--and the status of the transfer through the interface.                                   
	type state is ( IDLE,        -- This is the initial/idle state                    
	                SEND_STREAM);  -- In this state the                               
	                             -- stream data is output through M_AXIS_TDATA        
	-- State variable                                                                 
	signal  mst_exec_state : state;                                                   
	--streaming data valid
	signal axis_tvalid	: std_logic;
	-- End of transaction register
	signal eot_d	: std_logic;


begin
	-- I/O Connections assignments

	M_AXIS_TSTRB	<= (others => '1');
	M_AXIS_TLAST	<= last_word;
	M_AXIS_TVALID	<= valid;
	M_AXIS_TDATA	<= data_mst;
	eot 			<= eot_d;


	-- Control state machine implementation                                               
	process(M_AXIS_ACLK) begin                                                                                       
		if M_AXIS_ARESETN = '0' then                                                                                     
			mst_exec_state 	<= IDLE;
			eot_d <= '0';
		elsif rising_edge(M_AXIS_ACLK) then                                                                                
			eot_d <= '0';
			case mst_exec_state is                                                                                        
				when IDLE =>                                                                                                
					if sot = '1' then                                                                                         
						mst_exec_state <= SEND_STREAM;
					end if;                                                                                                                                                                           
			 	when SEND_STREAM =>                                                                                           
					if valid = '1' and M_AXIS_TREADY = '1' and last_word = '1' then                                                                                
						mst_exec_state <= IDLE;
						eot_d <= '1';                                                                                 
					end if;                                                                                                   
				when others =>                                                                                               
					mst_exec_state <= IDLE;                                                                                   
			end case;                                                                                                      
		end if;                                                                                    
	end process;                                                                                                                                                                                                                                                                                                     

end implementation;
