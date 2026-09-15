from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix(".vim"), repeat=2)
print("batches: PASS (selection, preview, failure editing, restart receipt recovery)")
