library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.hawk_pkg.all;

entity fft is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 32;
        g_addr_width  : integer := 9
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        data_in     : in std_logic_vector(g_data_width - 1 downto 0);
        data_out    : out std_logic_vector(g_data_width - 1 downto 0)
    );
end entity fft;

architecture rtl of fft is

    type state_t is (ST_IDLE, ST_INIT_RAM, ST_RD_DELTA, ST_RD_X1, ST_RD_X2, ST_TRANSFORM, ST_WR_T1, ST_WR_T2, ST_RD_FFT);
    signal state     : state_t;
    signal next_state : state_t;

    signal ram_fft_en : std_logic;
    signal ram_fft_we : std_logic_vector(0 downto 0);

    signal ram_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal ram_addrb : std_logic_vector(g_addr_width - 1 downto 0);

    signal ram_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_doutb : std_logic_vector(g_data_width - 1 downto 0);

    signal data_a : std_logic_vector(g_data_width - 1 downto 0);
    signal data_b : std_logic_vector(g_data_width - 1 downto 0);

    signal t  : std_logic_vector(12 downto 0);
    signal m  : std_logic_vector(12 downto 0);
    signal u  : std_logic_vector(12 downto 0);
    signal v  : std_logic_vector(12 downto 0);
    signal v0 : std_logic_vector(12 downto 0);

    signal addr_delta : std_logic_vector(g_addr_width - 1 downto 0);
    signal rom_delta  : std_logic_vector(2 * g_data_width - 1 downto 0);
    signal delta_real : signed(2 * g_data_width - 1 downto 0);
    signal delta_imag : signed(2 * g_data_width - 1 downto 0);
    signal rom_enable : std_logic;

    signal x1_real : signed(2 * g_data_width - 1 downto 0);
    signal x1_imag : signed(2 * g_data_width - 1 downto 0);
    signal x2_real : signed(2 * g_data_width - 1 downto 0);
    signal x2_imag : signed(2 * g_data_width - 1 downto 0);

    signal wait_ram : std_logic;
    signal done_x1 : std_logic;
    signal done_x2 : std_logic;

    signal t_real : signed(2 * g_data_width - 1 downto 0);
    signal t_imag : signed(2 * g_data_width - 1 downto 0);

    signal done_t1 : std_logic;
    signal done_t2 : std_logic;

    signal t1 : std_logic_vector(g_data_width - 1 downto 0);
    signal t2 : std_logic_vector(g_data_width - 1 downto 0);

    component blk_mem_gen_1
		port (
			clka  : in  std_logic;
			ena   : in  std_logic;
			wea   : in  std_logic_vector(0 downto 0);
			addra : in  std_logic_vector(8 downto 0);
            addrb : in  std_logic_vector(8 downto 0);
			dina  : in  std_logic_vector(g_data_width-1 downto 0);
            dinb  : in  std_logic_vector(g_data_width-1 downto 0);
			douta : out std_logic_vector(g_data_width-1 downto 0);
            doutb : out std_logic_vector(g_data_width-1 downto 0)
		);
	end component;

    component blk_mem_gen_2
        port (
            clka  : in  std_logic;
            ena   : in  std_logic;
            addra : in  std_logic_vector(8 downto 0);
            douta : out std_logic_vector(2 * g_data_width - 1 downto 0)
        );
    end component;

