"""Content-checked TD stage reuse. Physical effort and clock constraints are preserved."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
TD = Path(os.environ.get('MUSEUM_TD_EXE', 'D:/EDA/TD6.2.1/bin/td_commands_prompt.exe'))
INPUT_EXTENSIONS = {'.al', '.v', '.vh', '.sv', '.svh', '.vhd', '.vhdl', '.hex',
                    '.mem', '.mif', '.dat', '.bin', '.tcl', '.adc', '.sdc', '.ipc', '.xml', '.cwc'}


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inputs(root, variant, phys_opt):
    source = root / ('src' if variant == 'integrated' else 'baseline-src')
    files = sorted(p for p in source.rglob('*') if p.is_file() and p.suffix.lower() in INPUT_EXTENSIONS)
    files += [root / 'tools/build.tcl', root / 'tools/td_build.py', TD]
    manifest = {str(p.relative_to(root)) if p.is_relative_to(root) else str(p): sha(p) for p in files}
    manifest['options'] = {'variant': variant, 'phys_opt': phys_opt}
    return manifest


def fingerprint(manifest):
    return hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()


def valid_stage(run, record, stage):
    artifacts = record.get('stages', {}).get(stage, {})
    return bool(artifacts) and all((run / name).is_file() and sha(run / name) == digest
                                   for name, digest in artifacts.items())


def save_json(path, obj):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding='utf-8')
    tmp.replace(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--variant', choices=['baseline', 'integrated'], default='integrated')
    ap.add_argument('--stage', choices=['gate', 'place', 'route', 'full'], default='full')
    ap.add_argument('--clean', action='store_true', help='new isolated run; never delete old results')
    ap.add_argument('--phys-opt', action='store_true', help='extra optimizer that crashed on TD 6.2.1')
    args = ap.parse_args()
    diagnostics = ROOT / 'diagnostics'
    diagnostics.mkdir(exist_ok=True)
    import msvcrt
    # OS lock protects TD project files too; process exit releases the lock.
    with (diagnostics / 'td-build.lock').open('a+b') as lock:
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            raise SystemExit('Another managed TD build is active; no second writer started.')
        manifest = inputs(ROOT, args.variant, args.phys_opt)
        key = fingerprint(manifest)
        base = ROOT / 'build/runs'
        base.mkdir(parents=True, exist_ok=True)
        record, run = {}, None
        if not args.clean:
            for candidate in sorted(base.glob(key[:16] + '-*'), reverse=True):
                receipt = candidate / 'receipt.json'
                if not receipt.exists():
                    continue
                candidate_record = json.loads(receipt.read_text(encoding='utf-8'))
                if candidate_record.get('input_hash') == key:
                    run, record = candidate, candidate_record
                    break
        if run is None:
            run = base / (key[:16] + '-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
            run.mkdir()
            save_json(run / 'inputs.json', manifest)
            record = {'input_hash': key, 'stages': {}, 'attempts': []}
        print(f'RUN_DIRECTORY={run}', flush=True)
        target = 'complete' if args.stage == 'full' else args.stage
        if valid_stage(run, record, target):
            print(f'CACHE_HIT={target}; input and artifact SHA256 verified; no TD work repeated.', flush=True)
            save_json(diagnostics / 'latest-build.json', {'run': str(run), 'stage': target, 'cached': True})
            return 0
        resume = 'none'
        for stage in ['gate', 'place', 'route']:
            if valid_stage(run, record, stage):
                resume = stage
            else:
                break
            if stage == args.stage:
                break
        print(f'RESUME={resume}; STOP={args.stage}', flush=True)
        log = run / f'attempt-{len(record["attempts"])+1:02d}.log'
        env = os.environ.copy()
        env.update(MUSEUM_VARIANT=args.variant, MUSEUM_OUTPUT=run.as_posix(),
                   MUSEUM_STOP=args.stage, MUSEUM_RESUME=resume,
                   MUSEUM_PHYS_OPT=str(int(args.phys_opt)))
        start = time.perf_counter()
        with log.open('w', encoding='utf-8') as out:
            proc = subprocess.Popen([str(TD), (ROOT / 'tools/build.tcl').as_posix()],
                                    cwd=run, env=env, stdout=out, stderr=subprocess.STDOUT)
            last_tick = 0
            while proc.poll() is None:
                time.sleep(1)
                if 'HDL-5105' in log.read_text(encoding='utf-8', errors='replace'):
                    print('Missing ROM initialization file: stopping this owned TD process before physical work.', flush=True)
                    proc.terminate()
                    proc.wait(timeout=30)
                    break
                elapsed = time.perf_counter() - start
                if int(elapsed) // 30 > last_tick:
                    last_tick = int(elapsed) // 30
                    print(f'TD running {elapsed:.0f}s; log={log.name}', flush=True)
        duration = round(time.perf_counter() - start, 3)
        content = log.read_text(encoding='utf-8', errors='replace')
        unchanged = inputs(ROOT, args.variant, args.phys_opt) == manifest
        if unchanged:
            for stage in re.findall(r'^MUSEUM_CHECKPOINT (\w+)\s*$', content, re.M):
                names = [f'{stage}.db'] + (['gate.area'] if stage == 'gate' else [])
                if all((run / name).is_file() for name in names):
                    record['stages'][stage] = {name: sha(run / name) for name in names}
        metrics = {}
        status = run / 'timing_status.rpt'
        if status.exists():
            metrics = {k: float(v) for k, v in re.findall(r'(SWNS|STNS|HWNS|HTNS): ([+-]?[0-9.]+)ns', status.read_text())}
        initialization_ok = 'HDL-5105' not in content
        complete = proc.returncode == 0 and 'MUSEUM_BUILD_COMPLETE ' in content and unchanged and initialization_ok
        if complete:
            names = [f'{args.variant}.bit', 'final.db', 'route.area', 'timing_status.rpt', 'timing_summary.rpt']
            record['stages']['complete'] = {name: sha(run / name) for name in names}
        command_seconds = {name: float(seconds) for name, seconds in re.findall(
            r'finish command "([^"]+)" in\s+([0-9.]+)s wall', content)}
        attempt = {'log': log.name, 'seconds': duration, 'exit_code': proc.returncode,
                   'resume': resume, 'requested_stage': args.stage, 'inputs_unchanged': unchanged,
                   'timing_ns': metrics, 'command_seconds': command_seconds, 'complete': complete}
        record['attempts'].append(attempt)
        save_json(run / 'receipt.json', record)
        save_json(diagnostics / 'latest-build.json', {'run': str(run), **attempt})
        print(json.dumps(attempt, indent=2), flush=True)
        print('\n'.join(content.splitlines()[-16:]), flush=True)
        if not unchanged:
            print('INPUTS CHANGED DURING BUILD: artifacts cannot be reused or downloaded.')
            return 2
        return 0 if proc.returncode == 0 and (complete or f'MUSEUM_STAGE_COMPLETE {args.stage}' in content) else 1


if __name__ == '__main__':
    raise SystemExit(main())
