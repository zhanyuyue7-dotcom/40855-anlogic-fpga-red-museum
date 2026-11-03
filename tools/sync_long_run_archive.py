"""Rebuild the desktop's current archive from the supplied 72-hour capture."""
import csv
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / 'datasets/measured/long-run-72h-20261028-1031'
DATA = ROOT / 'desktop/report_data'


def main():
    audit = json.loads((CAPTURE / 'audit.json').read_text(encoding='utf-8'))
    test_summary = json.loads((CAPTURE / 'test-summary.json').read_text(encoding='utf-8'))
    source = CAPTURE / 'parsed.jsonl.gz'
    with source.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').hexdigest() == audit['compressed_sha256']
    samples, bins = [], {}
    count = changes = faults = 0
    previous = first = last = None
    digest = hashlib.sha256()
    stride = 3600
    with gzip.open(source, 'rb') as stream:
        for line in stream:
            digest.update(line)
            row = json.loads(line)
            if row.get('kind') != 'status':
                continue
            count += 1
            timestamp = datetime.fromisoformat(row['timestamp'])
            if first is None:
                first = timestamp
            minute = int((timestamp - first).total_seconds() // 60)
            bucket = bins.setdefault(minute, {'minute': minute, 'changes': 0, 'records': 0})
            changed = previous is not None and previous != row['image_index']
            previous = row['image_index']
            bucket['changes'] += int(changed)
            bucket['records'] += 1
            changes += int(changed)
            faults += int(bool(row.get('storage_fault_active')) or bool(row.get('storage_fault_code')))
            last = dict(row, record_number=count)
            if (count - 1) % stride == 0:
                samples.append(last)
            if count % 1000000 == 0:
                print(f'Scanned {count:,} status records', flush=True)
    if samples[-1]['record_number'] != count:
        samples.append(last)
    assert digest.hexdigest() == audit['uncompressed_sha256']
    assert count == audit['kinds']['status']
    assert changes == audit['statistics']['image_index_changes']
    assert faults == audit['statistics']['fault_records']
    note = '72小时长稳测试。音频和自动轮播并非全程开启。'
    trace = dict(id='final-72h', label='最终版本 · 72小时长稳', note=note,
                 source='../../datasets/measured/long-run-72h-20261028-1031/parsed.jsonl.gz',
                 repository_source=source.relative_to(ROOT).as_posix(),
                 source_sha256=audit['compressed_sha256'], raw_sha256=audit['uncompressed_sha256'],
                 records=count, fault_rows=faults, index_changes=changes,
                 first=audit['first_status_timestamp'], last=audit['last_status_timestamp'],
                 span_seconds=audit['status_span_seconds'],
                 summary=audit['non_status_records']['summary']['last'],
                 display_stride=stride, samples=samples, minute_bins=list(bins.values()),
                 test_summary=test_summary)
    manifest = json.loads((DATA / 'manifest.json').read_text(encoding='utf-8'))
    manifest['traces'] = [trace] + [t for t in manifest['traces'] if t.get('id') != 'final-72h']
    manifest['assembled_date'] = '2026-11-03'
    manifest['current_long_run'] = {'trace_id': 'final-72h', 'test_summary': test_summary,
                                    'audit': 'datasets/measured/long-run-72h-20261028-1031/audit.json'}
    cases = {c['id']: c for c in manifest['cases']}
    for key in ['T01', 'T02', 'T03', 'T04']:
        cases[key]['source'] = trace['repository_source']
    cases['T01'].update(title='最终版本约72小时运行', result='5,184,000 条 / 259,196.911649 s', scope=note)
    cases['T02'].update(title='长稳日志完整性', method='完整 gzip / JSON / SHA-256 复核；读取串口摘要',
                        result='JSON错误=0；摘要自报 invalid=0', scope='解码日志完整性；未附UART字节，不据此推断物理丢包率')
    cases['T03'].update(result='索引0/1/2/3；57,937次变化', scope='72小时窗口中的相邻索引变化，不代表人工按键次数')
    cases['T04'].update(method='统计故障激活标志或非零故障码', result='故障记录 0；字段缺失 0', scope='覆盖本次72小时状态日志')
    cases['T19'].update(title='真实网络整图上传专项复核', result='已有上传日志；专项独立复核待补',
                        source='datasets/measured/long-run-72h-20261028-1031/README.md',
                        scope='最终版本72小时长稳已完成；网络各边界场景不由长稳时长自动推导')
    for key in ['T40', 'T41', 'T42']:
        cases[key]['title'] = '历史容量计划 · ' + cases[key]['title'].removeprefix('历史容量计划 · ')
        cases[key]['result'] = cases[key]['result'].replace('待执行', '原计划快照')
        cases[key]['scope'] = '历史组合场景预算；当前72小时实测见T01，未逐项核对的组合场景继续保留计划属性'
    (DATA / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    with (DATA / '测试用例与证据.csv').open('w', newline='', encoding='utf-8-sig') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(manifest['cases'][0]))
        writer.writeheader()
        writer.writerows(manifest['cases'])
    print(json.dumps({'status_records': count, 'replay_samples': len(samples), 'minute_bins': len(bins),
                      'index_changes': changes, 'fault_records': faults, 'raw_sha256_verified': True}))


if __name__ == '__main__':
    main()
