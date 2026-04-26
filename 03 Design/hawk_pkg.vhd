library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package hawk_pkg is

    -- Constants
    constant HAWK_VERSION : std_logic_vector(7 downto 0) := x"01";

    -- Types
    type hawk_state_type is (IDLE, PROCESSING, DONE);

    -- Functions
    function parity_check(data : std_logic_vector) return std_logic;

    -- Procedures
    procedure increment_counter(signal cnt : inout integer);

end package hawk_pkg;

package body hawk_pkg is

    function parity_check(data : std_logic_vector) return std_logic is
        variable parity : std_logic := '0';
    begin
        for i in data'range loop
            parity := parity xor data(i);
        end loop;
        return parity;
    end function;

    procedure increment_counter(signal cnt : inout integer) is
    begin
        cnt <= cnt + 1;
    end procedure;

end package body hawk_pkg;