library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use hawk_pkg.ALL;

entity rebuild_s0 is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 32;
        g_addr_width  : integer := 9
    );
    port (
        clk            : in std_logic;
        rst_n          : in std_logic;
        start          : in std_logic;
        data_in_valid  : in std_logic;
        done           : out std_logic;
        data_q00       : in std_logic_vector(g_data_width - 1 downto 0);
        data_q01       : in std_logic_vector(g_data_width - 1 downto 0);
        data_w1        : in std_logic_vector(g_data_width - 1 downto 0);
        data_h0        : in std_logic_vector(g_num_samples -1 downto 0);
        data_out       : out std_logic_vector(g_data_width - 1 downto 0);
        data_out_valid : out std_logic;
        error          : out std_logic;
    );
end entity rebuild_s0;

architecture rtl of rebuild_s0 is

    -- La carga inicial acepta una palabra por ciclo cuando data_in_valid=1.
    -- El resto de la FSM separa las peticiones a memoria, los ciclos de
    -- espera y la captura/confirmacion para respetar las latencias sincrónicas.
    type state_t is (ST_IDLE, ST_RESCALE, ST_WR_FFT, ST_COMMIT_FFT, ST_RD_FFT, ST_WAIT_FFT, ST_CAPTURE_FFT, ST_CALC_X, , ST_WR_Q01, ST_COMMIT_Q01, ST_RD_Q01, ST_RD_Q01_WAIT, ST_RD_Q01_CAPTURE, ST_WR_FIFO, ST_CALC_W0, ST_DONE);
    signal state     : state_t;
    signal next_state : state_t;

    -- Rescale calculation signals

    constant c_bits_samples : natural := clog2(g_num_samples);
    constant c_alpha_shift  : integer range 0 to 32 := c_q00 + 1 - c_bits_samples;

    signal q00 : std_logic_vector(g_data_width - 1 downto 0);
    signal q01 : std_logic_vector(g_data_width - 1 downto 0);
    signal w1  : std_logic_vector(g_data_width - 1 downto 0);
    signal rescale_valid : std_logic;
    signal rescale_cnt : integer range 0 to 1024;

    signal error_flag;
    signal alpha : signed(g_data_width -1 downto 0);

    -- FFT calculation signals

    signal fft_q00_valid : std_logic;
    signal fft_q01_valid : std_logic;
    signal fft_w1_valid  : std_logic;

    signal fft_q00_done : std_logic;
    signal fft_q01_done : std_logic;
    signal fft_w1_done  : std_logic;

    signal fft_q00 : std_logic_vector(g_data_width -1 downto 0);
    signal fft_q01 : std_logic_vector(g_data_width -1 downto 0);
    signal fft_w1  : std_logic_vector(g_data_width -1 downto 0);

    -- FFT store signals

    signal q00_ena : std_logic;
    signal q01_ena : std_logic;
    signal w1_ena  : std_logic;

    signal q00_enb : std_logic;
    signal q01_enb : std_logic;
    signal w1_enb  : std_logic;

    signal q00_wea : std_logic;
    signal q01_wea : std_logic;
    signal w1_wea  : std_logic;

    signal ram_q00_web : std_logic;
    signal ram_q01_web : std_logic;
    signal ram_w1_web  : std_logic;

    signal q00_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal q01_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal w1_addra  : std_logic_vector(g_addr_width - 1 downto 0);
    signal fft_addr  : std_logic_vector(g_addr_width - 1 downto 0);

    signal q00_addrb : std_logic_vector(g_addr_width - 1 downto 0);
    signal q01_addrb : std_logic_vector(g_addr_width - 1 downto 0);
    signal w1_addrb  : std_logic_vector(g_addr_width - 1 downto 0);

    signal q00_dina : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_dina : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_dina  : std_logic_vector(g_data_width - 1 downto 0);

    signal q00_dinb : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_dinb : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_dinb  : std_logic_vector(g_data_width - 1 downto 0);

    signal q00_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_douta  : std_logic_vector(g_data_width - 1 downto 0);

    signal q00_doutb : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_doutb : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_doutb  : std_logic_vector(g_data_width - 1 downto 0);

    -- Rebuild calculation signals

    signal prod_uu  : signed(2 * g_data_width - 1 downto 0);
    signal prod_nn  : signed(2 * g_data_width - 1 downto 0);
    signal prod_un  : signed(2 * g_data_width - 1 downto 0);
    signal prod_nu  : signed(2 * g_data_width - 1 downto 0);

    signal v : signed(g_data_width downto 0);

    signal x_re : signed(2 * g_data_width downto 0);
    signal x_im : signed(2 * g_data_width downto 0);
    signal z_re : std_logic;
    signal z_im : std_logic;

    -- IFFT signals

    signal ifft_valid_in    : std_logic;
    signal ifft_valid_out   : std_logic;
    signal ifft_done        : std_logic;
    signal ifft_data_in     : std_logic_vector(g_data_width - 1 downto 0);
    signal ifft_data_out    : std_logic_vector(g_data_width - 1 downto 0);

    signal addr_count : integer range 0 to g_num_samples - 1 := 0;

    -- FIFO signals

    signal fifo_wr_en : std_logic := '0';
    signal fifo_rd_en : std_logic := '0';
    signal fifo_full  : std_logic;
    signal fifo_empty : std_logic;
    signal fifo_din   : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_dout  : std_logic_vector(g_data_width - 1 downto 0);

    -- W0 calculation signals
    signal ready_v : std_logic;
    signal ready_z : std_logic;
    signal v : signed(g_data_width downto 0);
    signal z : signed(g_data_width + 1 downto 0);
    signal w0 : std_logic_vector(g_data_width - 1 downto 0);
    signal w0_valid : std_logic;
    signal w0_done : std_logic;
    signal u : integer range 0 to 1023;

    component fft
        generic (
            g_num_samples : integer := 512;
            g_data_width  : integer := 32;
            g_addr_width  : integer := 9
        );
        port (
            clk            : in std_logic;
            rst_n          : in std_logic;
            start          : in std_logic;
            data_in_valid  : in std_logic;
            done           : out std_logic;
            data_in        : in std_logic_vector(g_data_width - 1 downto 0);
            data_out       : out std_logic_vector(g_data_width - 1 downto 0);
            data_out_valid : out std_logic
        );
    end component;

    component ifft
        generic (
            g_num_samples : integer := 512;
            g_data_width  : integer := 32;
            g_addr_width  : integer := 9
        );
        port (
            clk            : in std_logic;
            rst_n          : in std_logic;
            start          : in std_logic;
            data_in_valid  : in std_logic;
            done           : out std_logic;
            data_in        : in std_logic_vector(g_data_width - 1 downto 0);
            data_out       : out std_logic_vector(g_data_width - 1 downto 0);
            data_out_valid : out std_logic
        );
    end component;


    component blk_mem_gen_1
		port (
			clka  : in  std_logic;
			ena   : in  std_logic;
			wea   : in  std_logic_vector(0 downto 0);
			addra : in  std_logic_vector(8 downto 0);
			dina  : in  std_logic_vector(g_data_width-1 downto 0);
			douta : out std_logic_vector(g_data_width-1 downto 0);
			clkb  : in  std_logic;
			enb   : in  std_logic;
			web   : in  std_logic_vector(0 downto 0);
			addrb : in  std_logic_vector(8 downto 0);
            dinb  : in  std_logic_vector(g_data_width-1 downto 0);
            doutb : out std_logic_vector(g_data_width-1 downto 0)
		);
	end component;

    component fifo_generator_0
        port (
            clk   : in  std_logic;
            srst  : in  std_logic;
            din   : in  std_logic_vector(g_data_width - 1 downto 0);
            wr_en : in  std_logic;
            rd_en : in  std_logic;
            dout  : out std_logic_vector(g_data_width - 1 downto 0);
            full  : out std_logic;
            empty : out std_logic
        );
    end component;

