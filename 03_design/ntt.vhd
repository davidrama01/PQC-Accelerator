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
        clk, rst_n, start : in std_logic;
        data_in_valid : in std_logic;
        done : out std_logic;
        data_in : in std_logic_vector(g_data_width - 1 downto 0);
        data_out : out std_logic_vector(g_data_width - 1 downto 0);
        data_out_valid : out std_logic
    );
end entity ntt;

architecture rtl of ntt is
    -- Algoritmo 21. Entradas/salidas: residuos unsigned en [0,p-1].
    -- IP de RAM y ROM: 512 x 32. RAM con dos ciclos de lectura y EN activo
    -- en ambos ciclos. La ROM admite uno o dos ciclos de lectura.
    type state_t is (ST_IDLE, ST_INIT_RAM, ST_RD_GAMMA, ST_WAIT_GAMMA_1,
                     ST_WAIT_GAMMA_2, ST_CAPTURE_GAMMA, ST_RD_U, ST_WAIT_U_1,
                     ST_WAIT_U_2, ST_CAPTURE_U, ST_MUL, ST_TRANSFORM, ST_WR_U,
                     ST_COMMIT_U, ST_RD_NTT_INIT, ST_RD_NTT_WAIT_1,
                     ST_RD_NTT_WAIT_2, ST_RD_NTT_CAPTURE, ST_DONE);
    signal state, next_state : state_t;
    constant C_P : unsigned(g_data_width - 1 downto 0) := to_unsigned(g_modulus, g_data_width);
    signal ram_ntt_ena, ram_ntt_enb : std_logic;
    signal ram_ntt_wea, ram_ntt_web : std_logic_vector(0 downto 0);
    signal ram_addra, ram_addrb : std_logic_vector(g_addr_width - 1 downto 0);
    signal ram_douta, ram_doutb : std_logic_vector(g_data_width - 1 downto 0);
    -- Cada puerto accede a un coeficiente de la mariposa, sin partes complejas.
    signal data_a, data_b, ram_dina : std_logic_vector(g_data_width - 1 downto 0);
    signal ntt_out_count : integer range 0 to g_num_samples - 1 := 0;
    signal data_out_valid_reg : std_logic := '0';
    signal data_out_reg : std_logic_vector(g_data_width - 1 downto 0);
    -- m=1,2,...,n/2; i=0..m-1; j=0..t-1.
    -- t ya incluye la division por dos al comenzar cada etapa.
    signal t, m, i, j : unsigned(12 downto 0);
    signal addr_gamma : std_logic_vector(8 downto 0);
    signal rom_gamma : std_logic_vector(g_data_width - 1 downto 0);
    signal gamma, u0, u1, su1 : unsigned(g_data_width - 1 downto 0);
    signal prod_gamma : unsigned(2 * g_data_width - 1 downto 0);
    signal rom_enable : std_logic;

    component blk_mem_gen_1
        port (
            clka, ena : in std_logic;
            wea : in std_logic_vector(0 downto 0);
            addra : in std_logic_vector(8 downto 0);
            dina : in std_logic_vector(g_data_width-1 downto 0);
            douta : out std_logic_vector(g_data_width-1 downto 0);
            clkb, enb : in std_logic;
            web : in std_logic_vector(0 downto 0);
            addrb : in std_logic_vector(8 downto 0);
            dinb : in std_logic_vector(g_data_width-1 downto 0);
            doutb : out std_logic_vector(g_data_width-1 downto 0)
        );
    end component;
    -- Gamma[i] = gamma^rev_log2(n)(i) mod p; no es formato Q31.
    -- P1: gamma_p1_n512.coe, 512 x 32 bits.
    component blk_mem_gen_3
        port (
            clka, ena : in std_logic;
            addra : in std_logic_vector(8 downto 0);
            douta : out std_logic_vector(g_data_width-1 downto 0)
        );
    end component;
    -- P2: gamma_p2_n512.coe, 512 x 32 bits.
    component blk_mem_gen_4
        port (
            clka, ena : in std_logic;
            addra : in std_logic_vector(8 downto 0);
            douta : out std_logic_vector(g_data_width-1 downto 0)
        );
    end component;
