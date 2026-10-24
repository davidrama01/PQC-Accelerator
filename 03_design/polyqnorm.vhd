library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hawk_pkg.all;

entity polyqnorm is
    generic (
        g_num_samples : integer := 512;
        g_data_width  : integer := 32;
        g_addr_width  : integer := c_addr_width;
        g_modulus     : positive := 2147473409
    );
    port (
        clk            : in std_logic;
        rst_n          : in std_logic;
        start          : in std_logic;
        data_in_valid  : in std_logic;
        done           : out std_logic;
        data_q00       : in std_logic_vector(g_data_width - 1 downto 0);
        data_q01       : in std_logic_vector(g_data_width - 1 downto 0);
        data_w0        : in std_logic_vector(g_data_width - 1 downto 0);
        data_w1        : in std_logic_vector(g_data_width - 1 downto 0);
        data_out       : out std_logic_vector(g_data_width - 1 downto 0);
        data_out_valid : out std_logic;
        error          : out std_logic
    );
end entity polyqnorm;

architecture rtl of polyqnorm is

    ---------------------------------------------------------------------------
    -- Algoritmo 19, PolyQnorm. Residuos unsigned en [0,p-1], P1 o P2.
    -- Cuatro NTT en paralelo; se reciben n cuaternas con data_in_valid.
    -- Primera pasada: d=w1/q00, e=w0+d*q01 (todo modulo p).
    -- Se reutilizan w0_ram para d y q01_ram para e, conservando q00 y w1.
    -- Segunda pasada: c[i]=q00[i]*e[i]*e[n-1-i]+d[i]*w1[n-1-i].
    -- NTTadj invierte los indices: las raices de posiciones i y n-1-i
    -- son inversas en el orden bit-reversal de nuestra NTT.
    -- Salida unica: r=sum(c[i]) mod p, sin dividir por n.
    -- Inverso por Fermat: a^(p-2) mod p, exponenciacion binaria secuencial.
    -- No es una iNTT. Un denominador cero termina con error, sin salida.
    -- BRAM de dos ciclos; EN activo tambien para el registro de salida.
    ---------------------------------------------------------------------------
    type state_t is (
        ST_IDLE,

        -- Carga y almacenamiento de las cuatro NTT.
        ST_LOAD,
        ST_WR_NTT,
        ST_COMMIT_NTT,

        -- Lectura de coeficientes para calcular d y e.
        ST_RD_NTT,
        ST_WAIT_NTT_1,
        ST_WAIT_NTT_2,
        ST_CAPTURE_NTT,

        -- Inverso modular de q00 mediante Fermat.
        ST_INV_TEST,
        ST_INV_MUL,
        ST_INV_REDUCE,
        ST_INV_SQUARE,
        ST_INV_SQUARE_REDUCE,
        ST_INV_NEXT,

        -- Calculo y almacenamiento de d y e.
        ST_MUL_D,
        ST_REDUCE_D,
        ST_MUL_E,
        ST_REDUCE_E,
        ST_COMMIT_E,

        -- Lectura directa y adjunta para calcular c.
        ST_RD_C,
        ST_WAIT_C_1,
        ST_WAIT_C_2,
        ST_CAPTURE_C,

        -- Productos y acumulacion modular de c.
        ST_MUL_QE,
        ST_REDUCE_QE,
        ST_MUL_EADJ,
        ST_REDUCE_EADJ,
        ST_MUL_DW,
        ST_REDUCE_DW,
        ST_ACCUMULATE,
        ST_DONE,
        ST_ERROR
    );

    signal state      : state_t;
    signal next_state : state_t;

    subtype word_t is unsigned(g_data_width - 1 downto 0);
    constant C_P : word_t := to_unsigned(g_modulus, g_data_width);

    -- Control de las cuatro NTT y contadores de carga.
    signal core_rst_n    : std_logic;
    signal core_start    : std_logic;
    signal core_valid    : std_logic;
    signal load_count    : natural range 0 to g_num_samples - 1;
    signal ntt_count     : natural range 0 to g_num_samples - 1;
    signal u             : natural range 0 to g_num_samples - 1;
    signal ntt_valid     : std_logic_vector(3 downto 0);
    signal input_invalid : std_logic;

    -- Direcciones compartidas por las memorias de coeficientes.
    signal addr_a : std_logic_vector(g_addr_width - 1 downto 0);
    signal addr_b : std_logic_vector(g_addr_width - 1 downto 0);

    -- Operandos y resultados de las dos pasadas de PolyQnorm.
    signal q00_value : word_t;
    signal q01_value : word_t;
    signal w0_value  : word_t;
    signal w1_value  : word_t;
    signal d         : word_t;
    signal e         : word_t;
    signal e_adj     : word_t;
    signal w1_adj    : word_t;
    signal term_a    : word_t;
    signal term_b    : word_t;
    signal r         : word_t;

    -- Inverso modular por exponenciacion y producto completo.
    signal inv_base : word_t;
    signal inv_acc  : word_t;
    signal inv_exp  : word_t;
    signal product  : unsigned(2 * g_data_width - 1 downto 0);

    -- Registros de control de la salida.
    signal error_flag       : std_logic;
    signal done_reg         : std_logic;
    signal output_valid_reg : std_logic;

    function add_mod(a, b : word_t) return word_t is
        variable s : unsigned(g_data_width downto 0);
    begin
        s := resize(a, s'length) + resize(b, s'length);
        if s >= resize(C_P, s'length) then
            s := s - resize(C_P, s'length);
        end if;
        return resize(s, g_data_width);
    end function;

    -- RAM de coeficientes con dos puertos y dos ciclos de lectura.
    component blk_mem_gen_1
        port (
            clka  : in std_logic;
            ena   : in std_logic;
            wea   : in std_logic_vector(0 downto 0);
            addra : in std_logic_vector(g_addr_width - 1 downto 0);
            dina  : in std_logic_vector(g_data_width - 1 downto 0);
            douta : out std_logic_vector(g_data_width - 1 downto 0);
            clkb  : in std_logic;
            enb   : in std_logic;
            web   : in std_logic_vector(0 downto 0);
            addrb : in std_logic_vector(g_addr_width - 1 downto 0);
            dinb  : in std_logic_vector(g_data_width - 1 downto 0);
            doutb : out std_logic_vector(g_data_width - 1 downto 0)
        );
    end component;

    -- NTT y memoria de q00.
    signal ntt_q00   : std_logic_vector(g_data_width - 1 downto 0);
    signal q00_dina  : std_logic_vector(g_data_width - 1 downto 0);
    signal q00_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal q00_doutb : std_logic_vector(g_data_width - 1 downto 0);
    signal q00_ena   : std_logic;
    signal q00_enb   : std_logic;
    signal q00_wea   : std_logic_vector(0 downto 0);

    -- NTT y memoria de q01.
    signal ntt_q01   : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_dina  : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_doutb : std_logic_vector(g_data_width - 1 downto 0);
    signal q01_ena   : std_logic;
    signal q01_enb   : std_logic;
    signal q01_wea   : std_logic_vector(0 downto 0);

    -- NTT y memoria de w0.
    signal ntt_w0   : std_logic_vector(g_data_width - 1 downto 0);
    signal w0_dina  : std_logic_vector(g_data_width - 1 downto 0);
    signal w0_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal w0_doutb : std_logic_vector(g_data_width - 1 downto 0);
    signal w0_ena   : std_logic;
    signal w0_enb   : std_logic;
    signal w0_wea   : std_logic_vector(0 downto 0);

    -- NTT y memoria de w1.
    signal ntt_w1   : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_dina  : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_douta : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_doutb : std_logic_vector(g_data_width - 1 downto 0);
    signal w1_ena   : std_logic;
    signal w1_enb   : std_logic;
    signal w1_wea   : std_logic_vector(0 downto 0);

begin

    core_rst_n <= '0' when state = ST_ERROR else rst_n;
    core_start <= start when state = ST_IDLE else '0';
    core_valid <= data_in_valid when state = ST_LOAD else '0';
    input_invalid <= '1' when unsigned(data_q00) >= C_P or unsigned(data_q01) >= C_P or
                              unsigned(data_w0) >= C_P or unsigned(data_w1) >= C_P else '0';
    error <= error_flag;
    done <= done_reg;
    data_out <= std_logic_vector(r);
    data_out_valid <= output_valid_reg;

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

    -- Control combinacional de la FSM y habilitaciones de las RAM.
    p_next_state : process(all)
    begin
        next_state <= state;
        q00_ena <= '0';
        q00_enb <= '0';
        q00_wea <= (others => '0');
        q01_ena <= '0';
        q01_enb <= '0';
        q01_wea <= (others => '0');
        w0_ena <= '0';
        w0_enb <= '0';
        w0_wea <= (others => '0');
        w1_ena <= '0';
        w1_enb <= '0';
        w1_wea <= (others => '0');
        case state is

            when ST_IDLE =>
                if start = '1' then
                    next_state <= ST_LOAD;
                end if;

            when ST_LOAD =>
                if data_in_valid = '1' then
                    if input_invalid = '1' then
                        next_state <= ST_ERROR;
                    elsif load_count = g_num_samples - 1 then
                        next_state <= ST_WR_NTT;
                    end if;
                end if;

            when ST_WR_NTT =>
                if ntt_valid = "1111" then
                    q00_ena <= '1';
                    q00_wea <= (others => '1');
                    q01_ena <= '1';
                    q01_wea <= (others => '1');
                    w0_ena <= '1';
                    w0_wea <= (others => '1');
                    w1_ena <= '1';
                    w1_wea <= (others => '1');
                    if ntt_count = g_num_samples - 1 then
                        next_state <= ST_COMMIT_NTT;
                    end if;
                elsif ntt_valid /= "0000" then
                    next_state <= ST_ERROR;
                end if;

            when ST_COMMIT_NTT =>
                next_state <= ST_RD_NTT;

            when ST_RD_NTT =>
                next_state <= ST_WAIT_NTT_1;

            when ST_WAIT_NTT_1 | ST_WAIT_NTT_2 =>
                q00_ena <= '1';
                q01_ena <= '1';
                w0_ena <= '1';
                w1_ena <= '1';
                if state = ST_WAIT_NTT_1 then
                    next_state <= ST_WAIT_NTT_2;
                else
                    next_state <= ST_CAPTURE_NTT;
                end if;

            when ST_CAPTURE_NTT =>
                if unsigned(q00_douta) = 0 then
                    next_state <= ST_ERROR;
                else
                    next_state <= ST_INV_TEST;
                end if;

            when ST_INV_TEST =>
                if inv_exp = 0 then
                    next_state <= ST_MUL_D;
                elsif inv_exp(0) = '1' then
                    next_state <= ST_INV_MUL;
                else
                    next_state <= ST_INV_SQUARE;
                end if;

            when ST_INV_MUL =>
                next_state <= ST_INV_REDUCE;

            when ST_INV_REDUCE =>
                next_state <= ST_INV_SQUARE;

            when ST_INV_SQUARE =>
                next_state <= ST_INV_SQUARE_REDUCE;

            when ST_INV_SQUARE_REDUCE =>
                next_state <= ST_INV_NEXT;

            when ST_INV_NEXT =>
                next_state <= ST_INV_TEST;

            when ST_MUL_D =>
                next_state <= ST_REDUCE_D;

            when ST_REDUCE_D =>
                next_state <= ST_MUL_E;

            when ST_MUL_E =>
                next_state <= ST_REDUCE_E;

            when ST_REDUCE_E =>
                next_state <= ST_COMMIT_E;

            when ST_COMMIT_E =>
                q01_ena <= '1';
                q01_wea <= (others => '1');
                w0_ena <= '1';
                w0_wea <= (others => '1');
                if u = g_num_samples - 1 then
                    next_state <= ST_RD_C;
                else
                    next_state <= ST_RD_NTT;
                end if;

            when ST_RD_C =>
                next_state <= ST_WAIT_C_1;

            when ST_WAIT_C_1 | ST_WAIT_C_2 =>
                q00_ena <= '1';
                q01_ena <= '1';
                w0_ena <= '1';
                q01_enb <= '1';
                w1_enb <= '1';
                if state = ST_WAIT_C_1 then
                    next_state <= ST_WAIT_C_2;
                else
                    next_state <= ST_CAPTURE_C;
                end if;

            when ST_CAPTURE_C =>
                next_state <= ST_MUL_QE;

            when ST_MUL_QE =>
                next_state <= ST_REDUCE_QE;

            when ST_REDUCE_QE =>
                next_state <= ST_MUL_EADJ;

            when ST_MUL_EADJ =>
                next_state <= ST_REDUCE_EADJ;

            when ST_REDUCE_EADJ =>
                next_state <= ST_MUL_DW;

            when ST_MUL_DW =>
                next_state <= ST_REDUCE_DW;

            when ST_REDUCE_DW =>
                next_state <= ST_ACCUMULATE;

            when ST_ACCUMULATE =>
                if u = g_num_samples - 1 then
                    next_state <= ST_DONE;
                else
                    next_state <= ST_RD_C;
                end if;

            when ST_DONE | ST_ERROR =>
                next_state <= ST_IDLE;
        end case;
    end process p_next_state;

    -- Registros, operaciones modulares y acumulacion del resultado.
    p_datapath : process(clk)
        variable reduced : word_t;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                load_count <= 0;
                ntt_count <= 0;
                u <= 0;
                addr_a <= (others => '0');
                addr_b <= (others => '0');
                q00_value <= (others => '0');
                q01_value <= (others => '0');
                w0_value <= (others => '0');
                w1_value <= (others => '0');
                d <= (others => '0');
                e <= (others => '0');
                e_adj <= (others => '0');
                w1_adj <= (others => '0');
                inv_base <= (others => '0');
                inv_acc <= (others => '0');
                inv_exp <= (others => '0');
                product <= (others => '0');
                term_a <= (others => '0');
                term_b <= (others => '0');
                r <= (others => '0');
                error_flag <= '0';
                done_reg <= '0';
                output_valid_reg <= '0';
            else
                done_reg <= '0';
                output_valid_reg <= '0';
                case state is

                    when ST_IDLE =>
                        if start = '1' then
                            load_count <= 0;
                            ntt_count <= 0;
                            u <= 0;
                            addr_a <= (others => '0');
                            addr_b <= (others => '0');
                            r <= (others => '0');
                            error_flag <= '0';
                        end if;

                    when ST_LOAD =>
                        if data_in_valid = '1' and load_count < g_num_samples - 1 then
                            load_count <= load_count + 1;
                        end if;

                    when ST_WR_NTT =>
                        if ntt_valid = "1111" and ntt_count < g_num_samples - 1 then
                            ntt_count <= ntt_count + 1;
                            addr_a <= std_logic_vector(to_unsigned(ntt_count + 1, g_addr_width));
                        end if;

                    when ST_RD_NTT =>
                        addr_a <= std_logic_vector(to_unsigned(u, g_addr_width));

                    when ST_CAPTURE_NTT =>
                        q01_value <= unsigned(q01_douta);
                        w0_value <= unsigned(w0_douta);
                        w1_value <= unsigned(w1_douta);
                        inv_base <= unsigned(q00_douta);
                        inv_acc <= to_unsigned(1, g_data_width);
                        inv_exp <= to_unsigned(g_modulus - 2, g_data_width);

                    when ST_INV_MUL =>
                        product <= inv_acc * inv_base;

                    when ST_INV_REDUCE =>
                        inv_acc <= resize(product mod resize(C_P, product'length), g_data_width);

                    when ST_INV_SQUARE =>
                        product <= inv_base * inv_base;

                    when ST_INV_SQUARE_REDUCE =>
                        inv_base <= resize(product mod resize(C_P, product'length), g_data_width);

                    when ST_INV_NEXT =>
                        inv_exp <= shift_right(inv_exp, 1);

                    when ST_MUL_D =>
                        product <= w1_value * inv_acc;

                    when ST_REDUCE_D =>
                        d <= resize(product mod resize(C_P, product'length), g_data_width);

                    when ST_MUL_E =>
                        product <= d * q01_value;

                    when ST_REDUCE_E =>
                        reduced := resize(product mod resize(C_P, product'length), g_data_width);
                        e <= add_mod(w0_value, reduced);

                    when ST_COMMIT_E =>
                        if u = g_num_samples - 1 then
                            u <= 0;
                        else
                            u <= u + 1;
                        end if;

                    when ST_RD_C =>
                        addr_a <= std_logic_vector(to_unsigned(u, g_addr_width));
                        addr_b <= std_logic_vector(to_unsigned(g_num_samples - 1 - u, g_addr_width));

                    when ST_CAPTURE_C =>
                        q00_value <= unsigned(q00_douta);
                        e <= unsigned(q01_douta);
                        e_adj <= unsigned(q01_doutb);
                        d <= unsigned(w0_douta);
                        w1_adj <= unsigned(w1_doutb);

                    when ST_MUL_QE =>
                        product <= q00_value * e;

                    when ST_REDUCE_QE =>
                        term_a <= resize(product mod resize(C_P, product'length), g_data_width);

                    when ST_MUL_EADJ =>
                        product <= term_a * e_adj;

                    when ST_REDUCE_EADJ =>
                        term_a <= resize(product mod resize(C_P, product'length), g_data_width);

                    when ST_MUL_DW =>
                        product <= d * w1_adj;

                    when ST_REDUCE_DW =>
                        term_b <= resize(product mod resize(C_P, product'length), g_data_width);

                    when ST_ACCUMULATE =>
                        r <= add_mod(r, add_mod(term_a, term_b));
                        if u < g_num_samples - 1 then
                            u <= u + 1;
                        end if;

                    when ST_DONE =>
                        done_reg <= '1';
                        output_valid_reg <= '1';

                    when ST_ERROR =>
                        done_reg <= '1';
                        error_flag <= '1';

                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process p_datapath;

    -- Transformada y almacenamiento de q00.
    q00_dina <= ntt_q00 when state = ST_WR_NTT else (others => '0');

    ntt_q00_inst : entity work.ntt(rtl)
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width,
            g_modulus     => g_modulus
        )
        port map (
            clk            => clk,
            rst_n          => core_rst_n,
            start          => core_start,
            data_in_valid  => core_valid,
            data_in        => data_q00,
            done           => open,
            data_out       => ntt_q00,
            data_out_valid => ntt_valid(0)
        );

    q00_ram : blk_mem_gen_1
        port map (
            clka  => clk,
            ena   => q00_ena,
            wea   => q00_wea,
            addra => addr_a,
            dina  => q00_dina,
            douta => q00_douta,
            clkb  => clk,
            enb   => q00_enb,
            web   => "0",
            addrb => addr_b,
            dinb  => (others => '0'),
            doutb => q00_doutb
        );

    -- Transformada y almacenamiento de q01.
    q01_dina <= ntt_q01 when state = ST_WR_NTT else std_logic_vector(e);

    ntt_q01_inst : entity work.ntt(rtl)
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width,
            g_modulus     => g_modulus
        )
        port map (
            clk            => clk,
            rst_n          => core_rst_n,
            start          => core_start,
            data_in_valid  => core_valid,
            data_in        => data_q01,
            done           => open,
            data_out       => ntt_q01,
            data_out_valid => ntt_valid(1)
        );

    q01_ram : blk_mem_gen_1
        port map (
            clka  => clk,
            ena   => q01_ena,
            wea   => q01_wea,
            addra => addr_a,
            dina  => q01_dina,
            douta => q01_douta,
            clkb  => clk,
            enb   => q01_enb,
            web   => "0",
            addrb => addr_b,
            dinb  => (others => '0'),
            doutb => q01_doutb
        );

    -- Transformada y almacenamiento de w0.
    w0_dina <= ntt_w0 when state = ST_WR_NTT else std_logic_vector(d);

    ntt_w0_inst : entity work.ntt(rtl)
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width,
            g_modulus     => g_modulus
        )
        port map (
            clk            => clk,
            rst_n          => core_rst_n,
            start          => core_start,
            data_in_valid  => core_valid,
            data_in        => data_w0,
            done           => open,
            data_out       => ntt_w0,
            data_out_valid => ntt_valid(2)
        );

    w0_ram : blk_mem_gen_1
        port map (
            clka  => clk,
            ena   => w0_ena,
            wea   => w0_wea,
            addra => addr_a,
            dina  => w0_dina,
            douta => w0_douta,
            clkb  => clk,
            enb   => w0_enb,
            web   => "0",
            addrb => addr_b,
            dinb  => (others => '0'),
            doutb => w0_doutb
        );

    -- Transformada y almacenamiento de w1.
    w1_dina <= ntt_w1 when state = ST_WR_NTT else (others => '0');

    ntt_w1_inst : entity work.ntt(rtl)
        generic map (
            g_num_samples => g_num_samples,
            g_data_width  => g_data_width,
            g_addr_width  => g_addr_width,
            g_modulus     => g_modulus
        )
        port map (
            clk            => clk,
            rst_n          => core_rst_n,
            start          => core_start,
            data_in_valid  => core_valid,
            data_in        => data_w1,
            done           => open,
            data_out       => ntt_w1,
            data_out_valid => ntt_valid(3)
        );

    w1_ram : blk_mem_gen_1
        port map (
            clka  => clk,
            ena   => w1_ena,
            wea   => w1_wea,
            addra => addr_a,
            dina  => w1_dina,
            douta => w1_douta,
            clkb  => clk,
            enb   => w1_enb,
            web   => "0",
            addrb => addr_b,
            dinb  => (others => '0'),
            doutb => w1_doutb
        );

end architecture rtl;
