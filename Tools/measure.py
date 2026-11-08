#!/usr/bin/env python3
"""Measure a built, blank screeny window. Run from the project folder in a desktop session."""
import json
import pathlib
import re
import statistics
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
binary = root / 'build/screeny.app/Contents/MacOS/screeny'
measurements = []
for index in range(5):
    start = time.perf_counter()
    process = subprocess.Popen([str(binary), '--measure-launch'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        line = process.stdout.readline().strip()
        ready_ms = (time.perf_counter() - start) * 1000
        if not line.startswith('window-ready-ms '):
            raise RuntimeError('screeny did not report a ready window')
        time.sleep(1)
        rss = int(subprocess.check_output(['ps', '-o', 'rss=', '-p', str(process.pid)], text=True).strip()) * 1024
        row = {'process_to_window_ms': round(ready_ms, 2), 'delegate_to_window_ms': float(line.split()[-1]), 'idle_rss_bytes': rss}
        if index == 4:
            sample_path = root / 'build/idle-sample.txt'
            subprocess.run(['sample', str(process.pid), '1', '-file', str(sample_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            match = re.search(r'^Physical footprint:\s+(.+)$', sample_path.read_text(), re.M)
            row['physical_footprint'] = match.group(1).strip() if match else 'unavailable'
        measurements.append(row)
    finally:
        process.terminate()
        process.wait(timeout=5)
result = {'runs': measurements, 'median_launch_ms': round(statistics.median(x['process_to_window_ms'] for x in measurements), 2), 'median_idle_rss_mib': round(statistics.median(x['idle_rss_bytes'] for x in measurements) / 1048576, 2), 'release_bytes': sum(p.stat().st_size for p in (root / 'build/screeny.app').rglob('*') if p.is_file()), 'swift_source_lines': sum(len(p.read_text().splitlines()) for p in (root / 'Sources').glob('*.swift'))}
(root / 'build/measurements.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
