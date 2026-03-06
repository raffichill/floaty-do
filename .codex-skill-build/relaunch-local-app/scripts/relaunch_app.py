#!/usr/bin/env python3
import argparse
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Rebuild and relaunch a local app.")
    parser.add_argument("--workdir", default=".", help="Repository working directory.")
    parser.add_argument("--build-cmd", default="", help="Shell command to build the app before relaunch.")
    parser.add_argument("--launch-cmd", required=True, help="Shell command that launches the app.")
    parser.add_argument("--process-match", default="", help="Substring used to find the running process.")
    parser.add_argument("--log-path", default="", help="Optional log file for the relaunched app.")
    parser.add_argument("--delay", type=float, default=0.3, help="Seconds to wait after terminating the old process.")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without executing them.")
    return parser.parse_args()


def infer_process_match(launch_cmd: str) -> str:
    tokens = shlex.split(launch_cmd)
    if not tokens:
        raise ValueError("launch command is empty")
    return os.path.basename(tokens[0])


def run_shell(command: str, workdir: Path, dry_run: bool) -> None:
    print(f"$ {command}")
    if dry_run:
        return
    subprocess.run(["bash", "-lc", command], cwd=workdir, check=True)


def find_matching_pids(process_match: str) -> list[int]:
    ps_output = subprocess.run(
        ["ps", "-axo", "pid=,args="],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()

    pids: list[int] = []
    current_pid = os.getpid()
    parent_pid = os.getppid()

    for line in ps_output:
        stripped = line.strip()
        if not stripped:
            continue

        parts = stripped.split(maxsplit=1)
        if len(parts) != 2:
            continue

        pid = int(parts[0])
        args = parts[1]
        if pid in {current_pid, parent_pid}:
            continue
        if "relaunch_app.py" in args:
            continue
        if process_match not in args:
            continue
        pids.append(pid)

    return pids


def terminate_processes(pids: list[int], dry_run: bool) -> None:
    if not pids:
        print("No matching process found.")
        return

    print(f"Stopping process(es): {', '.join(str(pid) for pid in pids)}")
    if dry_run:
        return

    for pid in pids:
        os.kill(pid, signal.SIGTERM)


def launch_app(launch_cmd: str, workdir: Path, log_path: Path, dry_run: bool) -> None:
    print(f"Launching: {launch_cmd}")
    print(f"Log file: {log_path}")
    if dry_run:
        return

    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("ab") as log_file:
        subprocess.Popen(
            ["bash", "-lc", launch_cmd],
            cwd=workdir,
            stdout=log_file,
            stderr=log_file,
            start_new_session=True,
        )


def main() -> int:
    args = parse_args()
    workdir = Path(args.workdir).expanduser().resolve()
    if not workdir.exists():
        print(f"Working directory does not exist: {workdir}", file=sys.stderr)
        return 1

    process_match = args.process_match or infer_process_match(args.launch_cmd)
    safe_name = process_match.replace(os.sep, "_").replace(" ", "_")
    log_path = Path(args.log_path).expanduser().resolve() if args.log_path else Path(f"/tmp/{safe_name}.log")

    if args.build_cmd:
        run_shell(args.build_cmd, workdir, args.dry_run)

    pids = find_matching_pids(process_match)
    terminate_processes(pids, args.dry_run)

    if pids and not args.dry_run and args.delay > 0:
        time.sleep(args.delay)

    launch_app(args.launch_cmd, workdir, log_path, args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
