"""Embed deterministic algorithm-level vectors into hawk_verify_tb.vhd.

Uses the independent integer RebuildS0 model and direct root evaluation for
PolyQnorm. No simulation output is used to obtain expected results.
"""
import importlib.util
import json
from pathlib import Path
import random

HERE = Path(__file__).resolve().parent
N = 512


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def cases():
    def base(label):
        return dict(label=label, q00=[1]+[0]*(N-1), q01=[0]*N,
                    w1=[1]+[0]*(N-1), h0=[0]*N)

    result = [base('Impulso valido')]
    c = base('Rechazo temprano: q00 negativo'); c['q00'][0] = -1; result.append(c)
    c = base('Recuperacion: primer w1 no nulo en indice 511')
    c['w1'] = [0]*511+[2]; c['h0'] = [(i*7+i//3)%2 for i in range(N)]; result.append(c)
    c = base('Sym-break: w1 completamente cero'); c['w1'] = [0]*N; result.append(c)
    c = base('Sym-break: negativo antes de positivo')
    c['w1'] = [0]*N; c['w1'][17] = -1; c['w1'][18] = 2; result.append(c)
    c = base('Residuos P1 y P2 diferentes'); c['q00'][0] = 3; result.append(c)
    c = base('Residuos iguales pero no divisibles por n'); c['q00'][0] = 512; result.append(c)
    for total in (6688, 6689, 6690):
        c = base(f'Norma {total}: limite 6689')
        # 81^2 + 11^2 + 2^2 = 6686. Complete using unit coefficients.
        values = [81, 11, 2] + [1]*(total-6686)
        c['w1'] = values+[0]*(N-len(values)); result.append(c)
    c = base('Recuperacion: w1 denso con signos y h0 no uniforme')
    c['w1'] = [1 if i%3 else -1 for i in range(N)]; c['w1'][0] = 1
    c['h0'] = [(i*7+i//3)%2 for i in range(N)]; result.append(c)
    c = base('q00 no constante y q01 denso: oraculo completo')
    c['q00'][0] = 64
    c['q00'][1], c['q00'][511], c['q00'][7], c['q00'][505] = 3, -3, -2, 2
    rng = random.Random(20261018)
    c['q01'] = [rng.randint(-1000, 1000) for _ in range(N)]
    c['w1'] = [rng.randint(-250, 250) for _ in range(N)]; c['w1'][0] = 1
    c['h0'] = [(i*7+i//3)%2 for i in range(N)]; result.append(c)
    result.append(base('Recuperacion final tras caso complejo'))
    return result


def main():
    rebuild = module('rebuild_model', HERE.parent/'tb_rebuild_s0/generate_vectors.py')
    norm = module('norm_model', HERE.parent/'tb_polyqnorm/run_polyqnorm.py')
    vectors = cases()
    threshold = (8*N*10469**2)//2**26
    assert threshold == 6689
    for i, c in enumerate(vectors):
        if c['q00'][0] < 0:
            c.update(error=1, r1=None, r2=None)
        else:
            w0 = rebuild.rebuild(c['q00'], c['q01'], c['w1'], c['h0'])
            first = next((x for x in c['w1'] if x), 0)
            results = [norm.reference([[x%p for x in a] for a in
                       (c['q00'], c['q01'], w0, c['w1'])], p, g)
                       for p, g in ((2147473409, 3), (2147389441, 11))]
            (e1, r1), (e2, r2) = results
            error = int(first <= 0 or e1 or e2 or r1 != r2 or r1%N != 0 or r1//N > threshold)
            c.update(error=error, r1=r1, r2=r2)
        print(f'{i}: error={c["error"]}, r1={c["r1"]}, r2={c["r2"]}: {c["label"]}')
    assert [c['error'] for c in vectors[:11]] == [0,1,0,1,1,1,1,0,0,1,0]
    assert vectors[5]['r1'] != vectors[5]['r2']
    assert vectors[6]['r1'] == vectors[6]['r2'] == 1
    for i, total in zip((7,8,9), (6688,6689,6690)):
        assert vectors[i]['r1'] == vectors[i]['r2'] == N*total

    lines = ['    -- BEGIN GENERATED VECTORS',
             '    -- Regenerar con generate_vectors.py; no usa resultados del DUT.',
             f'    constant C_CASES : positive := {len(vectors)};',
             '    type vector_t is array (0 to 511) of integer;',
             '    type vectors_t is array (0 to C_CASES - 1) of vector_t;',
             '    type hashes_t is array (0 to C_CASES - 1) of std_logic_vector(511 downto 0);']
    for key in ('q00','q01','w1'):
        lines.append(f'    constant C_{key.upper()} : vectors_t := (')
        for i,c in enumerate(vectors):
            pairs = [f'{j} => {x}' for j,x in enumerate(c[key]) if x]
            lines.append(f'        {i} => (')
            for j in range(0,len(pairs),6):
                lines.append('            '+', '.join(pairs[j:j+6])+',')
            lines.append("            others => 0)"+(',' if i<len(vectors)-1 else ''))
        lines.append('    );')
    lines.append('    constant C_H0 : hashes_t := (')
    for i,c in enumerate(vectors):
        value = sum(x<<j for j,x in enumerate(c['h0']))
        lines.append(f'        {i} => x"{value:0128X}"'+(',' if i<len(vectors)-1 else ''))
    lines.append('    );')
    lines.append('    constant C_ERROR : std_logic_vector(0 to C_CASES - 1) := "'+''.join(str(c['error']) for c in vectors)+'";')
    lines += ['    function case_name(index : natural) return string is', '    begin', '        case index is']
    for i,c in enumerate(vectors):
        lines.append(f'            when {i} => return "{c["label"]}";')
    lines += ['            when others => return "Caso desconocido";', '        end case;',
              '    end function;', '    -- END GENERATED VECTORS']
    path = HERE/'hawk_verify_tb.vhd'
    text = path.read_text()
    a = text.index('    -- BEGIN GENERATED VECTORS')
    b = text.index('    -- END GENERATED VECTORS')+len('    -- END GENERATED VECTORS')
    path.write_text(text[:a]+'\n'.join(lines)+text[b:])
    (HERE/'expected_results.json').write_text(json.dumps([
        {k:c[k] for k in ('label','error','r1','r2')} for c in vectors], indent=2)+'\n')


if __name__ == '__main__':
    main()