begin

    p_state : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= ST_IDLE;
            else
                state <= next_state;
            end if;
        end if;
    end process p_state;

    p_next_state : process(all)
    begin
        next_state <= state;

        case state is
            when ST_IDLE =>
                ram_fft_en <= '0';
                ram_fft_we <= (others => '0');
                done <= '0';

                if start = '1' then
                    next_state <= ST_INIT_RAM;
                    ram_fft_en <= '1';
                    ram_fft_we <= (others => '1');
                end if;

            when ST_INIT_RAM =>
                data_a   <= data_in;

                if unsigned(ram_addra) = g_num_samples - 1 then
                    next_state <= ST_RD_DELTA;
                    ram_fft_en <= '0';
                    ram_fft_we <= (others => '0');
                end if;

            when ST_RD_DELTA =>
                next_state <= ST_RD_X1;

            when ST_RD_X1 =>
                if done_x1 = '1' then
                    next_state <= ST_RD_X2;
                end if;

            when ST_RD_X2 =>
                if done_x2 = '1' then
                    next_state <= ST_TRANSFORM;
                end if;

            when ST_TRANSFORM =>
                next_state <= ST_WR_T1;

            when ST_WR_T1 =>
                if done_t1 = '1' then
                    next_state <= ST_WR_T2;
                end if;

            when ST_WR_T2 =>
                if done_t2 = '1' then
                    if unsigned(v) = unsigned(v0) + shift_right(unsigned(t), 1) - 1 then

                        if unsigned(u) = shift_right(unsigned(m), 1) - 1 and 
                        shift_left(unsigned(m), 1) = to_unsigned(g_num_samples, m'length) then
                            next_state <= ST_RD_FFT;
                        else
                            next_state <= ST_RD_DELTA;
                        end if;
                    else
                        next_state <= ST_RD_X1;
                    end if;
                end if;

            when ST_RD_FFT =>
                if unsigned(ram_addra) = g_num_samples - 1 then
                    next_state <= ST_IDLE;
                    ram_fft_en <= '0';
                    ram_fft_we <= (others => '0');
                end if;
        end case;
    end process p_next_state;

    p_counter : process(clk) begin
        if rising_edge(clk) then
            if rst_n = '0' then
                ram_addra <= (others => '0');
                ram_addrb <= (others => '0');
                rom_enable  <= '0';
                wait_ram   <= '0';
                done_x1    <= '0';
                done_x2    <= '0';
                done_t1    <= '0';
                done_t2    <= '0';
            else
                done_x1 <= '0';
                done_x2 <= '0';
                done_t1 <= '0';
                done_t2 <= '0';
                case state is
                when ST_IDLE =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');
                    rom_enable  <= '0';
                    wait_ram   <= '0';
                    done_x1    <= '0';
                    done_x2    <= '0';

                    t  <= std_logic_vector(shift_right(to_unsigned(g_num_samples, t'length), 1));
                    m  <= std_logic_vector(to_unsigned(2, m'length));
                    u  <= (others => '0');
                    v  <= (others => '0');
                    v0 <= (others => '0');

                when ST_INIT_RAM =>
                    if unsigned(ram_addra) = g_num_samples - 1 then
                        ram_addra <= (others => '0');
                        ram_addrb <= (others => '0');
                        rom_enable <= '1';
                    else
                        ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);
                        ram_addrb <= std_logic_vector(unsigned(ram_addrb) + 1);
                    end if;

                when ST_RD_DELTA =>
                    rom_enable <= '0';
                    delta_real <= resize(signed(rom_delta(g_data_width - 1 downto 0)), 2 * g_data_width);
                    delta_imag <= resize(signed(rom_delta(2 * g_data_width - 1 downto g_data_width)), 2 * g_data_width);
                    v <= v0;

                when ST_RD_X1 =>
                    ram_addra <= v;
                    ram_addrb <= std_logic_vector(unsigned(v) + to_unsigned(g_num_samples / 2, ram_addrb'length));
                    wait_ram <= '1';
                    if wait_ram = '1' then
                        x1_real <= resize(signed(ram_douta), 2 * g_data_width);
                        x1_imag <= resize(signed(ram_doutb), 2 * g_data_width);
                        wait_ram <= '0';
                        done_x1 <= '1';
                    end if;

                when ST_RD_X2 =>
                    ram_addra <= std_logic_vector(unsigned(v) + shift_right(unsigned(t), 1));
                    ram_addrb <= std_logic_vector(unsigned(v) + shift_right(unsigned(t), 1) + to_unsigned(g_num_samples / 2, ram_addrb'length));
                    wait_ram <= '1';
                    if wait_ram = '1' then
                        x2_real <= resize(signed(ram_douta), 2 * g_data_width);
                        x2_imag <= resize(signed(ram_doutb), 2 * g_data_width);
                        wait_ram <= '0';
                        done_x2 <= '1';
                    end if;
                when ST_TRANSFORM =>
                    -- Perform the FFT butterfly operation here
                    -- This is a placeholder for the actual FFT computation
                    t_real <= x2_real * delta_real - x2_imag * delta_imag;
                    t_imag <= x2_real * delta_imag + x2_imag * delta_real;
                
                when ST_WR_T1 =>
                    ram_addra <= v;
                    ram_addrb <= std_logic_vector(unsigned(v) + to_unsigned(g_num_samples / 2, ram_addrb'length));
                    wait_ram <= '1';
                    if wait_ram = '1' then
                        data_a <= std_logic_vector(resize(shift_right((shift_left(x1_real, 31) + t_real), 32), g_data_width));
                        data_b <= std_logic_vector(resize(shift_right((shift_left(x1_imag, 31) + t_imag), 32), g_data_width));
                        wait_ram <= '0';
                        done_t1 <= '1';
                    end if;

                when ST_WR_T2 =>
                    ram_addra <= std_logic_vector(unsigned(v) + unsigned(t) / 2);
                    ram_addrb <= std_logic_vector(unsigned(v) + unsigned(t) / 2 + to_unsigned(g_num_samples / 2, ram_addrb'length));
                    wait_ram <= '1';
                    if wait_ram = '1' then
                        data_a <= std_logic_vector(resize(shift_right((shift_left(x1_real, 31) - t_real), 32), g_data_width));
                        data_b <= std_logic_vector(resize(shift_right((shift_left(x1_imag, 31) - t_imag), 32), g_data_width));
                        wait_ram <= '0';
                        done_t2 <= '1';
                        v <= std_logic_vector(unsigned(v) + to_unsigned(1, v'length));
                        if unsigned(v) = unsigned(v0) + shift_right(unsigned(t), 1) - 1 then

                            if unsigned(u) = shift_right(unsigned(m), 1) - 1 then
                                t  <= std_logic_vector(shift_right(unsigned(t), 1));
                                m  <= std_logic_vector(shift_left(unsigned(m), 1));
                                u  <= (others => '0');
                                v  <= (others => '0');
                                v0 <= (others => '0');
                            else 
                                v0 <= std_logic_vector(unsigned(v0) + unsigned(t));
                                u  <= std_logic_vector(unsigned(u) + to_unsigned(1, u'length));
                                v  <= std_logic_vector(unsigned(v0) + unsigned(t));
                            end if;
                        end if;
                    end if;
                
                when ST_RD_FFT =>
                    -- Read the final FFT results
                    if unsigned(ram_addra) = g_num_samples - 1 then
                        ram_addra <= (others => '0');
                        ram_addrb <= (others => '0');
                    else
                        ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);
                        data_out <= ram_douta; -- Output the FFT result
                    end if;
                when others =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');
                    rom_enable  <= '0';
                    wait_ram   <= '0';
                    done_t1    <= '0';
                    done_t2    <= '0';
                    done_x2    <= '0';
                end case;
            end if;
        end if;
    end process p_counter;

    addr_delta <= std_logic_vector(resize(unsigned(u) + unsigned(m), addr_delta'length));

    ram_fft : blk_mem_gen_1
		port map (
			clka  => clk,
			ena   => ram_fft_en,
			wea   => ram_fft_we,
			addra => ram_addra,
            addrb => ram_addrb,
			dina  => data_a,
            dinb  => data_b,
			douta => ram_douta,
            doutb => ram_doutb
		);

    rom_delta_inst : blk_mem_gen_2
        port map (
            clka  => clk,
            ena   => rom_enable,
            addra => addr_delta,
            douta => rom_delta
        );

end architecture rtl;