begin

    data_out_valid <= data_out_valid_reg;

    -- Registro del estado. El reset es sincrono y activo a nivel bajo.
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

    -- Logica combinacional de transicion y control de los puertos de RAM.
    -- Los valores por defecto deshabilitan ambos puertos y evitan latches.
    p_next_state : process(all)
    begin
        next_state <= state;

        q00_ena <= '0';
        q01_ena <= '0';
        w1_ena  <= '0';
        q00_wea <= (others => '0');
        q01_wea <= (others => '0');
        w1_wea  <= (others => '0');
        done <= '0';
        case state is
            when ST_IDLE =>
                if start = '1' then
                    next_state <= ST_RESCALE;
                end if;

            when ST_RESCALE =>
                if data_in_valid = '1' then
                    next_state <= ST_WR_FFT;
                end if;

            when ST_WR_FFT =>
                -- FFTs calculated stored in BRAMS.
                if rescale_valid = '1' then
                    q00_ena <= '1';
                    q01_ena <= '1';
                    w1_ena  <= '1';
                    q00_wea <= (others => '1');
                    q01_wea <= (others => '1');
                    w1_wea  <= (others => '1');

                    if unsigned(ram_addra) = g_num_samples - 1 then
                        next_state <= ST_COMMIT_FFT;
                    end if;
                end if;

            when ST_COMMIT_FFT =>
                next_state <= ST_RD_FFT;

            when ST_RD_FFT =>
                next_state <= ST_WAIT_FFT;

            when ST_WAIT_FFT =>
                next_state <= ST_CAPTURE_FFT;

            when ST_CAPTURE_FFT =>
                q00_ena <= '1';
                q01_ena <= '1';
                q01_enb <= '1';

                w1_ena <= '1';
                w1_enb <= '1';

                next_state <= CALC;

            when ST_CALC_X =>
                -- Forma T_re y T_im sumando/restando los productos.
                next_state <= ST_WR_T1;

            when ST_WR_Q01 =>
                next_state <= ST_COMMIT_Q01;

            when ST_COMMIT_Q01 =>
                -- Escribe la primera salida de la mariposa en v y v+n/2.
                q01_ena <= '1';
                q01_enb <= '1';
                q01_wea <= (others => '1');
                q01_web <= (others => '1');
                if u = unsigned(g_num_samples/2 - 1) then
                    next_state <= ST_RD_FFT;
                else
                    next_state <= ST_RD_Q01;
                end if;

            when ST_RD_Q01 =>
                -- Ceba la lectura secuencial final empezando por la direccion 0.
                q01_ena <= '1';
                next_state <= ST_RD_Q01_WAIT;

            when ST_RD_Q01_WAIT =>
                next_state <= ST_RD_Q01_CAPTURE;

            when ST_RD_Q01_CAPTURE =>
                -- Una vez cebada la BRAM se obtiene una palabra por ciclo.
                q01_ena <= '1';
                if ifft_out_count = g_num_samples - 1 then
                    next_state <= ST_DONE;
                end if;

            when ST_WR_FIFO =>
                
            when ST_CALC_W0 =>
                next_state <= ST_DONE;

            when ST_DONE =>
                -- Pulso de un ciclo; coincide con la ultima salida valida.
                done <= '1';
                next_state <= ST_IDLE;
        end case;
    end process p_next_state;

    -- Datapath secuencial: registra direcciones, datos, productos, resultados
    -- de mariposa y contadores. Las escrituras se preparan en ST_WR_* y se
    -- ejecutan en el estado ST_COMMIT_* correspondiente.
    p_counter : process(clk) begin
        if rising_edge(clk) then
            if rst_n = '0' then
                delta_real <= (others => '0');
                delta_imag <= (others => '0');
                prod_uu <= (others => '0');
                prod_un <= (others => '0');
                prod_nu <= (others => '0');
                prod_nn <= (others => '0');
                read_valid <= '0';
                w1 <= (others => '0');
                q00 <= (others => '0');
                q01 <= (others => '0');
                rescale_valid <= '0';
                rescale_cnt <= 0;
                error_flag <= '0';
                alpha <= (others => '0');
                fft_addr <= (others => '0');

            else
                data_out_valid_reg <= '0';
                read_valid <= '0';
                rescale_valid <= data_in_valid;
                case state is
                when ST_IDLE =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');
                    ram_addra_q00 <= (others => '0');
                    ram_addra_q01 <= (others => '0');
                    ram_addra_w1  <= (others => '0');
                    rom_enable  <= '0';

                    t  <= std_logic_vector(shift_right(to_unsigned(g_num_samples, t'length), 1));
                    m  <= std_logic_vector(to_unsigned(2, m'length));
                    u  <= (others => '0');
                    v  <= (others => '0');
                    v0 <= (others => '0');
                    fft_out_count <= 0;

                    w1 <= (others => '0');
                    q00 <= (others => '0');
                    q01 <= (others => '0');
                    alpha <= (others => '0');

                    fft_addr <= (others => '0');

                when ST_RESCALE =>
                    w1 <= std_logic_vector(shift_left(signed(data_w1), c_w1));
                    q00 <= std_logic_vector(shift_left(signed(data_q00), c_q00));
                    q01 <= std_logic_vector(shift_left(signed(data_q01), c_q01));
                    rescale_cnt <= rescale_cnt + 1;

                    if rescale_cnt = 0 then
                        if to_integer(signed(data_q00)) < 0 then
                            error_flag <= '1';
                        else
                            error_flag <= '0';
                        end if;
                        q00 <= (others => '0');
                        alpha <= shift_left(signed(data_q00), c_alpha_shift);
                    end if;

                when ST_WR_FFT =>
                    if rescale_valid = '1' then
                        if unsigned(fft_addr) = g_num_samples - 1 then
                            fft_addr <= (others => '0');
                        else
                            fft_addr <= std_logic_vector(unsigned(fft_addr) + 1);
                        end if;
                    end if;

                when ST_COMMIT_FFT =>
                    null;

                when ST_RD_FFT =>
                    q00_addra <= std_logic_vector(resize(unsigned(u), q00_addra'length));
                
                    q01_addra <= std_logic_vector(resize(unsigned(u), q01_addra'length));
                    q01_addrb <= std_logic_vector(resize(unsigned(u) + to_unsigned(g_num_samples / 2, v'length), q01_addrb'length));

                    w1_addra <= std_logic_vector(resize(unsigned(u), w1_addra'length));
                    w1_addrb <= std_logic_vector(resize(unsigned(u) + to_unsigned(g_num_samples / 2, v'length), w1_addrb'length));

                when ST_WAIT_FFT =>
                    null;

                when ST_CAPTURE_FFT =>

                    prod_uu <= signed(q01_douta) * signed(w1_douta);
                    prod_un <= signed(q01_douta) * signed(w1_doutb);
                    prod_nu <= signed(q01_doutb) * signed(w1_douta);
                    prod_nn <= signed(q01_doutb) * signed(w1_doutb);

                    v <= alpha + signed(q00_douta);

                when ST_CALC_X =>
                    -- Multiplicacion compleja: x2*(eps_re+j*eps_im).
                    x_re <= prod_uu - prod_nn;
                    x_im <= prod_un + prod_nu;

                when ST_WR_Q01 =>
                    -- floor((2^31*x1 + T)/2^32). shift_right sobre signed
                    -- implementa la division aritmetica indicada en la norma.

                    q01_addra <= std_logic_vector(resize(unsigned(u), q01_addra'length));
                    q01_addrb <= std_logic_vector(resize(unsigned(u) + to_unsigned(g_num_samples / 2, u'length), q01_addrb'length));
                    q01_dina  <= std_logic_vector(resize((x_re / resize(v, x_re'length)), q01_dina'length));
                    q01_dinb  <= std_logic_vector(resize((x_im / resize(v, x_im'length)), q01_dinb'length));

                    if to_integer(v) <= 0 then
                        error_flag <= '1';
                    elsif v >= to_signed(2**30, v'length) then
                        error_flag <= '1';
                    elsif x_re >= shift_left(resize(v, x_re'length), 32) then
                        error_flag <= '1';
                    elsif x_im >= shift_left(resize(v, x_im'length), 32) then
                        error_flag <= '1';
                    else
                        error_flag <= '0';
                    end if;

                when ST_COMMIT_Q01 =>
                    if to_integer(u) == g_num_samples/2 - 1 then
                        u <= (others => '0');
                    else
                        u <= u + unsigned(1, u'length);
                    end if;
                
                when ST_RD_Q01 =>
                    q01_addra <= (others => '0');
                    addr_count <= 0;

                when ST_RD_Q01_WAIT =>
                    -- La direccion 0 esta en vuelo; se adelanta la direccion 1.
                    ram_addra <= std_logic_vector(unsigned(ram_addra) + to_unsigned(1, ram_addra'length));

                when ST_RD_Q01_CAPTURE =>
                    -- count es la palabra capturada, count+1 ya esta en vuelo
                    -- y count+2 es la siguiente direccion que debe solicitarse.
                    ifft_data_in    <= q01_douta;
                    ifft_valid_in   <= '1';

                    if addr_count < g_num_samples - 1 then
                        addr_count <= addr_count + 1;

                        if addr_count < g_num_samples - 2 then
                            ram_addra <= std_logic_vector(to_unsigned(
                                addr_count + 2, ram_addra'length));
                        end if;
                    end if;
                when ST_CALC_W0 =>
                    fifo_wr_en <= '1';
                    if fifo_wr_en = '1' then
                        ready_v <= '1';
                        if h0(u) = '1' then
                            v <= signed(fifo_dout) + shift_left(to_signed(1, v'length), c_s0);
                        else
                            v <= resize(signed(fifo_dout), v'length);
                        end if;
                    else
                        v <= (others => '0');
                    end if;

                    if ready_v = '1' then
                        z <= shift_right((v + shift_left(to_signed(1, v'length), c_s0)), 1 + c_s0);
                        ready_z <= '1';
                    end if;

                    if ready_z = '1' then
                        w0_valid <= '1';
                        if z < -2**c_high_s0 or z >= 2**c_high_s0 then
                            error_flag <= '1';
                        end if;
                        if h0(u) = '1' then
                            w0 <= std_logic_vector(to_signed(1, w0'length + 1) - shift_left((z), 1));
                        else
                            w0 <= std_logic_vector(-shift_left((z), 1));
                        end if;
                        u <= u + 1;

                    end if;

                when ST_DONE =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');
                    w0_done <= '1';

                when others =>
                    null;
                end case;
            end if;
        end if;
    end process p_counter;

    q00_addra <= fft_addr when state = ST_WR_FFT else (others => '0');
    q01_addra <= fft_addr when state = ST_WR_FFT else (others => '0');
    w1_addra  <= fft_addr when state = ST_WR_FFT else (others => '0');

    error <= error_flag;
    data_out <= w0;
    data_out_valid <= w0_valid;
    done <= w0_done;

    ram_fft : blk_mem_gen_1
		port map (
			clka  => clk,
			ena   => ram_fft_en,
			wea   => ram_fft_we,
			addra => ram_addra,
			dina  => ram_dina,
			douta => ram_douta,
			clkb  => clk,
			enb   => ram_fft_enb,
			web   => ram_fft_web,
			addrb => ram_addrb,
            dinb  => data_b,
            doutb => ram_doutb
		);

    fft_q00 : fft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  rst_n,
            start           =>  start,
            data_in_valid   =>  rescale_valid,
            done            =>  fft_q00_done,
            data_in         =>  q00,
            data_out        =>  fft_q00,
            data_out_valid  =>  fft_q00_valid
        );

    fft_q01 : fft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  rst_n,
            start           =>  start,
            data_in_valid   =>  rescale_valid,
            done            =>  fft_q01_done,
            data_in         =>  q01,
            data_out        =>  fft_q01,
            data_out_valid  =>  fft_q01_valid
        );

    fft_w1 : fft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  rst_n,
            start           =>  start,
            data_in_valid   =>  rescale_valid,
            done            =>  fft_w1_done,
            data_in         =>  w1,
            data_out        =>  fft_w1,
            data_out_valid  =>  fft_w1_valid
        );

    ifft_q01 : ifft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  rst_n,
            start           =>  start,
            data_in_valid   =>  ifft_valid_in,
            done            =>  ifft_done,
            data_in         =>  ifft_data_in,
            data_out        =>  ifft_data_out,
            data_out_valid  =>  ifft_valid_out
        );

    input_q00_ram : blk_mem_gen_1
        port map (
            clka => clk, 
            ena => q00_ena, 
            wea => q00_wea,
            addra => q00_addra, 
            dina => q00_dina, 
            douta => q00_douta,
            clkb => clk, 
            enb => q00_enb, 
            web => q00_web,
            addrb => q00_addrb, 
            dinb => q00_dinb, 
            doutb => q00_doutb
        );

    input_q01_ram : blk_mem_gen_1
        port map (
            clka => clk, 
            ena => q01_ena, 
            wea => q01_wea,
            addra => q01_addra, 
            dina => q01_dina, 
            douta => q01_douta,
            clkb => clk, 
            enb => q01_enb, 
            web => q01_web,
            addrb => q01_addrb, 
            dinb => q01_dinb, 
            doutb => q01_doutb
        );

    input_w1_ram : blk_mem_gen_1
        port map (
            clka => clk, 
            ena => w1_ena, 
            wea => w1_wea,
            addra => w1_addra, 
            dina => w1_dina, 
            douta => w1_douta,
            clkb => clk, 
            enb => w1_enb, 
            web => w1_web,
            addrb => w1_addrb, 
            dinb => w1_dinb, 
            doutb => w1_doutb
        );

    fifo_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not rst_n,
            din   => ifft_data_out,
            wr_en => fifo_wr_en,
            rd_en => fifo_rd_en,
            dout  => fifo_dout,
            full  => fifo_full,
            empty => fifo_empty
        );

end architecture rtl;
