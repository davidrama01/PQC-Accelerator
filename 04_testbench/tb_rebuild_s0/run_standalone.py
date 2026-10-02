"""Run the real FFT/IFFT/rebuild RTL with synchronous memory/FIFO models.

Usage: python run_standalone.py [Vivado bin directory]
Does not replace or validate the project's Xilinx IP configuration. Models
have two-clock BRAM reads, common-clock dual-port RAM and a standard (not FWFT)
FIFO. Generated files and logs are retained in a printed temporary directory.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN = Path(sys.argv[1] if len(sys.argv) > 1 else 'C:/Xilinx/Vivado/2022.1/bin')
HEADER = 'library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;\n'
MODELS = HEADER + '''
entity blk_mem_gen_1 is
port(clka, ena: in std_logic; wea: in std_logic_vector(0 downto 0);
addra: in std_logic_vector(8 downto 0); dina: in std_logic_vector(31 downto 0);
douta: out std_logic_vector(31 downto 0);
clkb, enb: in std_logic; web: in std_logic_vector(0 downto 0);
addrb: in std_logic_vector(8 downto 0); dinb: in std_logic_vector(31 downto 0);
doutb: out std_logic_vector(31 downto 0)); end;
architecture model of blk_mem_gen_1 is
type mem_t is array(0 to 511) of std_logic_vector(31 downto 0);
signal mem: mem_t; -- Uninitialized on purpose: expose unwritten reads.
signal qa,qb: std_logic_vector(31 downto 0);
begin
process(clka) begin
if rising_edge(clka) then
if ena='1' then
 douta <= qa;
 qa <= mem(to_integer(unsigned(addra)));
 if wea(0)='1' then mem(to_integer(unsigned(addra))) <= dina; end if;
end if;
if enb='1' then
 doutb <= qb;
 qb <= mem(to_integer(unsigned(addrb)));
 if web(0)='1' then mem(to_integer(unsigned(addrb))) <= dinb; end if;
end if;
end if;
end process; end;
''' + HEADER + '''
entity fifo_generator_0 is
port(clk,srst: in std_logic; din: in std_logic_vector(31 downto 0);
wr_en,rd_en: in std_logic; dout: out std_logic_vector(31 downto 0);
full,empty: out std_logic); end;
architecture model of fifo_generator_0 is
type mem_t is array(0 to 1023) of std_logic_vector(31 downto 0);
signal mem: mem_t;
signal count: integer range 0 to 1024 := 0;
signal rp,wp: integer range 0 to 1023 := 0;
begin
full <= '1' when count=1024 else '0';
empty <= '1' when count=0 else '0';
process(clk) begin
if rising_edge(clk) then
 if srst='1' then count<=0; rp<=0; wp<=0; dout<=(others=>'0');
 else
  if wr_en='1' then
   assert count<1024 report "FIFO overflow" severity failure;
   mem(wp)<=din; wp<=(wp+1) mod 1024;
  end if;
  if rd_en='1' then
   assert count>0 report "FIFO underflow" severity failure;
   dout<=mem(rp); rp<=(rp+1) mod 1024;
  end if;
  if wr_en='1' and rd_en='0' then count<=count+1;
  elsif rd_en='1' and wr_en='0' then count<=count-1; end if;
 end if;
end if;
end process; end;
'''


def main():
    work = Path(tempfile.mkdtemp(prefix='hawk-rebuild-'))
    print(f'Simulation directory: {work}', flush=True)
    coe = (ROOT/'05_software/rom/delta_rom.coe').read_text().split('memory_initialization_vector=')[1]
    words = re.findall(r'[0-9A-Fa-f]{16}', coe)
    assert len(words) == 1024
    rom = HEADER + '''
entity blk_mem_gen_2 is
port(clka,ena: in std_logic; addra: in std_logic_vector(9 downto 0);
douta: out std_logic_vector(63 downto 0)); end;
architecture model of blk_mem_gen_2 is
type rom_t is array(0 to 1023) of std_logic_vector(63 downto 0);
constant rom: rom_t := (''' + ','.join(f'x"{x}"' for x in words) + ''');
begin
process(clka) begin
if rising_edge(clka) then
if ena='1' then douta<=rom(to_integer(unsigned(addra))); end if;
end if;
end process; end;
'''
    (work/'models.vhd').write_text(MODELS+rom)
    def run(tool, *args):
        subprocess.run([str(BIN/(tool+'.bat')), *map(str,args)], cwd=work, check=True)
    run('xvhdl', '--2008', work/'models.vhd',
        *[ROOT/'03_design'/f'{name}.vhd' for name in ('hawk_pkg','fft','ifft','rebuild_s0')],
        Path(__file__).with_name('rebuild_s0_tb.vhd'))
    run('xelab', 'work.rebuild_s0_tb', '-s', 'rebuild_test')
    # Bound the batch run even when the interactive TB ends with wait/stop.
    (work/'run.tcl').write_text('run 3 ms\nquit\n')
    run('xsim', 'rebuild_test', '-tclbatch', 'run.tcl')
    log = (work/'xsim.log').read_text()
    assert 'Todas las pruebas de RebuildS0 han finalizado correctamente' in log
    assert 'Failure:' not in log and 'Fatal:' not in log
    print('PASS: all six cases matched; behavioral memory/FIFO models.')


if __name__ == '__main__':
    main()
