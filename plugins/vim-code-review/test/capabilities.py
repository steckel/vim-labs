from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix(".vim"))
print("capabilities: PASS (read-only, actor changes, optional body, receipt recovery)")
