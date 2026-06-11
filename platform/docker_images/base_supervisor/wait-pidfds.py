#!/usr/bin/env python3

import glob
import os
import select
import sys


def read_pidfile(path: str) -> int | None:
    try:
        with open(path, "r", encoding="ascii") as f:
            value = f.read().strip()
    except FileNotFoundError:
        return None

    if not value:
        return None

    try:
        return int(value)
    except ValueError:
        return None


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} PID_DIR", file=sys.stderr)
        return 2

    pid_dir = sys.argv[1]
    pidfiles = sorted(glob.glob(os.path.join(pid_dir, "*.pid")))

    if not pidfiles:
        print(f"error: no pidfiles found in {pid_dir}", file=sys.stderr)
        return 1

    poller = select.poll()
    pidfds: dict[int, tuple[int, str]] = {}

    for pidfile in pidfiles:
        pid = read_pidfile(pidfile)

        if pid is None:
            # Empty, missing, or malformed pidfile: treat as stopped.
            return 1

        try:
            pidfd = os.pidfd_open(pid, 0)
        except ProcessLookupError:
            # PID from pidfile is already gone.
            return 1
        except AttributeError:
            print(
                "error: Python does not support os.pidfd_open(); "
                "need Linux + Python 3.9+",
                file=sys.stderr,
            )
            return 2
        except PermissionError as e:
            print(
                f"error: permission denied opening pidfd for PID {pid} "
                f"from {pidfile}: {e}",
                file=sys.stderr,
            )
            return 2

        pidfds[pidfd] = (pid, pidfile)
        poller.register(pidfd, select.POLLIN | select.POLLHUP | select.POLLERR)

    try:
        # Kernel-blocking wait. No busy loop.
        events = poller.poll()

        for pidfd, _event in events:
            pid, pidfile = pidfds[pidfd]
            print(
                f"daemon process exited: pid={pid}, pidfile={pidfile}",
                file=sys.stderr,
            )

        return 1
    finally:
        for pidfd in pidfds:
            try:
                os.close(pidfd)
            except OSError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())