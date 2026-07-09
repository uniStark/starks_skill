#!/usr/bin/env python3
"""Run a reviewer command in its own process group with a hard timeout."""

from __future__ import annotations

import os
import signal
import subprocess
import sys


TIMEOUT_EXIT_CODE = 124


def terminate_group(process: subprocess.Popen[bytes], grace_seconds: float = 1.0) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=grace_seconds)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait()


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: run_with_timeout.py SECONDS COMMAND [ARG ...]", file=sys.stderr)
        return 2

    try:
        timeout_seconds = int(sys.argv[1])
    except ValueError:
        print("timeout must be a positive integer", file=sys.stderr)
        return 2
    if timeout_seconds <= 0:
        print("timeout must be a positive integer", file=sys.stderr)
        return 2

    process = subprocess.Popen(
        sys.argv[2:],
        stdin=sys.stdin.buffer,
        start_new_session=True,
    )

    def forward_signal(signum: int, _frame: object) -> None:
        terminate_group(process)
        raise SystemExit(128 + signum)

    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, forward_signal)

    try:
        return process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        terminate_group(process)
        return TIMEOUT_EXIT_CODE


if __name__ == "__main__":
    raise SystemExit(main())
