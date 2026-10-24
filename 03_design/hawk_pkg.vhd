library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package hawk_pkg is

    -- Constants
    constant c_max_samples : positive := 1024;
    constant c_num_samples  : integer range 0 to c_max_samples := 1024;
    constant c_data_width   : integer range 0 to 40 := 32;
    constant c_addr_width   : integer range 0 to 10 := 10;
    constant c_size_fifo : integer range 0 to c_max_samples := c_num_samples / c_data_width;

    -- Rebuild S0 constants

    function clog2(value : positive) return natural;
    function verify_threshold(n : positive) return unsigned;
    function high_q00(n : positive) return natural;
    function high_q01(n : positive) return natural;
    function high_s0(n : positive) return natural;
    function high_s1(n : positive) return natural;

    -- Types
    -- type t_poly_coef is array (natural range <>) of signed(natural range <>);

    -- Functions
    --function parity_check(data : std_logic_vector) return std_logic;


    -- Procedures
    --procedure increment_counter(signal cnt : inout integer);

end package hawk_pkg;

package body hawk_pkg is

    -- floor(8*n*sigma_verify^2), igual que NORM_THR en hawk_params.h.
    -- Se selecciona el entero exacto para evitar aproximaciones Q13.
    function verify_threshold(n : positive) return unsigned is
    begin
        case n is
            when 256 => return to_unsigned(2223, 32);
            when 1024 => return to_unsigned(20218, 32);
            when others => return to_unsigned(8317, 32);
        end case;
    end function;

    -- Parametros de RebuildS0 seleccionados por el registro num_samples.
    function high_q00(n : positive) return natural is
    begin
        if n = 1024 then return 10; else return 9; end if;
    end function;

    function high_q01(n : positive) return natural is
    begin
        case n is
            when 256 => return 11;
            when 1024 => return 14;
            when others => return 12;
        end case;
    end function;

    function high_s0(n : positive) return natural is
    begin
        case n is
            when 256 => return 12;
            when 1024 => return 14;
            when others => return 13;
        end case;
    end function;

    function high_s1(n : positive) return natural is
    begin
        if n = 1024 then return 10; else return 9; end if;
    end function;


    -- function parity_check(data : std_logic_vector) return std_logic is
    --     variable parity : std_logic := '0';
    -- begin
    --     for i in data'range loop
    --         parity := parity xor data(i);
    --     end loop;
    --     return parity;
    -- end function;

    -- procedure increment_counter(signal cnt : inout integer) is
    -- begin
    --     cnt <= cnt + 1;
    -- end procedure;

    function clog2(value : positive) return natural is
        variable result : natural := 0;
        variable x      : natural := value - 1;
    begin
        while x > 0 loop
            x := x / 2;
            result := result + 1;
        end loop;

        return result;
    end function;

end package body hawk_pkg;
