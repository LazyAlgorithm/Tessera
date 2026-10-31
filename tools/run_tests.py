#!/usr/bin/env python3
"""Build and run the engine's headless test fixtures (the BeefBuild -run list in Tests/README.md) and report each.

    python3 tools/run_tests.py                     every fixture in the list, for this machine
    python3 tools/run_tests.py Quality Culling     only these
    python3 tools/run_tests.py --platform macos    name the Beef platform (linux, macos, windows)

Exits non-zero if any fixture fails to build or reports a FAIL.
"""
import argparse
import os
from pathlib import Path
import platform as host
import re
import subprocess
import sys
import time
import tomllib

PLATFORMS = {'linux': 'Linux64', 'macos': 'macOS', 'windows': 'Win64'}


def listed(root):
    """The fixtures Tests/README.md lists for BeefBuild -run."""
    for line in (root / 'Tests/README.md').read_text().splitlines():
        if line.startswith('For ') and line.rstrip().endswith(':'):
            names = line[4:].split(':')[0]
            names = re.sub(r'\([^)]*\)', '', names).replace(' and ', ', ')
            return [name.strip() for name in names.split(',') if name.strip()]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('names', nargs='*')
    default = 'macos' if sys.platform == 'darwin' else 'windows' if os.name == 'nt' else 'linux'
    parser.add_argument('--platform', choices=PLATFORMS, default=default)
    parser.add_argument('--skip', nargs='*', default=[], help='fixtures to leave out')
    parser.add_argument('--timeout', type=int, default=1800)
    parser.add_argument('--retries', type=int, default=0,
                        help='run a failed fixture again up to this many times (the networking fixtures run in real time over loopback and can miss on a busy machine); it is listed as passing on a retry')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    names = args.names or listed(root)
    beef = os.environ.get('BEEFBUILD', 'BeefBuild')
    failed, flaky = [], []
    for name in names:
        if name in args.skip:
            print(f'SKIP {name}', flush=True)
            continue
        folder = root / 'Tests' / name
        if not (folder / 'BeefProj.toml').is_file():
            print(f'MISSING {name}', flush=True)
            failed.append(name)
            continue
        good, retried = False, 0
        while not good and retried <= args.retries:
            if retried:
                print(f'  again: {name} (try {retried + 1})', flush=True)
            good = run_one(beef, folder, name, args)
            retried += 1
        if not good:
            failed.append(name)
        elif retried > 1:
            flaky.append(name)
    print(f'\n{len(names) - len(failed) - len(args.skip)} passed, {len(failed)} failed' + (f': {", ".join(failed)}' if failed else '')
          + (f'; passed on a retry: {", ".join(flaky)}' if flaky else ''))
    return 1 if failed else 0


def run_one(beef, folder, name, args):
    started = time.time()
    try:
        built = subprocess.run([beef, '-config=Debug', f'-platform={PLATFORMS[args.platform]}'], cwd=folder,
                               capture_output=True, text=True, errors='replace', timeout=args.timeout)
        output = built.stdout + built.stderr
        code = built.returncode
        if code == 0:
            # BeefBuild -run cannot launch executables beneath paths containing spaces on some compiler versions.
            # Spawn the compiled fixture directly, preserving the workspace working directory.
            project = tomllib.loads((folder / 'BeefProj.toml').read_text())['Project']['Name']
            executable = folder / f'build/Debug_{PLATFORMS[args.platform]}/{project}' / (project + ('.exe' if args.platform == 'windows' else ''))
            run = subprocess.run([str(executable)], cwd=folder, capture_output=True, text=True,
                                 errors='replace', timeout=args.timeout)
            output += run.stdout + run.stderr
            code = run.returncode
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b'').decode(errors='replace') if isinstance(error.stdout, bytes) else (error.stdout or '')
        code = 'timeout'
    # A fixture's failed checks, and the compiler's errors (a passing check may quote an error message).
    fails = [line for line in output.splitlines() if line.startswith('FAIL') or line.startswith('ERROR')]
    good = code == 0 and not fails
    print(f'{"PASS" if good else "FAIL"} {name} ({time.time() - started:.0f}s, exit {code})', flush=True)
    if not good:
        print('\n'.join('    ' + line for line in (fails or output.splitlines())[-25:]), flush=True)
    return good


if __name__ == '__main__':
    sys.exit(main())
