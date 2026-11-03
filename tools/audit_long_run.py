"""Stream the supplied decoded telemetry without expanding it to disk.

Usage: python tools/audit_long_run.py [input.jsonl.gz]
Outputs are derived statistics, not new hardware measurements.
"""
import collections
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'datasets/measured/long-run-72h-20261028-1031'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEST / 'parsed.jsonl.gz'
    kinds = collections.Counter()
    fields = collections.defaultdict(set)
    other = collections.defaultdict(lambda: {'count': 0, 'first': None, 'last': None, 'examples': []})
    counters = collections.Counter()
    indices = collections.Counter()
    hours = {}
    raw_hash = hashlib.sha256()
    raw_bytes = lines = blank = errors = 0
    first = last = previous_time = previous_index = None
    first_all = last_all = None
    max_gap = 0.0
    max_gap_pair = None
    gap_examples = []
    last_row = None
    with gzip.open(source, 'rb') as stream:
        for line in stream:
            lines += 1
            raw_hash.update(line)
            raw_bytes += len(line)
            if not line.strip():
                blank += 1
                continue
            try:
                row = json.loads(line)
                if not isinstance(row, dict):
                    raise ValueError('Expected object')
            except (ValueError, UnicodeError):
                errors += 1
                continue
            kind = row.get('kind', '(missing)')
            kinds[kind] += 1
            fields[kind].update(row)
            stamp = row.get('timestamp')
            if stamp:
                first_all = stamp if first_all is None else first_all
                last_all = stamp
            if kind != 'status':
                item = other[kind]
                item['count'] += 1
                if item['first'] is None:
                    item['first'] = row
                item['last'] = row
                if len(item['examples']) < 4:
                    item['examples'].append(row)
                continue
            try:
                t = datetime.fromisoformat(stamp)
            except (ValueError, TypeError):
                counters['invalid_status_timestamps'] += 1
                continue
            if first is None:
                first = t
            last = t
            delta = (t - previous_time).total_seconds() if previous_time else None
            if delta is not None:
                counters['backward_status_timestamps'] += delta < 0
                counters['duplicate_status_timestamps'] += delta == 0
                counters['status_gaps_gt_1s'] += delta > 1
                if delta > max_gap:
                    max_gap = delta
                    max_gap_pair = [previous_time.isoformat(), t.isoformat()]
                if delta > 1 and len(gap_examples) < 20:
                    gap_examples.append({'before': previous_time.isoformat(), 'after': t.isoformat(), 'seconds': delta})
            hour = int((t-first).total_seconds() // 3600)
            b = hours.setdefault(hour, collections.Counter())
            changed = previous_index is not None and previous_index != row.get('image_index')
            metrics = {
                'status_records': 1,
                'image_index_changes': int(changed),
                'audio_enabled_records': int(row.get('audio_enabled') is True),
                'auto_play_records': int(row.get('auto_play') is True),
                'fault_records': int(bool(row.get('storage_fault_active')) or bool(row.get('storage_fault_code'))),
                'missing_fault_fields': int('storage_fault_active' not in row or 'storage_fault_code' not in row),
                'missing_audio_field': int('audio_enabled' not in row),
                'missing_auto_play_field': int('auto_play' not in row),
            }
            counters.update(metrics)
            b.update(metrics)
            indices[str(row.get('image_index'))] += 1
            previous_time, previous_index, last_row = t, row.get('image_index'), row
            if kinds['status'] % 1000000 == 0:
                print(f"Scanned {kinds['status']:,} status records", flush=True)
    DEST.mkdir(parents=True, exist_ok=True)
    test_summary = json.loads((DEST / 'test-summary.json').read_text(encoding='utf-8'))
    source_hash = digest(source)
    summary_hash_matches = (source_hash == test_summary['capture_sha256'] and
                       test_summary['test_type'] == 'hardware_stability_test')
    assert summary_hash_matches, 'Capture differs from test summary'
    result = {
        'schema': 1,
        'evidence_type': 'reanalysis_of_long_run_decoded_telemetry',
        'source_original': '长稳72h_20261028-1031/parsed.jsonl.gz',
        'archived_path': 'datasets/measured/long-run-72h-20261028-1031/parsed.jsonl.gz',
        'provenance': '72-hour hardware stability test; archived decoded telemetry.',
        'new_board_test': False,
        'test_summary': 'test-summary.json',
        'compressed_bytes': source.stat().st_size,
        'compressed_sha256': source_hash,
        'uncompressed_bytes': raw_bytes,
        'uncompressed_sha256': raw_hash.hexdigest(),
        'gzip_integrity': 'passed (stream consumed to EOF)',
        'lines': lines, 'blank_lines': blank, 'json_errors': errors,
        'kinds': dict(kinds),
        'fields_by_kind': {k: sorted(v) for k, v in fields.items()},
        'first_record_timestamp': first_all, 'last_record_timestamp': last_all,
        'first_status_timestamp': first.isoformat() if first else None,
        'last_status_timestamp': last.isoformat() if last else None,
        'status_span_seconds': (last-first).total_seconds() if first else None,
        'statistics': dict(counters), 'image_index_records': dict(indices),
        'max_status_gap_seconds': max_gap, 'max_status_gap_endpoints': max_gap_pair,
        'status_gap_examples': gap_examples,
        'non_status_records': dict(other), 'last_status_record': last_row,
        'limitations': [
            'Decoded JSON only; cannot independently recheck serial frame checksums or packet loss.',
            'Host timestamp span is not proof of uninterrupted operation or continuous audiovisual quality.',
            'Test duration and archived file identities are listed in test-summary.json.',
            'Non-status events are retained as supplied claims, not independently repeated hardware tests.',
        ],
    }
    (DEST/'audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    hourly = {'source': 'parsed.jsonl.gz', 'source_sha256': result['compressed_sha256'],
              'evidence_type': 'derived_statistics',
              'bin_definition': 'floor((status_timestamp - first_status_timestamp) / 3600); no interpolation',
              'hours': [{'hour_from_first_sample': h, **b} for h,b in sorted(hours.items())]}
    (DEST/'per-hour.json').write_text(json.dumps(hourly, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in {'fields_by_kind','non_status_records','last_status_record'}}, ensure_ascii=False, indent=2))
    print('Non-status kinds: ' + ', '.join(other))


if __name__ == '__main__':
    main()
