#!/usr/bin/env python3
"""Compile a packaged editor project with spaces in engine, compiler and project paths.

Uses real Windows executables, on Windows or through --wine. No graphics required.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib


def link_or_copy(source, target):
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--beef', type=Path, required=True, help='BeefBuild.exe, with its installed toolchain')
    parser.add_argument('--wine', action='store_true')
    parser.add_argument('--work', type=Path, help='Keep all test files and logs in this new directory')
    args = parser.parse_args()
    work = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix='tessera-project-test-'))
    work.mkdir(parents=True, exist_ok=True)
    package = work / 'Tessera Hub' / 'Engine' / 'tessera' / 'Tessera-Windows'
    compiler = work / 'Compiler Tools' / 'beef'
    shutil.copytree(args.package.resolve(), package, copy_function=link_or_copy)
    shutil.copytree(args.beef.resolve().parent.parent, compiler, copy_function=link_or_copy)
    beef = compiler / 'bin' / args.beef.name
    project = work / 'Projects With Spaces' / 'OpenProjectSmoke'
    environment = dict(os.environ)

    def target(path):
        return 'Z:' + str(path).replace('/', '\\') if args.wine else str(path)

    environment['BEEFBUILD'] = target(beef)
    # Exercise engine discovery from the installed launcher, without a developer override.
    environment.pop('TESSERA_ROOT', None)
    launcher = (['wine'] if args.wine else []) + [str(package / 'Tessera.exe')]

    def run(arguments, name):
        result = subprocess.run(launcher + arguments, env=environment, text=True, capture_output=True, timeout=600)
        (work / (name + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            print(result.stdout + result.stderr)
            raise RuntimeError(f'{name} failed ({result.returncode}); evidence: {work}')

    run(['--create', target(project)], 'create')
    # A moved project remembers an engine from another computer. Opening must relocate it.
    settings = project / 'project.tessera'
    settings.write_text('\n'.join('engine = Z:/missing-engine' if line.startswith('engine =') else line
                                  for line in settings.read_text().splitlines()) + '\n')
    run(['--build-project', target(project)], 'compile')
    executable = project / 'build/Debug_Win64/OpenProjectSmoke/OpenProjectSmoke.exe'
    assert executable.read_bytes()[:2] == b'MZ', 'Project did not produce a Windows editor executable'
    flags = tomllib.loads((project / 'BeefProj.toml').read_text())['Configs']['Debug']['Win64']['OtherLinkFlags']
    assert '"' in flags and 'Tessera Hub' in flags, flags
    assert 'missing-engine' not in settings.read_text(), 'Moved project did not relocate its engine'
    # The existing executable is moved aside during rebuild. Verify the second build succeeds too.
    run(['--build-project', target(project)], 'rebuild')
    assert executable.is_file()
    print(f'PASS: packaged Windows project create, relocation, compile and rebuild with spaces; evidence: {work}')


if __name__ == '__main__':
    main()
