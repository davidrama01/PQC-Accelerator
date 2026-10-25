"""Check sampling and RegenerateFG against hashlib and Table 5 of the local spec.

Requires the previously extracted PDF text .work/hawk_spec_audit.txt.
Reference arithmetic uses full Python integers, not the C 80-bit comparator.
"""
from pathlib import Path
import hashlib
import re
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'06_test/.work/sampler_spec'


def x4(seed,length):
    lanes=[struct.unpack('<'+'Q'*length,hashlib.shake_256(seed+bytes([j])).digest(8*length)) for j in range(4)]
    return [lanes[j][i] for i in range(length) for j in range(4)]


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    doc=(ROOT/'06_test/.work/hawk_spec_audit.txt').read_text(encoding='utf-8')
    table=doc[doc.index('Table 5: Cumulative'):doc.index('Algorithm 14 SamplerSign:')]
    reference={}
    for n,count in ((256,10),(512,13),(1024,13)):
        section=table.split(f'HA WK-{n} ')[1]
        values=[int(x,16) for x in re.findall(r'0x([0-9A-F]{20})',section)[:2*count]]
        assert len(values)==2*count
        reference[n]=(values[::2],values[1::2])
    (WORK/'test.c').write_text('''
#include <assert.h>
#include <stdio.h>
#include "hawk_params.h"
#include "sampler_sign.h"
#include "regenerate.h"
int main(void) {
unsigned sizes[]={256,512,1024};
for(unsigned k=0;k<3;k++) {
assert(hawk_select_params(sizes[k])==0);
uint8_t seed[148],t[2*HAWK_N_BYTES];int16_t x[2*HAWK_N];int8_t f[HAWK_N],g[HAWK_N];
for(unsigned i=0;i<148;i++)seed[i]=(uint8_t)(17*i+11);
assert(RegenerateFG(seed,f,g)==0);
printf("N %u\\n",HAWK_N);
for(unsigned i=0;i<HAWK_N;i++)printf("%d %d\\n",f[i],g[i]);
for(unsigned mode=0;mode<3;mode++) {
for(unsigned i=0;i<sizeof t;i++)t[i]=mode==0?0:mode==1?255:(uint8_t)(i*29+7);
assert(SamplerSign(seed,HAWK_M_BYTES+HAWK_KGSEED_BYTES+44,t,x)==0);
for(unsigned i=0;i<2*HAWK_N;i++)printf("%d\\n",x[i]);
}
}return 0;}
''')
    sources=[ROOT/'05_software/src'/f'{s}.c' for s in ('hawk_params','shake256','regenerate','sampler_sign')]
    command=['C:/MINGW/bin/gcc.exe','-std=c99','-O2','-Wall','-Wextra','-I'+str(ROOT/'05_software/headers'),*map(str,sources),str(WORK/'test.c'),'-o',str(WORK/'test.exe')]
    p=subprocess.run(command,capture_output=True,text=True);(WORK/'compile.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr
    p=subprocess.run([str(WORK/'test.exe')],capture_output=True,text=True);(WORK/'test.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr
    lines=iter(p.stdout.splitlines())
    source=(ROOT/'05_software/src/hawk_params.c').read_text()
    header=(ROOT/'05_software/headers/hawk_params.h').read_text()
    for n,kglen in ((256,16),(512,24),(1024,40)):
        assert next(lines)==f'N {n}'
        for which in (0,1):
            body=re.search(rf'static const hawk_u80 t{which}_{n}\[\] = \{{(.*?)\}};',source,re.S)[1]
            actual=[(int(hi,16)<<64)|int(lo,16) for hi,lo in re.findall(r'HAWK_U80\(0x([0-9A-Fa-f]+), 0x([0-9A-Fa-f]+)ULL\)',body)]
            assert actual==reference[n][which],f'Runtime CDT differs from specification n={n}'
        # Fixed-parameter builds carry separate copies of the same CDT.
        fixed=header.split(f'HAWK_N == {n}\n')[1]
        for which in (0,1):
            body=re.search(rf'static const hawk_u80 HAWK_T{which}\[HAWK_SAMPLER_TABLE_LEN\] = \{{(.*?)\}};',fixed,re.S)[1]
            actual=[(int(hi,16)<<64)|int(lo,16) for hi,lo in re.findall(r'HAWK_U80\(0x([0-9A-Fa-f]+), 0x([0-9A-Fa-f]+)ULL\)',body)]
            assert actual==reference[n][which],f'Fixed CDT differs from specification n={n}'
        seed=bytes((17*i+11)&255 for i in range(148))
        b=n//64
        words=x4(seed[:kglen],(2*b*n//64)//4)
        stream=b''.join(v.to_bytes(8,'little') for v in words)
        fg=[sum((stream[(i*b+j)//8]>>((i*b+j)%8))&1 for j in range(b))-b//2 for i in range(2*n)]
        for i in range(n):assert list(map(int,next(lines).split()))==[fg[i],fg[n+i]],f'Regenerate mismatch n={n} i={i}'
        y=x4(seed[:64+kglen+44],5*n//8)
        for mode in range(3):
            t=bytes([0]*(n//4)) if mode==0 else bytes([255]*(n//4)) if mode==1 else bytes((i*29+7)&255 for i in range(n//4))
            expected=[None]*(2*n)
            for j in range(4):
                for i in range(n//8):
                    for k in range(4):
                        r=16*i+4*j+k;a=y[j+4*(5*i+k)]
                        bpart=(y[j+4*(5*i+4)]>>(16*k))&32767
                        c=(a&((1<<63)-1))+(bpart<<63)
                        bit=(t[r//8]>>(r%8))&1
                        value=2*sum(c<z for z in reference[n][bit])+bit
                        expected[r]=-value if a>>63 else value
            for i,value in enumerate(expected):assert int(next(lines))==value,f'Sampler mismatch n={n} mode={mode} i={i}'
        print(f'PASS n={n}: RegenerateFG, SHAKE256x4, spec CDT and all 3 parity patterns',flush=True)
    assert next(lines,None) is None


if __name__=='__main__':main()
