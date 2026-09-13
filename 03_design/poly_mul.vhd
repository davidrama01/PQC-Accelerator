library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity poly_mul is
    generic (
        g_num_samples   : integer := 512;
        g_data_width    : integer := 16;
        g_addr_width    : integer := 9 -- Log2(g_num_samples)
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;
        start       : in std_logic;
        done        : out std_logic;
        data_a      : in std_logic_vector(g_data_width - 1 downto 0);
        data_b      : in std_logic_vector(g_data_width - 1 downto 0);
        addr_a      : out std_logic_vector(g_addr_width - 1 downto 0);
        addr_b      : out std_logic_vector(g_addr_width - 1 downto 0);
        result      : out std_logic_vector(g_data_width - 1 downto 0)
    );
end entity poly_mul;

architecture rtl of poly_mul is

signal temp_result  : signed(2*g_data_width - 1 downto 0);
signal acc          : signed(2*g_data_width - 1 downto 0);
signal i            : integer range 0 to g_num_samples - 1;
signal j_addr       : integer range 0 to g_num_samples - 1;
signal j_data       : integer range 0 to g_num_samples - 1;
signal done_d       : std_logic;
signal enable       : std_logic;
signal reading      : std_logic;
signal data_valid   : std_logic;

begin

    pol_mul_process : process(clk, rst_n)
    variable temp_product : signed(2*g_data_width - 1 downto 0);
    begin
        if rst_n = '0' then
            temp_result <= (others => '0');
            acc         <= (others => '0');
            i           <= 0;
            j_addr      <= 0;
            j_data      <= 0;
            done_d      <= '0';
            enable      <= '0';
            reading     <= '0';
            data_valid  <= '0';
        elsif rising_edge(clk) then
            done_d <= '0';
            if start = '1' then
                i           <= 0;
                j_addr      <= 0;
                j_data      <= 0;
                acc         <= (others => '0');
                enable      <= '1';
                reading     <= '1';
                data_valid  <= '0';
                temp_result <= (others => '0');
            elsif enable = '1' then
                -- El ultimo dato llega un ciclo despues de presentar
                -- la direccion correspondiente a j_addr = n - 1.
                if data_valid = '1' and j_data = g_num_samples - 1 then
                    if j_data > i then
                        temp_product := -(signed(data_a) * signed(data_b));
                    else
                        temp_product := signed(data_a) * signed(data_b);
                    end if;

                    temp_result <= acc + temp_product;
                    acc         <= (others => '0');
                    done_d      <= '1';
                    data_valid  <= '0';

                    if i = g_num_samples - 1 then
                        i       <= 0;
                        enable  <= '0';
                        reading <= '0';
                    else
                        i       <= i + 1;
                        j_addr  <= 0;
                        j_data  <= 0;
                        reading <= '1';
                    end if;
                else
                    -- Procesar el dato cuyo indice se registro durante
                    -- el ciclo anterior.
                    if data_valid = '1' then
                        if j_data > i then
                            temp_product := -(signed(data_a) * signed(data_b));
                        else
                            temp_product := signed(data_a) * signed(data_b);
                        end if;

                        acc <= acc + temp_product;
                    end if;

                    -- Registrar el indice de la direccion presentada ahora.
                    if reading = '1' then
                        j_data     <= j_addr;
                        data_valid <= '1';

                        if j_addr = g_num_samples - 1 then
                            reading <= '0';
                        else
                            j_addr <= j_addr + 1;
                        end if;
                    else
                        data_valid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process pol_mul_process;

    addr_a <= std_logic_vector(to_unsigned(j_addr, g_addr_width));
    addr_b <= std_logic_vector(
        to_unsigned((i - j_addr + g_num_samples) mod g_num_samples, g_addr_width)
    );

    result <= std_logic_vector(resize(temp_result, g_data_width));
    done <= done_d;

end architecture rtl;
