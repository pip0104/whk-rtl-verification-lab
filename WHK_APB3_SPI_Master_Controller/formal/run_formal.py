#!/usr/bin/env python3
"""Run scoped SPI formal checks; baseline FAIL is required, not ignored."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
SPI = HERE.parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output = (args.output_dir or SPI / 'results' / 'formal' / stamp).resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = {'utc': stamp, 'configuration': {'ADDR_WIDTH': 32, 'DATA_WIDTH': 32},
                'scope': 'scoped safety properties, not complete SPI correctness or liveness',
                'sources': {}, 'tools': {}, 'tasks': [], 'passed': False, 'property_counts': {'reset': 6, 'config': 4, 'timing': 6, 'rx': 2, 'cover': 3}}
    inputs = [SPI / 'rtl/apb3_spi_master.sv', HERE / 'spi_formal.sv',
              HERE / 'spi_properties.svh', HERE / 'spi.sby', HERE / 'baseline.sby',
              HERE / 'baseline_apb3_spi_master.sv', Path(__file__).resolve()]
    for path in inputs:
        manifest['sources'][str(path.relative_to(SPI))] = sha(path)
    manifest_path = output / 'manifest.json'
    try:
        for tool, flag in [('yosys', '-V'), ('sby', '--version'), ('boolector', '--version')]:
            exe = shutil.which(tool)
            if not exe:
                raise RuntimeError(f'{tool} missing from PATH; initialize OSS CAD Suite first')
            probe = subprocess.run([exe, flag], capture_output=True, cwd=HERE, timeout=15)
            manifest['tools'][tool] = (probe.stdout + probe.stderr).decode('utf-8', 'replace').strip()
            if probe.returncode:
                raise RuntimeError(f'{tool} version probe failed')
        sby = shutil.which('sby')
        jobs = [('baseline', 'baseline.sby', None, 'FAIL')]
        jobs += [(task, 'spi.sby', task, 'PASS') for task in ['reset','config','timing','rx','cover']]
        for name, config, task, expected in jobs:
            work = output / name
            command = [sby, '-f', '-d', os.path.relpath(work, HERE), config] + ([task] if task else [])
            started = time.monotonic()
            child_env = os.environ.copy()
            child_env['PYTHONIOENCODING'] = 'utf-8'
            completed = subprocess.run(command, cwd=HERE, capture_output=True, timeout=150, env=child_env)
            (output / f'{name}.console.log').write_bytes(completed.stdout + completed.stderr)
            status_file = work / 'status'
            status = status_file.read_text().split()[0] if status_file.exists() else 'MISSING'
            log = (work / 'logfile.txt').read_text(errors='replace') if (work / 'logfile.txt').exists() else ''
            checks = status == expected
            if name == 'baseline':
                checks = checks and completed.returncode != 0 and (work / 'engine_0/trace.vcd').exists()
                checks = checks and 'count_bound' in log and 'edge_due' in log
            else:
                checks = checks and completed.returncode == 0
            if name == 'cover':
                reached = re.findall(r'reached cover statement.*?\.(cover_\w+).*?step (\d+)', log)
                checks = checks and len({label for label, _ in reached}) == 3
            else:
                reached = []
            record = {'name': name, 'mode': 'bmc' if name == 'baseline' else ('cover' if name == 'cover' else 'prove'),
                      'expected': expected, 'status': status, 'returncode': completed.returncode,
                      'elapsed_seconds': round(time.monotonic()-started, 3), 'checked': checks,
                      'command': command, 'cwd': str(HERE), 'cover_reached': reached}
            manifest['tasks'].append(record)
            manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
            print(f'{name}: {status} (expected {expected}; checked={checks})', flush=True)
            if not checks:
                raise RuntimeError(f'{name} did not meet its required evidence gate; see {work}')
        for path in inputs:
            if manifest['sources'][str(path.relative_to(SPI))] != sha(path):
                raise RuntimeError(f'source changed during execution: {path}')
        manifest['passed'] = True
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        manifest['error'] = str(exc)
        print(str(exc), file=sys.stderr)
    finally:
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        (SPI / 'results' / 'formal').mkdir(parents=True, exist_ok=True)
        (SPI / 'results' / 'formal' / 'latest.json').write_text(json.dumps({'manifest': str(manifest_path), 'passed': manifest['passed']}, indent=2), encoding='utf-8')
        print(f'Manifest: {manifest_path}', flush=True)
    return 0 if manifest['passed'] else 1

if __name__ == '__main__':
    sys.exit(main())
