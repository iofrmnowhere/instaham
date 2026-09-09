"""Generate onnxruntime.def from dumpbin /exports output, then run `lib` to produce
onnxruntime.lib. Phase 1 of docs/test-plan-phase/1-host-toolchain.md.

Usage (inside a vcvars64.bat shell, cwd = this directory):
    dumpbin /exports onnxruntime.dll > ort_exports.txt
    python make_ort_lib.py
    lib /def:onnxruntime.def /machine:x64 /out:onnxruntime.lib
"""
import re
import sys

names = []
with open("ort_exports.txt", "r", encoding="utf-8", errors="replace") as f:
    lines = f.readlines()

# dumpbin's export table rows look like:
#     ordinal hint RVA      name
#           1    0 00029600 OrtGetApiBase
row_re = re.compile(r"^\s*(\d+)\s+([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)\s+(\S+)\s*$")
in_table = False
for line in lines:
    if "ordinal hint RVA" in line:
        in_table = True
        continue
    if in_table:
        m = row_re.match(line)
        if m:
            names.append(m.group(4))
        elif line.strip() == "" and names:
            break

if not names:
    print("no export names parsed -- check ort_exports.txt format", file=sys.stderr)
    sys.exit(1)

with open("onnxruntime.def", "w", encoding="utf-8") as f:
    f.write("EXPORTS\n")
    for n in names:
        f.write(n + "\n")

print("parsed %d export(s): %s" % (len(names), ", ".join(names)))
if "OrtGetApiBase" not in names:
    print("WARNING: OrtGetApiBase not found -- onnx_runner.cpp needs this symbol", file=sys.stderr)
    sys.exit(1)
