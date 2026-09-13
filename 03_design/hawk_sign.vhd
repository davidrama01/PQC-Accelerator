library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hawk_pkg.all;

entity hawk_sign is
	generic (
		g_data_width : integer := 32;
        g_num_samples : integer := 512;
        g_addr_width : integer := 9;
        g_size_fifo : integer := c_size_fifo
	);
	port (
		clk      : in  std_logic;
		rst_n    : in  std_logic;
		data_in  : in  std_logic_vector(g_data_width-1 downto 0);
		data_out : out std_logic_vector(g_data_width-1 downto 0);
		ack_in   : in  std_logic;
        ready     : in  std_logic;
        valid     : out std_logic;
        last_word : out std_logic;
        start_out : out std_logic
	);
end entity hawk_sign;

architecture rtl of hawk_sign is

    type state_t is 
        (IDLE, 
        WRITE_H0, 
        WRITE_H1,
        WRITE_FMOD2, 
        WRITE_GMOD2, 
        WRITE_F, 
        WRITE_G,
        CALC_T,
        READ_T,
        WRITE_X0,
        WRITE_X1,
        CALC_W1,
        CALC_SYM_BREAK,
        CALC_S1
        );
    signal current_state : state_t;
    signal next_state : state_t;
    signal wr_h0 : std_logic;
    signal wr_h1 : std_logic;
    signal wr_Fmod2 : std_logic;
    signal wr_Gmod2 : std_logic;
    signal wr_f : std_logic;
    signal wr_g : std_logic;
    signal wr_x0 : std_logic;
    signal wr_x1 : std_logic;
    signal wr_w1 : std_logic;
    signal cnt_Fmod2 : integer range 0 to c_size_fifo+1;
    signal cnt_Gmod2 : integer range 0 to c_size_fifo+1;
    signal cnt_h0 : integer range 0 to c_size_fifo+1;
    signal cnt_h1 : integer range 0 to c_size_fifo+1;
    signal cnt_f : integer range 0 to c_num_samples+1;
    signal cnt_g : integer range 0 to c_num_samples+1;
    signal cnt_t : integer range 0 to 2*c_size_fifo+1;
    signal cnt_x0 : integer range 0 to c_num_samples+1;
    signal cnt_x1 : integer range 0 to c_num_samples+1;
    signal cnt_w1 : integer range 0 to c_num_samples+1;
    signal h0 : std_logic_vector(c_num_samples-1 downto 0);
    signal h1 : std_logic_vector(c_num_samples-1 downto 0);
    signal Fmod2 : std_logic_vector(c_num_samples-1 downto 0);
    signal Gmod2 : std_logic_vector(c_num_samples-1 downto 0);
    signal f_mod2 : std_logic_vector(c_num_samples-1 downto 0);
    signal g_mod2 : std_logic_vector(c_num_samples-1 downto 0);
    signal wea_f : std_logic_vector(0 downto 0);
    signal wea_g : std_logic_vector(0 downto 0);
    signal wea_x0 : std_logic_vector(0 downto 0);
    signal wea_x1 : std_logic_vector(0 downto 0);
    signal wea_w1 : std_logic_vector(0 downto 0);
    signal ram_addr_f : std_logic_vector(8 downto 0);
    signal ram_addr_g : std_logic_vector(8 downto 0);
    signal ram_addr_x0 : std_logic_vector(8 downto 0);
    signal ram_addr_x1 : std_logic_vector(8 downto 0);
    signal ram_addr_w1 : std_logic_vector(8 downto 0);
    signal start_t : std_logic;
    signal start_w1 : std_logic;
    signal start_s1 : std_logic;
    signal done_t0 : std_logic;
    signal done_t1 : std_logic;
    signal done_w1 : std_logic;
    signal done_s1 : std_logic;
    signal ready_s1 : std_logic;
    signal t0 : std_logic_vector(c_num_samples-1 downto 0);
    signal t1 : std_logic_vector(c_num_samples-1 downto 0);
    signal w1 : std_logic_vector(g_data_width-1 downto 0);
    signal s1 : std_logic_vector(g_data_width-1 downto 0);
    signal last_word_int : std_logic;
    signal valid_int : std_logic;

    signal ram_en       : std_logic;
	signal ram_wea      : std_logic_vector(0 downto 0);
	signal addr_f       : unsigned(8 downto 0);
	signal ram_dina     : std_logic_vector(g_data_width-1 downto 0);
	signal ram_doutf    : std_logic_vector(g_data_width-1 downto 0);
    signal ram_doutg    : std_logic_vector(g_data_width-1 downto 0);
    signal ram_dout_x0   : std_logic_vector(g_data_width-1 downto 0);
    signal ram_dout_x1   : std_logic_vector(g_data_width-1 downto 0);
    signal ram_dout_w1   : std_logic_vector(g_data_width-1 downto 0);

    signal addr_f_int : std_logic_vector(8 downto 0);
    signal addr_g_int : std_logic_vector(8 downto 0);
    signal addr_x0_int : std_logic_vector(8 downto 0);
    signal addr_x1_int : std_logic_vector(8 downto 0);
    signal addr_w1_s1 : std_logic_vector(8 downto 0);

    signal ready_sym_break : std_logic;
    signal sym_break : std_logic;

    attribute MARK_DEBUG : string;
    attribute MARK_DEBUG of current_state : signal is "TRUE";
    attribute MARK_DEBUG of next_state : signal is "TRUE";
    attribute MARK_DEBUG of wr_h0 : signal is "TRUE";
    attribute MARK_DEBUG of wr_h1 : signal is "TRUE";
    attribute MARK_DEBUG of wr_Fmod2 : signal is "TRUE";
    attribute MARK_DEBUG of wr_Gmod2 : signal is "TRUE";
    attribute MARK_DEBUG of wr_f : signal is "TRUE";
    attribute MARK_DEBUG of wr_g : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_Fmod2 : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_Gmod2 : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_h0 : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_h1 : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_f : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_g : signal is "TRUE";
    -- attribute MARK_DEBUG of cnt_t : signal is "TRUE";
    -- attribute MARK_DEBUG of h0 : signal is "TRUE";
    -- attribute MARK_DEBUG of h1 : signal is "TRUE";
    -- attribute MARK_DEBUG of Fmod2 : signal is "TRUE";
    -- attribute MARK_DEBUG of Gmod2 : signal is "TRUE";
    -- attribute MARK_DEBUG of f_mod2 : signal is "TRUE";
    -- attribute MARK_DEBUG of g_mod2 : signal is "TRUE";
    -- attribute MARK_DEBUG of wea_f : signal is "TRUE";
    -- attribute MARK_DEBUG of wea_g : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_addr_f : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_addr_g : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_addr_x0 : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_addr_x1 : signal is "TRUE";
    attribute MARK_DEBUG of start_t : signal is "TRUE";
    attribute MARK_DEBUG of done_t0 : signal is "TRUE";
    attribute MARK_DEBUG of done_t1 : signal is "TRUE";
    attribute MARK_DEBUG of t0 : signal is "TRUE";
    -- attribute MARK_DEBUG of t1 : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_en : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_wea : signal is "TRUE";
    -- attribute MARK_DEBUG of addr_f : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_dina : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_doutf : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_doutg : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_dout_x0 : signal is "TRUE";
    -- attribute MARK_DEBUG of ram_dout_x1 : signal is "TRUE";

	component blk_mem_gen_0
		port (
			clka  : in  std_logic;
			ena   : in  std_logic;
			wea   : in  std_logic_vector(0 downto 0);
			addra : in  std_logic_vector(8 downto 0);
			dina  : in  std_logic_vector(g_data_width-1 downto 0);
			douta : out std_logic_vector(g_data_width-1 downto 0)
		);
	end component;

    component calculate_t
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
    end component;

    component calculate_w1
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
    end component;

    component sym_break_w1
        generic (
            g_num_samples : integer := 512;
            g_data_width  : integer := 16
        );
        port (
            clk         : in std_logic;
            rst_n       : in std_logic;
            start       : in std_logic;
            valid       : in std_logic;
            ready       : out std_logic;
            sym_break   : out std_logic;
            w1          : in std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

    component calculate_s1
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
    end component;

begin
    -----------------------------------------------
    -- Process to register the current state
    -----------------------------------------------
    state_register : process(clk) begin
        if rising_edge(clk) then
            if rst_n = '0' then
                current_state <= IDLE;
            else
                current_state <= next_state;
            end if;
        end if;
    end process;

    -----------------------------------------------
    -- Next state logic
    -----------------------------------------------
    next_state_logic : process(all) begin
        wr_h0       <= '0';  -- Default value
        wr_h1       <= '0';  -- Default value
        wr_Fmod2    <= '0';  -- Default value
        wr_Gmod2    <= '0';  -- Default value
        wr_f        <= '0';  -- Default value
        wr_g        <= '0';  -- Default value
        wr_x0       <= '0';  -- Default value
        wr_x1       <= '0';  -- Default value
        wr_w1       <= '0';  -- Default value
        valid_int   <= '0';  -- Default value
        start_t     <= '0';  -- Default value
        start_w1    <= '0';  -- Default value
        start_s1    <= '0';  -- Default value
        start_out   <= '0';  -- Default value
        next_state  <= current_state;  -- Default value
        case current_state is
            when IDLE =>
                if ack_in = '1' then
                    next_state <= WRITE_H0;
                    wr_h0 <= '1';
                end if;
            when WRITE_H0 =>
                if ack_in = '1' then
                    wr_h0 <= '1';
                    if cnt_h0 = c_size_fifo - 1 then
                        next_state <= WRITE_H1;
                    end if;
                end if;
            when WRITE_H1 =>
                if ack_in = '1' then
                    wr_h1 <= '1';
                    if cnt_h1 = c_size_fifo - 1 then
                        next_state <= WRITE_FMOD2;
                    end if;
                end if;
            when WRITE_FMOD2 =>
                if ack_in = '1' then
                    wr_Fmod2 <= '1';
                    if cnt_Fmod2 = c_size_fifo - 1 then
                        next_state <= WRITE_GMOD2;
                    end if;
                end if;
            when WRITE_GMOD2 =>
                if ack_in = '1' then
                    wr_Gmod2 <= '1';
                    if cnt_Gmod2 = c_size_fifo - 1 then
                        next_state <= WRITE_F;
                    end if;
                end if;
            when WRITE_F =>
                if ack_in = '1' then
                    wr_f <= '1';
                    if cnt_f = c_num_samples - 1 then
                        next_state <= WRITE_G;
                    end if;
                end if;
            when WRITE_G =>
                if ack_in = '1' then
                    wr_g <= '1';
                    if cnt_g = c_num_samples - 1 then
                        next_state <= CALC_T;
                        start_t <= '1';  -- Start the calculation of t
                    end if;
                end if;
            when CALC_T =>
                if done_t0 = '1' and done_t1 = '1' then
                    next_state <= READ_T;
                    start_out <= '1';  -- Indicate that the calculation is done
                end if;
            when READ_T =>
                valid_int <= '1';
                if last_word_int = '1' and ready = '1' then
                    next_state <= WRITE_X0;
                end if;
            when WRITE_X0 =>
                if ack_in = '1' then
                    wr_x0 <= '1';
                    if cnt_x0 = c_num_samples - 1 then
                        next_state <= WRITE_X1;
                    end if;
                end if;
            when WRITE_X1 =>
                if ack_in = '1' then
                    wr_x1 <= '1';
                    if cnt_x1 = c_num_samples - 1 then
                        next_state <= CALC_W1;
                        start_w1 <= '1';  -- Start the calculation of w1
                    end if;
                end if;
            when CALC_W1 =>
                if done_w1 = '1' then
                    wr_w1 <= '1';  -- Write the calculated w1
                    if cnt_w1 = c_num_samples - 1 then
                        next_state <= CALC_SYM_BREAK;
                    end if;
                end if;
            when CALC_SYM_BREAK =>
                if ready_sym_break = '1' then
                    next_state <= CALC_S1;
                    start_s1   <= '1';
                    start_out   <= '1';  -- Indicate that the calculation is done
                end if;
            when CALC_S1 =>
                valid_int <= ready_s1;  -- Set valid_int based on ready_s1
                if done_s1 = '1' and ready = '1' then
                    next_state <= IDLE;
                end if;
            when others =>
                next_state <= IDLE;
        end case;
    end process;

    -----------------------------------------------
    -- Counter to assign data to immediate registers
    -----------------------------------------------

    cnt_process : process(clk) begin
        if rising_edge(clk) then
            if rst_n = '0' then
                cnt_h0 <= 0;
                cnt_h1 <= 0;
                cnt_Fmod2 <= 0;
                cnt_Gmod2 <= 0;
                cnt_f <= 0;
                cnt_g <= 0;
                cnt_t <= 0;
                cnt_x0 <= 0;
                cnt_x1 <= 0;
                cnt_w1 <= 0;
            else
                if cnt_h0 = c_size_fifo then
                    cnt_h0 <= 0;
                elsif wr_h0 = '1' then
                    if cnt_h0 < c_size_fifo then
                        cnt_h0 <= cnt_h0 + 1;
                        h0((cnt_h0+1)*g_data_width-1 downto cnt_h0*g_data_width) <= data_in;
                    end if;
                end if;

                if cnt_h1 = c_size_fifo then
                    cnt_h1 <= 0;
                elsif wr_h1 = '1' then
                    if cnt_h1 < c_size_fifo then
                        cnt_h1 <= cnt_h1 + 1;
                        h1((cnt_h1+1)*g_data_width-1 downto cnt_h1*g_data_width) <= data_in;
                    end if;
                end if;

                if cnt_Fmod2 = c_size_fifo then
                    cnt_Fmod2 <= 0;
                elsif wr_Fmod2 = '1' then
                    if cnt_Fmod2 < c_size_fifo then
                        cnt_Fmod2 <= cnt_Fmod2 + 1;
                        Fmod2((cnt_Fmod2+1)*g_data_width-1 downto cnt_Fmod2*g_data_width) <= data_in;
                    end if;
                end if;

                if cnt_Gmod2 = c_size_fifo then
                    cnt_Gmod2 <= 0;
                elsif wr_Gmod2 = '1' then
                    if cnt_Gmod2 < c_size_fifo then
                        cnt_Gmod2 <= cnt_Gmod2 + 1;
                        Gmod2((cnt_Gmod2+1)*g_data_width-1 downto cnt_Gmod2*g_data_width) <= data_in;
                    end if;
                end if;

                if cnt_f = c_num_samples then
                    cnt_f <= 0;
                elsif wr_f = '1' then
                    if cnt_f < c_num_samples then
                        cnt_f <= cnt_f + 1;
                        f_mod2(cnt_f) <= data_in(0);
                    end if;
                end if;

                if cnt_g = c_num_samples then
                    cnt_g <= 0;
                elsif wr_g = '1' then
                    if cnt_g < c_num_samples then
                        cnt_g <= cnt_g + 1;
                        g_mod2(cnt_g) <= data_in(0);
                    end if;
                end if;

                if cnt_t = 2 * c_size_fifo then
                    cnt_t <= 0;
                elsif valid_int = '1' and ready = '1' then
                    if cnt_t < c_size_fifo then
                        cnt_t <= cnt_t + 1;
                    elsif cnt_t < 2 * c_size_fifo then
                        cnt_t <= cnt_t + 1;
                    end if;
                end if;

                if cnt_x0 = c_num_samples then
                    cnt_x0 <= 0;
                elsif wr_x0 = '1' then
                    if cnt_x0 < c_num_samples then
                        cnt_x0 <= cnt_x0 + 1;
                    end if;
                end if;

                if cnt_x1 = c_num_samples then
                    cnt_x1 <= 0;
                elsif wr_x1 = '1' then
                    if cnt_x1 < c_num_samples then
                        cnt_x1 <= cnt_x1 + 1;
                    end if;
                end if;

                if cnt_w1 = c_num_samples then
                    cnt_w1 <= 0;
                elsif wr_w1 = '1' then
                    if cnt_w1 < c_num_samples then
                        cnt_w1 <= cnt_w1 + 1;
                    end if;
                end if;

            end if;
        end if;
    end process;

    -----------------------------------------------
    -- Combinational process to read calculations
    -----------------------------------------------

    output_process : process(all)
    begin
        data_out <= (others => '0');
        last_word_int <= '0';

        if current_state = READ_T then
            if cnt_t < c_size_fifo then
                data_out <= t0(
                    (cnt_t + 1) * g_data_width - 1
                    downto
                    cnt_t * g_data_width
                );
            else
                data_out <= t1(
                    (cnt_t - c_size_fifo + 1) * g_data_width - 1
                    downto
                    (cnt_t - c_size_fifo) * g_data_width
                );
            end if;

            if cnt_t = 2 * c_size_fifo - 1 then
                last_word_int <= '1';
            end if;
        elsif current_state = CALC_S1 then
            data_out <= s1;
            last_word_int <= done_s1;
        end if;
    end process;

    valid       <= valid_int;
    last_word   <= last_word_int;  -- Indicate the last word when reading t

	ram_en   <= '1';
    wea_f <= "1" when wr_f = '1' else "0";
    wea_g <= "1" when wr_g = '1' else "0";
    wea_x0 <= "1" when wr_x0 = '1' else "0";
    wea_x1 <= "1" when wr_x1 = '1' else "0";
    wea_w1 <= "1" when wr_w1 = '1' else "0";
    ram_addr_f <= std_logic_vector(to_unsigned(cnt_f, 9)) when current_state = WRITE_F else
                  addr_f_int when current_state = CALC_W1 else
                  (others => '0');
    ram_addr_g <= std_logic_vector(to_unsigned(cnt_g, 9)) when current_state = WRITE_G else
                  addr_g_int when current_state = CALC_W1 else
                  (others => '0');
    ram_addr_x0 <= std_logic_vector(to_unsigned(cnt_x0, 9)) when current_state = WRITE_X0 else
                   addr_x0_int when current_state = CALC_W1 else
                   (others => '0');
    ram_addr_x1 <= std_logic_vector(to_unsigned(cnt_x1, 9)) when current_state = WRITE_X1 else
                   addr_x1_int when current_state = CALC_W1 else
                   (others => '0');
    ram_addr_w1 <= addr_w1_s1 when current_state = CALC_S1 else
                   std_logic_vector(to_unsigned(cnt_w1, 9));

	ram_f : blk_mem_gen_0
		port map (
			clka  => clk,
			ena   => ram_en,
			wea   => wea_f,
			addra => ram_addr_f,
			dina  => data_in,
			douta => ram_doutf
		);

    ram_g : blk_mem_gen_0
		port map (
			clka  => clk,
			ena   => ram_en,
			wea   => wea_g,
			addra => ram_addr_g,
			dina  => data_in,
			douta => ram_doutg
		);
    
    ram_x0 : blk_mem_gen_0
		port map (
			clka  => clk,
			ena   => ram_en,
			wea   => wea_x0,
			addra => ram_addr_x0,
			dina  => data_in,
			douta => ram_dout_x0
		);

    ram_x1 : blk_mem_gen_0
		port map (
			clka  => clk,
			ena   => ram_en,
			wea   => wea_x1,
			addra => ram_addr_x1,
			dina  => data_in,
			douta => ram_dout_x1
		);

    ram_w1 : blk_mem_gen_0
		port map (
			clka  => clk,
			ena   => ram_en,
			wea   => wea_w1,
			addra => ram_addr_w1,
			dina  => w1,
			douta => ram_dout_w1
		);

    calculate_t0_inst : calculate_t
        generic map (
            g_num_samples => g_num_samples
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start       => start_t,
            done        => done_t0,
            h0          => h0,
            h1          => h1,
            f_regen     => f_mod2,
            f_decoded   => Fmod2,
            t           => t0
        );

    calculate_t1_inst : calculate_t
        generic map (
            g_num_samples => g_num_samples
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start       => start_t,
            done        => done_t1,
            h0          => h0,
            h1          => h1,
            f_regen     => g_mod2,
            f_decoded   => Gmod2,
            t           => t1
        );

    calculate_w1_inst : calculate_w1
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start       => start_w1,
            done        => done_w1,
            x0          => ram_dout_x0,
            x1          => ram_dout_x1,
            f_regen     => ram_doutf,
            g_regen     => ram_doutg,
            addr_f      => addr_f_int,
            addr_g      => addr_g_int,
            addr_x0     => addr_x0_int,
            addr_x1     => addr_x1_int,
            w1          => w1
        );

    sym_break_w1_inst : sym_break_w1
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start       => start_w1,
            valid       => done_w1,
            ready       => ready_sym_break,
            sym_break   => sym_break,
            w1          => w1
        );

    calculate_s1_inst : calculate_s1
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            start       => start_s1,
            out_ready   => ready,
            done        => done_s1,
            ready       => ready_s1,
            sym_break   => sym_break,
            h1          => h1,
            w1          => ram_dout_w1,
            addr        => addr_w1_s1,
            s1          => s1
        );

end architecture rtl;
