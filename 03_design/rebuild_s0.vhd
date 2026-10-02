library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hawk_pkg.ALL;

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
        error          : out std_logic
    );
end entity rebuild_s0;

architecture rtl of rebuild_s0 is

    ---------------------------------------------------------------------------
    -- RebuildS0
    --
    --  1. Escala q00, q01 y w1 y calcula alpha a partir de q00[0].
    --  2. Calcula FFT(c_q00*z00), FFT(c_q01*q01) y FFT(c_w1*w1).
    --  3. Reconstruye qhat01 por parejas complejas u y u+n/2.
    --  4. Aplica la IFFT para obtener t.
    --  5. Calcula z=floor((c_s0*h0+t)/(2*c_q00)) y w0=h0-2*z.
    --
    -- Las lecturas de BRAM y FIFO se separan en estados de direccion,
    -- espera y captura para respetar sus latencias sincronas.
    ---------------------------------------------------------------------------
    type state_t is (
        ST_IDLE,

        -- Carga, escalado y FFT.
        ST_RESCALE,
        ST_WR_FFT,
        ST_COMMIT_FFT,

        -- Reconstruccion de qhat01 en el dominio FFT.
        ST_RD_FFT,
        ST_WAIT_FFT,
        ST_WAIT_FFT_2,
        ST_CAPTURE_FFT,
        ST_CALC_X,
        ST_WR_Q01,
        ST_COMMIT_Q01,

        -- Transferencia de qhat01 a la IFFT.
        ST_RD_Q01,
        ST_RD_Q01_WAIT,
        ST_RD_Q01_WAIT_2,
        ST_RD_Q01_CAPTURE,
        ST_WAIT_IFFT,

        -- Reconstruccion final de w0.
        ST_RD_FIFO,
        ST_WAIT_FIFO,
        ST_CALC_V,
        ST_CALC_Z,
        ST_OUTPUT_W0,

        ST_DONE,
        ST_ERROR
    );

    signal state      : state_t;
    signal next_state : state_t;
    signal core_rst_n : std_logic;

    ---------------------------------------------------------------------------
    -- Escalado de las entradas
    ---------------------------------------------------------------------------

    constant c_bits_samples : natural := clog2(g_num_samples);
    constant c_alpha_shift  : integer range 0 to 32 := c_q00_shift + 1 - c_bits_samples;

    signal q00           : std_logic_vector(g_data_width - 1 downto 0);
    signal q01           : std_logic_vector(g_data_width - 1 downto 0);
    signal w1            : std_logic_vector(g_data_width - 1 downto 0);
    signal rescale_valid : std_logic;
    signal rescale_cnt   : integer range 0 to 1024;

    signal error_flag : std_logic;
    signal alpha      : signed(g_data_width - 1 downto 0);

    ---------------------------------------------------------------------------
    -- Resultados de las tres FFT
    ---------------------------------------------------------------------------

    signal fft_q00_valid : std_logic;
    signal fft_q01_valid : std_logic;
    signal fft_w1_valid  : std_logic;

    signal fft_q00_done : std_logic;
    signal fft_q01_done : std_logic;
    signal fft_w1_done  : std_logic;

    signal fft_q00 : std_logic_vector(g_data_width - 1 downto 0);
    signal fft_q01 : std_logic_vector(g_data_width - 1 downto 0);
    signal fft_w1  : std_logic_vector(g_data_width - 1 downto 0);

    ---------------------------------------------------------------------------
    -- Memorias de resultados FFT
    ---------------------------------------------------------------------------

    signal q00_ena : std_logic;
    signal q01_ena : std_logic;
    signal w1_ena  : std_logic;

    signal q00_enb : std_logic;
    signal q01_enb : std_logic;
    signal w1_enb  : std_logic;

    signal q00_wea : std_logic_vector(0 downto 0);
    signal q01_wea : std_logic_vector(0 downto 0);
    signal w1_wea  : std_logic_vector(0 downto 0);

    signal q00_web : std_logic_vector(0 downto 0);
    signal q01_web : std_logic_vector(0 downto 0);
    signal w1_web  : std_logic_vector(0 downto 0);

    signal q00_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal q01_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal w1_addra  : std_logic_vector(g_addr_width - 1 downto 0);

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

    signal q01_a : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_b : std_logic_vector(g_data_width - 1 downto 0);

    ---------------------------------------------------------------------------
    -- Reconstruccion de qhat01
    ---------------------------------------------------------------------------

    signal prod_uu  : signed(2 * g_data_width - 1 downto 0);
    signal prod_nn  : signed(2 * g_data_width - 1 downto 0);
    signal prod_un  : signed(2 * g_data_width - 1 downto 0);
    signal prod_nu  : signed(2 * g_data_width - 1 downto 0);

    signal v    : signed(g_data_width downto 0);
    signal x_re : signed(2 * g_data_width downto 0);
    signal x_im : signed(2 * g_data_width downto 0);

    ---------------------------------------------------------------------------
    -- IFFT y almacenamiento temporal de t
    ---------------------------------------------------------------------------

    signal ifft_valid_in    : std_logic;
    signal ifft_valid_out   : std_logic;
    signal ifft_done        : std_logic;
    signal ifft_data_in     : std_logic_vector(g_data_width - 1 downto 0);
    signal ifft_data_out    : std_logic_vector(g_data_width - 1 downto 0);

    signal addr_count : integer range 0 to g_num_samples - 1 := 0;

    signal fifo_wr_en : std_logic;
    signal fifo_rd_en : std_logic;
    signal fifo_full  : std_logic;
    signal fifo_empty : std_logic;
    signal fifo_dout  : std_logic_vector(g_data_width - 1 downto 0);

    ---------------------------------------------------------------------------
    -- Reconstruccion final de w0
    ---------------------------------------------------------------------------

    signal z        : signed(g_data_width + 1 downto 0);
    signal w0       : std_logic_vector(g_data_width - 1 downto 0);
    signal w0_valid : std_logic;
    signal w0_done  : std_logic;

    -- Indice compartido por los bucles u=0..n/2-1 y u=0..n-1.
    signal u : unsigned(g_addr_width - 1 downto 0);

    ---------------------------------------------------------------------------
    -- Componentes de calculo y almacenamiento
    ---------------------------------------------------------------------------

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

    ---------------------------------------------------------------------------
    -- Control global
    ---------------------------------------------------------------------------

    -- Ante un error se reinician solamente los nucleos internos. La FSM
    -- principal permanece activa para generar error/done y volver a ST_IDLE.
    -- Esto evita reutilizar datos parciales en la operacion siguiente.
    core_rst_n <= '0' when state = ST_ERROR else rst_n;

    -- Registro de estado con reset sincrono activo a nivel bajo.
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

    ---------------------------------------------------------------------------
    -- FSM combinacional y control de las memorias
    ---------------------------------------------------------------------------
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

        q00_enb <= '0';
        q01_enb <= '0';
        w1_enb  <= '0';
        q00_web <= (others => '0');
        q01_web <= (others => '0');
        w1_web  <= (others => '0');
        case state is
            when ST_IDLE =>
                if start = '1' then
                    next_state <= ST_RESCALE;
                end if;

            when ST_RESCALE =>
                -- Se consumen exactamente n ternas (q00,q01,w1). Los huecos
                -- de data_in_valid no avanzan el contador.
                if data_in_valid = '1' then
                    if rescale_cnt = 0 and signed(data_q00) < 0 then
                        next_state <= ST_ERROR;
                    elsif rescale_cnt = g_num_samples - 1 then
                        next_state <= ST_WR_FFT;
                    end if;
                end if;

            when ST_WR_FFT =>
                -- Las tres FFT trabajan en paralelo. Cada salida valida se
                -- almacena en su BRAM utilizando un contador independiente.
                if fft_q00_valid = '1' then
                    q00_ena <= '1';
                    q00_wea <= (others => '1');
                end if;

                if fft_q01_valid = '1' then
                    q01_ena <= '1';
                    q01_wea <= (others => '1');
                end if;

                if fft_w1_valid = '1' then
                    w1_ena  <= '1';
                    w1_wea  <= (others => '1');
                end if;

                if fft_q00_valid = '1' and
                fft_q01_valid = '1' and
                fft_w1_valid  = '1' and
                unsigned(q00_addra) = g_num_samples - 1 and
                unsigned(q01_addra) = g_num_samples - 1 and
                unsigned(w1_addra)  = g_num_samples - 1 then
                    next_state <= ST_COMMIT_FFT;
                end if;

            when ST_COMMIT_FFT =>
                -- Ciclo de separacion entre la ultima escritura y la primera
                -- lectura de las memorias FFT.
                next_state <= ST_RD_FFT;

            when ST_RD_FFT =>
                -- Las direcciones u y u+n/2 se registran en el datapath.
                next_state <= ST_WAIT_FFT;

            when ST_WAIT_FFT =>
                -- Con las direcciones ya estables se solicita la lectura.
                q00_ena <= '1';
                q01_ena <= '1';
                q01_enb <= '1';

                w1_ena <= '1';
                w1_enb <= '1';

                next_state <= ST_WAIT_FFT_2;

            when ST_WAIT_FFT_2 =>
                -- Sin REGCE independiente, EN tambien habilita el registro
                -- de salida de la BRAM. Mantenerlo durante ambos ciclos.
                q00_ena <= '1';
                q01_ena <= '1';
                q01_enb <= '1';
                w1_ena <= '1';
                w1_enb <= '1';
                next_state <= ST_CAPTURE_FFT;

            when ST_CAPTURE_FFT =>
                -- dout ya es estable; los operandos se registran en este ciclo.
                next_state <= ST_CALC_X;

            when ST_CALC_X =>
                -- Forma X_re y X_im sumando/restando los cuatro productos.
                next_state <= ST_WR_Q01;

            when ST_WR_Q01 =>
                -- Comprueba las cotas antes de dividir. Si son validas, el
                -- datapath calcula los dos componentes reconstruidos.
                if v <= 0 then
                    next_state <= ST_ERROR;
                elsif v >= shift_left(to_signed(1, v'length), 30) then
                    next_state <= ST_ERROR;
                elsif abs(x_re) >= shift_left(resize(v, x_re'length), 32) then
                    next_state <= ST_ERROR;
                elsif abs(x_im) >= shift_left(resize(v, x_im'length), 32) then
                    next_state <= ST_ERROR;
                else
                    next_state <= ST_COMMIT_Q01;
                end if;

            when ST_COMMIT_Q01 =>
                -- Escribe qhat01[u] y qhat01[u+n/2] por los dos puertos.
                q01_ena <= '1';
                q01_enb <= '1';
                q01_wea <= (others => '1');
                q01_web <= (others => '1');
                if u = g_num_samples/2 - 1 then
                    next_state <= ST_RD_Q01;
                else
                    next_state <= ST_RD_FFT;
                end if;

            when ST_RD_Q01 =>
                -- Registra la direccion del coeficiente que se enviara a IFFT.
                next_state <= ST_RD_Q01_WAIT;

            when ST_RD_Q01_WAIT =>
                -- La direccion ya esta estable: se solicita la lectura.
                q01_ena <= '1';
                next_state <= ST_RD_Q01_WAIT_2;

            when ST_RD_Q01_WAIT_2 =>
                -- Habilita tambien el registro de salida de la BRAM.
                q01_ena <= '1';
                next_state <= ST_RD_Q01_CAPTURE;

            when ST_RD_Q01_CAPTURE =>
                -- La IFFT acepta huecos: solo se activa valid al capturar dout.
                if addr_count = g_num_samples - 1 then
                    next_state <= ST_WAIT_IFFT;
                else
                    next_state <= ST_RD_Q01;
                end if;

            when ST_WAIT_IFFT =>
                -- Las salidas de la IFFT se almacenan en la FIFO en paralelo.
                if ifft_done = '1' then
                    next_state <= ST_RD_FIFO;
                end if;

            when ST_RD_FIFO =>
                -- FIFO estandar: solicita una palabra solamente si no esta vacia.
                if fifo_empty = '0' then
                    next_state <= ST_WAIT_FIFO;
                end if;

            when ST_WAIT_FIFO =>
                -- Espera la latencia de lectura de la FIFO estandar.
                next_state <= ST_CALC_V;

            when ST_CALC_V =>
                -- v = c_s0*h0[u] + t[u].
                next_state <= ST_CALC_Z;

            when ST_CALC_Z =>
                -- z = floor(v/(2*c_q00)).
                next_state <= ST_OUTPUT_W0;

            when ST_OUTPUT_W0 =>
                -- Comprueba z y publica w0[u]=h0[u]-2*z.
                if z < to_signed(-(2**c_high_s0), z'length) or
                   z >= to_signed(2**c_high_s0, z'length) then
                    next_state <= ST_ERROR;
                elsif u = g_num_samples - 1 then
                    next_state <= ST_DONE;
                else
                    next_state <= ST_RD_FIFO;
                end if;

            when ST_DONE =>
                -- Pulso de finalizacion de un ciclo.
                next_state <= ST_IDLE;

            when ST_ERROR =>
                -- Termina sin producir mas coeficientes y limpia los nucleos.
                next_state <= ST_IDLE;
        end case;
    end process p_next_state;

    ---------------------------------------------------------------------------
    -- Datapath secuencial
    ---------------------------------------------------------------------------
    -- Registra datos, direcciones, productos y contadores. Las escrituras en
    -- BRAM se calculan primero y se ejecutan en el ST_COMMIT_* correspondiente.
    p_datapath : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                prod_uu <= (others => '0');
                prod_un <= (others => '0');
                prod_nu <= (others => '0');
                prod_nn <= (others => '0');
                w1 <= (others => '0');
                q00 <= (others => '0');
                q01 <= (others => '0');
                rescale_valid <= '0';
                rescale_cnt <= 0;
                error_flag <= '0';
                alpha <= (others => '0');
                u <= (others => '0');
                q01_a <= (others => '0');
                q01_b <= (others => '0');
                x_re <= (others => '0');
                x_im <= (others => '0');
                w0_valid     <= '0';
                w0_done      <= '0';
                fifo_rd_en   <= '0';
                ifft_valid_in <= '0';
                addr_count   <= 0;
                v            <= (others => '0');
                z            <= (others => '0');
                w0           <= (others => '0');

            else
                rescale_valid <= '0';
                fifo_rd_en <= '0';
                ifft_valid_in <= '0';
                w0_valid <= '0';
                w0_done <= '0';
                case state is
                when ST_IDLE =>

                    w1 <= (others => '0');
                    q00 <= (others => '0');
                    q01 <= (others => '0');
                    alpha <= (others => '0');
                    error_flag <= '0';
                    rescale_cnt <= 0;
                    q00_addra <= (others => '0');
                    q01_addra <= (others => '0');
                    w1_addra  <= (others => '0');
                    u <= (others => '0');
                    prod_uu <= (others => '0');
                    prod_un <= (others => '0');
                    prod_nu <= (others => '0');
                    prod_nn <= (others => '0');
                    q01_a <= (others => '0');
                    q01_b <= (others => '0');

                when ST_RESCALE =>
                    if data_in_valid = '1' then
                        rescale_valid <= '1';

                        -- c_w1=2^c_w1_shift y c_q01=2^c_q01_shift.
                        w1 <= std_logic_vector(
                            shift_left(signed(data_w1), c_w1_shift));

                        q01 <= std_logic_vector(
                            shift_left(signed(data_q01), c_q01_shift));

                        if rescale_cnt = 0 then
                            -- q00[0] se conserva en alpha, se comprueba su
                            -- signo y despues se fuerza z00[0]=0.
                            if signed(data_q00) < 0 then
                                error_flag <= '1';
                            end if;

                            alpha <= shift_left(
                                resize(signed(data_q00), alpha'length),
                                c_alpha_shift);

                            q00 <= (others => '0');
                        else
                            -- Resto de z00: c_q00*q00[i].
                            q00 <= std_logic_vector(
                                shift_left(signed(data_q00), c_q00_shift));
                        end if;

                        if rescale_cnt = g_num_samples - 1 then
                            rescale_cnt <= 0;
                        else
                            rescale_cnt <= rescale_cnt + 1;
                        end if;
                    end if;

                when ST_WR_FFT =>
                    if fft_q00_valid = '1' then
                        if unsigned(q00_addra) = g_num_samples - 1 then
                            q00_addra <= (others => '0');
                        else
                            q00_addra <= std_logic_vector(unsigned(q00_addra) + 1);
                        end if;
                    end if;

                    if fft_q01_valid = '1' then
                        if unsigned(q01_addra) = g_num_samples - 1 then
                            q01_addra <= (others => '0');
                        else
                            q01_addra <= std_logic_vector(unsigned(q01_addra) + 1);
                        end if;
                    end if;

                    if fft_w1_valid = '1' then
                        if unsigned(w1_addra) = g_num_samples - 1 then
                            w1_addra <= (others => '0');
                        else
                            w1_addra <= std_logic_vector(unsigned(w1_addra) + 1);
                        end if;
                    end if;

                when ST_COMMIT_FFT =>
                    null;

                when ST_RD_FFT =>
                    q00_addra <= std_logic_vector(resize(u, q00_addra'length));
                
                    q01_addra <= std_logic_vector(resize(u, q01_addra'length));
                    q01_addrb <= std_logic_vector(resize(u + to_unsigned(g_num_samples / 2, u'length), q01_addrb'length));

                    w1_addra <= std_logic_vector(resize(u, w1_addra'length));
                    w1_addrb <= std_logic_vector(resize(u + to_unsigned(g_num_samples / 2, u'length), w1_addrb'length));

                when ST_WAIT_FFT =>
                    null;

                when ST_WAIT_FFT_2 =>
                    null;

                when ST_CAPTURE_FFT =>
                    -- Producto complejo qhat01[u] * what1[u]. Los indices de
                    -- la segunda mitad representan las componentes imaginarias.
                    prod_uu <= signed(q01_douta) * signed(w1_douta);
                    prod_un <= signed(q01_douta) * signed(w1_doutb);
                    prod_nu <= signed(q01_doutb) * signed(w1_douta);
                    prod_nn <= signed(q01_doutb) * signed(w1_doutb);

                    v <= resize(alpha, v'length) + resize(signed(q00_douta), v'length);

                when ST_CALC_X =>
                    -- X_re = q01_re*w1_re - q01_im*w1_im.
                    -- X_im = q01_re*w1_im + q01_im*w1_re.
                    x_re <= resize(prod_uu, x_re'length) - resize(prod_nn, x_re'length);
                    x_im <= resize(prod_un, x_im'length) + resize(prod_nu, x_im'length);

                when ST_WR_Q01 =>
                    -- v = alpha + qhat00[u]. Las divisiones signed de VHDL
                    -- truncan hacia cero, equivalente a floor(abs(X)/v) y a
                    -- restaurar despues el signo indicado por el algoritmo.
                    q01_addra   <= std_logic_vector(resize(u, q01_addra'length));
                    q01_addrb   <= std_logic_vector(resize(u + to_unsigned(g_num_samples / 2, u'length), q01_addrb'length));

                    if v <= 0 then
                        error_flag <= '1';
                    elsif v >= shift_left(to_signed(1, v'length), 30) then
                        error_flag <= '1';
                    elsif abs(x_re) >= shift_left(resize(v, x_re'length), 32) then
                        error_flag <= '1';
                    elsif abs(x_im) >= shift_left(resize(v, x_im'length), 32) then
                        error_flag <= '1';
                    else
                        q01_a <= std_logic_vector(
                            resize(x_re / resize(v, x_re'length), q01_a'length));
                        q01_b <= std_logic_vector(
                            resize(x_im / resize(v, x_im'length), q01_b'length));
                    end if;

                when ST_COMMIT_Q01 =>
                    if to_integer(u) = g_num_samples/2 - 1 then
                        u <= (others => '0');
                        addr_count <= 0;
                    else
                        u <= u + 1;
                    end if;
                
                when ST_RD_Q01 =>
                    -- Lectura no canalizada: la IFFT recibe un valid por cada
                    -- coeficiente realmente capturado.
                    q01_addra <= std_logic_vector(
                        to_unsigned(addr_count, q01_addra'length));

                when ST_RD_Q01_WAIT =>
                    null;

                when ST_RD_Q01_WAIT_2 =>
                    null;

                when ST_RD_Q01_CAPTURE =>
                    ifft_data_in    <= q01_douta;
                    ifft_valid_in   <= '1';

                    if addr_count < g_num_samples - 1 then
                        addr_count <= addr_count + 1;
                    end if;

                when ST_WAIT_IFFT =>
                    null;
                
                when ST_RD_FIFO =>
                    if fifo_empty = '0' then
                        fifo_rd_en <= '1';
                    end if;

                when ST_WAIT_FIFO =>
                    -- FIFO estandar: espera tras activar rd_en.
                    null;

                when ST_CALC_V =>
                    -- v = c_s0*h0[u] + t[u], con c_s0=2^c_s0_shift.
                    if data_h0(to_integer(u)) = '1' then
                        v <= resize(signed(fifo_dout), v'length)
                           + shift_left(to_signed(1, v'length), c_s0_shift);
                    else
                        v <= resize(signed(fifo_dout), v'length);
                    end if;

                when ST_CALC_Z =>
                    -- shift_right sobre signed redondea hacia menos infinito:
                    -- z=floor(v/(2*c_q00)), 2*c_q00=2^(1+c_q00_shift).
                    z <= resize(shift_right(v, 1 + c_q00_shift), z'length);

                when ST_OUTPUT_W0 =>
                    if z < to_signed(-(2**c_high_s0), z'length) or
                       z >= to_signed(2**c_high_s0, z'length) then
                        error_flag <= '1';
                    else
                        -- Ultimo paso del algoritmo: w0[u]=h0[u]-2*z.
                        if data_h0(to_integer(u)) = '1' then
                            w0 <= std_logic_vector(resize(
                                to_signed(1, z'length) - shift_left(z, 1),
                                w0'length));
                        else
                            w0 <= std_logic_vector(resize(
                                -shift_left(z, 1),
                                w0'length));
                        end if;

                        w0_valid <= '1';
                    end if;

                    if u < g_num_samples - 1 then
                        u <= u + 1;
                    end if;

                when ST_DONE =>
                    w0_done <= '1';

                when ST_ERROR =>
                    error_flag <= '1';
                    w0_done <= '1';

                when others =>
                    null;
                end case;
            end if;
        end if;
    end process p_datapath;

    ---------------------------------------------------------------------------
    -- Seleccion de datos y salidas
    ---------------------------------------------------------------------------

    q00_dina <= fft_q00 when state = ST_WR_FFT else (others => '0');

    -- La memoria q01 guarda primero FFT(c_q01*q01) y despues se reutiliza
    -- para almacenar los dos cocientes reconstruidos de cada pareja compleja.
    q01_dina <= fft_q01 when state = ST_WR_FFT else
                q01_a   when state = ST_COMMIT_Q01 
                else (others => '0');
    q00_dinb <= (others => '0');
    q01_dinb <= q01_b   when state = ST_COMMIT_Q01 else (others => '0');
    w1_dina  <= fft_w1  when state = ST_WR_FFT else (others => '0');
    w1_dinb  <= (others => '0');

    fifo_wr_en <= ifft_valid_out when fifo_full = '0'
                  else '0';

    error <= error_flag;
    data_out <= w0;
    data_out_valid <= w0_valid;
    done <= w0_done;

    ---------------------------------------------------------------------------
    -- Transformadas
    ---------------------------------------------------------------------------

    fft_q00_inst : fft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  core_rst_n,
            start           =>  start,
            data_in_valid   =>  rescale_valid,
            done            =>  fft_q00_done,
            data_in         =>  q00,
            data_out        =>  fft_q00,
            data_out_valid  =>  fft_q00_valid
        );

    fft_q01_inst : fft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  core_rst_n,
            start           =>  start,
            data_in_valid   =>  rescale_valid,
            done            =>  fft_q01_done,
            data_in         =>  q01,
            data_out        =>  fft_q01,
            data_out_valid  =>  fft_q01_valid
        );

    fft_w1_inst : fft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  core_rst_n,
            start           =>  start,
            data_in_valid   =>  rescale_valid,
            done            =>  fft_w1_done,
            data_in         =>  w1,
            data_out        =>  fft_w1,
            data_out_valid  =>  fft_w1_valid
        );

    ifft_q01_inst : ifft 
        generic map (
            g_num_samples   =>  g_num_samples,
            g_data_width    =>  g_data_width,
            g_addr_width    =>  g_addr_width
            )
        port map (
            clk             =>  clk,
            rst_n           =>  core_rst_n,
            start           =>  start,
            data_in_valid   =>  ifft_valid_in,
            done            =>  ifft_done,
            data_in         =>  ifft_data_in,
            data_out        =>  ifft_data_out,
            data_out_valid  =>  ifft_valid_out
        );

    ---------------------------------------------------------------------------
    -- Memorias de resultados FFT
    ---------------------------------------------------------------------------

    q00_ram : blk_mem_gen_1
        port map (
            clka    => clk, 
            ena     => q00_ena, 
            wea     => q00_wea,
            addra   => q00_addra, 
            dina    => q00_dina, 
            douta   => q00_douta,
            clkb    => clk, 
            enb     => q00_enb, 
            web     => q00_web,
            addrb   => q00_addrb, 
            dinb    => q00_dinb, 
            doutb   => q00_doutb
        );

    q01_ram : blk_mem_gen_1
        port map (
            clka    => clk, 
            ena     => q01_ena, 
            wea     => q01_wea,
            addra   => q01_addra, 
            dina    => q01_dina, 
            douta   => q01_douta,
            clkb    => clk, 
            enb     => q01_enb, 
            web     => q01_web,
            addrb   => q01_addrb, 
            dinb    => q01_dinb, 
            doutb   => q01_doutb
        );

    w1_ram : blk_mem_gen_1
        port map (
            clka    => clk, 
            ena     => w1_ena, 
            wea     => w1_wea,
            addra   => w1_addra, 
            dina    => w1_dina, 
            douta   => w1_douta,
            clkb    => clk, 
            enb     => w1_enb, 
            web     => w1_web,
            addrb   => w1_addrb, 
            dinb    => w1_dinb, 
            doutb   => w1_doutb
        );

    ---------------------------------------------------------------------------
    -- FIFO de resultados t=InvFFT(qhat01)
    ---------------------------------------------------------------------------

    fifo_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => ifft_data_out,
            wr_en => fifo_wr_en,
            rd_en => fifo_rd_en,
            dout  => fifo_dout,
            full  => fifo_full,
            empty => fifo_empty
        );

end architecture rtl;
