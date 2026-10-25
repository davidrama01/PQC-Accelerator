library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hawk_pkg.all;

entity poly_mul is
    generic (

        g_data_width    : integer := 16;
        g_addr_width    : integer := c_addr_width -- Ancho fisico de direccion
    );
    port (
        num_samples : in integer range 256 to c_max_samples := c_num_samples;
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
signal i            : integer range 0 to c_max_samples - 1;
signal j_addr       : integer range 0 to c_max_samples - 1;
signal j_data       : integer range 0 to c_max_samples - 1;
signal done_d       : std_logic;
signal enable       : std_logic;
signal reading      : std_logic;
signal data_valid   : std_logic;
signal read_valid_d : std_logic;
signal j_read       : integer range 0 to c_max_samples - 1;
signal product_reg, signed_product : signed(2*g_data_width-1 downto 0);
signal product_valid, signed_valid : std_logic;
signal product_negative, product_last, signed_last : std_logic;

begin

    pol_mul_process : process(clk, rst_n)
    begin
        if rst_n = '0' then
            temp_result <= (others=>'0'); acc <= (others=>'0');
            product_reg <= (others=>'0'); signed_product <= (others=>'0');
            product_valid<='0'; signed_valid<='0'; product_negative<='0';
            product_last<='0'; signed_last<='0';
            i<=0; j_addr<=0; j_data<=0; j_read<=0; read_valid_d<='0';
            done_d<='0'; enable<='0'; reading<='0'; data_valid<='0';
        elsif rising_edge(clk) then
            done_d<='0';
            if start='1' then
                i<=0; j_addr<=0; j_data<=0; j_read<=0; read_valid_d<='0';
                acc<=(others=>'0'); temp_result<=(others=>'0');
                enable<='1'; reading<='1'; data_valid<='0';
                product_valid<='0'; signed_valid<='0';
                product_negative<='0'; product_last<='0'; signed_last<='0';
            elsif enable='1' then
                -- blk_mem_gen_0 has a registered output: align both the
                -- valid flag and index tag with its two-clock read latency.
                read_valid_d<=reading;
                data_valid<=read_valid_d;
                if read_valid_d='1' then j_data<=j_read; end if;
                if reading='1' then
                    j_read<=j_addr;
                    if j_addr=num_samples-1 then reading<='0';
                    else j_addr<=j_addr+1; end if;
                end if;

                -- Stage 1: full signed product, no sign adjustment or addition.
                product_valid<=data_valid;
                if data_valid='1' then
                    product_reg<=signed(data_a)*signed(data_b);
                    product_negative<='0'; product_last<='0';
                    if j_data>i then product_negative<='1'; end if;
                    if j_data=num_samples-1 then product_last<='1'; end if;
                end if;

                -- Stage 2: negacyclic sign, with matching end-of-coefficient tag.
                signed_valid<=product_valid;
                if product_valid='1' then
                    signed_last<=product_last;
                    if product_negative='1' then signed_product<=-product_reg;
                    else signed_product<=product_reg; end if;
                end if;

                -- Stage 3: accumulator only. Drain the pipe before changing i
                -- and restarting memory requests for the next coefficient.
                if signed_valid='1' then
                    if signed_last='1' then
                        temp_result<=acc+signed_product;
                        acc<=(others=>'0'); done_d<='1';
                        data_valid<='0'; read_valid_d<='0';
                        product_valid<='0'; signed_valid<='0';
                        if i=num_samples-1 then
                            i<=0; enable<='0'; reading<='0';
                        else
                            i<=i+1; j_addr<=0; j_data<=0; reading<='1';
                        end if;
                    else acc<=acc+signed_product; end if;
                end if;
            end if;
        end if;
    end process;

    addr_a <= std_logic_vector(to_unsigned(j_addr, g_addr_width));
    addr_b <= std_logic_vector(
        to_unsigned(i - j_addr, g_addr_width)
    ) when i >= j_addr else std_logic_vector(
        to_unsigned(i - j_addr + num_samples, g_addr_width)
    );

    result <= std_logic_vector(resize(temp_result, g_data_width));
    done <= done_d;

end architecture rtl;
