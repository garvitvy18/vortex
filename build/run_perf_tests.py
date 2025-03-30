import os
import subprocess
import csv
from datetime import datetime

# === Configuration ===
apps = ['vecadd', 'demo', 'sgemm', 'sfilter', 'saxpy', 'nearn']
perfs = [1, 2, 3]
input_sizes = ['-n16', '-n32', '-n64', '-n128']

output_dir = "vortex_perf_logs"
os.makedirs(output_dir, exist_ok=True)

def run_command(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout

def parse_output(perf_level, output):
    lines = output.splitlines()
    data = {}

    for line in lines:
        if line.startswith("PERF:") or line.startswith("DEBUG:"):
            if "Warp Efficiency" in line:
                data['warp_efficiency'] = line.split('=')[1].strip().replace('%', '')
            elif "instrs=" in line and "cycles=" in line and "IPC=" in line:
                try:
                    instr_info = line.split('PERF:')[-1].split(',')
                    for item in instr_info:
                        if '=' in item:
                            key, val = item.strip().split('=')
                            data[key.strip()] = val.strip()
                except Exception as e:
                    print("Warning: Could not parse instrs/cycles/IPC line:", line)
            elif ':' in line:
                try:
                    keyval = line.split(":", 1)[1].strip()
                    if '=' in keyval:
                        key, val = keyval.split('=', 1)
                        data[key.strip()] = val.strip()
                except Exception:
                    pass

    return data

def write_csv(perf_level, rows):
    if perf_level == 1:
        filename = "core_counters.csv"
    elif perf_level == 2:
        filename = "memory_counters.csv"
    else:
        filename = "warp_efficiency.csv"

    filepath = os.path.join(output_dir, filename)

    if rows:
        headers = list(rows[0].keys())
        with open(filepath, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)

def run_perf_tests():
    all_data = {1: [], 2: [], 3: []}

    for app in apps:
        for perf in perfs:
            for arg in input_sizes:
                print(f"Running: app={app}, perf={perf}, arg={arg}")
                cmd = f'./ci/blackbox.sh --cores=1 --app={app} --perf={perf} --driver=rtlsim --args="{arg}"'
                out = run_command(cmd)
                parsed = parse_output(perf, out)
                parsed['app'] = app
                parsed['perf'] = perf
                parsed['arg'] = arg
                parsed['timestamp'] = datetime.now().isoformat()
                all_data[perf].append(parsed)
                print(f"Completed: {app}, perf={perf}, arg={arg}")

    for perf_level, rows in all_data.items():
        write_csv(perf_level, rows)

if __name__ == "__main__":
    run_perf_tests()

