library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ifft is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 32;
        g_addr_width  : integer := 9
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        data_in_valid : in std_logic;
        done        : out std_logic;
        data_in     : in std_logic_vector(g_data_width - 1 downto 0);
        data_out    : out std_logic_vector(g_data_width - 1 downto 0);
        data_out_valid : out std_logic
    );
end entity ifft;

architecture rtl of ifft is

    -- La carga inicial acepta una palabra por ciclo cuando data_in_valid=1.
    -- El resto de la FSM separa las peticiones a memoria, los ciclos de
    -- espera y la captura/confirmacion para respetar las latencias sincrónicas.
    type state_t is (ST_IDLE, ST_INIT_RAM, ST_RD_DELTA, ST_WAIT_DELTA, ST_CAPTURE_DELTA, ST_RD_X1, ST_WAIT_X1, ST_CAPTURE_X1, ST_RD_X2, ST_WAIT_X2, ST_CAPTURE_X2, ST_TRANSFORM, ST_MUL, ST_WR_T1, ST_COMMIT_T1, ST_WR_T2, ST_COMMIT_T2, ST_RD_IFFT_INIT, ST_RD_IFFT_WAIT, ST_RD_IFFT, ST_DONE);
    signal state     : state_t;
    signal next_state : state_t;

    signal ram_ifft_ena : std_logic;
    signal ram_ifft_wea : std_logic_vector(0 downto 0);
    signal ram_ifft_enb : std_logic;
    signal ram_ifft_web : std_logic_vector(0 downto 0);

    signal ram_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal ram_addrb : std_logic_vector(g_addr_width - 1 downto 0);

    signal ram_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_doutb : std_logic_vector(g_data_width - 1 downto 0);

    -- La representacion IFFT ocupa n palabras: las posiciones 0..n/2-1
    -- contienen las partes reales y n/2..n-1 las partes imaginarias.
    -- Los dos puertos permiten acceder a ambas partes en el mismo ciclo.
    signal data_a : std_logic_vector(g_data_width - 1 downto 0);
    signal data_b : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_dina : std_logic_vector(g_data_width - 1 downto 0);

    -- Cuenta las palabras ya entregadas durante la lectura final. Tras cebar
    -- la tuberia de lectura, data_out_valid se activa durante 512 ciclos.
    signal ifft_out_count : integer range 0 to g_num_samples - 1 := 0;
    signal data_out_valid_reg : std_logic := '0';

    -- Variables de los tres bucles del Algoritmo 16:
    --   while m < n; u = 0..m/2-1; v = v0..v0+t/2-1.
    -- Al finalizar un grupo se hace v0 <- v0+t; al finalizar una etapa,
    -- t <- t/2 y m <- 2*m.
    signal t  : std_logic_vector(12 downto 0);
    signal m  : std_logic_vector(12 downto 0);
    signal u  : std_logic_vector(12 downto 0);
    signal v  : std_logic_vector(12 downto 0);
    signal v0 : std_logic_vector(12 downto 0);

    signal addr_delta : std_logic_vector(9 downto 0);
    signal rom_delta  : std_logic_vector(2 * g_data_width - 1 downto 0);
    signal delta_real : signed(g_data_width - 1 downto 0);
    signal delta_imag : signed(g_data_width - 1 downto 0);
    signal rom_enable : std_logic;

    signal x1_real : signed(g_data_width - 1 downto 0);
    signal x1_imag : signed(g_data_width - 1 downto 0);
    signal x2_real : signed(g_data_width - 1 downto 0);
    signal x2_imag : signed(g_data_width - 1 downto 0);

    -- Un producto 32x32 ocupa 64 bits. La suma o resta de dos productos
    -- necesita un bit adicional, por eso T_re y T_im tienen 65 bits.
    signal t1_real : signed(g_data_width downto 0);
    signal t1_imag : signed(g_data_width downto 0);
    signal t2_real : signed(g_data_width downto 0);
    signal t2_imag : signed(g_data_width downto 0);

    signal prod_rr : signed(2 * g_data_width downto 0);
    signal prod_ii : signed(2 * g_data_width downto 0);
    signal prod_ri : signed(2 * g_data_width downto 0);
    signal prod_ir : signed(2 * g_data_width downto 0);

    signal data_out_reg : std_logic_vector(g_data_width - 1 downto 0);

    signal read_valid : std_logic;

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

    component blk_mem_gen_2
        port (
            clka  : in  std_logic;
            ena   : in  std_logic;
            addra : in  std_logic_vector(9 downto 0);
            douta : out std_logic_vector(2 * g_data_width - 1 downto 0)
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

        ram_ifft_ena <= '0';
        ram_ifft_wea <= (others => '0');
        ram_ifft_enb <= '0';
        ram_ifft_web <= (others => '0');
        done <= '0';
        case state is
            when ST_IDLE =>
                if start = '1' then
                    next_state <= ST_INIT_RAM;
                end if;

            when ST_INIT_RAM =>
                -- La BRAM escribe data_in en el mismo flanco en el que valid
                -- esta activo. Si valid baja, se conservan dato y direccion.
                if data_in_valid = '1' then
                    ram_ifft_ena <= '1';
                    ram_ifft_wea <= (others => '1');

                    if unsigned(ram_addra) = g_num_samples - 1 then
                        next_state <= ST_RD_DELTA;
                    end if;
                end if;

            when ST_RD_DELTA =>
                -- Inicia la lectura de Delta[u+m].
                next_state <= ST_WAIT_DELTA;

            when ST_WAIT_DELTA =>
                if read_valid = '1' then
                    next_state <= ST_CAPTURE_DELTA;
                end if;

            when ST_CAPTURE_DELTA =>
                next_state <= ST_RD_X1;

            when ST_RD_X1 =>
                -- Solicita simultaneamente x1,re=a[v] y x1,im=a[v+n/2].
                ram_ifft_ena <= '1';
                ram_ifft_enb <= '1';
                next_state <= ST_WAIT_X1;

            when ST_WAIT_X1 =>
                ram_ifft_ena <= '1';
                ram_ifft_enb <= '1';
                if read_valid = '1' then
                    next_state <= ST_CAPTURE_X1;
                end if;

            when ST_CAPTURE_X1 =>
                next_state <= ST_RD_X2;

            when ST_RD_X2 =>
                -- Solicita x2 en v+t/2 y su parte imaginaria en n/2.
                ram_ifft_ena <= '1';
                ram_ifft_enb <= '1';
                next_state <= ST_WAIT_X2;

            when ST_WAIT_X2 =>
                ram_ifft_ena <= '1';
                ram_ifft_enb <= '1';
                if read_valid = '1' then
                    next_state <= ST_CAPTURE_X2;
                end if;

            when ST_CAPTURE_X2 =>
                next_state <= ST_TRANSFORM;
            
            when ST_TRANSFORM =>
                -- Forma T_re y T_im sumando/restando los productos.
                next_state <= ST_MUL;
        
            when ST_MUL =>
                -- Los cuatro productos complejos se registran en esta etapa.
                next_state <= ST_WR_T1;

            when ST_WR_T1 =>
                next_state <= ST_COMMIT_T1;

            when ST_COMMIT_T1 =>
                -- Escribe la primera salida de la mariposa en v y v+n/2.
                ram_ifft_ena <= '1';
                ram_ifft_wea <= (others => '1');
                ram_ifft_enb <= '1';
                ram_ifft_web <= (others => '1');
                next_state <= ST_WR_T2;

            when ST_WR_T2 =>
                next_state <= ST_COMMIT_T2;

            when ST_COMMIT_T2 =>
                -- Escribe la segunda salida en v+t/2. Despues decide si
                -- continua el grupo, avanza de grupo o termina una etapa.
                ram_ifft_ena <= '1';
                ram_ifft_wea <= (others => '1');
                ram_ifft_enb <= '1';
                ram_ifft_web <= (others => '1');
                if unsigned(v) = unsigned(v0) + shift_right(unsigned(t), 1) - 1 then

                    if unsigned(u) = shift_right(unsigned(m), 1) - 1 and unsigned(m) = 2 then
                        next_state <= ST_RD_IFFT_INIT;
                    else
                        next_state <= ST_RD_DELTA;
                    end if;
                else
                    next_state <= ST_RD_X1;
                end if;

            when ST_RD_IFFT_INIT =>
                -- Ceba la lectura secuencial final empezando por la direccion 0.
                ram_ifft_ena <= '1';
                next_state <= ST_RD_IFFT_WAIT;

            when ST_RD_IFFT_WAIT =>
                ram_ifft_ena <= '1';
                if read_valid = '1' then
                    next_state <= ST_RD_IFFT;
                end if;

            when ST_RD_IFFT =>
                -- Una vez cebada la BRAM se obtiene una palabra por ciclo.
                ram_ifft_ena <= '1';
                if ifft_out_count = g_num_samples - 1 then
                    next_state <= ST_DONE;
                end if;

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
                ram_addra <= (others => '0');
                ram_addrb <= (others => '0');
                rom_enable  <= '0';
                ifft_out_count <= 0;
                data_out_valid_reg <= '0';
                data_out_reg <= (others => '0');
                x1_real <= (others => '0');
                x1_imag <= (others => '0');
                x2_real <= (others => '0');
                x2_imag <= (others => '0');
                t <= (others => '0');
                m <= (others => '0');
                u <= (others => '0');
                v <= (others => '0');
                v0 <= (others => '0');
                delta_real <= (others => '0');
                delta_imag <= (others => '0');
                prod_rr <= (others => '0');
                prod_ii <= (others => '0');
                prod_ri <= (others => '0');
                prod_ir <= (others => '0');
                t1_real <= (others => '0');
                t1_imag <= (others => '0');
                t2_real <= (others => '0');
                t2_imag <= (others => '0');
                data_a <= (others => '0');
                data_b <= (others => '0');
                read_valid <= '0';
            else
                data_out_valid_reg <= '0';
                read_valid <= '0';
                case state is
                when ST_IDLE =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');
                    rom_enable  <= '0';

                    t  <= std_logic_vector(to_unsigned(2, t'length));
                    m  <= std_logic_vector(shift_right(to_unsigned(g_num_samples, m'length), 1));
                    u  <= (others => '0');
                    v  <= (others => '0');
                    v0 <= (others => '0');
                    ifft_out_count <= 0;

                when ST_INIT_RAM =>
                    if data_in_valid = '1' then
                        if unsigned(ram_addra) = g_num_samples - 1 then
                            ram_addra <= (others => '0');
                        else
                            ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);
                        end if;
                    end if;

                when ST_RD_DELTA =>
                    rom_enable <= '1';

                when ST_WAIT_DELTA =>
                    rom_enable <= '1';
                    read_valid <= '1';

                when ST_CAPTURE_DELTA =>
                    rom_enable <= '0';
                    -- Delta se almacena en formato complejo Q31: parte real
                    -- en los 32 bits bajos e imaginaria en los 32 altos.
                    delta_real <= signed(rom_delta(g_data_width - 1 downto 0));
                    delta_imag <= -signed(rom_delta(2 * g_data_width - 1 downto g_data_width));
                    v <= v0;

                when ST_RD_X1 =>
                    ram_addra <= std_logic_vector(resize(
                        unsigned(v), ram_addra'length));
                    ram_addrb <= std_logic_vector(resize(
                        unsigned(v) + to_unsigned(g_num_samples / 2, v'length),
                        ram_addrb'length));

                when ST_WAIT_X1 =>
                    read_valid <= '1';

                when ST_CAPTURE_X1 =>
                    x1_real <= signed(ram_douta);
                    x1_imag <= signed(ram_doutb);

                when ST_RD_X2 =>
                    ram_addra <= std_logic_vector(resize(
                        unsigned(v) + shift_right(unsigned(t), 1),
                        ram_addra'length));
                    ram_addrb <= std_logic_vector(resize(
                        unsigned(v) + shift_right(unsigned(t), 1) +
                        to_unsigned(g_num_samples / 2, v'length),
                        ram_addrb'length));

                when ST_WAIT_X2 =>
                    read_valid <= '1';

                when ST_CAPTURE_X2 =>
                    x2_real <= signed(ram_douta);
                    x2_imag <= signed(ram_doutb);

                when ST_TRANSFORM =>
                    -- t1_re=x1,re+x2,re, t1_im=x1,im+x2,im
                    -- t2_re=x1,re-x2,re, t2_im=x1,im-x2,im
                    t1_real <= resize(x1_real, g_data_width + 1) + resize(x2_real, g_data_width + 1);
                    t1_imag <= resize(x1_imag, g_data_width + 1) + resize(x2_imag, g_data_width + 1);
                    t2_real <= resize(x1_real, g_data_width + 1) - resize(x2_real, g_data_width + 1);
                    t2_imag <= resize(x1_imag, g_data_width + 1) - resize(x2_imag, g_data_width + 1);

                when ST_MUL =>
                    -- Multiplicacion compleja: x2*(eps_re+j*eps_im).
                    prod_rr <= t2_real * delta_real;
                    prod_ii <= t2_imag * delta_imag;
                    prod_ri <= t2_real * delta_imag;
                    prod_ir <= t2_imag * delta_real;

                when ST_WR_T1 =>
                    -- floor((2^31*x1 + T)/2^32). shift_right sobre signed
                    -- implementa la division aritmetica indicada en la norma.
                    ram_addra <= std_logic_vector(resize(
                        unsigned(v), ram_addra'length));
                    ram_addrb <= std_logic_vector(resize(
                        unsigned(v) + to_unsigned(g_num_samples / 2, v'length),
                        ram_addrb'length));
                    data_a <= std_logic_vector(resize(shift_right(t1_real, 1), g_data_width));
                    data_b <= std_logic_vector(resize(shift_right(t1_imag, 1), g_data_width));

                when ST_COMMIT_T1 =>
                    null;

                when ST_WR_T2 =>
                    -- floor((2^31*x1 - T)/2^32), segunda salida.
                    ram_addra <= std_logic_vector(resize(
                        unsigned(v) + unsigned(t) / 2,
                        ram_addra'length));
                    ram_addrb <= std_logic_vector(resize(
                        unsigned(v) + unsigned(t) / 2 +
                        to_unsigned(g_num_samples / 2, v'length),
                        ram_addrb'length));
                    data_a <= std_logic_vector(resize(shift_right((resize(prod_rr, 2 * g_data_width + 2) - resize(prod_ii, 2 * g_data_width + 2)), 32), g_data_width));
                    data_b <= std_logic_vector(resize(shift_right((resize(prod_ri, 2 * g_data_width + 2) + resize(prod_ir, 2 * g_data_width + 2)), 32), g_data_width));

                when ST_COMMIT_T2 =>
                    -- Actualiza los indices solo cuando ambas salidas ya han
                    -- sido escritas. Las condiciones usan los valores actuales
                    -- de v, u, t y m, anteriores a este flanco.
                    v <= std_logic_vector(unsigned(v) + to_unsigned(1, v'length));
                    if unsigned(v) = unsigned(v0) + shift_right(unsigned(t), 1) - 1 then

                        if unsigned(u) = shift_right(unsigned(m), 1) - 1 then
                            t  <= std_logic_vector(shift_left(unsigned(t), 1));
                            m  <= std_logic_vector(shift_right(unsigned(m), 1));
                            u  <= (others => '0');
                            v  <= (others => '0');
                            v0 <= (others => '0');
                        else
                            v0 <= std_logic_vector(unsigned(v0) + unsigned(t));
                            u  <= std_logic_vector(unsigned(u) + to_unsigned(1, u'length));
                            v  <= std_logic_vector(unsigned(v0) + unsigned(t));
                        end if;
                    end if;
                
                when ST_RD_IFFT_INIT =>
                    ram_addra <= (others => '0');
                    ifft_out_count <= 0;

                when ST_RD_IFFT_WAIT =>
                    -- La direccion 0 esta en vuelo; se adelanta la direccion 1.
                    ram_addra <= std_logic_vector(unsigned(ram_addra) + to_unsigned(1, ram_addra'length));
                    read_valid <= '1';

                when ST_RD_IFFT =>
                    -- count es la palabra capturada, count+1 ya esta en vuelo
                    -- y count+2 es la siguiente direccion que debe solicitarse.
                    data_out_reg <= ram_douta;
                    data_out_valid_reg <= '1';

                    if ifft_out_count < g_num_samples - 1 then
                        ifft_out_count <= ifft_out_count + 1;

                        if ifft_out_count < g_num_samples - 3 then
                            ram_addra <= std_logic_vector(to_unsigned(
                                ifft_out_count + 3, ram_addra'length));
                        end if;
                    end if;

                when ST_DONE =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');

                when others =>
                    ram_addra <= (others => '0');
                    ram_addrb <= (others => '0');
                    rom_enable  <= '0';
                end case;
            end if;
        end if;
    end process p_counter;

    -- Indice del twiddle de la etapa y grupo actuales.
    addr_delta <= std_logic_vector(resize(unsigned(u) + unsigned(m), addr_delta'length));
    data_out <= data_out_reg;
    -- Durante la carga se evita un registro intermedio: la BRAM muestrea el
    -- data_in actual en cada flanco valido. En las mariposas usa data_a.
    ram_dina <= data_in when state = ST_INIT_RAM else data_a;

    ram_ifft : blk_mem_gen_1
		port map (
			clka  => clk,
			ena   => ram_ifft_ena,
			wea   => ram_ifft_wea,
			addra => ram_addra,
			dina  => ram_dina,
			douta => ram_douta,
			clkb  => clk,
			enb   => ram_ifft_enb,
			web   => ram_ifft_web,
			addrb => ram_addrb,
            dinb  => data_b,
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
