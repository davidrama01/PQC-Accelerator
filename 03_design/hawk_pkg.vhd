library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package hawk_pkg is

    -- Constants
    constant c_num_samples  : integer range 0 to 1024 := 512;
    constant c_data_width   : integer range 0 to 40 := 32;
    constant c_sigma_verify : integer range 0 to 12000 := 10469; -- LSB = 13 bits
    constant c_threshold_verify : signed(13 downto 0) := resize(shift_right(to_signed(8 * c_sigma_verify * c_sigma_verify * c_num_samples + 2**25, 40), 26), 14);
    constant c_size_fifo : integer range 0 to 1024 := c_num_samples / c_data_width;

    constant c_low_q00  : integer range 0 to 11 := 5;
    constant c_high_q00 : integer range 0 to 11 := 9;

    constant c_low_q01  : integer range 0 to 15 := 9;
    constant c_high_q01 : integer range 0 to 15 := 12;

    constant c_high_q11 : integer range 0 to 20 := 15;

    constant c_high_s0  : integer range 0 to 20 := 13;

    constant c_low_s1   : integer range 0 to 15 := 5;
    constant c_high_s1  : integer range 0 to 15 := 9;

    -- Rebuild S0 constants

    constant c_w1 : integer range 0 to 29 := 29 - 1 - c_high_s1;
    constant c_q00 : integer range 0 to 29 := 29 - c_high_q00;
    constant c_q01 : integer range 0 to 29 := 29 - c_high_q01;
    constant c_s0  : integer range 0 to 29 := (2 * c_w1 * c_q01) / (c_num_samples * c_q00);

    -- Types
    -- type t_poly_coef is array (natural range <>) of signed(natural range <>);

    -- Functions
    --function parity_check(data : std_logic_vector) return std_logic;

    -- Procedures
    --procedure increment_counter(signal cnt : inout integer);

end package hawk_pkg;

package body hawk_pkg is

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