begin
    data_out_valid <= data_out_valid_reg;
    data_out <= data_out_reg;

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
        ram_ntt_ena <= '0';
        ram_ntt_wea <= (others => '0');
        ram_ntt_enb <= '0';
        ram_ntt_web <= (others => '0');
        done <= '0';
        case state is
            when ST_IDLE =>
                if start = '1' then next_state <= ST_INIT_RAM; end if;
            when ST_INIT_RAM =>
                if data_in_valid = '1' then
                    ram_ntt_ena <= '1';
                    ram_ntt_wea <= (others => '1');
                    if unsigned(ram_addra) = g_num_samples - 1 then
                        next_state <= ST_RD_GAMMA;
                    end if;
                end if;
            when ST_RD_GAMMA => next_state <= ST_WAIT_GAMMA_1;
            when ST_WAIT_GAMMA_1 => next_state <= ST_WAIT_GAMMA_2;
            when ST_WAIT_GAMMA_2 => next_state <= ST_CAPTURE_GAMMA;
            when ST_CAPTURE_GAMMA => next_state <= ST_RD_U;
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
            when ST_CAPTURE_U => next_state <= ST_MUL;
            when ST_MUL => next_state <= ST_TRANSFORM;
            when ST_TRANSFORM => next_state <= ST_WR_U;
            when ST_WR_U => next_state <= ST_COMMIT_U;
            when ST_COMMIT_U =>
                -- Escribe ambas salidas simultaneamente, una por puerto.
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
            when ST_RD_NTT_INIT => next_state <= ST_RD_NTT_WAIT_1;
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

    p_counter : process(clk)
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
                t <= (others => '0'); m <= (others => '0');
                i <= (others => '0'); j <= (others => '0');
                u0 <= (others => '0'); u1 <= (others => '0');
                gamma <= (others => '0');
                prod_gamma <= (others => '0'); su1 <= (others => '0');
                data_a <= (others => '0'); data_b <= (others => '0');
            else
                data_out_valid_reg <= '0';
                case state is
                    when ST_IDLE =>
                        ram_addra <= (others => '0');
                        ram_addrb <= (others => '0');
                        rom_enable <= '0';
                        t <= to_unsigned(g_num_samples / 2, t'length);
                        m <= to_unsigned(1, m'length);
                        i <= (others => '0'); j <= (others => '0');
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
                        rom_enable <= '0';
                        gamma <= unsigned(rom_gamma);
                    when ST_RD_U =>
                        ram_addra <= std_logic_vector(resize(2 * t * i + j, ram_addra'length));
                        ram_addrb <= std_logic_vector(resize(2 * t * i + t + j, ram_addrb'length));
                    when ST_CAPTURE_U =>
                        u0 <= unsigned(ram_douta);
                        u1 <= unsigned(ram_doutb);
                    when ST_MUL =>
                        -- Producto completo antes de reducir, sin truncarlo.
                        prod_gamma <= gamma * u1;
                    when ST_TRANSFORM =>
                        su1 <= resize(prod_gamma mod resize(C_P, prod_gamma'length), su1'length);
                    when ST_WR_U =>
                        -- Suma y resta modulo p; un bit extra evita perder acarreo.
                        sum_u := resize(u0, sum_u'length) + resize(su1, sum_u'length);
                        if sum_u >= resize(C_P, sum_u'length) then
                            sum_u := sum_u - resize(C_P, sum_u'length);
                        end if;
                        data_a <= std_logic_vector(resize(sum_u, g_data_width));
                        if u0 >= su1 then
                            data_b <= std_logic_vector(u0 - su1);
                        else
                            data_b <= std_logic_vector(C_P - (su1 - u0));
                        end if;
                    when ST_COMMIT_U =>
                        -- Avanza los bucles solo tras escribir la pareja.
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
                        ram_addra <= (others => '0');
                        ntt_out_count <= 0;
                    when ST_RD_NTT_WAIT_1 | ST_RD_NTT_WAIT_2 =>
                        ram_addra <= std_logic_vector(unsigned(ram_addra) + 1);
                    when ST_RD_NTT_CAPTURE =>
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
                    when others => null;
                end case;
            end if;
        end if;
    end process p_counter;

    addr_gamma <= std_logic_vector(resize(i + m, addr_gamma'length));
    ram_dina <= data_in when state = ST_INIT_RAM else data_a;
    ram_ntt : blk_mem_gen_1
        port map (
            clka => clk, ena => ram_ntt_ena, wea => ram_ntt_wea,
            addra => ram_addra, dina => ram_dina, douta => ram_douta,
            clkb => clk, enb => ram_ntt_enb, web => ram_ntt_web,
            addrb => ram_addrb, dinb => data_b, doutb => ram_doutb
        );
    gen_gamma_p1 : if g_modulus = 2147473409 generate
        rom_gamma_inst : blk_mem_gen_3
            port map (
                clka => clk, ena => rom_enable,
                addra => addr_gamma, douta => rom_gamma
            );
    end generate gen_gamma_p1;

    gen_gamma_p2 : if g_modulus = 2147389441 generate
        rom_gamma_inst : blk_mem_gen_4
            port map (
                clka => clk, ena => rom_enable,
                addra => addr_gamma, douta => rom_gamma
            );
    end generate gen_gamma_p2;
end architecture rtl;
