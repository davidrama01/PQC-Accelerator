library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ntt is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 32;
        g_addr_width  : integer := 9;
        g_modulus     : positive := 2147473409 -- Solo P1 o P2; selecciona tambien la ROM.
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
end entity ntt;

architecture rtl of ntt is

    ---------------------------------------------------------------------------
    -- NTT directa del Algoritmo 21, calculada sobre la propia RAM.
    -- Para n = g_num_samples y p = g_modulus:
    --   1. Carga los n coeficientes a[0], ..., a[n-1] en orden consecutivo.
    --   2. Recorre etapas con m = 1, 2, ..., n/2 y t = n/(2*m).
    --      Cada etapa contiene m grupos de t mariposas, n/2 en total.
    --   3. Para cada grupo i y pareja j, calcula:
    --          k   = 2*t*i + j
    --          s   = Gamma[m+i]
    --          u0  = a[k]; u1 = a[k+t]
    --          su1 = (s*u1) mod p
    --          a[k]   = (u0 + su1) mod p
    --          a[k+t] = (u0 - su1) mod p
    --   4. Lee el resultado de las direcciones 0 a n-1, sin reordenarlo.
    --
    -- La tabla Gamma fija el orden de la transformada: la salida r evalua
    -- el polinomio en gamma_raiz^(2*rev_log2(n)(r)+1), modulo p.
    -- rev invierte los bits del indice; gamma_raiz es una raiz de orden 2*n.
    -- La senal gamma guarda s, no la raiz primitiva usada al crear la tabla.
    -- No se aplica normalizacion por n: este bloque es la NTT directa.
    --
    -- Entradas/salidas: residuos unsigned en [0,p-1], sin escalado Q31.
    -- El emisor debe reducir las entradas; los negativos se codifican mod p.
    -- La configuracion actual de las IP y sus tablas corresponde a n=512.
    -- IP de RAM y ROM: 512 x 32. RAM con dos ciclos de lectura y EN activo
    -- en ambos ciclos. La ROM admite uno o dos ciclos de lectura.
    ---------------------------------------------------------------------------
    type state_t is (
        ST_IDLE,
        ST_INIT_RAM,
        ST_RD_GAMMA,
        ST_WAIT_GAMMA_1,
        ST_WAIT_GAMMA_2,
        ST_CAPTURE_GAMMA,
        ST_RD_U,
        ST_WAIT_U_1,
        ST_WAIT_U_2,
        ST_CAPTURE_U,
        ST_MUL,
        ST_TRANSFORM,
        ST_WR_U,
        ST_COMMIT_U,
        ST_RD_NTT_INIT,
        ST_RD_NTT_WAIT_1,
        ST_RD_NTT_WAIT_2,
        ST_RD_NTT_CAPTURE,
        ST_DONE
    );

    signal state      : state_t;
    signal next_state : state_t;

    constant C_P : unsigned(g_data_width - 1 downto 0) := to_unsigned(g_modulus, g_data_width);

    signal ram_ntt_ena : std_logic;
    signal ram_ntt_enb : std_logic;
    signal ram_ntt_wea : std_logic_vector(0 downto 0);
    signal ram_ntt_web : std_logic_vector(0 downto 0);

    signal ram_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal ram_addrb : std_logic_vector(g_addr_width - 1 downto 0);

    signal ram_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_doutb : std_logic_vector(g_data_width - 1 downto 0);

    -- Cada puerto accede a un coeficiente de la mariposa, sin partes complejas.
    signal data_a   : std_logic_vector(g_data_width - 1 downto 0);
    signal data_b   : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_dina : std_logic_vector(g_data_width - 1 downto 0);

    signal ntt_out_count      : integer range 0 to g_num_samples - 1 := 0;
    signal data_out_valid_reg : std_logic := '0';
    signal data_out_reg       : std_logic_vector(g_data_width - 1 downto 0);

    -- m: numero de grupos de la etapa; i: grupo actual, entre 0 y m-1.
    -- t: distancia entre los operandos y numero de mariposas por grupo.
    -- j: pareja dentro del grupo, entre 0 y t-1. Se mantiene 2*m*t = n.
    -- En cada nueva etapa m se duplica y t se divide por dos.
    signal t : unsigned(12 downto 0);
    signal m : unsigned(12 downto 0);
    signal i : unsigned(12 downto 0);
    signal j : unsigned(12 downto 0);

    signal addr_gamma : std_logic_vector(8 downto 0);
    signal rom_gamma  : std_logic_vector(g_data_width - 1 downto 0);

    -- Operandos registrados antes de sobrescribir sus posiciones en RAM.
    -- prod_gamma conserva el producto completo; su1 es su residuo modulo p.
    signal gamma      : unsigned(g_data_width - 1 downto 0);
    signal u0         : unsigned(g_data_width - 1 downto 0);
    signal u1         : unsigned(g_data_width - 1 downto 0);
    signal su1        : unsigned(g_data_width - 1 downto 0);
    signal prod_gamma : unsigned(2 * g_data_width - 1 downto 0);
    signal rom_enable : std_logic;

    component blk_mem_gen_1
        port (
            clka  : in std_logic;
            ena   : in std_logic;
            wea   : in std_logic_vector(0 downto 0);
            addra : in std_logic_vector(8 downto 0);
            dina  : in std_logic_vector(g_data_width - 1 downto 0);
            douta : out std_logic_vector(g_data_width - 1 downto 0);
            clkb  : in std_logic;
            enb   : in std_logic;
            web   : in std_logic_vector(0 downto 0);
            addrb : in std_logic_vector(8 downto 0);
            dinb  : in std_logic_vector(g_data_width - 1 downto 0);
            doutb : out std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

    -- Gamma[q] = gamma_raiz^rev_log2(n)(q) mod p, precalculada en ROM.
    -- Se consulta q=m+i: las t mariposas de un grupo comparten el factor.
    -- P1: gamma_p1_n512.coe, 512 x 32 bits.
    component blk_mem_gen_3
        port (
            clka  : in std_logic;
            ena   : in std_logic;
            addra : in std_logic_vector(8 downto 0);
            douta : out std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

    -- P2: gamma_p2_n512.coe, 512 x 32 bits.
    component blk_mem_gen_4
        port (
            clka  : in std_logic;
            ena   : in std_logic;
            addra : in std_logic_vector(8 downto 0);
            douta : out std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

begin

    data_out_valid <= data_out_valid_reg;
    data_out <= data_out_reg;

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

    -- Control combinacional: separa direccion, espera, captura y escritura.
    -- Por defecto ambos puertos quedan deshabilitados; los registros del
    -- datapath se actualizan en p_counter al flanco de reloj.
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
                -- Acepta una palabra por flanco solo si data_in_valid='1'.
                -- Una pausa no escribe ni avanza la direccion de carga.
                if data_in_valid = '1' then
                    ram_ntt_ena <= '1';
                    ram_ntt_wea <= (others => '1');
                    if unsigned(ram_addra) = g_num_samples - 1 then
                        next_state <= ST_RD_GAMMA;
                    end if;
                end if;

            when ST_RD_GAMMA =>
                -- La habilitacion de ROM es registrada. Los estados de
                -- espera permiten que Gamma[m+i] llegue antes de capturarlo.
                next_state <= ST_WAIT_GAMMA_1;

            when ST_WAIT_GAMMA_1 =>
                next_state <= ST_WAIT_GAMMA_2;

            when ST_WAIT_GAMMA_2 =>
                next_state <= ST_CAPTURE_GAMMA;

            when ST_CAPTURE_GAMMA =>
                next_state <= ST_RD_U;

            when ST_RD_U =>
                -- Registra primero 2*t*i+j y 2*t*i+t+j.
                next_state <= ST_WAIT_U_1;

            when ST_WAIT_U_1 =>
                ram_ntt_ena <= '1';
                ram_ntt_enb <= '1';
                next_state <= ST_WAIT_U_2;

            when ST_WAIT_U_2 =>
                -- EN habilita tambien el registro de salida de la BRAM.
                ram_ntt_ena <= '1';
                ram_ntt_enb <= '1';
                next_state <= ST_CAPTURE_U;

            when ST_CAPTURE_U =>
                next_state <= ST_MUL;

            when ST_MUL =>
                next_state <= ST_TRANSFORM;

            when ST_TRANSFORM =>
                next_state <= ST_WR_U;

            when ST_WR_U =>
                next_state <= ST_COMMIT_U;

            when ST_COMMIT_U =>
                -- Escribe ambas salidas simultaneamente, una por puerto.
                -- Si quedan parejas, conserva gamma y vuelve a leer RAM.
                -- Al cambiar de grupo o etapa debe cargar el nuevo factor.
                ram_ntt_ena <= '1';
                ram_ntt_wea <= (others => '1');
                ram_ntt_enb <= '1';
                ram_ntt_web <= (others => '1');
                if j = t - 1 then
                    if i = m - 1 and m = g_num_samples / 2 then
                        next_state <= ST_RD_NTT_INIT;
                    else
                        next_state <= ST_RD_GAMMA;
                    end if;
                else
                    next_state <= ST_RD_U;
                end if;

            when ST_RD_NTT_INIT =>
                next_state <= ST_RD_NTT_WAIT_1;

            when ST_RD_NTT_WAIT_1 =>
                ram_ntt_ena <= '1';
                next_state <= ST_RD_NTT_WAIT_2;

            when ST_RD_NTT_WAIT_2 =>
                ram_ntt_ena <= '1';
                next_state <= ST_RD_NTT_CAPTURE;

            when ST_RD_NTT_CAPTURE =>
                -- Una vez cebada la BRAM: una salida por ciclo.
                ram_ntt_ena <= '1';
                if ntt_out_count = g_num_samples - 1 then
                    next_state <= ST_DONE;
                end if;

            when ST_DONE =>
                -- Pulso de un ciclo, simultaneo a la ultima salida valida.
                done <= '1';
                next_state <= ST_IDLE;
        end case;
    end process p_next_state;

    -- Datapath secuencial: operandos, aritmetica modular, indices y salida.
    -- Cada operacion usa los registros producidos en estados anteriores.
    p_counter : process(clk)
        -- Un bit extra permite comparar la suma con p sin perder acarreo.
        variable sum_u : unsigned(g_data_width downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                ram_addra <= (others => '0');
                ram_addrb <= (others => '0');
                rom_enable <= '0';
                ntt_out_count <= 0;
                data_out_valid_reg <= '0';
                data_out_reg <= (others => '0');
                t <= (others => '0');
                m <= (others => '0');
                i <= (others => '0');
                j <= (others => '0');
                u0 <= (others => '0');
                u1 <= (others => '0');
                gamma <= (others => '0');
                prod_gamma <= (others => '0');
                su1 <= (others => '0');
                data_a <= (others => '0');
                data_b <= (others => '0');
            else
                data_out_valid_reg <= '0';
                case state is

                    when ST_IDLE =>
                        -- Primera etapa: un grupo con n/2 parejas separadas
                        -- n/2 posiciones. start se atiende en este estado;
                        -- la carga de datos comienza en el siguiente ciclo.
                        ram_addra <= (others => '0');
                        ram_addrb <= (others => '0');
                        rom_enable <= '0';
                        t <= to_unsigned(g_num_samples / 2, t'length);
                        m <= to_unsigned(1, m'length);
                        i <= (others => '0');
                        j <= (others => '0');
                        ntt_out_count <= 0;

                    when ST_INIT_RAM =>
                        if data_in_valid = '1' then
                            if unsigned(ram_addra) = g_num_samples - 1 then
                                ram_addra <= (others => '0');
                            else
                                ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);
                            end if;
                        end if;

                    when ST_RD_GAMMA | ST_WAIT_GAMMA_1 | ST_WAIT_GAMMA_2 =>
                        rom_enable <= '1';

                    when ST_CAPTURE_GAMMA =>
                        -- Retiene el factor del grupo mientras se recorren
                        -- todas sus parejas j; la ROM ya puede deshabilitarse.
                        rom_enable <= '0';
                        gamma <= unsigned(rom_gamma);

                    when ST_RD_U =>
                        -- Los puertos A y B leen las dos mitades del grupo i.
                        -- Las direcciones se mantienen hasta ST_COMMIT_U,
                        -- donde los resultados sustituyen estos operandos.
                        ram_addra <= std_logic_vector(resize(2 * t * i + j, ram_addra'length));
                        ram_addrb <= std_logic_vector(resize(2 * t * i + t + j, ram_addrb'length));

                    when ST_CAPTURE_U =>
                        -- Captura conjunta tras los dos ciclos de lectura.
                        u0 <= unsigned(ram_douta);
                        u1 <= unsigned(ram_doutb);

                    when ST_MUL =>
                        -- Producto unsigned de 32x32 bits en la configuracion
                        -- actual. Se conservan los 64 bits antes de reducir.
                        prod_gamma <= gamma * u1;

                    when ST_TRANSFORM =>
                        -- su1 = s*u1 mod p. Primero reduce el producto ancho
                        -- y despues ajusta el resultado al ancho del dato.
                        -- mod expresa la reduccion por constante; no es una
                        -- multiplicacion Montgomery ni una operacion Q31.
                        su1 <= resize(prod_gamma mod resize(C_P, prod_gamma'length), su1'length);

                    when ST_WR_U =>
                        -- Prepara los dos resultados; la RAM se escribira
                        -- en ST_COMMIT_U, cuando estos registros sean validos.
                        -- Como u0 y su1 estan en [0,p-1], su suma es < 2*p:
                        -- basta restar p una vez si la suma no es menor que p.
                        sum_u := resize(u0, sum_u'length) + resize(su1, sum_u'length);
                        if sum_u >= resize(C_P, sum_u'length) then
                            sum_u := sum_u - resize(C_P, sum_u'length);
                        end if;
                        data_a <= std_logic_vector(resize(sum_u, g_data_width));
                        -- Evita una resta unsigned negativa. Si u0 < su1,
                        -- p-(su1-u0) equivale a sumar p a la diferencia.
                        if u0 >= su1 then
                            data_b <= std_logic_vector(u0 - su1);
                        else
                            data_b <= std_logic_vector(C_P - (su1 - u0));
                        end if;

                    when ST_COMMIT_U =>
                        -- Avanza los bucles solo tras escribir la pareja.
                        -- j es el bucle interior. Al agotarlo, avanza i;
                        -- al agotar i, comienza otra etapa con m*2 y t/2.
                        -- La ultima etapa tiene m=n/2, t=1. La FSM detecta
                        -- su ultima pareja y pasa a la lectura de resultados.
                        if j = t - 1 then
                            j <= (others => '0');
                            if i = m - 1 then
                                i <= (others => '0');
                                if m < g_num_samples / 2 then
                                    m <= shift_left(m, 1);
                                    t <= shift_right(t, 1);
                                end if;
                            else
                                i <= i + 1;
                            end if;
                        else
                            j <= j + 1;
                        end if;

                    when ST_RD_NTT_INIT =>
                        -- Reinicia la direccion para emitir a[0] primero.
                        ram_addra <= (others => '0');
                        ntt_out_count <= 0;

                    when ST_RD_NTT_WAIT_1 | ST_RD_NTT_WAIT_2 =>
                        -- Lanza las primeras lecturas consecutivas para
                        -- llenar la tuberia de dos ciclos de la BRAM.
                        ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);

                    when ST_RD_NTT_CAPTURE =>
                        -- Registra a[ntt_out_count] y su pulso valid.
                        -- La direccion +3 anticipa las proximas lecturas:
                        -- direccion registrada, dos ciclos de BRAM y captura.
                        -- Deja de avanzar antes de exceder el final de RAM;
                        -- las ultimas palabras ya estan en la tuberia.
                        data_out_reg <= ram_douta;
                        data_out_valid_reg <= '1';
                        if ntt_out_count < g_num_samples - 1 then
                            ntt_out_count <= ntt_out_count + 1;
                            if ntt_out_count < g_num_samples - 3 then
                                ram_addra <= std_logic_vector(to_unsigned(ntt_out_count + 3, ram_addra'length));
                            end if;
                        end if;

                    when ST_DONE =>
                        ram_addra <= (others => '0');
                        ram_addrb <= (others => '0');

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process p_counter;

    -- La etapa m usa el tramo Gamma[m .. 2*m-1] de la tabla.
    addr_gamma <= std_logic_vector(resize(i + m, addr_gamma'length));
    -- El puerto A recibe entradas durante la carga y resultados despues.
    -- El puerto B solo escribe la segunda salida de cada mariposa.
    ram_dina <= data_in when state = ST_INIT_RAM else data_a;

    ram_ntt : blk_mem_gen_1
        port map (
            clka  => clk,
            ena   => ram_ntt_ena,
            wea   => ram_ntt_wea,
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

    -- Seleccion estatica durante elaboracion: cada primo requiere su propia
    -- tabla de potencias. g_modulus no conmuta las ROM durante la ejecucion.
    gen_gamma_p1 : if g_modulus = 2147473409 generate
        rom_gamma_inst : blk_mem_gen_3
            port map (
                clka  => clk,
                ena   => rom_enable,
                addra => addr_gamma,
                douta => rom_gamma
            );
    end generate gen_gamma_p1;

    gen_gamma_p2 : if g_modulus = 2147389441 generate
        rom_gamma_inst : blk_mem_gen_4
            port map (
                clka  => clk,
                ena   => rom_enable,
                addra => addr_gamma,
                douta => rom_gamma
            );
    end generate gen_gamma_p2;

end architecture rtl;
