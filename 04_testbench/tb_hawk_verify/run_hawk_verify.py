"""Compile and simulate HawkVerify using the project's generated Xilinx IP."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path('C:/David/TFM/project_1'))
    parser.add_argument('--vivado-bin', type=Path, default=Path('C:/Xilinx/Vivado/2022.1/bin'))
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix='hawk-verify-tb-'))
    print(f'Simulation directory: {work}', flush=True)

    def run(tool, *params):
        result = subprocess.run([str(args.vivado_bin/(tool+'.bat')), *map(str, params)],
                                cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True)
        (work/(tool+'_output.txt')).write_text(result.stdout)
        if result.returncode or 'remains a black box' in result.stdout:
            raise RuntimeError(result.stdout)
        print(f'{tool}: OK', flush=True)

    ip_root = args.project/(args.project.name+'.gen')/'sources_1/ip'
    ips = ('fifo_generator_0', 'blk_mem_gen_1', 'blk_mem_gen_2', 'blk_mem_gen_3', 'blk_mem_gen_4')
    sources = []
    for ip in ips:
        path = ip_root/ip/'sim'/f'{ip}.v'
        if not path.is_file():
            raise FileNotFoundError(f'Generate output products for {ip}: {path}')
        sources.append(path)
        for mif in (ip_root/ip).rglob('*.mif'):
            shutil.copyfile(mif, work/mif.name)
    run('xvlog', '--work', 'work', *sources)
    run('xvhdl', '--2008', *[ROOT/'03_design'/f'{name}.vhd' for name in
        ('hawk_pkg', 'fft', 'ifft', 'rebuild_s0', 'ntt', 'polyqnorm', 'sym_break_w1', 'hawk_verify')],
        HERE/'hawk_verify_tb.vhd')
    run('xelab', '--relax', '-debug', 'typical', '-L', 'fifo_generator_v13_2_7',
        '-L', 'blk_mem_gen_v8_4_5', 'work.hawk_verify_tb', '-s', 'verify_test')
    (work/'run.tcl').write_text('run 50 ms\nquit\n')
    run('xsim', 'verify_test', '-tclbatch', 'run.tcl')
    log = (work/'xsim.log').read_text()
    if ('PASS: HawkVerify, todos los casos y resets superados' not in log or
            'Failure:' in log or 'Fatal:' in log):
        raise RuntimeError(f'Simulation failed; inspect {work / "xsim.log"}\n{log[-4000:]}')
    print('\n'.join(line for line in log.splitlines() if 'Note:' in line))


if __name__ == '__main__':
    main()
