#!/usr/bin/env python3
"""Build a player (Linux, or Windows with --platform windows) with no TesseraEditor dependency and stage its runtime assets.

A Windows player is built here on Linux: the Windows Beef compiler runs under Wine and links against the native
libraries in build/native-win. tools/windows/setup.sh downloads and builds what that needs, once."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib

import pack_assets

# Windows system libraries the native libraries call into (SDL, bgfx, ENet, miniaudio).
WINDOWS_SYSTEM_LIBS = ('user32', 'gdi32', 'shell32', 'winmm', 'imm32', 'ole32', 'oleaut32', 'version', 'setupapi', 'advapi32',
                       'ws2_32', 'psapi', 'uuid', 'cfgmgr32')
WINDOWS_NATIVE_LIBS = ('tessera_native.lib', 'bgfx/cmake/bgfx/bgfx.lib', 'bgfx/cmake/bimg/bimg.lib', 'bgfx/cmake/bimg/bimg_decode.lib',
                       'bgfx/cmake/bx/bx.lib', 'SDL/SDL3-static.lib', 'joltc/joltc.lib', '_deps/joltphysics-build/Jolt.lib', 'enet/enet.lib')


def wine_path(path, separator='\\'):
    """A Linux path as Wine sees it: its Z: drive is the whole file system."""
    return 'Z:' + str(path).replace('/', separator)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--scene', help='Asset-relative start scene')
    parser.add_argument('--config', choices=('Debug', 'Release'), default='Release')
    parser.add_argument('--platform', choices=('linux', 'windows'), default='windows' if os.name == 'nt' else 'linux')
    parser.add_argument('--replace', action='store_true', help='Replace the output folder if it holds an earlier build (it must contain game.tessera)')
    parser.add_argument('--fullscreen', action='store_true', help='The game starts fullscreen, whatever the project says')
    parser.add_argument('--windowed', action='store_true', help='The game starts in a window, whatever the project says')
    parser.add_argument('--no-compress', action='store_true', help='Pack the assets without compressing them')
    parser.add_argument('--loose', action='store_true', help='Leave the assets as loose files instead of packing them into game.tpak')
    parser.add_argument('--console', action='store_true', help='Windows: keep a console window for log output (a dedicated server wants one)')
    parser.add_argument('--bootstrap', help='Static registration method, e.g. Sandbox.GameSetup.Register')
    args = parser.parse_args()
    project = args.project.resolve()
    output = args.output.resolve()
    if output.exists():
        # Only ever delete a folder this tool made: an earlier build, recognised by its game.tessera or game.tpak.
        if not args.replace:
            parser.error('Output already exists; choose a new folder to preserve the existing build, or pass --replace.')
        if not output.is_dir() or (any(output.iterdir()) and not (output / 'game.tessera').is_file() and not (output / 'game.tpak').is_file()):
            parser.error(f'{output} exists and is not an earlier build of a game, so it is left alone. Choose another folder.')
    settings = {}
    for line in (project / 'project.tessera').read_text().splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            settings[key.strip()] = value.strip()
    windows = args.platform == 'windows'
    # On a Windows machine Beef builds for Windows by itself; on Linux its Windows release runs under Wine.
    cross = windows and os.name != 'nt'
    if os.name == 'nt' and not windows:
        parser.error('A Linux player is built on Linux.')
    engine = Path(settings['engine']).resolve()
    recorded_engine = settings['engine']
    # A project copied from another machine names an engine folder that is not here: use the engine this tool
    # belongs to, and point the project's link settings at it.
    if not (engine / 'Engine' / 'src').is_dir():
        engine = Path(__file__).resolve().parent.parent
    name = settings['name']
    if windows:
        toolchain = Path(os.environ.get('TESSERA_WIN', Path.home() / '.local/share/tessera-win'))
        natives = engine / 'build' / 'native-win'
        if args.config != 'Release':
            parser.error('Windows players are built in the Release configuration only.')
        if cross and not shutil.which('wine'):
            parser.error('Building for Windows needs Wine (it runs the Windows Beef compiler).')
        if cross and (not (toolchain / 'beef/bin/BeefBuild.exe').is_file() or not (natives / 'tessera_native.lib').is_file()):
            parser.error(f'The Windows toolchain is not set up. Run {engine / "tools/windows/setup.sh"} once.')
        if not cross and not (natives / 'tessera_native.lib').is_file():
            parser.error(f'The native libraries for Windows are missing from {natives}.')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
        parser.error('Project name must be a valid Beef identifier.')
    scene = args.scene or settings.get('startScene', 'Scenes/Main.tscene')
    scene_path = (project / 'src' / scene).resolve()
    if not scene_path.is_relative_to(project / 'src') or not scene_path.is_file():
        parser.error('Start scene must exist inside the project src folder. Save it in the editor first.')
    proj = tomllib.loads((project / 'BeefProj.toml').read_text())
    space = tomllib.loads((project / 'BeefSpace.toml').read_text())
    dependencies = {key: value for key, value in proj['Dependencies'].items() if key != 'TesseraEditor'}
    bootstrap = args.bootstrap
    if bootstrap is None and re.search(r'\bGameSetup\.Register\(\)', (project / 'src' / 'Program.bf').read_text()):
        bootstrap = f'{name}.GameSetup.Register'
    if bootstrap and not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.]*', bootstrap):
        parser.error('Invalid bootstrap method name.')
    with tempfile.TemporaryDirectory(prefix='tessera-player-') as temporary:
        workspace = Path(temporary)
        source = workspace / 'src'
        source.mkdir()
        for file in (project / 'src').rglob('*.bf'):
            if file == project / 'src' / 'Program.bf':
                continue
            if re.search(r'\bTessera\.Editor\b', file.read_text()):
                parser.error(f'Runtime script references the editor: {file}')
            target = source / file.relative_to(project / 'src')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, target)
        (source / 'Program.bf').write_text('using System;\nusing Tessera;\nnamespace ' + name + ';\nclass Program { public static int Main(String[] args) {\n' + (f'{bootstrap}();\n' if bootstrap else '') + 'return GameMain.Run(args);\n} }\n')
        q = json.dumps
        # Beef under Wine is given forward-slash Z: paths for projects and backslash ones on the link line.
        located = (lambda path: wine_path(path, '/')) if cross else (lambda path: str(path).replace('\\', '/'))
        project_entries = [f'{name} = {{Path = "."}}', f'Tessera = {{Path = {q(located(engine / "Engine"))}}}']
        for dependency in dependencies:
            if dependency in ('corlib', 'Tessera'):
                continue
            location = (project / space['Projects'][dependency]['Path']).resolve()
            project_entries.append(f'{dependency} = {{Path = {q(located(location))}}}')
        (workspace / 'BeefSpace.toml').write_text('FileVersion = 1\nProjects = {' + ', '.join(project_entries) + '}\n[Workspace]\nStartupProject = ' + q(name) + '\n'
                                               + (f'[Configs.{args.config}.Win64]\nToolset = "LLVM"\n' if windows else ''))
        if windows:
            # The project's own settings are for Linux; a Windows player links the same libraries as built for Windows.
            config = {'OtherLinkFlags': '$(LinkFlags) ' + ' '.join([(wine_path(natives / lib) if cross else str(natives / lib)) for lib in WINDOWS_NATIVE_LIBS] + [lib + '.lib' for lib in WINDOWS_SYSTEM_LIBS])}
        else:
            config = proj['Configs'][args.config]['Linux64']
        target_type = 'BeefGUIApplication' if windows and not args.console else 'BeefConsoleApplication'
        beef_platform = 'Win64' if windows else 'Linux64'
        lines = ['FileVersion = 1', 'Dependencies = {' + ', '.join(f'{key} = {q(value)}' for key, value in dependencies.items()) + '}', '[Project]', f'Name = {q(name)}', f'TargetType = {q(target_type)}', f'StartupObject = {q(name + ".Program")}', f'[Configs.{args.config}.{beef_platform}]']
        for key, value in config.items():
            if not windows and isinstance(value, str) and recorded_engine and str(engine) != recorded_engine:
                value = value.replace(recorded_engine, str(engine))
            lines.append(f'{key} = {q(value)}')
        (workspace / 'BeefProj.toml').write_text('\n'.join(lines) + '\n')
        if cross:
            environment = dict(os.environ, WINEPREFIX=str(toolchain / 'wine'), WINEDEBUG='-all', WINEDLLOVERRIDES='mscoree,mshtml=')
            built = subprocess.run(['wine', str(toolchain / 'beef/bin/BeefBuild.exe'), '-workspace=.', f'-config={args.config}', '-platform=Win64', '-verbosity=minimal'],
                                   cwd=workspace, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            # Wine's own chatter about graphics drivers is noise here; the compiler's messages are not.
            print('\n'.join(line for line in built.stdout.splitlines() if 'MESA' not in line and 'pci id' not in line))
            if built.returncode != 0:
                raise SystemExit('The Windows build failed.')
        else:
            subprocess.run([os.environ.get('BEEFBUILD', 'BeefBuild'), f'-workspace={workspace}', f'-config={args.config}', '-verbosity=minimal'] + (['-platform=Win64'] if windows else []), check=True)
        output.parent.mkdir(parents=True, exist_ok=True)
        staging = Path(tempfile.mkdtemp(prefix=output.name + '-', dir=output.parent))
        try:
            executable = name + ('.exe' if windows else '')
            shutil.copy2(workspace / 'build' / f'{args.config}_{beef_platform}' / name / executable, staging / executable)
            # Of the engine's files a game reads only the compiled shaders, and only those of the graphics backends
            # it can start on this system: Vulkan, plus OpenGL as the fallback on Linux.
            for backend in (('spirv',) if windows else ('spirv', 'glsl')):
                shutil.copytree(engine / 'Engine' / 'assets' / 'shaders' / backend, staging / 'Engine' / 'assets' / 'shaders' / backend)
            for file in (engine / 'Engine' / 'assets').iterdir():
                if file.is_file():
                    shutil.copy2(file, staging / 'Engine' / 'assets' / file.name)
            # The libraries' licences ask to travel with what is built from them.
            if (engine / 'THIRD_PARTY_LICENSES.txt').exists():
                shutil.copy2(engine / 'THIRD_PARTY_LICENSES.txt', staging / 'THIRD_PARTY_LICENSES.txt')
            for file in (project / 'src').rglob('*'):
                if not file.is_file() or file.suffix in ('.bf', '.tgraph', '.py', '.sh') or any(part.startswith('.') for part in file.relative_to(project / 'src').parts):
                    continue
                target = staging / 'Assets' / file.relative_to(project / 'src')
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file, target)
            steam = settings.get('steamAppId', '')
            if steam:
                # A game that is not started from Steam says which app it is with this file, and needs Valve's
                # Steamworks library beside it: the project's own copy if it has one, else one found on this machine.
                (staging / 'steam_appid.txt').write_text(steam + '\n')
                library = 'steam_api64.dll' if windows else 'libsteam_api.so'
                for candidate in (project / library, project / 'Libraries' / library, Path.home() / '.local/share/Steam/steamrt64' / library):
                    if candidate.is_file():
                        shutil.copy2(candidate, staging / library)
                        break
                else:
                    print(f'Note: {library} was not found, so this build runs without Steam. Put the file from the Steamworks SDK in {project} and build again.')
            hrtf = settings.get('audioHrtf', '')
            # How the game starts out: the project's Build setting, unless this run says otherwise.
            fullscreen = (settings.get('fullscreen', '') == '1' or args.fullscreen) and not args.windowed
            (staging / 'game.tessera').write_text(f'name = {name}\nstartScene = {scene}\n' + (f'steamAppId = {steam}\n' if steam else '') + (f'audioHrtf = {hrtf}\n' if hrtf else '') + ('fullscreen = 1\n' if fullscreen else '') + ''.join(f'{k} = {settings[k]}\n' for k in ('antiCheat', 'voiceChat', 'voicePushToTalk', 'voiceProximity', 'voiceTeamOnly', 'voiceKey') if settings.get(k)))
            if output.exists():
                shutil.rmtree(output)
            # Everything the game reads goes into one pack, unless the project (or --loose) says to leave it loose.
            if not args.loose and settings.get('packAssets', '1') != '0':
                packed = [(file.relative_to(staging).as_posix(), str(file)) for folder in ('Assets', 'Engine') for file in (staging / folder).rglob('*') if file.is_file()]
                packed.append(('game.tessera', str(staging / 'game.tessera')))
                pack_assets.write_pack(staging / 'game.tpak', packed, compress=not args.no_compress and settings.get('packCompress', '1') != '0')
                shutil.rmtree(staging / 'Assets')
                shutil.rmtree(staging / 'Engine')
                (staging / 'game.tessera').unlink()
            staging.rename(output)
        except BaseException:
            shutil.rmtree(staging)
            raise
    print(f'{args.platform.capitalize()} player packaged at {output}; TesseraEditor excluded.')


if __name__ == '__main__':
    main()
