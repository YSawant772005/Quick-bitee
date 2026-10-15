import subprocess

cmd = [
    ".venv/Scripts/python",
    "-m",
    "pytest",
    "tests",
    "-q",
    "--asyncio-mode=auto",
    "--no-header",
    "-p",
    "no:warnings",
]
result = subprocess.run(cmd, capture_output=True, text=True)
with open("test_out19.log", "w", encoding="utf-8") as f:
    f.write(result.stdout)
with open("test_err19.log", "w", encoding="utf-8") as f:
    f.write(result.stderr)
print("RC=", result.returncode)
print(result.stdout[:15000])