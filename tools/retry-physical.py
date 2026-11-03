"""Retry only physical packing using an exactly verified gate checkpoint."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from datetime import datetime
import msvcrt
import td_build as build

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('gate_run', type=Path)
ap.add_argument('--pack-mode', choices=['more_lut_pair', 'auto', 'lower_pin_density'], default='more_lut_pair')
args = ap.parse_args()
source_run = args.gate_run.resolve()
manifest = json.loads((source_run / 'inputs.json').read_text(encoding='utf-8'))
record = json.loads((source_run / 'receipt.json').read_text(encoding='utf-8'))
variant = manifest['options']['variant']
phys_opt = manifest['options']['phys_opt']
if build.inputs(build.ROOT, variant, phys_opt) != manifest:
    raise SystemExit('Inputs changed since gate run; refusing to reuse its netlist.')
if build.fingerprint(manifest) != record['input_hash'] or not build.valid_stage(source_run, record, 'gate'):
    raise SystemExit('Invalid gate receipt or gate artifacts; refusing retry.')
with (build.ROOT / 'diagnostics/td-build.lock').open('a+b') as lock:
    lock.seek(0)
    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    run = build.ROOT / 'build/physical-retries' / (datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+args.pack_mode)
    run.mkdir(parents=True)
    for name in ['gate.db', 'gate.area']:
        shutil.copy2(source_run / name, run / name)
    recipe = (build.ROOT / 'tools/build.tcl').read_text(encoding='utf-8')
    original = 'set_param place pack_mode adaptive_pin_density'
    if recipe.count(original) != 1:
        raise SystemExit('Unrecognized physical recipe; manual review required.')
    recipe = recipe.replace(original, f'set_param place pack_mode {args.pack_mode}')
    # The generated file lives in the run dir, so bind root explicitly.
    recipe = recipe.replace(recipe.splitlines()[0], 'set root {' + build.ROOT.as_posix() + '}')
    script = run / 'physical.tcl'
    script.write_text(recipe, encoding='utf-8')
    receipt = {'source_run': str(source_run), 'input_hash': record['input_hash'],
               'pack_mode': args.pack_mode, 'recipe_sha256': build.sha(script),
               'gate_sha256': build.sha(run / 'gate.db'), 'complete': False}
    build.save_json(run / 'receipt.json', receipt)
    build.save_json(run / 'inputs.json', manifest)
    env = os.environ.copy()
    env.update(MUSEUM_VARIANT=variant, MUSEUM_OUTPUT=run.as_posix(),
               MUSEUM_STOP='full', MUSEUM_RESUME='gate', MUSEUM_PHYS_OPT=str(int(phys_opt)))
    print(f'PHYSICAL_RUN={run}; verified gate reused; packing={args.pack_mode}', flush=True)
    start = time.perf_counter()
    with (run / 'build.log').open('w', encoding='utf-8') as out:
        result = subprocess.run([str(build.TD), script.as_posix()], cwd=run, env=env,
                                stdout=out, stderr=subprocess.STDOUT)
    content = (run / 'build.log').read_text(encoding='utf-8', errors='replace')
    unchanged = build.inputs(build.ROOT, variant, phys_opt) == manifest
    complete = unchanged and result.returncode == 0 and 'MUSEUM_BUILD_COMPLETE ' in content
    receipt.update(seconds=round(time.perf_counter()-start, 3), exit_code=result.returncode,
                   inputs_unchanged=unchanged, complete=complete)
    receipt['artifacts'] = {p.name: build.sha(p) for p in run.iterdir()
                             if p.suffix in {'.db', '.bit', '.area', '.rpt'}}
    build.save_json(run / 'receipt.json', receipt)
    build.save_json(build.ROOT / 'diagnostics/latest-build.json', {'run': str(run), **receipt})
    print(json.dumps(receipt, indent=2), flush=True)
    print('\n'.join(content.splitlines()[-20:]), flush=True)
    raise SystemExit(0 if complete else 1)
