library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ntt is
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
end entity ntt;

architecture rtl of ntt is

    -- La carga inicial acepta una palabra por ciclo cuando data_in_valid=1.
    -- El resto de la FSM separa las peticiones a memoria, los ciclos de
    -- espera y la captura/confirmacion para respetar las latencias sincrónicas.
    type state_t is (ST_IDLE, ST_INIT_RAM, ST_RD_GAMMA, ST_WAIT_GAMMA_1, 
                     ST_WAIT_GAMMA_2, ST_GAMMA_DELTA, ST_RD_U, ST_WAIT_U_1, 
                     ST_WAIT_U_2, ST_CAPTURE_U, ST_MUL, ST_TRANSFORM, ST_WR_U, 
                     ST_COMMIT_U, ST_RD_NTT_INIT, ST_RD_NTT_WAIT_1, 
                     ST_RD_NTT_WAIT_2, ST_RD_NTT_CAPTURE, ST_DONE);
    signal state     : state_t;
    signal next_state : state_t;

    signal ram_ntt_ena : std_logic;
    signal ram_ntt_wea : std_logic_vector(0 downto 0);
    signal ram_ntt_enb : std_logic;
    signal ram_ntt_web : std_logic_vector(0 downto 0);

    signal ram_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal ram_addrb : std_logic_vector(g_addr_width - 1 downto 0);

    signal ram_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_doutb : std_logic_vector(g_data_width - 1 downto 0);

    -- La representacion ntt ocupa n palabras: las posiciones 0..n/2-1
    -- contienen las partes reales y n/2..n-1 las partes imaginarias.
    -- Los dos puertos permiten acceder a ambas partes en el mismo ciclo.
    signal data_a : std_logic_vector(g_data_width - 1 downto 0);
    signal data_b : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_dina : std_logic_vector(g_data_width - 1 downto 0);

    -- Cuenta las palabras ya entregadas durante la lectura final. Tras cebar
    -- la tuberia de lectura, data_out_valid se activa durante 512 ciclos.
    signal ntt_out_count : integer range 0 to g_num_samples - 1 := 0;
    signal data_out_valid_reg : std_logic := '0';

    -- Variables de los tres bucles del Algoritmo 16:
    --   while m < n; u = 0..m/2-1; v = v0..v0+t/2-1.
    -- Al finalizar un grupo se hace v0 <- v0+t; al finalizar una etapa,
    -- t <- t/2 y m <- 2*m.
    signal t  : unsigned(12 downto 0);
    signal m  : std_logic_vector(12 downto 0);
    signal u  : std_logic_vector(12 downto 0);
    signal v  : std_logic_vector(12 downto 0);
    signal i  : unsigned(12 downto 0);
    signal j  : unsigned(12 downto 0);
    signal v0 : std_logic_vector(12 downto 0);

    signal addr_gamma   : std_logic_vector(8 downto 0);
    signal rom_gamma    : std_logic_vector(2 * g_data_width - 1 downto 0);
    signal gamma        : signed(g_data_width - 1 downto 0);
    signal rom_enable   : std_logic;

    signal u0 : signed(g_data_width - 1 downto 0);
    signal u1 : signed(g_data_width - 1 downto 0);

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

    component blk_mem_gen_3
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

        ram_ntt_ena <= '0';
        ram_ntt_wea <= (others => '0');
        ram_ntt_enb <= '0';
        ram_ntt_web <= (others => '0');
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
                    ram_ntt_ena <= '1';
                    ram_ntt_wea <= (others => '1');

                    if unsigned(ram_addra) = g_num_samples - 1 then
                        next_state <= ST_RD_GAMMA;
                    end if;
                end if;

            when ST_RD_GAMMA =>
                -- Inicia la lectura de Gamma[u+m].
                next_state <= ST_WAIT_GAMMA_1;

            when ST_WAIT_GAMMA_1 =>
                    next_state <= ST_WAIT_GAMMA_2;

            when ST_WAIT_GAMMA_2 =>
                    next_state <= ST_CAPTURE_GAMMA;

            when ST_CAPTURE_GAMMA =>
                next_state <= ST_RD_U;

            when ST_RD_U =>
                -- Solicita simultaneamente u,re=a[v] y u,im=a[v+n/2].
                ram_ntt_ena <= '1';
                ram_ntt_enb <= '1';
                next_state <= ST_WAIT_U_1;

            when ST_WAIT_U_1 =>
                ram_ntt_ena <= '1';
                ram_ntt_enb <= '1';
                next_state <= ST_WAIT_U_2;

            when ST_WAIT_U_2 =>
                ram_ntt_ena <= '1';
                ram_ntt_enb <= '1';
                next_state <= ST_CAPTURE_U;

            when ST_CAPTURE_U =>
                next_state <= ST_CALC;

            when ST_CALC =>
                -- Los cuatro productos complejos se registran en esta etapa.
                next_state <= ST_WR_U;

            when ST_WR_U =>
                next_state <= ST_COMMIT_U;

            when ST_COMMIT_U =>
                -- Escribe la primera salida de la mariposa en v y v+n/2.
                ram_ntt_ena <= '1';
                ram_ntt_wea <= (others => '1');
                ram_ntt_enb <= '1';
                ram_ntt_web <= (others => '1');
                next_state <= ST_WR_T2;

            when ST_WR_T2 =>
                next_state <= ST_COMMIT_T2;

            when ST_COMMIT_T2 =>
                -- Escribe la segunda salida en v+t/2. Despues decide si
                -- continua el grupo, avanza de grupo o termina una etapa.
                ram_ntt_ena <= '1';
                ram_ntt_wea <= (others => '1');
                ram_ntt_enb <= '1';
                ram_ntt_web <= (others => '1');
                if unsigned(v) = unsigned(v0) + shift_right(unsigned(t), 1) - 1 then

                    if unsigned(u) = shift_right(unsigned(m), 1) - 1 and
                    shift_left(unsigned(m), 1) = to_unsigned(g_num_samples, m'length) then
                        next_state <= ST_RD_NTT_INIT;
                    else
                        next_state <= ST_RD_DELTA;
                    end if;
                else
                    next_state <= ST_RD_X1;
                end if;

            when ST_RD_NTT_INIT =>
                -- Ceba la lectura secuencial final empezando por la direccion 0.
                ram_ntt_ena <= '1';
                next_state <= ST_RD_NTT_WAIT;

            when ST_RD_NTT_WAIT =>
                ram_ntt_ena <= '1';
                if read_valid = '1' then
                    next_state <= ST_RD_NTT;
                end if;

            when ST_RD_NTT =>
                -- Una vez cebada la BRAM se obtiene una palabra por ciclo.
                ram_ntt_ena <= '1';
                if ntt_out_count = g_num_samples - 1 then
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
                ntt_out_count <= 0;
                data_out_valid_reg <= '0';
                data_out_reg <= (others => '0');
                x1_real <= (others => '0');
                x1_imag <= (others => '0');
                x2_real <= (others => '0');
                x2_imag <= (others => '0');
                t <= (others => '0');
                i <= (others => '0');
                j <= (others => '0');
                m <= (others => '0');
                u <= (others => '0');
                v <= (others => '0');
                v0 <= (others => '0');
                u0 <= (others => '0');
                u1 <= (others => '0');
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

                    t  <= std_logic_vector(shift_right(to_unsigned(g_num_samples, t'length), 1));
                    m  <= std_logic_vector(to_unsigned(1, m'length));
                    u  <= (others => '0');
                    i  <= (others => '0');
                    j  <= (others => '0');
                    v  <= (others => '0');
                    v0 <= (others => '0');
                    u0 <= (others => '0');
                    u1 <= (others => '0');
                    ntt_out_count <= 0;

                when ST_INIT_RAM =>
                    if data_in_valid = '1' then
                        if unsigned(ram_addra) = g_num_samples - 1 then
                            ram_addra <= (others => '0');
                        else
                            ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);
                        end if;
                    end if;

                when ST_RD_GAMMA =>
                    rom_enable <= '1';

                when ST_WAIT_GAMMA_1 =>
                    rom_enable <= '1';

                when ST_WAIT_GAMMA_2 =>
                    rom_enable <= '1';

                when ST_CAPTURE_GAMMA =>
                    rom_enable <= '0';
                    -- Gamma se almacena en formato complejo Q31: parte real
                    -- en los 32 bits bajos e imaginaria en los 32 altos.
                    gamma <= signed(rom_gamma(g_data_width - 1 downto 0));
                    v <= v0;

                when ST_RD_U =>
                    ram_addra <= std_logic_vector(resize(2 * t * i + j, ram_addra'length));
                    ram_addrb <= std_logic_vector(resize(2 * t * i + t + j, ram_addrb'length));

                when ST_WAIT_U_1 =>
                    null;
                
                when ST_WAIT_U_2 =>
                    null;

                when ST_CAPTURE_U =>
                    u0 <= signed(ram_douta);
                    u1 <= signed(ram_doutb);

                when ST_CALC =>
                    prod_gamma <= gamma * u1;

                when ST_WR_T1 =>
                    -- floor((2^31*x1 + T)/2^32). shift_right sobre signed
                    -- implementa la division aritmetica indicada en la norma.
                    ram_addra <= std_logic_vector(resize(2 * t * i + j, ram_addra'length));
                    ram_addrb <= std_logic_vector(resize(2 * t * i + t + j, ram_addrb'length));
                    data_a <= std_logic_vector(u0 + prod_gamma);
                    data_b <= std_logic_vector(u0 - prod_gamma);

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
                    data_a <= std_logic_vector(resize(shift_right(shift_left(resize(x1_real, t_real'length), 31) - t_real,32),g_data_width));
                    data_b <= std_logic_vector(resize(shift_right(shift_left(resize(x1_imag, t_imag'length), 31) - t_imag,32),g_data_width));

                when ST_COMMIT_T2 =>
                    -- Actualiza los indices solo cuando ambas salidas ya han
                    -- sido escritas. Las condiciones usan los valores actuales
                    -- de v, u, t y m, anteriores a este flanco.
                    v <= std_logic_vector(unsigned(v) + to_unsigned(1, v'length));
                    if unsigned(v) = unsigned(v0) + shift_right(unsigned(t), 1) - 1 then

                        if j = t - 1 then
                            j  <= (others => '0');
                        else
                            j <= j + 1;
                        end if;
                    end if;
                
                when ST_RD_ntt_INIT =>
                    ram_addra <= (others => '0');
                    ntt_out_count <= 0;

                when ST_RD_ntt_WAIT =>
                    -- La direccion 0 esta en vuelo; se adelanta la direccion 1.
                    ram_addra <= std_logic_vector(unsigned(ram_addra) + to_unsigned(1, ram_addra'length));
                    read_valid <= '1';

                when ST_RD_ntt =>
                    -- count es la palabra capturada, count+1 ya esta en vuelo
                    -- y count+2 es la siguiente direccion que debe solicitarse.
                    data_out_reg <= ram_douta;
                    data_out_valid_reg <= '1';

                    if ntt_out_count < g_num_samples - 1 then
                        ntt_out_count <= ntt_out_count + 1;

                        if ntt_out_count < g_num_samples - 3 then
                            ram_addra <= std_logic_vector(to_unsigned(
                                ntt_out_count + 3, ram_addra'length));
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
    addr_delta <= std_logic_vector(resize(unsigned(i) + unsigned(m), addr_delta'length));
    data_out <= data_out_reg;
    -- Durante la carga se evita un registro intermedio: la BRAM muestrea el
    -- data_in actual en cada flanco valido. En las mariposas usa data_a.
    ram_dina <= data_in when state = ST_INIT_RAM else data_a;

    ram_ntt : blk_mem_gen_1
		port map (
			clka  => clk,
			ena   => ram_ntt_en,
			wea   => ram_ntt_we,
			addra => ram_addra,
			dina  => ram_dina,
			douta => ram_douta,
			clkb  => clk,
			enb   => ram_ntt_enb,
			web   => ram_ntt_web,
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
