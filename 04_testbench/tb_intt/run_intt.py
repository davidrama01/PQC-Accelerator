"""Validate INTT against inverse evaluation and RTL NTT -> INTT for P1/P2."""
import argparse
import random
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
HEADER = 'library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;\n'
RAM = HEADER + '''
entity blk_mem_gen_1 is
port(clka,ena: in std_logic; wea: in std_logic_vector(0 downto 0);
addra: in std_logic_vector(8 downto 0); dina: in std_logic_vector(31 downto 0);
douta: out std_logic_vector(31 downto 0); clkb,enb: in std_logic;
web: in std_logic_vector(0 downto 0); addrb: in std_logic_vector(8 downto 0);
dinb: in std_logic_vector(31 downto 0); doutb: out std_logic_vector(31 downto 0)); end;
architecture model of blk_mem_gen_1 is
type memory_t is array(0 to 511) of std_logic_vector(31 downto 0);
signal mem: memory_t;
signal qa,qb: std_logic_vector(31 downto 0);
begin
process(clka) begin
if rising_edge(clka) then
 if ena='1' then
  douta<=qa; qa<=mem(to_integer(unsigned(addra)));
  if wea(0)='1' then mem(to_integer(unsigned(addra)))<=dina; end if;
 end if;
 if enb='1' then
  doutb<=qb; qb<=mem(to_integer(unsigned(addrb)));
  if web(0)='1' then mem(to_integer(unsigned(addrb)))<=dinb; end if;
 end if;
end if;
end process; end;
'''


def expected_intt(values, p, g):
    # Inverse evaluation matrix, independent of the RTL butterfly schedule.
    n = len(values)
    gamma = pow(g, (p-1)//(2*n), p)
    result = [0]*n
    for r, value in enumerate(values):
        rev = int(f'{r:09b}'[::-1], 2)
        inverse_root = pow(pow(gamma, 2*rev+1, p), -1, p)
        power = 1
        for j in range(n):
            result[j] = (result[j]+value*power) % p
            power = power*inverse_root % p
    inv_n = pow(n, -1, p)
    return [x*inv_n % p for x in result]


def write_vectors(directory, name, p, g):
    rng = random.Random(20261003)
    cases = [[0]*512, [1]+[0]*511, [0]*511+[1], [p-1]*512,
             [(0, 1, p-1, p-2)[i % 4] for i in range(512)],
             [rng.randrange(p) for _ in range(512)]]
    for mode in (0, 1):
        output_path = directory/f'vectors_{name}_{mode}.txt'
        with output_path.open('w') as output:
            for values in cases:
                expected = expected_intt(values, p, g) if mode == 0 else values
                for a, b in zip(values, expected):
                    output.write(f'{a} {b}\n')
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-bin', type=Path, default=Path('C:/Xilinx/Vivado/2022.1/bin'))
    parser.add_argument('--ram-ip', type=Path)
    parser.add_argument('--vectors-only', action='store_true')
    parser.add_argument('--output-dir', type=Path, default=HERE)
    args = parser.parse_args()
    parameters = [('p1', 2147473409, 3), ('p2', 2147389441, 11)]
    if args.vectors_only:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for name, p, g in parameters:
            print(write_vectors(args.output_dir, name, p, g))
        return
    work = Path(tempfile.mkdtemp(prefix='hawk-intt-both-'))
    print(f'P1 + P2: {work}', flush=True)
    for name, p, g in parameters:
        write_vectors(work, name, p, g)
    roms = ''
    # Both ROMs retain their own COE in every run: the DUT generate must
    # select the right component, not a test-side swap of its contents.
    for rom_name, component in [('p1', 'blk_mem_gen_3'), ('p2', 'blk_mem_gen_4'),
                                ('inv_p1', 'blk_mem_gen_5'), ('inv_p2', 'blk_mem_gen_6')]:
        coe = (ROOT/f'05_software/rom/gamma_{rom_name}_n512.coe').read_text()
        words = re.findall(r'[0-9a-fA-F]{8}', coe.split('memory_initialization_vector=')[1])
        assert len(words) == 512
        rom = HEADER + '''
entity blk_mem_gen_3 is
port(clka,ena: in std_logic; addra: in std_logic_vector(8 downto 0);
douta: out std_logic_vector(31 downto 0)); end;
architecture model of blk_mem_gen_3 is
type rom_t is array(0 to 511) of std_logic_vector(31 downto 0);
constant rom: rom_t := (''' + ','.join(f'x"{x}"' for x in words) + ''');
signal q: std_logic_vector(31 downto 0);
begin
process(clka) begin
if rising_edge(clka) then
 if ena='1' then q<=rom(to_integer(unsigned(addra))); douta<=q; end if;
end if;
end process; end;
'''
        roms += rom.replace('blk_mem_gen_3', component)
    (work/'models.vhd').write_text(roms if args.ram_ip else RAM+roms)
    def run(tool, *params):
        subprocess.run([str(args.vivado_bin/(tool+'.bat')), *map(str, params)],
                       cwd=work, check=True)
    libraries = []
    if args.ram_ip:
        run('xvlog', '--work', 'work', args.ram_ip.resolve())
        libraries = ['-L', 'blk_mem_gen_v8_4_5']
    run('xvhdl', '--2008', work/'models.vhd', ROOT/'03_design/ntt.vhd', ROOT/'03_design/intt.vhd', HERE/'intt_tb.vhd')
    run('xelab', '--relax', *libraries, 'work.intt_tb', '-s', 'intt_test')
    (work/'run.tcl').write_text('run 10 ms\nquit\n')
    run('xsim', 'intt_test', '-tclbatch', 'run.tcl')
    log = (work/'xsim.log').read_text()
    if 'INTT: P1 y P2, todas las pruebas superadas' not in log or 'Failure:' in log or 'Fatal:' in log:
        raise RuntimeError(f'INTT validation failed: {work}')
    print('PASS P1 + P2: 24 vectors, 12288 coefficients (inverse + RTL roundtrip) and reset recovery', flush=True)


if __name__ == '__main__':
    main()
