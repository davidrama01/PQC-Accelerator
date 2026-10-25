library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hawk_pkg.all;

entity poly_mul_mod2 is
    port (
        num_samples : in integer range 1 to c_max_samples := c_num_samples;
        clk : in std_logic;
        rst_n : in std_logic;
        start : in std_logic;
        done : out std_logic;
        data_a : in std_logic_vector(c_max_samples - 1 downto 0);
        data_b : in std_logic_vector(c_max_samples - 1 downto 0);
        result : out std_logic_vector(c_max_samples - 1 downto 0)
    );
end entity poly_mul_mod2;

architecture rtl of poly_mul_mod2 is
    constant C_BANK_BITS : positive := 32;
    constant C_BANKS : positive := (c_max_samples+C_BANK_BITS-1)/C_BANK_BITS;
    signal n : integer range 1 to c_max_samples;
    signal i,j : integer range 0 to c_max_samples-1;
    signal issuing : std_logic;
    signal index_a,index_b : integer range 0 to c_max_samples-1;
    signal a_bank,b_bank : integer range 0 to C_BANKS-1;
    signal a_banks,b_banks : std_logic_vector(C_BANKS-1 downto 0);
    signal a_bit,b_bit,acc,coefficient : std_logic;
    -- Tags advance with the data, including across coefficient boundaries.
    signal valid,last_j,last_i : std_logic_vector(0 to 2);
    signal store_valid,store_last : std_logic;
    signal write_token : std_logic_vector(c_max_samples-1 downto 0);
    signal bank_coefficient, bank_valid : std_logic_vector(C_BANKS-1 downto 0);
    signal bank_token : std_logic_vector(c_max_samples-1 downto 0);
    signal commit_last : std_logic;
    -- Preserve the small local driver bank through synthesis (not debug probes).
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of bank_coefficient : signal is "TRUE";
    signal temp_result : std_logic_vector(c_max_samples-1 downto 0);
begin
    result <= temp_result;
    -- Static output destinations, with local one-hot write enables.
    process(clk,rst_n) begin
        if rst_n='0' then
            temp_result<=(others=>'0');
        elsif rising_edge(clk) then
            if start='1' then
                temp_result<=(others=>'0');
            else
                for k in 0 to c_max_samples-1 loop
                    if bank_valid(k/C_BANK_BITS)='1' and bank_token(k)='1' then
                        temp_result(k)<=bank_coefficient(k/C_BANK_BITS);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    process(clk,rst_n)
        variable a_pos,b_pos : natural;
    begin
        if rst_n='0' then
            n<=1; i<=0; j<=0; issuing<='0'; index_a<=0; index_b<=0;
            a_bank<=0; b_bank<=0;
            a_banks<=(others=>'0'); b_banks<=(others=>'0');
            a_bit<='0'; b_bit<='0'; acc<='0'; coefficient<='0';
            valid<=(others=>'0'); last_j<=(others=>'0'); last_i<=(others=>'0');
            store_valid<='0'; store_last<='0';
            bank_coefficient<=(others=>'0'); bank_valid<=(others=>'0');
            bank_token<=(others=>'0'); commit_last<='0';
            write_token<=(others=>'0'); done<='0';
        elsif rising_edge(clk) then
            done<='0';
            -- Restart flushes all pending data and tags, as well as the output.
            if start='1' then
                n<=num_samples; i<=0; j<=0; issuing<='1'; acc<='0';
                valid<=(others=>'0'); last_j<=(others=>'0'); last_i<=(others=>'0');
                store_valid<='0'; store_last<='0';
                bank_valid<=(others=>'0'); bank_token<=(others=>'0'); commit_last<='0';
                write_token<=(0=>'1',others=>'0');
            else
                -- Stage 1: accept one pair every cycle, register circular index.
                valid(0)<=issuing;
                if issuing='1' then
                    index_a<=j;
                    if i>=j then index_b<=i-j;
                    else index_b<=n-j+i; end if;
                    last_j(0)<='0'; last_i(0)<='0';
                    if j=n-1 then
                        last_j(0)<='1'; j<=0;
                        if i=n-1 then last_i(0)<='1'; issuing<='0';
                        else i<=i+1; end if;
                    else j<=j+1; end if;
                end if;

                -- Stage 2: registered selection within each 32-bit bank.
                valid(1)<=valid(0); last_j(1)<=last_j(0); last_i(1)<=last_i(0);
                if valid(0)='1' then
                    for bank in 0 to C_BANKS-1 loop
                        a_pos:=bank*C_BANK_BITS+(index_a-(index_a/C_BANK_BITS)*C_BANK_BITS);
                        b_pos:=bank*C_BANK_BITS+(index_b-(index_b/C_BANK_BITS)*C_BANK_BITS);
                        if a_pos<c_max_samples then a_banks(bank)<=data_a(a_pos);
                        else a_banks(bank)<='0'; end if;
                        if b_pos<c_max_samples then b_banks(bank)<=data_b(b_pos);
                        else b_banks(bank)<='0'; end if;
                    end loop;
                    a_bank<=index_a/C_BANK_BITS; b_bank<=index_b/C_BANK_BITS;
                end if;

                -- Stage 3: registered bank selection.
                valid(2)<=valid(1); last_j(2)<=last_j(1); last_i(2)<=last_i(1);
                if valid(1)='1' then
                    a_bit<=a_banks(a_bank); b_bit<=b_banks(b_bank);
                end if;

                -- Stage 4: XOR accumulation. Reset at each tagged boundary,
                -- while the next coefficient is already moving through the pipe.
                store_valid<='0';
                if valid(2)='1' then
                    if last_j(2)='1' then
                        coefficient<=acc xor (a_bit and b_bit); acc<='0';
                        store_valid<='1'; store_last<=last_i(2);
                    else acc<=acc xor (a_bit and b_bit); end if;
                end if;

                -- Stage 5: distribute to local registered drivers. Each bank
                -- has a distinct enable, so unrelated banks retain their value.
                bank_valid<=(others=>'0');
                commit_last<=store_valid and store_last;
                if store_valid='1' then
                    bank_token<=write_token;
                    for bank in 0 to C_BANKS-1 loop
                        for offset in 0 to C_BANK_BITS-1 loop
                            if bank*C_BANK_BITS+offset<c_max_samples then
                                if write_token(bank*C_BANK_BITS+offset)='1' then
                                    bank_coefficient(bank)<=coefficient;
                                    bank_valid(bank)<='1';
                                end if;
                            end if;
                        end loop;
                    end loop;
                    write_token<=std_logic_vector(shift_left(unsigned(write_token),1));
                end if;
                -- Stage 6 writes bank data in the output process above.
                if commit_last='1' then done<='1'; end if;
            end if;
        end if;
    end process;
end architecture rtl;
