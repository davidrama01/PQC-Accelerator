library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.hawk_pkg.all;

entity hawk_verify is
    generic (
        g_data_width  : integer := 32;

        g_addr_width  : integer := c_addr_width;
        g_size_fifo   : integer := c_size_fifo
    );
    port (
        num_samples : in integer range 256 to c_max_samples := c_num_samples;
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        data_in     : in  std_logic_vector(g_data_width - 1 downto 0);
        error_out   : out std_logic;
        ack_in      : in  std_logic;
        input_ready : out std_logic;
        ready       : in  std_logic;
        valid       : out std_logic;
        start_out   : out std_logic
    );
end entity hawk_verify;

architecture rtl of hawk_verify is

    ---------------------------------------------------------------------------
    -- Recepcion del bus: h0, q00, q01 y w1, en ese orden.
    -- ack_in indica una palabra valida; admite pausas entre palabras.
    -- h0 ocupa 512 bits (16 palabras de 32 bits), empezando por los bits bajos.
    -- Cada polinomio ocupa 512 palabras, una por coeficiente, en su propia FIFO.
    -- La IP fifo_generator_0 existente es de 32 bits y 1024 posiciones.
    -- Tras la carga, q00, q01 y w1 se leen juntos para RebuildS0.
    -- Las copias de q00/q01/w1 y el w0 reconstruido alimentan ambas normas.
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        WRITE_H0,
        WRITE_Q00,
        WRITE_Q01,
        WRITE_W1,
        INPUTS_LOADED,
        READ_REBUILD,
        WAIT_REBUILD_DATA,
        SEND_REBUILD_DATA,
        CALC_REBUILD,
        REBUILD_DONE,
        INIT_POLYQNORM,
        READ_POLYQNORM,
        WAIT_POLYQNORM_DATA,
        SEND_POLYQNORM_DATA,
        CALC_POLYQNORM,
        POLYQNORM_DONE,
        SEND_RESULT,
        RESET_INTERNAL
    );

    signal current_state : state_t;
    signal next_state    : state_t;

    -- Reset comun de los bloques y registros entre operaciones. La FSM
    -- principal solo usa rst_n para poder completar esta secuencia.
    constant C_RESET_CYCLES    : positive := 8;
    constant C_RECOVERY_CYCLES : positive := 8;
    signal reset_count : natural range 0 to C_RESET_CYCLES + C_RECOVERY_CYCLES - 1;
    signal core_rst_n  : std_logic;

    -- g_size_fifo se conserva por compatibilidad con la interfaz existente.
    -- El numero de palabras de h0 se obtiene de sus bits y del ancho del bus.
    signal c_h0_words : integer range 8 to 32;
    signal h0     : std_logic_vector(c_max_samples - 1 downto 0);
    signal wr_h0  : std_logic;
    signal cnt_h0 : integer range 0 to c_max_samples / g_data_width;

    -- FIFO de q00: entrada de RebuildS0.
    signal wr_q00         : std_logic;
    signal cnt_q00        : integer range 0 to c_max_samples;
    signal fifo_q00_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_q00_full  : std_logic;
    signal fifo_q00_empty : std_logic;

    -- FIFO de q01: entrada de RebuildS0.
    signal wr_q01         : std_logic;
    signal cnt_q01        : integer range 0 to c_max_samples;
    signal fifo_q01_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_q01_full  : std_logic;
    signal fifo_q01_empty : std_logic;

    -- FIFO de w1: entrada de RebuildS0.
    signal wr_w1         : std_logic;
    signal cnt_w1        : integer range 0 to c_max_samples;
    signal fifo_w1_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_w1_full  : std_logic;
    signal fifo_w1_empty : std_logic;

    -- Lectura comun de las tres FIFO y control de RebuildS0.
    signal rd_rebuild        : std_logic;
    signal cnt_rebuild       : integer range 0 to c_max_samples;
    signal start_rebuild     : std_logic;
    signal rebuild_in_valid  : std_logic;
    signal done_rebuild      : std_logic;
    signal rebuild_finished  : std_logic;
    signal error_rebuild     : std_logic;
    signal error_rebuild_core : std_logic;
    signal rebuild_out_valid : std_logic;
    signal rebuild_w0        : std_logic_vector(g_data_width - 1 downto 0);

    -- Copias para PolyQnorm: no se consumen durante RebuildS0.
    signal fifo_norm_q00_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_norm_q00_full  : std_logic;
    signal fifo_norm_q00_empty : std_logic;

    signal fifo_norm_q01_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_norm_q01_full  : std_logic;
    signal fifo_norm_q01_empty : std_logic;

    signal fifo_norm_w1_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_norm_w1_full  : std_logic;
    signal fifo_norm_w1_empty : std_logic;

    signal fifo_norm_w0_dout  : std_logic_vector(g_data_width - 1 downto 0);
    signal fifo_norm_w0_full  : std_logic;
    signal fifo_norm_w0_empty : std_logic;

    signal wr_rebuild_w0    : std_logic;
    signal cnt_rebuild_w0   : integer range 0 to c_max_samples;
    signal rd_polyqnorm     : std_logic;
    signal start_polyqnorm  : std_logic;
    signal polyqnorm_valid  : std_logic;
    signal cnt_polyqnorm    : integer range 0 to c_max_samples;

    constant C_P1 : positive := 2147473409;
    constant C_P2 : positive := 2147389441;
    signal r1               : std_logic_vector(g_data_width - 1 downto 0);
    signal r2               : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p1_out      : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p1_valid    : std_logic;
    signal norm_p1_done     : std_logic;
    signal norm_p1_error    : std_logic;
    signal norm_p1_finished : std_logic;
    signal norm_p1_failed   : std_logic;
    signal norm_p1_q00      : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p1_q01      : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p1_w0       : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p1_w1       : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p2_out      : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p2_valid    : std_logic;
    signal norm_p2_done     : std_logic;
    signal norm_p2_error    : std_logic;
    signal norm_p2_finished : std_logic;
    signal norm_p2_failed   : std_logic;
    signal norm_p2_q00      : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p2_q01      : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p2_w0       : std_logic_vector(g_data_width - 1 downto 0);
    signal norm_p2_w1       : std_logic_vector(g_data_width - 1 downto 0);

    -- Entradas del bus/RebuildS0: enteros signed de 32 bits.
    -- PolyQnorm requiere residuos unsigned. Para P1/P2, dos sumas bastan
    -- incluso para -2^31; una resta basta para el mayor positivo de 32 bits.
    -- El bit adicional evita desbordamiento al convertir el minimo negativo.
    function signed_to_residue(value : std_logic_vector; modulus : positive)
        return std_logic_vector is
        variable reduced : signed(value'length downto 0);
        variable prime   : signed(value'length downto 0);
    begin
        reduced := resize(signed(value), reduced'length);
        prime := to_signed(modulus, prime'length);
        if reduced < 0 then
            reduced := reduced + prime;
            if reduced < 0 then
                reduced := reduced + prime;
            end if;
        elsif reduced >= prime then
            reduced := reduced - prime;
        end if;
        return std_logic_vector(resize(reduced, value'length));
    end function;

    -- Divisibilidad y division mediante log2(n) bits.
    -- El paquete selecciona el umbral entero de cada variante.
    signal C_LOGN : natural range 8 to 10;
    signal threshold_value : unsigned(31 downto 0);
    signal error_threshold : std_logic;
    signal error_verify    : std_logic;

    -- Comprobacion de signo en paralelo a la escritura de w1.
    signal start_sym_break : std_logic;
    signal ready_sym_break : std_logic;
    signal sym_break       : std_logic;

    attribute MARK_DEBUG : string;
    attribute MARK_DEBUG of current_state : signal is "TRUE";
    attribute MARK_DEBUG of next_state : signal is "TRUE";
    attribute MARK_DEBUG of wr_h0 : signal is "TRUE";
    attribute MARK_DEBUG of wr_q00 : signal is "TRUE";
    attribute MARK_DEBUG of wr_q01 : signal is "TRUE";
    attribute MARK_DEBUG of wr_w1 : signal is "TRUE";

    component polyqnorm
        generic (

            g_data_width  : integer := 32;
            g_addr_width  : integer := c_addr_width;
            g_modulus     : positive := 2147473409
        );
        port (
            num_samples : in integer range 256 to c_max_samples := c_num_samples;
            clk            : in  std_logic;
            rst_n          : in  std_logic;
            start          : in  std_logic;
            data_in_valid  : in  std_logic;
            done           : out std_logic;
            data_q00       : in  std_logic_vector(g_data_width - 1 downto 0);
            data_q01       : in  std_logic_vector(g_data_width - 1 downto 0);
            data_w0        : in  std_logic_vector(g_data_width - 1 downto 0);
            data_w1        : in  std_logic_vector(g_data_width - 1 downto 0);
            data_out       : out std_logic_vector(g_data_width - 1 downto 0);
            data_out_valid : out std_logic;
            error          : out std_logic
        );
    end component;

    component rebuild_s0
        generic (

            g_data_width  : integer := 32;
            g_addr_width  : integer := c_addr_width
        );
        port (
            num_samples : in integer range 256 to c_max_samples := c_num_samples;
            clk            : in  std_logic;
            rst_n          : in  std_logic;
            start          : in  std_logic;
            data_in_valid  : in  std_logic;
            done           : out std_logic;
            data_q00       : in  std_logic_vector(g_data_width - 1 downto 0);
            data_q01       : in  std_logic_vector(g_data_width - 1 downto 0);
            data_w1        : in  std_logic_vector(g_data_width - 1 downto 0);
            data_h0        : in  std_logic_vector(c_max_samples - 1 downto 0);
            data_out       : out std_logic_vector(g_data_width - 1 downto 0);
            data_out_valid : out std_logic;
            error          : out std_logic
        );
    end component;

    component sym_break_w1
        generic (

            g_data_width  : integer := 16
        );
        port (
            num_samples : in integer range 256 to c_max_samples := c_num_samples;
            clk       : in  std_logic;
            rst_n     : in  std_logic;
            start     : in  std_logic;
            valid     : in  std_logic;
            ready     : out std_logic;
            sym_break : out std_logic;
            w1        : in  std_logic_vector(g_data_width - 1 downto 0)
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
    c_h0_words <= num_samples / g_data_width;
    C_LOGN <= 8 when num_samples = 256 else 9 when num_samples = 512 else 10;
    threshold_value <= verify_threshold(num_samples);

    -- Ocho ciclos de reset seguidos de ocho de recuperacion sin accesos.
    core_rst_n <= '0' when rst_n = '0' or
                          (current_state = RESET_INTERNAL and reset_count < C_RESET_CYCLES) else '1';

    -- El emisor solo entrega palabras cuando input_ready esta activo.
    -- Durante calculo, salida y limpieza no se aceptan datos del bus.
    input_ready <= '1' when rst_n = '1' and
        (current_state = IDLE or current_state = WRITE_H0 or
         (current_state = WRITE_Q00 and fifo_q00_full = '0' and fifo_norm_q00_full = '0') or
         (current_state = WRITE_Q01 and fifo_q01_full = '0' and fifo_norm_q01_full = '0') or
         (current_state = WRITE_W1 and fifo_w1_full = '0' and fifo_norm_w1_full = '0')) else '0';

    -- Resultado de un bit: 1 si hay error, 0 si verifica.
    -- Se mantiene estable hasta que el receptor acepte valid y ready.
    -- sym_break vale 1 si la condicion de signo se cumple.
    -- Los errores de ambas normas se conservan al recibir sus respectivos done.
    error_verify <= (not sym_break) or error_rebuild or
                    norm_p1_failed or norm_p2_failed or error_threshold;
    error_out <= error_verify;
    valid <= '1' when current_state = SEND_RESULT and rst_n = '1' else '0';
    start_out <= '1' when rst_n = '1' and
                          (current_state = POLYQNORM_DONE or
                           (current_state = REBUILD_DONE and error_rebuild = '1')) else '0';

    -- start tiene prioridad sobre valid en sym_break_w1: se activa al
    -- aceptar el ultimo q01, antes de que pueda llegar el primer w1.
    start_sym_break <= '1' when wr_q01 = '1' and cnt_q01 = num_samples - 1 else '0';

    -- w0 se obtiene exclusivamente de RebuildS0 y se guarda para las normas.
    wr_rebuild_w0 <= '1' when core_rst_n = '1' and rebuild_out_valid = '1' and
                             fifo_norm_w0_full = '0' and cnt_rebuild_w0 < num_samples else '0';

    norm_p1_q00 <= signed_to_residue(fifo_norm_q00_dout, C_P1);
    norm_p1_q01 <= signed_to_residue(fifo_norm_q01_dout, C_P1);
    norm_p1_w0 <= signed_to_residue(fifo_norm_w0_dout, C_P1);
    norm_p1_w1 <= signed_to_residue(fifo_norm_w1_dout, C_P1);

    norm_p2_q00 <= signed_to_residue(fifo_norm_q00_dout, C_P2);
    norm_p2_q01 <= signed_to_residue(fifo_norm_q01_dout, C_P2);
    norm_p2_w0 <= signed_to_residue(fifo_norm_w0_dout, C_P2);
    norm_p2_w1 <= signed_to_residue(fifo_norm_w1_dout, C_P2);

    state_register : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                current_state <= RESET_INTERNAL;
            else
                current_state <= next_state;
            end if;
        end if;
    end process state_register;

    reset_counter : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                reset_count <= 0;
            elsif current_state = RESET_INTERNAL then
                if reset_count < C_RESET_CYCLES + C_RECOVERY_CYCLES - 1 then
                    reset_count <= reset_count + 1;
                end if;
            else
                reset_count <= 0;
            end if;
        end if;
    end process reset_counter;

    next_state_logic : process(all)
    begin
        next_state <= current_state;
        wr_h0 <= '0';
        wr_q00 <= '0';
        wr_q01 <= '0';
        wr_w1 <= '0';
        rd_rebuild <= '0';
        start_rebuild <= '0';
        rebuild_in_valid <= '0';
        rd_polyqnorm <= '0';
        start_polyqnorm <= '0';
        polyqnorm_valid <= '0';

        -- No se escriben las FIFO durante su reset sincrono.
        if rst_n = '1' then
            case current_state is
                when IDLE =>
                    -- La primera palabra ya pertenece a h0: no es una cabecera.
                    if ack_in = '1' then
                        wr_h0 <= '1';
                        if c_h0_words = 1 then
                            next_state <= WRITE_Q00;
                        else
                            next_state <= WRITE_H0;
                        end if;
                    end if;

                when WRITE_H0 =>
                    if ack_in = '1' then
                        wr_h0 <= '1';
                        if cnt_h0 = c_h0_words - 1 then
                            next_state <= WRITE_Q00;
                        end if;
                    end if;

                when WRITE_Q00 =>
                    if ack_in = '1' and fifo_q00_full = '0' and fifo_norm_q00_full = '0' then
                        wr_q00 <= '1';
                        if cnt_q00 = num_samples - 1 then
                            next_state <= WRITE_Q01;
                        end if;
                    end if;

                when WRITE_Q01 =>
                    if ack_in = '1' and fifo_q01_full = '0' and fifo_norm_q01_full = '0' then
                        wr_q01 <= '1';
                        if cnt_q01 = num_samples - 1 then
                            next_state <= WRITE_W1;
                        end if;
                    end if;

                when WRITE_W1 =>
                    if ack_in = '1' and fifo_w1_full = '0' and fifo_norm_w1_full = '0' then
                        wr_w1 <= '1';
                        if cnt_w1 = num_samples - 1 then
                            next_state <= INPUTS_LOADED;
                        end if;
                    end if;

                when INPUTS_LOADED =>
                    -- start precede al primer coeficiente valido.
                    start_rebuild <= '1';
                    next_state <= READ_REBUILD;

                when READ_REBUILD =>
                    -- Una unica habilitacion conserva la alineacion de indices.
                    if fifo_q00_empty = '0' and fifo_q01_empty = '0' and
                       fifo_w1_empty = '0' then
                        rd_rebuild <= '1';
                        next_state <= WAIT_REBUILD_DATA;
                    end if;

                when WAIT_REBUILD_DATA =>
                    -- FIFO estandar, no FWFT: dout cambia despues de rd_en.
                    -- Mantener las salidas estables antes de validarlas.
                    next_state <= SEND_REBUILD_DATA;

                when SEND_REBUILD_DATA =>
                    rebuild_in_valid <= '1';
                    if cnt_rebuild = num_samples - 1 then
                        next_state <= CALC_REBUILD;
                    else
                        next_state <= READ_REBUILD;
                    end if;

                when CALC_REBUILD =>
                    if rebuild_finished = '1' then
                        next_state <= REBUILD_DONE;
                    end if;

                when REBUILD_DONE =>
                    -- Un rechazo puede dejar w0 incompleto. Devuelve falso
                    -- sin esperar datos que RebuildS0 no va a producir.
                    if error_rebuild = '1' then
                        next_state <= SEND_RESULT;
                    else
                        next_state <= INIT_POLYQNORM;
                    end if;

                when INIT_POLYQNORM =>
                    start_polyqnorm <= '1';
                    next_state <= READ_POLYQNORM;

                when READ_POLYQNORM =>
                    if fifo_norm_q00_empty = '0' and fifo_norm_q01_empty = '0' and
                       fifo_norm_w0_empty = '0' and fifo_norm_w1_empty = '0' then
                        rd_polyqnorm <= '1';
                        next_state <= WAIT_POLYQNORM_DATA;
                    end if;

                when WAIT_POLYQNORM_DATA =>
                    next_state <= SEND_POLYQNORM_DATA;

                when SEND_POLYQNORM_DATA =>
                    -- Ambas normas aceptan el mismo indice en el mismo flanco.
                    polyqnorm_valid <= '1';
                    if cnt_polyqnorm = num_samples - 1 then
                        next_state <= CALC_POLYQNORM;
                    else
                        next_state <= READ_POLYQNORM;
                    end if;

                when CALC_POLYQNORM =>
                    -- Las latencias de P1 y P2 pueden ser distintas.
                    if norm_p1_finished = '1' and norm_p2_finished = '1' then
                        next_state <= POLYQNORM_DONE;
                    end if;

                when POLYQNORM_DONE =>
                    next_state <= SEND_RESULT;

                when SEND_RESULT =>
                    if ready = '1' then
                        next_state <= RESET_INTERNAL;
                    end if;

                when RESET_INTERNAL =>
                    if reset_count = C_RESET_CYCLES + C_RECOVERY_CYCLES - 1 then
                        next_state <= IDLE;
                    end if;
            end case;
        end if;
    end process next_state_logic;

    cnt_process : process(clk)
    begin
        if rising_edge(clk) then
            if core_rst_n = '0' then
                h0 <= (others => '0');
                cnt_h0 <= 0;
                cnt_q00 <= 0;
                cnt_q01 <= 0;
                cnt_w1 <= 0;
                cnt_rebuild <= 0;
                rebuild_finished <= '0';
                error_rebuild <= '0';
            else
                -- Conserva done aunque llegue durante la carga de ternas.
                if start_rebuild = '1' then
                    rebuild_finished <= '0';
                    error_rebuild <= '0';
                elsif done_rebuild = '1' then
                    rebuild_finished <= '1';
                    -- El bloque borra su error al volver a reposo.
                    error_rebuild <= error_rebuild_core;
                end if;

                if wr_h0 = '1' then
                    h0((cnt_h0 + 1) * g_data_width - 1 downto cnt_h0 * g_data_width) <= data_in;
                    cnt_h0 <= cnt_h0 + 1;
                end if;

                if wr_q00 = '1' then
                    cnt_q00 <= cnt_q00 + 1;
                end if;

                if wr_q01 = '1' then
                    cnt_q01 <= cnt_q01 + 1;
                end if;

                if rebuild_in_valid = '1' then
                    cnt_rebuild <= cnt_rebuild + 1;
                end if;

                if wr_w1 = '1' then
                    cnt_w1 <= cnt_w1 + 1;
                end if;
            end if;
        end if;
    end process cnt_process;

    polyqnorm_registers : process(clk)
    begin
        if rising_edge(clk) then
            if core_rst_n = '0' then
                cnt_rebuild_w0 <= 0;
                cnt_polyqnorm <= 0;
                r1 <= (others => '0');
                r2 <= (others => '0');
                norm_p1_finished <= '0';
                norm_p2_finished <= '0';
                norm_p1_failed <= '0';
                norm_p2_failed <= '0';
            else
                if rebuild_out_valid = '1' then
                    if wr_rebuild_w0 = '1' then
                        cnt_rebuild_w0 <= cnt_rebuild_w0 + 1;
                    end if;
                end if;
                if polyqnorm_valid = '1' then
                    cnt_polyqnorm <= cnt_polyqnorm + 1;
                end if;
                if norm_p1_valid = '1' then
                    r1 <= norm_p1_out;
                end if;
                if norm_p1_done = '1' then
                    norm_p1_finished <= '1';
                    norm_p1_failed <= norm_p1_error;
                end if;
                if norm_p2_valid = '1' then
                    r2 <= norm_p2_out;
                end if;
                if norm_p2_done = '1' then
                    norm_p2_finished <= '1';
                    norm_p2_failed <= norm_p2_error;
                end if;
            end if;
        end if;
    end process polyqnorm_registers;

    verify_process : process(clk)
    begin
        if rising_edge(clk) then
            if core_rst_n = '0' then
                error_threshold <= '0';
            else
                case current_state is
                    when POLYQNORM_DONE =>
                        -- Comprueba los residuos, la divisibilidad y r1/n
                        -- en el mismo ciclo, usando directamente r1 y r2.
                        -- Error activo a 1; la igualdad con el umbral se acepta.
                        error_threshold <= '1';
                        if r1 = r2 and (unsigned(r1) and to_unsigned(num_samples - 1, r1'length)) = 0 and
                           shift_right(unsigned(r1), C_LOGN) <=
                           resize(threshold_value, g_data_width) then
                            error_threshold <= '0';
                        end if;

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process verify_process;

    fifo_q00_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => data_in,
            wr_en => wr_q00,
            rd_en => rd_rebuild,
            dout  => fifo_q00_dout,
            full  => fifo_q00_full,
            empty => fifo_q00_empty
        );

    fifo_q01_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => data_in,
            wr_en => wr_q01,
            rd_en => rd_rebuild,
            dout  => fifo_q01_dout,
            full  => fifo_q01_full,
            empty => fifo_q01_empty
        );

    fifo_w1_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => data_in,
            wr_en => wr_w1,
            rd_en => rd_rebuild,
            dout  => fifo_w1_dout,
            full  => fifo_w1_full,
            empty => fifo_w1_empty
        );

    -- Observa exactamente los coeficientes aceptados por la FIFO, incluidas
    -- las pausas del bus. w1 se interpreta como entero con signo.
    -- ready_sym_break pulsa al terminar; sym_break conserva el resultado
    -- para la decision final de HawkVerify, sin detener la FSM de carga.
    sym_break_w1_inst : sym_break_w1
        generic map (
            g_data_width  => g_data_width
        )
        port map (
            num_samples => num_samples,
            clk       => clk,
            rst_n     => core_rst_n,
            start     => start_sym_break,
            valid     => wr_w1,
            ready     => ready_sym_break,
            sym_break => sym_break,
            w1        => data_in
        );

    rebuild_s0_inst : rebuild_s0
        generic map (
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width
        )
        port map (
            num_samples => num_samples,
            clk            => clk,
            rst_n          => core_rst_n,
            start          => start_rebuild,
            data_in_valid  => rebuild_in_valid,
            done           => done_rebuild,
            data_q00       => fifo_q00_dout,
            data_q01       => fifo_q01_dout,
            data_w1        => fifo_w1_dout,
            data_h0        => h0,
            data_out       => rebuild_w0,
            data_out_valid => rebuild_out_valid,
            error          => error_rebuild_core
        );

    fifo_norm_q00_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => data_in,
            wr_en => wr_q00,
            rd_en => rd_polyqnorm,
            dout  => fifo_norm_q00_dout,
            full  => fifo_norm_q00_full,
            empty => fifo_norm_q00_empty
        );

    fifo_norm_q01_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => data_in,
            wr_en => wr_q01,
            rd_en => rd_polyqnorm,
            dout  => fifo_norm_q01_dout,
            full  => fifo_norm_q01_full,
            empty => fifo_norm_q01_empty
        );

    fifo_norm_w1_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => data_in,
            wr_en => wr_w1,
            rd_en => rd_polyqnorm,
            dout  => fifo_norm_w1_dout,
            full  => fifo_norm_w1_full,
            empty => fifo_norm_w1_empty
        );

    fifo_norm_w0_inst : fifo_generator_0
        port map (
            clk   => clk,
            srst  => not core_rst_n,
            din   => rebuild_w0,
            wr_en => wr_rebuild_w0,
            rd_en => rd_polyqnorm,
            dout  => fifo_norm_w0_dout,
            full  => fifo_norm_w0_full,
            empty => fifo_norm_w0_empty
        );

    polyqnorm_p1_inst : polyqnorm
        generic map (
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width,
            g_modulus     => C_P1
        )
        port map (
            num_samples => num_samples,
            clk            => clk,
            rst_n          => core_rst_n,
            start          => start_polyqnorm,
            data_in_valid  => polyqnorm_valid,
            done           => norm_p1_done,
            data_q00       => norm_p1_q00,
            data_q01       => norm_p1_q01,
            data_w0        => norm_p1_w0,
            data_w1        => norm_p1_w1,
            data_out       => norm_p1_out,
            data_out_valid => norm_p1_valid,
            error          => norm_p1_error
        );

    polyqnorm_p2_inst : polyqnorm
        generic map (
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width,
            g_modulus     => C_P2
        )
        port map (
            num_samples => num_samples,
            clk            => clk,
            rst_n          => core_rst_n,
            start          => start_polyqnorm,
            data_in_valid  => polyqnorm_valid,
            done           => norm_p2_done,
            data_q00       => norm_p2_q00,
            data_q01       => norm_p2_q01,
            data_w0        => norm_p2_w0,
            data_w1        => norm_p2_w1,
            data_out       => norm_p2_out,
            data_out_valid => norm_p2_valid,
            error          => norm_p2_error
        );

end architecture rtl;
