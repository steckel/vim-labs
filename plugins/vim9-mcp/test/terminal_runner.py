"""Give integration-test Vim a real terminal; relay stdin/stdout without dependencies."""
import os
import pty
import select
import signal
import sys

pid, master = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])

def stop(*_):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    while True:
        ready, _, _ = select.select([master, sys.stdin.fileno()], [], [])
        if master in ready:
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            os.write(sys.stdout.fileno(), data)
        if sys.stdin.fileno() in ready:
            data = os.read(sys.stdin.fileno(), 65536)
            if not data:
                stop()
                break
            os.write(master, data)
finally:
    os.close(master)
    _, status = os.waitpid(pid, 0)
    sys.exit(os.waitstatus_to_exitcode(status))
