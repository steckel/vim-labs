from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('activity: PASS (durable outcomes, unread identity/navigation, refresh/focus, save-failure recovery)')
