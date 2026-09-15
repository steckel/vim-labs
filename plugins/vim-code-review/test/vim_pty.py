"""Exercise review interactions in a real Vim, using only a fixture."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import subprocess
import struct
import tempfile
import termios
import time


def run(script, repeat=1, forbidden=(), dimensions=None):
    with tempfile.TemporaryDirectory(prefix='revue-capabilities-') as directory:
        store = Path(directory)
        for _ in range(repeat):
            master, slave = pty.openpty()
            if dimensions is not None:
                # Configure the PTY itself: :set columns/lines alone can be
                # reset by Vim when switching tabs or processing terminal input.
                columns, lines = dimensions
                fcntl.ioctl(slave, termios.TIOCSWINSZ,
                            struct.pack('HHHH', lines, columns, 0, 0))
            layout = os.environ.get('REVUE_TEST_READING_LAYOUT', '')
            if layout not in ('', 'auto', 'split', 'tab'):
                raise ValueError('Unknown test reading layout')
            options = ['--cmd', 'let g:revue_reading_layout = ' + repr(layout)] if layout else []
            proc = subprocess.Popen(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n'] + options + ['-S',
                                     str(script)],
                                    stdin=slave, stdout=slave, stderr=slave,
                                    env=dict(os.environ, REVUE_CAP_STORE=directory, TERM='xterm'))
            os.close(slave)
            transcript = pending = b''
            deadline = time.monotonic() + 20
            try:
                while proc.poll() is None and time.monotonic() < deadline:
                    if not select.select([master], [], [], .1)[0]:
                        continue
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    transcript += chunk
                    pending += chunk
                    for prompt in forbidden:
                        if prompt in pending:
                            raise AssertionError('Unexpected interaction: ' + prompt.decode())
                    if b'(S)ave, [K]eep draft:' in pending or b'(S)end, [K]eep draft:' in pending or b'(S)ave privately, [K]eep draft:' in pending or b'(S)ave assignment, [K]eep draft:' in pending or b'(S)tart participant, [K]eep draft:' in pending or b'(S)tart prepared run, [K]eep draft:' in pending:
                        os.write(master, b's\r')
                        pending = b''
                    elif b'(R)esolve, [K]eep draft:' in pending or b'(R)eopen, [K]eep draft:' in pending or b'(R)esume participant, [K]eep draft:' in pending:
                        os.write(master, b'r\r')
                        pending = b''
                    elif b'(D)elete, [K]eep draft:' in pending or b'(D)iscard, [K]eep:' in pending:
                        os.write(master, b'd\r')
                        pending = b''
                    elif b'(C)ancel assignment, [K]eep draft:' in pending:
                        os.write(master, b'c\r')
                        pending = b''
                    elif b'(A)bandon prepared run, [K]eep draft:' in pending:
                        os.write(master, b'a\r')
                        pending = b''
                    elif b'(A)pply suggestion, [K]eep draft:' in pending:
                        os.write(master, b'a\r')
                        pending = b''
                    elif b'(A)ccept, [K]eep original base:' in pending:
                        os.write(master, b'a\r')
                        pending = b''
            finally:
                if proc.poll() is None:
                    proc.terminate()
                proc.wait(timeout=5)
                os.close(master)
            errors = (store / 'errors').read_text() if (store / 'errors').exists() else 'Vim did not finish'
            if proc.returncode or errors:
                raise SystemExit(errors + '\n' + transcript.decode('utf-8', 'replace')[-4000:])
