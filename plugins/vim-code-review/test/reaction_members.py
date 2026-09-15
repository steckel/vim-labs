from pathlib import Path
from vim_pty import run

for dimensions in [(80, 24), (120, 40)]:
    run(Path(__file__).with_suffix('.vim'), dimensions=dimensions)
print('reaction members: PASS (exact reply, unavailable accounts, anonymous reads, inert rows, exact return at 80/120 columns)')
