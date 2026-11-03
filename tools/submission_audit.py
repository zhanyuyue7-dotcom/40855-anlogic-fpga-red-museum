"""Audit the review folder, frozen hardware inputs, and historical raw telemetry."""
import csv
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
VERIFY=ROOT/'verification'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def save(name,value):
    (VERIFY/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def history():
    source=ROOT/'desktop/report_data/sources'
    audit=json.loads((source/'m5-two-hour-audit-20261003.json').read_text(encoding='utf-8-sig'))
    archive=source/'m5-two-hour-com8-20261003.jsonl.gz'
    assert sha(archive)==audit['compressed_sha256']
    h=hashlib.sha256(); size=0; count=0; changes=0; faults=0; audio=0
    first=last=None; previous=None; indices=set(); bins={}; summary=None
    with gzip.open(archive,'rb') as stream:
        for line in stream:
            h.update(line); size+=len(line); row=json.loads(line)
            if row['kind']=='summary': summary=row; continue
            if row['kind']!='status': continue
            count+=1; t=datetime.fromisoformat(row['timestamp'])
            if first is None: first=t
            last=t; minute=int((t-first).total_seconds()//60)
            b=bins.setdefault(minute,{'minute_from_first_sample':minute,'status_records':0,
                'image_index_changes':0,'fault_records':0,'audio_enabled_records':0})
            changed=previous is not None and previous!=row['image_index']
            changes+=changed; previous=row['image_index']; indices.add(previous)
            fault=bool(row['storage_fault_active']); enabled=bool(row['audio_enabled'])
            faults+=fault; audio+=enabled
            b['status_records']+=1; b['image_index_changes']+=changed
            b['fault_records']+=fault; b['audio_enabled_records']+=enabled
    assert h.hexdigest()==audit['raw_sha256'] and size==audit['raw_bytes']
    assert count==audit['kinds']['status']==143680
    assert changes==audit['index_changes']==2892
    assert faults==audit['fault_samples']==0
    assert audio==audit['audio_enabled_samples']['true']==58
    assert summary['invalid']==0
    span=(last-first).total_seconds()
    assert abs(span-audit['sample_span_seconds'])<1e-6
    dest=ROOT/'datasets/historical'; dest.mkdir(parents=True,exist_ok=True)
    with (dest/'m5-minute-summary.csv').open('w',encoding='utf-8-sig',newline='') as out:
        writer=csv.DictWriter(out,fieldnames=list(bins[0])); writer.writeheader(); writer.writerows(bins.values())
    save('historical-raw-recheck.json',{'result':'passed','evidence_type':'reanalysis_of_historical_measurements',
        'source':archive.relative_to(ROOT).as_posix(),'compressed_sha256':sha(archive),
        'raw_sha256':h.hexdigest(),'raw_bytes':size,'status_records':count,'summary':summary,
        'sample_span_seconds':span,'index_coverage':sorted(indices),'index_changes':changes,
        'fault_records':faults,'audio_enabled_records':audio,'audio_disabled_records':count-audio,
        'new_board_test':False,'version_scope':'historical M5, October 2026; NOT final November 2 bitstream',
        'limitations':['7198.516521 s observed span, not exactly 7200 s',
            'UART invalid=0 does not establish zero lost packets',
            'audio mostly disabled; not a continuous audio endurance test']})


def main():
    VERIFY.mkdir(exist_ok=True)
    history()
    # Supplemental capture capture is separate from the original 21 historical sessions.
    capture_dir=ROOT/'datasets/measured/long-run-72h-20261028-1031'
    capture=json.loads((capture_dir/'audit.json').read_text(encoding='utf-8'))
    assert sha(capture_dir/'parsed.jsonl.gz')==capture['compressed_sha256']
    assert (capture_dir/'parsed.jsonl.gz').stat().st_size==capture['compressed_bytes']
    assert capture['json_errors']==0 and capture['kinds']['status']==5184000
    assert sum(capture['kinds'].values())+capture['blank_lines']==capture['lines']
    assert capture['non_status_records']['summary']['last']['received']==capture['kinds']['status']
    hours=json.loads((capture_dir/'per-hour.json').read_text(encoding='utf-8'))
    assert hours['source_sha256']==capture['compressed_sha256']
    assert len(hours['hours'])==72
    for key in ('status_records','fault_records','image_index_changes','audio_enabled_records','auto_play_records'):
        assert sum(row[key] for row in hours['hours'])==capture['statistics'][key], key
    measured=ROOT/'datasets/measured'
    measured_manifest=json.loads((measured/'manifest.json').read_text(encoding='utf-8'))
    for name,meta in measured_manifest['files'].items():
        assert sha(measured/name)==meta['sha256'], name
        assert (measured/name).stat().st_size==meta['bytes'], name
    test_summary=json.loads((capture_dir/'test-summary.json').read_text(encoding='utf-8'))
    assert test_summary['capture_sha256']==capture['compressed_sha256']
    assert test_summary['submitted_bitstream_sha256']==sha(ROOT/'bitstream/integrated.bit')
    archive=json.loads((ROOT/'desktop/report_data/manifest.json').read_text(encoding='utf-8'))
    current=archive['traces'][0]
    assert current['id']=='final-72h' and current['records']==capture['kinds']['status']
    assert current['test_summary']==test_summary
    assert current['source_sha256']==capture['compressed_sha256']
    assert sum(b['records'] for b in current['minute_bins'])==current['records']
    assert sum(b['changes'] for b in current['minute_bins'])==capture['statistics']['image_index_changes']
    desktop_sync_log=(VERIFY/'desktop-72h-sync-tests.log').read_text(encoding='utf-8-sig')
    assert 'Ran 32 tests' in desktop_sync_log and re.search(r'^OK\s*$',desktop_sync_log,re.M)
    frozen=VERIFY/'frozen-build'
    inputs=json.loads((frozen/'inputs.json').read_text(encoding='utf-8-sig'))
    source_paths={name.replace('\\','/'):val for name,val in inputs.items()
                  if name.replace('\\','/').startswith('src/')}
    assert len(source_paths)>80, 'Frozen manifest must contain actual hardware inputs'
    for name,val in source_paths.items():
        assert sha(ROOT/name)==val, f'Frozen hardware mismatch: {name}'
    bit=ROOT/'bitstream/integrated.bit'
    assert sha(bit)=='625d0b2d7974b01f5d138eef0ae82afd547d5584011d1e3d4a1fb04416900b76'
    receipt=json.loads((frozen/'receipt.json').read_text(encoding='utf-8-sig'))
    for name,val in receipt['artifacts'].items():
        p=bit if name=='integrated.bit' else frozen/name
        if p.exists(): assert sha(p)==val, name
    project=ROOT/'src/td_project/HDMI1.4b_Transmitter_v1.0.al'
    paths=re.findall(r'<File Path="([^"]+)"',project.read_text(encoding='utf-8-sig'))
    assert paths and all((project.parent/p).is_file() for p in paths)
    log=(VERIFY/'submission-regression.log').read_text(encoding='utf-8-sig')
    assert len(re.findall(r'^PASS',log,re.M))==12
    assert 'Ran 30 tests' in log and re.search(r'^OK\s*$',log,re.M)
    assert '1226 packet scenarios, 614912 pixels checked, 1 display commits' in log
    cache=(VERIFY/'build-cache-tests.log').read_text(encoding='utf-8-sig')
    assert 'Ran 2 tests' in cache and re.search(r'^OK\s*$',cache,re.M)
    assert 'PASS: nonnegative' in (VERIFY/'timing-check.log').read_text(encoding='utf-8-sig')
    imported=json.loads((VERIFY/'import-manifest.json').read_text(encoding='utf-8'))
    changed=[row['path'] for row in imported['files'] if sha(ROOT/row['path'])!=row['source_sha256']]
    allowed={'tools/test-integration.ps1','tools/build.ps1','tools/td_build.py',
             'fpga_upload/tests/run_cosim.py','fpga_upload/README.md','fpga_upload/PROTOCOL.md',
             'desktop/README.md','desktop/DELIVERY.md','desktop/REPORT_GUIDE.md',
             'desktop/report_view.py','desktop/report_extensions.py','desktop/test_report.py','desktop/build_windows.py',
             'desktop/build_report_dataset.py','desktop/package_release.py',
             'desktop/report_data/manifest.json','desktop/report_data/测试用例与证据.csv',
             'verification/frozen-build/run.log'}
    assert set(changed)<=allowed, f'Unexpected copied-source change: {set(changed)-allowed}'
    v=list((ROOT/'src').rglob('*.v')); vhd=list((ROOT/'src').rglob('*.vhd'))
    save('submission-audit.json',{'result':'passed','checked_at':datetime.now().astimezone().isoformat(),
        'hardware_inputs_verified':len(source_paths),'td_project_references_resolved':len(paths),
        'verilog_files':len(v),'vhdl_files':len(vhd),'bitstream_bytes':bit.stat().st_size,
        'bitstream_sha256':sha(bit),'copied_files_changed':changed,
        'regression':{'rtl_suites':11,'hxfp_packet_scenarios':1226,'hxfp_pixel_writes':614912,
            'desktop_tests':30,'build_cache_tests':2},
        'new_td_build':False,'new_board_test':False,'archive_created':False,
        'desktop_archive_update':{'date':'2026-11-03','tests_passed':32,
            'test_log':'verification/desktop-72h-sync-tests.log',
            'replay_samples':len(current['samples']),'minute_bins':len(current['minute_bins']),
            'current_trace_id':current['id']},
        'long_run_capture':{'path':capture['archived_path'],
            'compressed_sha256':capture['compressed_sha256'],
            'status_records':capture['kinds']['status'],
            'status_span_seconds':capture['status_span_seconds'],
            'fault_records':capture['statistics']['fault_records'],
            'source_file_hash_verified':True,'hourly_totals_reconciled':True,
            'full_log_reanalysis_receipt':'datasets/measured/long-run-72h-20261028-1031/audit.json',
            'test_summary':'datasets/measured/long-run-72h-20261028-1031/test-summary.json',
            'desktop_archive_synchronized':True},
        'missing_acceptance':['independent physical Ethernet image transfer boundary-case verification'],
        'review_limit_bytes':200000000})
    # This manifest covers every deliverable except itself. It also records existing generated caches,
    # so the on-disk byte total cannot silently exclude large files.
    target=ROOT/'FILE_MANIFEST.csv'
    files=sorted(p for p in ROOT.rglob('*') if p.is_file() and p!=target
                 and '.git' not in p.relative_to(ROOT).parts)
    total=sum(p.stat().st_size for p in files)
    with target.open('w',encoding='utf-8-sig',newline='') as out:
        writer=csv.writer(out); writer.writerow(['relative_path','bytes','sha256'])
        for p in files: writer.writerow([p.relative_to(ROOT).as_posix(),p.stat().st_size,sha(p)])
    total+=target.stat().st_size
    assert total<200000000, f'Review folder exceeds conservative 200 MB limit: {total}'
    print(json.dumps({'result':'passed','files_including_manifest':len(files)+1,'total_bytes':total,
        'MiB':round(total/1048576,2),'hardware_inputs_verified':len(source_paths),
        'project_references':len(paths),'changed_copied_files':changed},ensure_ascii=False))


if __name__=='__main__': main()
