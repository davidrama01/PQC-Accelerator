library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package hawk_pkg is

    -- Constants
    constant c_num_samples  : integer range 0 to 1024 := 512;
    constant c_num_phases   : integer range 0 to 15 := 8;
    constant c_data_width   : integer range 0 to 31 := 16;
    constant c_sigma_verify : integer range 0 to 12000 := 10469; -- LSB = 13 bits
    constant c_threshold_verify : signed(13 downto 0) := resize(shift_right(to_signed(8 * c_sigma_verify * c_sigma_verify * c_num_samples + 2**25, 40), 26), 14);

    -- Types
    type t_poly_coef is array (natural range <>) of signed(natural range <>);

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

end package body hawk_pkg;