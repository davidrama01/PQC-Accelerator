library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity intt is
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
end entity intt;

architecture rtl of intt is

    ---------------------------------------------------------------------------
    -- INTT del Algoritmo 22, adaptada de ntt.vhd sobre la propia RAM.
    -- Recibe los n valores de la NTT en el mismo orden que produce ntt.vhd.
    -- Recorre las etapas con m = n/2, n/4, ..., 1 y t = 1, 2, ..., n/2.
    -- Equivale a iniciar m=n y dividirlo por dos antes de cada etapa.
    -- Cada grupo i comparte s = Gamma_inv[m+i] = Gamma[m+i]^(-1) mod p.
    -- Para j = 0, ..., t-1 y k = 2*t*i+j, la mariposa inversa calcula:
    --     u0 = a[k]; u1 = a[k+t]
    --     a[k]   = (u0+u1)/2 mod p
    --     a[k+t] = s*(u0-u1)/2 mod p
    -- La suma y la diferencia se reducen antes de multiplicar/dividir.
    -- Dividir por dos significa multiplicar por el inverso de 2 modulo p:
    -- si el residuo es impar, se suma p antes del desplazamiento a derecha.
    -- Las log2(n) etapas incorporan asi el factor 1/n; no se normaliza otra
    -- vez al final. La salida son los coeficientes en orden natural.
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
        ST_ADD_SUB,
        ST_MUL,
        ST_TRANSFORM,
        ST_WR_U,
        ST_COMMIT_U,
        ST_RD_INTT_INIT,
        ST_RD_INTT_WAIT_1,
        ST_RD_INTT_WAIT_2,
        ST_RD_INTT_CAPTURE,
        ST_DONE
    );

    signal state      : state_t;
    signal next_state : state_t;

    constant C_P : unsigned(g_data_width - 1 downto 0) := to_unsigned(g_modulus, g_data_width);

    signal ram_intt_ena : std_logic;
    signal ram_intt_enb : std_logic;
    signal ram_intt_wea : std_logic_vector(0 downto 0);
    signal ram_intt_web : std_logic_vector(0 downto 0);

    signal ram_addra : std_logic_vector(g_addr_width - 1 downto 0);
    signal ram_addrb : std_logic_vector(g_addr_width - 1 downto 0);

    signal ram_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_doutb : std_logic_vector(g_data_width - 1 downto 0);

    -- Cada puerto accede a un coeficiente de la mariposa, sin partes complejas.
    signal data_a   : std_logic_vector(g_data_width - 1 downto 0);
    signal data_b   : std_logic_vector(g_data_width - 1 downto 0);
    signal ram_dina : std_logic_vector(g_data_width - 1 downto 0);

    signal intt_out_count      : integer range 0 to g_num_samples - 1 := 0;
    signal data_out_valid_reg : std_logic := '0';
    signal data_out_reg       : std_logic_vector(g_data_width - 1 downto 0);

    -- m: numero de grupos de la etapa; i: grupo actual, entre 0 y m-1.
    -- t: distancia entre los operandos y numero de mariposas por grupo.
    -- j: pareja dentro del grupo, entre 0 y t-1. Se mantiene 2*m*t = n.
    -- En cada nueva etapa m se divide por dos y t se duplica.
    signal t : unsigned(12 downto 0);
    signal m : unsigned(12 downto 0);
    signal i : unsigned(12 downto 0);
    signal j : unsigned(12 downto 0);

    signal addr_gamma : std_logic_vector(8 downto 0);
    signal rom_gamma  : std_logic_vector(g_data_width - 1 downto 0);

    -- Operandos registrados antes de sobrescribir sus posiciones en RAM.
    -- prod_gamma conserva el producto completo; scaled_diff es su residuo modulo p.
    signal sum_mod     : unsigned(g_data_width - 1 downto 0);
    signal diff_mod    : unsigned(g_data_width - 1 downto 0);
    signal gamma       : unsigned(g_data_width - 1 downto 0);
    signal u0          : unsigned(g_data_width - 1 downto 0);
    signal u1          : unsigned(g_data_width - 1 downto 0);
    signal scaled_diff : unsigned(g_data_width - 1 downto 0);
    signal prod_gamma  : unsigned(2 * g_data_width - 1 downto 0);
    signal rom_enable  : std_logic;

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

    -- Gamma_inv[q] = gamma_raiz^(-rev_log2(n)(q)) mod p, precalculada en ROM.
    -- Se consulta q=m+i: las t mariposas de un grupo comparten el factor.
    -- P1: gamma_inv_p1_n512.coe, 512 x 32 bits.
    component blk_mem_gen_5
        port (
            clka  : in std_logic;
            ena   : in std_logic;
            addra : in std_logic_vector(8 downto 0);
            douta : out std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

    -- P2: gamma_inv_p2_n512.coe, 512 x 32 bits.
    component blk_mem_gen_6
        port (
            clka  : in std_logic;
            ena   : in std_logic;
            addra : in std_logic_vector(8 downto 0);
            douta : out std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

    -- Para x en [0,p-1], (x + (x mod 2)*p)/2 es x/2 en F_p.
    -- p es impar, por lo que el numerador siempre es par y no se trunca.
    function half_mod(value : unsigned) return unsigned is
        variable extended : unsigned(g_data_width downto 0);
    begin
        extended := resize(value, extended'length);
        if value(0) = '1' then
            extended := extended + resize(C_P, extended'length);
        end if;
        return resize(shift_right(extended, 1), g_data_width);
    end function half_mod;

begin

    assert g_num_samples = 512 and g_data_width = 32 and g_addr_width = 9
        report "INTT: las IP y tablas requieren 512 muestras de 32 bits" severity failure;
    assert g_modulus = 2147473409 or g_modulus = 2147389441
        report "INTT: g_modulus debe ser P1 o P2" severity failure;

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
        ram_intt_ena <= '0';
        ram_intt_wea <= (others => '0');
        ram_intt_enb <= '0';
        ram_intt_web <= (others => '0');
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
                    ram_intt_ena <= '1';
                    ram_intt_wea <= (others => '1');
                    if unsigned(ram_addra) = g_num_samples - 1 then
                        next_state <= ST_RD_GAMMA;
                    end if;
                end if;

            when ST_RD_GAMMA =>
                -- La habilitacion de ROM es registrada. Los estados de
                -- espera permiten que Gamma_inv[m+i] llegue antes de capturarlo.
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
                ram_intt_ena <= '1';
                ram_intt_enb <= '1';
                next_state <= ST_WAIT_U_2;

            when ST_WAIT_U_2 =>
                -- EN habilita tambien el registro de salida de la BRAM.
                ram_intt_ena <= '1';
                ram_intt_enb <= '1';
                next_state <= ST_CAPTURE_U;

            when ST_CAPTURE_U =>
                next_state <= ST_ADD_SUB;

            when ST_ADD_SUB =>
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
                ram_intt_ena <= '1';
                ram_intt_wea <= (others => '1');
                ram_intt_enb <= '1';
                ram_intt_web <= (others => '1');
                if j = t - 1 then
                    if i = m - 1 and m = 1 then
                        next_state <= ST_RD_INTT_INIT;
                    else
                        next_state <= ST_RD_GAMMA;
                    end if;
                else
                    next_state <= ST_RD_U;
                end if;

            when ST_RD_INTT_INIT =>
                next_state <= ST_RD_INTT_WAIT_1;

            when ST_RD_INTT_WAIT_1 =>
                ram_intt_ena <= '1';
                next_state <= ST_RD_INTT_WAIT_2;

            when ST_RD_INTT_WAIT_2 =>
                ram_intt_ena <= '1';
                next_state <= ST_RD_INTT_CAPTURE;

            when ST_RD_INTT_CAPTURE =>
                -- Una vez cebada la BRAM: una salida por ciclo.
                ram_intt_ena <= '1';
                if intt_out_count = g_num_samples - 1 then
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
                intt_out_count <= 0;
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
                scaled_diff <= (others => '0');
                sum_mod <= (others => '0');
                diff_mod <= (others => '0');
                data_a <= (others => '0');
                data_b <= (others => '0');
            else
                data_out_valid_reg <= '0';
                case state is

                    when ST_IDLE =>
                        -- Primera etapa: n/2 grupos con una pareja de
                        -- coeficientes consecutivos. start se atiende en este estado;
                        -- la carga de datos comienza en el siguiente ciclo.
                        ram_addra <= (others => '0');
                        ram_addrb <= (others => '0');
                        rom_enable <= '0';
                        t <= to_unsigned(1, t'length);
                        m <= to_unsigned(g_num_samples / 2, m'length);
                        i <= (others => '0');
                        j <= (others => '0');
                        intt_out_count <= 0;

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

                    when ST_ADD_SUB =>
                        -- Ambos operandos estan en [0,p-1]: la suma requiere
                        -- como maximo una resta de p. El bit extra evita acarreo.
                        sum_u := resize(u0, sum_u'length) + resize(u1, sum_u'length);
                        if sum_u >= resize(C_P, sum_u'length) then
                            sum_u := sum_u - resize(C_P, sum_u'length);
                        end if;
                        sum_mod <= resize(sum_u, g_data_width);
                        -- Representa u0-u1 modulo p sin una resta unsigned negativa.
                        if u0 >= u1 then
                            diff_mod <= u0 - u1;
                        else
                            diff_mod <= C_P - (u1 - u0);
                        end if;

                    when ST_MUL =>
                        -- Multiplica la diferencia por el factor inverso del
                        -- grupo. Conserva el producto completo de 64 bits.
                        prod_gamma <= gamma * diff_mod;

                    when ST_TRANSFORM =>
                        -- Reduccion modular ordinaria, sin escalado Montgomery.
                        scaled_diff <= resize(prod_gamma mod resize(C_P, prod_gamma'length), scaled_diff'length);

                    when ST_WR_U =>
                        -- Normaliza ambas ramas por 2 en el cuerpo finito.
                        -- La RAM toma estos registros en ST_COMMIT_U.
                        data_a <= std_logic_vector(half_mod(sum_mod));
                        data_b <= std_logic_vector(half_mod(scaled_diff));

                    when ST_COMMIT_U =>
                        -- Avanza los bucles solo tras escribir la pareja.
                        -- j es el bucle interior. Al agotarlo, avanza i;
                        -- al agotar i, comienza otra etapa con m/2 y t*2.
                        -- La ultima etapa tiene m=1, t=n/2. La FSM detecta
                        -- su ultima pareja y pasa a la lectura de resultados.
                        if j = t - 1 then
                            j <= (others => '0');
                            if i = m - 1 then
                                i <= (others => '0');
                                if m > 1 then
                                    m <= shift_right(m, 1);
                                    t <= shift_left(t, 1);
                                end if;
                            else
                                i <= i + 1;
                            end if;
                        else
                            j <= j + 1;
                        end if;

                    when ST_RD_INTT_INIT =>
                        -- Reinicia la direccion para emitir a[0] primero.
                        ram_addra <= (others => '0');
                        intt_out_count <= 0;

                    when ST_RD_INTT_WAIT_1 | ST_RD_INTT_WAIT_2 =>
                        -- Lanza las primeras lecturas consecutivas para
                        -- llenar la tuberia de dos ciclos de la BRAM.
                        ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);

                    when ST_RD_INTT_CAPTURE =>
                        -- Registra a[intt_out_count] y su pulso valid.
                        -- La direccion +3 anticipa las proximas lecturas:
                        -- direccion registrada, dos ciclos de BRAM y captura.
                        -- Deja de avanzar antes de exceder el final de RAM;
                        -- las ultimas palabras ya estan en la tuberia.
                        data_out_reg <= ram_douta;
                        data_out_valid_reg <= '1';
                        if intt_out_count < g_num_samples - 1 then
                            intt_out_count <= intt_out_count + 1;
                            if intt_out_count < g_num_samples - 3 then
                                ram_addra <= std_logic_vector(to_unsigned(intt_out_count + 3, ram_addra'length));
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

    -- La etapa m usa el tramo Gamma_inv[m .. 2*m-1] de la tabla.
    addr_gamma <= std_logic_vector(resize(i + m, addr_gamma'length));
    -- El puerto A recibe entradas durante la carga y resultados despues.
    -- El puerto B solo escribe la segunda salida de cada mariposa.
    ram_dina <= data_in when state = ST_INIT_RAM else data_a;

    ram_intt : blk_mem_gen_1
        port map (
            clka  => clk,
            ena   => ram_intt_ena,
            wea   => ram_intt_wea,
            addra => ram_addra,
            dina  => ram_dina,
            douta => ram_douta,
            clkb  => clk,
            enb   => ram_intt_enb,
            web   => ram_intt_web,
            addrb => ram_addrb,
            dinb  => data_b,
            doutb => ram_doutb
        );

    -- Seleccion estatica durante elaboracion: cada primo requiere su propia
    -- tabla de potencias. g_modulus no conmuta las ROM durante la ejecucion.
    gen_gamma_p1 : if g_modulus = 2147473409 generate
        rom_gamma_inst : blk_mem_gen_5
            port map (
                clka  => clk,
                ena   => rom_enable,
                addra => addr_gamma,
                douta => rom_gamma
            );
    end generate gen_gamma_p1;

    gen_gamma_p2 : if g_modulus = 2147389441 generate
        rom_gamma_inst : blk_mem_gen_6
            port map (
                clka  => clk,
                ena   => rom_enable,
                addra => addr_gamma,
                douta => rom_gamma
            );
    end generate gen_gamma_p2;

end architecture rtl;
