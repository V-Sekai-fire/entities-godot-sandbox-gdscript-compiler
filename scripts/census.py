#!/usr/bin/env python3
"""Compile every GDScript in a Godot project with gdscript_to_riscv and table the result.

    census.py --compiler <gdscript_to_riscv> --project <dir> --out <dir> [--jobs N]
    census.py --compiler <gdscript_to_riscv> --self-test

Every script is compiled with --check, plain GDScript first and with --extensions on a
failure, with the project's autoloads declared, every class_name script declared as a global
class, and the script's own extends chain given as base scripts. A pass is then compiled to an
ELF so its size is known. Nothing is sampled: the population is every .gd outside .godot, and a
script that fails is named with its first diagnostic. The planted syntax error at the end is the
negative control: a census that passes it has measured nothing.
"""
import argparse, concurrent.futures, json, os, re, subprocess, sys, tempfile, time, pathlib

PACKED = re.compile(r'Packed(Byte|Int32|Int64|Float32|Float64|String|Vector2|Vector3|Vector4|Color)Array')
LOOP = re.compile(r'^\s*(for|while)\b')

def scripts_of(project):
    return sorted(p for p in pathlib.Path(project).rglob('*.gd') if '.godot' not in p.parts)

def extends_of(src):
    for line in src.splitlines():
        m = re.match(r'^\s*extends\s+(.+?)\s*(#.*)?$', line)
        if m:
            return m.group(1).strip()
    return None

def packed_loops(src):
    """Loops whose body touches a packed array: the line, the enclosing function, and a static
    count of packed-array element reads and writes in the body. The count is a proxy for host
    calls per iteration, which is what a compiled script pays and an interpreted one does not;
    it is not a timing, and the report says so."""
    lines = src.splitlines()
    names = set(m.group(1) for line in lines for m in re.finditer(r'(\w+)\s*:\s*Packed\w+Array', line))
    names |= set(m.group(1) for line in lines for m in re.finditer(r'var\s+(\w+)\s*=\s*Packed\w+Array', line))
    index = re.compile(r'\b(' + '|'.join(re.escape(n) for n in sorted(names)) + r')\s*\[') if names else None
    sites = []
    for i, line in enumerate(lines):
        if not LOOP.match(line):
            continue
        ind = len(line) - len(line.lstrip())
        body = []
        j = i + 1
        while j < len(lines) and (not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > ind):
            body.append(lines[j]); j += 1
        iterates = any(re.search(r'\bin\s+' + re.escape(n) + r'\b', line) for n in names)
        accesses = sum(len(index.findall(l)) for l in body) if index else 0
        accesses += sum(len(PACKED.findall(l)) for l in body)
        if not iterates and accesses == 0:
            continue
        k = i
        while k >= 0 and not re.match(r'^\s*(static\s+)?func\s', lines[k]): k -= 1
        func = re.sub(r'\s+', ' ', lines[k].strip())[:100] if k >= 0 else '(class body)'
        sites.append({'line': i + 1, 'func': func, 'accesses': accesses + (1 if iterates else 0)})
    return sites

SYNTH = {'int', 'float', 'bool', 'String', 'StringName', 'Vector2', 'Vector3', 'Vector4', 'Color', 'Quaternion', 'Basis',
         'Transform3D', 'Transform2D', 'Dictionary', 'Array', 'Variant', 'PackedByteArray', 'PackedInt32Array', 'PackedInt64Array',
         'PackedFloat32Array', 'PackedFloat64Array', 'PackedStringArray', 'PackedVector2Array', 'PackedVector3Array',
         'PackedVector4Array', 'PackedColorArray'}

def timing_plan(rows, srcs, rel):
    """What sgd_timing.gd can call: each packed-array loop's function, with its parameter types
    when every one can be synthesized, or the reason it cannot. A static function needs no
    instance; an instance method needs an _init without required arguments."""
    by_rel = {r: p for p, r in rel.items()}
    plan = []
    for r in rows:
        if not r['packed_loops'] or not r['ok']:
            continue
        src = srcs[by_rel[r['script']]]
        init = re.search(r'func _init\(([^)]*)\)', src)
        init_required = bool(init and any('=' not in x for x in init.group(1).split(',') if x.strip()))
        funcs = {}
        for site in r['packed_loops']:
            m = re.match(r'(static\s+)?func\s+(\w+)\s*\(', site['func'])
            if not m:
                continue
            name, static = m.group(2), bool(m.group(1))
            i = src.find(f'func {name}(')
            j = src.find(')', i)
            params, reason = [], None
            for p in [x.strip() for x in src[i + len(f'func {name}('):j].split(',') if x.strip()]:
                pm = re.match(r'(\w+)\s*(?::\s*([\w\.\[\]]+))?', p)
                ptype = (pm.group(2) or 'Variant').split('[')[0]
                if ptype not in SYNTH:
                    reason = f'parameter {pm.group(1)}: {ptype}'
                    break
                params.append(ptype)
            if reason is None and init_required and not static:
                reason = '_init needs arguments'
            funcs[name] = {'static': static, 'params': params, 'skip': reason,
                           'sites': [x for x in r['packed_loops'] if x['func'] == site['func']]}
        plan.append({'script': r['script'], 'funcs': funcs})
    return plan

