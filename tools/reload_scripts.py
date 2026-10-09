#!/usr/bin/env python3
"""Compile a private game-code library against the running Linux debug host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import struct
import tomllib
import time

TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|=>|[A-Za-z_][A-Za-z_0-9]*|[^\s]', re.S)


def schema(text):
    """Conservatively keep declarations and discard only method/accessor bodies."""
    tokens = [m.group() for m in TOKEN.finditer(text) if not m.group().startswith(('//', '/*'))]
    result = []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        previous = tokens[i - 1] if i else ''
        if token == '{' and previous in (')', 'get', 'set'):
            result += ['{', '}']
            depth = 1
            i += 1
            while i < len(tokens) and depth:
                depth += (tokens[i] == '{') - (tokens[i] == '}')
                i += 1
            continue
        if token == '=>' and previous in (')', 'get', 'set'):
            result += ['=>', ';']
            i += 1
            depth = 0
            while i < len(tokens):
                if tokens[i] == ';' and depth == 0:
                    i += 1
                    break
                depth += (tokens[i] in ('(', '[', '{')) - (tokens[i] in (')', ']', '}'))
                i += 1
            continue
        result.append(token)
        i += 1
    return hashlib.sha256(' '.join(result).encode()).hexdigest()


def snapshot(project):
    config = tomllib.loads((project / 'BeefSpace.toml').read_text())
    engine = (project / config['Projects']['Tessera']['Path']).resolve().parent
    sources = {str(p.relative_to(project / 'src')): schema(p.read_text()) for p in sorted((project / 'src').rglob('*.bf'))}
    digest = hashlib.sha256()
    files = list((engine / 'Engine' / 'src').rglob('*.bf')) + list((engine / 'Editor' / 'src').rglob('*.bf'))
    files += list((engine / 'native').glob('*.cpp')) + list((engine / 'native').glob('*.h')) + [engine / 'native' / 'CMakeLists.txt']
    files += [project / 'BeefSpace.toml', project / 'BeefProj.toml']
    # Extra libraries currently remain resident; changes to them need a full rebuild.
    for name, entry in config['Projects'].items():
        if name not in ('Tessera', 'TesseraEditor', tomllib.loads((project / 'BeefProj.toml').read_text())['Project']['Name']):
            folder = (project / entry['Path']).resolve()
            files += list(folder.rglob('*.bf')) + [folder / 'BeefProj.toml']
    for file in sorted(set(files)):
        if file.is_file():
            digest.update(str(file).encode()); digest.update(file.read_bytes())
    code = hashlib.sha256()
    for file in sorted((project / 'src').rglob('*.bf')):
        code.update(str(file.relative_to(project / 'src')).encode()); code.update(file.read_bytes())
    return {'schemas': sources, 'resident': digest.hexdigest(), 'code': code.hexdigest()}


def symbols(objects):
    output = subprocess.check_output(['nm', '-g', '-S', '--defined-only', *map(str, objects)], text=True)
    values = {}
    force = set()
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[-1].startswith('FORCELINKMOD_'):
            force.add(parts[-1][len('FORCELINKMOD_'):])
        if len(parts) == 4 and parts[2] in ('B', 'D'):
            values[parts[3]] = int(parts[1], 16)
    return force, values


def alias_host_globals(source, target, names):
    """Leave mutable script data in the host: make its ELF symbols undefined in the module."""
    data = bytearray(source.read_bytes())
    if data[:6] != b'\x7fELF\x02\x01':
        raise ValueError('Reload requires little-endian ELF64 object files.')
    shoff = struct.unpack_from('<Q', data, 40)[0]
    shsize, shcount = struct.unpack_from('<HH', data, 58)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shsize) for i in range(shcount)]
    removed_functions = []
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        strings = sections[section[6]]
        string_table = data[strings[4]:strings[4] + strings[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            name_index, info, other, index, value, size = struct.unpack_from('<IBBHQQ', data, offset)
            end = string_table.find(b'\0', name_index)
            name = string_table[name_index:end].decode()
            if name in names and index != 0:
                if info & 15 == 2 and index < len(sections):
                    removed_functions.append((index, value, value + size))
                    body = sections[index][4] + value
                    data[body:body + size] = b'\x90' * size
                struct.pack_into('<HQQ', data, offset + 6, 0, 0, 0)
    for section in sections:
        if section[1] != 4:  # SHT_RELA
            continue
        ranges = [(a, b) for index, a, b in removed_functions if index == section[7]]
        if not ranges:
            continue
        for offset in range(section[4], section[4] + section[5], section[9]):
            position = struct.unpack_from('<Q', data, offset)[0]
            if any(a <= position < b for a, b in ranges):
                struct.pack_into('<Qq', data, offset + 8, 0, 0)
    target.write_bytes(data)


def exported_symbols(path):
    command = ['nm', '-g', '-S', '--defined-only', str(path)]
    values = {}
    for line in subprocess.check_output(command, text=True).splitlines():
        parts = line.split()
        if len(parts) == 4:
            values[parts[3]] = int(parts[1], 16)
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--snapshot', action='store_true')
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--commit', action='store_true', help='Record symbols of an activated generation.')
    args = parser.parse_args()
    project = args.project.resolve()
    current = snapshot(project)
    if args.commit:
        baseline = json.loads(args.baseline.read_text())
        module = Path(json.loads(args.manifest.read_text().splitlines()[0].removeprefix('module ')))
        baseline['exports'].update(exported_symbols(module))
        args.baseline.write_text(json.dumps(baseline))
        return 0
    if args.snapshot:
        args.baseline.parent.mkdir(parents=True, exist_ok=True)
        name = tomllib.loads((project / 'BeefProj.toml').read_text())['Project']['Name']
        host = project / 'build' / 'Debug_Linux64' / name / name
        current['exports'] = exported_symbols(host)
        args.baseline.write_text(json.dumps(current))
        return 0
    baseline = json.loads(args.baseline.read_text())
    if baseline['resident'] != current['resident']:
        print('ERROR: Engine, editor, build configuration or resident library changed. Use File > Full Rebuild & Restart.', flush=True)
        return 3
    if args.manifest is None:
        parser.error('--manifest is required for builds')
    name = tomllib.loads((project / 'BeefProj.toml').read_text())['Project']['Name']
    workspace = project / '.tessera-reload' / (args.baseline.stem + '-workspace')
    workspace.mkdir(parents=True, exist_ok=True)
    source = workspace / 'src'
    if not source.exists():
        source.symlink_to(project / 'src', target_is_directory=True)
    config = tomllib.loads((project / 'BeefSpace.toml').read_text())
    entries = []
    for key, entry in config['Projects'].items():
        path = '.' if key == name else str((project / entry['Path']).resolve())
        entries.append(f'{key} = {{Path = {json.dumps(path)}}}')
    (workspace / 'BeefSpace.toml').write_text('FileVersion = 1\nProjects = {' + ', '.join(entries) + '}\n[Workspace]\nStartupProject = ' + json.dumps(name) + '\n')
    proj_text = (project / 'BeefProj.toml').read_text()
    proj_text = proj_text.replace('[Configs.Debug.Linux64]', '[Configs.Debug.Linux64]\nBuildKind = "DynamicLib"', 1)
    (workspace / 'BeefProj.toml').write_text(proj_text)
    completed = subprocess.run([os.environ.get('BEEFBUILD', 'BeefBuild'), f'-workspace={workspace}', '-config=Debug', '-verbosity=minimal'])
    if completed.returncode:
        return completed.returncode
    # A save during compilation must never activate a stale or mixed revision.
    if current != snapshot(project):
        print('ERROR: Source declarations or resident code changed during compilation; build again.', flush=True)
        return 4
    root = workspace / 'build' / 'Debug_Linux64' / name
    tokens = shlex.split((root / 'ObjectArgs.txt').read_text())
    objects = [Path(p) for p in tokens if p.endswith('.o') and Path(p).name != 'vdata.o']
    game_objects = [p for p in objects if p.parent == root]
    vdata = root / 'vdata.o'
    force, state = symbols(game_objects)
    force.update(obj.stem for obj in game_objects)
    _, metadata = symbols([vdata])
    classes = []
    for symbol, size in metadata.items():
        if symbol.endswith('13sBfClassVDataE'):
            demangled = subprocess.check_output(['c++filt', symbol], text=True).strip()
            key = demangled.removeprefix('bf::').removesuffix('::sBfClassVData').replace('::', '_')
            if key in force:
                classes.append((symbol, size))
    if not classes:
        print('ERROR: No reloadable class metadata found.', flush=True)
        return 5
    module = project / '.tessera-reload' / f'scripts-{time.time_ns()}.so'
    resident = baseline['exports']
    shared = {symbol: size for symbol, size in state.items() if symbol in resident and size > 0 and not symbol.startswith('FORCELINKMOD_')}
    for symbol, size in shared.items():
        if resident[symbol] != size:
            raise ValueError('Static field layout changed; change its name or full rebuild: ' + symbol)
    aliases = workspace / 'aliased-objects'
    aliases.mkdir(exist_ok=True)
    linked_objects = []
    for index, obj in enumerate(objects):
        target = aliases / f'{index}-{obj.name}'
        # Existing runtime functions/data stay in the host. New generic implementations
        # emitted for game code can be included without duplicating engine state.
        alias_host_globals(obj, target, shared if obj in game_objects else resident)
        linked_objects.append(target)
    renamed = {symbol: 'reload_private_' + symbol for symbol in metadata
               if symbol in resident and (symbol.endswith('11sBfTypeDataE')
                   or (symbol.endswith('13sBfClassVDataE') and symbol not in {s for s, _ in classes}))}
    # nm's data list excludes read-only metadata on some toolchains.
    for symbol in exported_symbols(vdata):
        if symbol in resident and symbol.endswith('11sBfTypeDataE'):
            renamed[symbol] = 'reload_private_' + symbol
    mapping = aliases / 'metadata-renames.txt'
    mapping.write_text(''.join(f'{a} {b}\n' for a, b in renamed.items()))
    metadata_object = aliases / 'vdata.o'
    subprocess.run(['objcopy', '--redefine-syms=' + str(mapping), str(vdata), str(metadata_object)], check=True)
    subprocess.run(['c++', '-shared', '-Wl,-Bsymbolic', '-o', str(module), *map(str, linked_objects), str(metadata_object)], check=True)
    lines = ['module ' + json.dumps(str(module)), 'mode structural']
    lines += [f'class {symbol} {size}' for symbol, size in classes]
    lines += [f'shared {symbol} {size}' for symbol, size in shared.items()]
    manifest = args.manifest.resolve()
    manifest.parent.mkdir(parents=True, exist_ok=True)
    temporary = manifest.with_suffix('.tmp')
    temporary.write_text('\n'.join(lines) + '\n')
    temporary.replace(manifest)
    print(f'Compiled script library: {module}. Engine implementations remain in the host.', flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f'ERROR: Script library build failed: {error}', flush=True)
        sys.exit(1)
