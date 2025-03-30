import os
import subprocess
import csv
from datetime import datetime
import re

# --- CONFIGURATION ---
apps = ['vecadd', 'demo', 'sgemm', 'sfilter', 'saxpy', 'nearn']
perfs = [1, 2, 3]
input_sizes = ['-n16', '-n32', '-n64', '-n128']
output_csv = "vortex_master_perf.csv"

# --- SETUP ---
os.chdir("/home/gv2361/vortex/build")
subprocess.run("source ./ci/toolchain_env.sh", shell=True, executable="/bin/bash")

def run_test(app, perf, arg):
    cmd = f'./ci/blackbox.sh --cores=1 --app={app} --perf={perf} --driver=rtlsim --args="{arg}"'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, executable="/bin/bash")
    return result.stdout

def extract_perf_metrics(output):
    timestamp = datetime.now().isoformat()
    lines = output.splitlines()
    row = {}

    for line in lines:
        if line.startswith("PERF:") or line.startswith("DEBUG:") or "Warp Efficiency" in line:
            keyval = line.replace("PERF:", "").replace("DEBUG:", "").strip()
            if ":" in keyval:
                key, val = keyval.split(":", 1)
                row[key.strip()] = val.strip()
            elif "=" in keyval:
                key, val = keyval.split("=", 1)
                row[key.strip()] = val.strip()
            else:
                row[keyval.strip()] = ""
    
    row["Timestamp"] = timestamp
    return row

def save_to_master_csv(app, perf, arg, perf_data):
    file_exists = os.path.exists(output_csv)
    with open(output_csv, "a", newline="") as f:
        writer = csv.writer(f)
        # Write header if new file
        if not file_exists:
            headers = ["App", "Perf", "Arg", "Timestamp"] + list(perf_data.keys())
            writer.writerow(headers)
        row = [app, perf, arg, perf_data.get("Timestamp", "")] + list(perf_data.values())
        writer.writerow(row)

# --- MAIN ---
for app in apps:
    for perf in perfs:
        for arg in input_sizes:
            print(f"Running {app} perf={perf} arg={arg}")
            output = run_test(app, perf, arg)
            perf_data = extract_perf_metrics(output)
            save_to_master_csv(app, perf, arg, perf_data)

print(f"\n✅ All results saved to: {output_csv}")