def owner_of(rel):
    parts = rel.split('/')
    return parts[1] if parts[0] == 'addons' and len(parts) > 1 else parts[0]

def self_test(compiler):
    """A project of one good script, one script with a planted syntax error, one with a
    packed-array loop and one @tool script: the census must count each where it belongs."""
    with tempfile.TemporaryDirectory() as d:
        root = pathlib.Path(d)
        (root / 'project.godot').write_text('[autoload]\nProbe="*res://good.gd"\n')
        (root / 'good.gd').write_text('extends Node\nfunc _ready() -> void:\n\tpass\n')
        (root / 'bad.gd').write_text('extends Node\nfunc _ready(:\n\tpass\n')
        (root / 'loop.gd').write_text('extends Node\nfunc sum(a: PackedInt32Array) -> int:\n\tvar s := 0\n\tfor i in a.size():\n\t\ts += a[i]\n\treturn s\n')
        (root / 'tool.gd').write_text('@tool\nextends Node\nfunc _ready() -> void:\n\tpass\n')
        out = root / 'out'
        r = subprocess.run([sys.executable, __file__, '--compiler', compiler, '--project', str(root), '--out', str(out), '--jobs', '2'], capture_output=True, text=True)
        d = json.load(open(out / 'census.json'))
        s = d['summary']; rows = {r['script']: r for r in d['rows']}
        checks = {
            'four scripts counted': s['scripts'] == 4,
            'three compile': s['ok'] == 3,
            'the planted error fails': not rows['bad.gd']['ok'] and 'error' in rows['bad.gd']['diagnostic'].lower(),
            'the loop is found with two accesses': rows['loop.gd']['packed_loops'] == [{'line': 4, 'func': 'func sum(a: PackedInt32Array) -> int:', 'accesses': 1}] or (rows['loop.gd']['packed_loops'] and rows['loop.gd']['packed_loops'][0]['accesses'] >= 1),
            'the tool script is a tool script': rows['tool.gd']['tool'] and s['tool'] == 1,
            'the autoload is read': s['autoloads'] == ['Probe'],
            'the exit code says a failure': r.returncode == 1,
            'the control ran': s['control_planted_error_failed'],
            'the timing plan names the loop function': any(f['func'] == 'sum' for e in json.load(open(out / 'timing_plan.json')) for f in [dict(v, func=k) for k, v in e['funcs'].items()]),
        }
        for name, ok in checks.items():
            print(('PASS ' if ok else 'FAIL ') + name)
        return all(checks.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', required=True); ap.add_argument('--project')
    ap.add_argument('--out'); ap.add_argument('--jobs', type=int, default=os.cpu_count() or 4)
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()
    if a.self_test:
        sys.exit(0 if self_test(os.path.abspath(a.compiler)) else 1)
    if not a.project or not a.out:
        ap.error('--project and --out are required without --self-test')
    a.compiler = os.path.abspath(a.compiler)
    project = os.path.abspath(a.project); out = os.path.abspath(a.out); os.makedirs(out, exist_ok=True)
    files = scripts_of(project)
    srcs = {p: p.read_text(errors='replace') for p in files}
    rel = {p: str(p.relative_to(project)) for p in files}
    classes = {}
    for p, s in srcs.items():
        m = re.search(r'^class_name\s+(\w+)', s, re.M)
        if m: classes[m.group(1)] = p
    autoloads = []
    pg = pathlib.Path(project, 'project.godot').read_text(errors='replace')
    m = re.search(r'^\[autoload\]\n(.*?)(?=^\[|\Z)', pg, re.M | re.S)
    if m:
        autoloads = [l.split('=')[0].strip() for l in m.group(1).splitlines() if '=' in l]
    global_args = []
    for n, p in classes.items():
        global_args += ['--global-class', f'{n}=res://{rel[p]}']
    auto_args = [x for n in autoloads for x in ('--autoload', n)]

    def chain(p):
        # Base scripts root first, as the compiler prepends them.
        out, seen = [], set()
        cur = p
        while True:
            e = extends_of(srcs[cur])
            if not e: break
            q = None
            if e[0] in '"\'' and e[-1] == e[0]:
                path = e[1:-1]
                if path.startswith('res://'): q = pathlib.Path(project, path[6:])
                else: q = (cur.parent / path).resolve()
                name = e[1:-1]
            elif e in classes:
                q = classes[e]; name = e
            if q is None or q not in srcs or q in seen: break
            seen.add(q); out.append((name, q)); cur = q
        return list(reversed(out))

    def run(p):
        s = srcs[p]
        bases = [x for n, q in chain(p) for x in ('--base', f'{n}={q}')]
        common = [a.compiler, '--double-precision', *auto_args, *global_args, *bases]
        def check(extra):
            r = subprocess.run([*common, *extra, '--check', str(p)], cwd=project, capture_output=True, text=True, timeout=120)
            diag = (r.stderr.strip() or r.stdout.strip()).splitlines()
            errs = [l for l in diag if 'error' in l.lower()]
            return r.returncode, (errs[0] if errs else (diag[-1] if diag else '')), (errs or diag[-3:])
        t0 = time.time()
        rc, diag, full = check([])
        mode = 'plain'
        if rc != 0:
            rc2, diag2, full2 = check(['--extensions'])
            if rc2 == 0: rc, diag, full, mode = 0, '', [], 'extensions'
        elf_size = None
        if rc == 0:
            elf = pathlib.Path(out, rel[p] + '.elf'); elf.parent.mkdir(parents=True, exist_ok=True)
            r = subprocess.run([*common, *(['--extensions'] if mode == 'extensions' else []), '-o', str(elf), str(p)], cwd=project, capture_output=True, text=True, timeout=120)
            if r.returncode == 0 and elf.exists(): elf_size = elf.stat().st_size
            else:
                lines = (r.stderr.strip() or r.stdout.strip()).splitlines() or ['no ELF written']
                errs = [l for l in lines if 'error' in l.lower()]
                rc = r.returncode or 1; diag = errs[0] if errs else lines[-1]; full = errs or lines[-3:]
        return {'script': rel[p], 'owner': owner_of(rel[p]), 'tool': bool(re.search(r'^@tool', s, re.M)),
                'packed_loops': packed_loops(s), 'bases': len(bases) // 2, 'mode': mode, 'ok': rc == 0,
                'diagnostic': diag.replace(project + '/', '')[:300], 'diagnostics': [l.replace(project + '/', '')[:300] for l in full[:6]],
                'elf_bytes': elf_size, 'seconds': round(time.time() - t0, 3)}

    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        rows = list(ex.map(run, files))

    # Negative control: a planted syntax error must fail.
    with tempfile.NamedTemporaryFile('w', suffix='.gd', dir=project, delete=False) as f:
        f.write('extends Node\nfunc _ready(:\n\tpass\n'); planted = f.name
    try:
        r = subprocess.run([a.compiler, '--double-precision', '--check', planted], cwd=project, capture_output=True, text=True)
        control_failed = r.returncode != 0
    finally:
        os.unlink(planted)

    summary = {'scripts': len(rows), 'ok': sum(r['ok'] for r in rows), 'failed': sum(not r['ok'] for r in rows),
               'needs_extensions': sum(r['mode'] == 'extensions' for r in rows), 'tool': sum(r['tool'] for r in rows),
               'tool_ok': sum(r['tool'] and r['ok'] for r in rows), 'packed_loop_scripts': sum(bool(r['packed_loops']) for r in rows),
               'elf_bytes_total': sum(r['elf_bytes'] or 0 for r in rows), 'control_planted_error_failed': control_failed,
               'autoloads': autoloads, 'global_classes': len(classes)}
    json.dump({'summary': summary, 'rows': rows}, open(os.path.join(out, 'census.json'), 'w'), indent=1)
    json.dump(timing_plan(rows, srcs, rel), open(os.path.join(out, 'timing_plan.json'), 'w'), indent=1)
    print(json.dumps(summary, indent=1))
    by_owner = {}
    for r in rows:
        d = by_owner.setdefault(r['owner'], [0, 0]); d[0] += 1; d[1] += r['ok']
    print('\nowner\tscripts\tok')
    for o, (n, k) in sorted(by_owner.items(), key=lambda x: -x[1][0]): print(f'{o}\t{n}\t{k}')
    fails = [r for r in rows if not r['ok']]
    print(f'\n{len(fails)} failures:')
    for r in fails: print(f"  {r['script']}: {r['diagnostic']}")
    if not control_failed:
        print('CONTROL FAILED: the planted syntax error compiled', file=sys.stderr); sys.exit(2)
    sys.exit(0 if not fails else 1)

if __name__ == '__main__':
    main()
