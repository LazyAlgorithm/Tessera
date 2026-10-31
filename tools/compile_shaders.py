#!/usr/bin/env python3
"""Compile the engine shaders using the locally built shaderc on Linux or Windows."""
import argparse
import os
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', action='append', choices=['spirv', 'glsl', 'essl', 'webgl', 'metal'],
                        help='Repeat to select backends; default is every shipped backend.')
    args = parser.parse_args()
    native = 'native-win' if os.name == 'nt' else 'native'
    compiler = os.environ.get('SHADERC', str(root / 'build' / native / 'bgfx/cmake/bgfx' / ('shaderc.exe' if os.name == 'nt' else 'shaderc')))
    source = root / 'Engine/shaders'
    targets = {'spirv': ('spirv', 'linux'), 'glsl': ('430', 'linux'), 'essl': ('310_es', 'android'),
               'webgl': ('300_es', 'asm.js'), 'metal': ('metal', 'osx')}
    failed = []
    for prefix, stage in [('vs_', 'vertex'), ('fs_', 'fragment'), ('cs_', 'compute')]:
        for shader in sorted(source.glob(prefix + '*.sc')):
            if shader.name == 'cs_template.sc':
                continue
            for backend in args.backend or list(targets):
                if backend == 'webgl' and stage == 'compute':
                    continue
                profile, platform = targets[backend]
                output = root / 'Engine/assets/shaders' / backend / (shader.stem + '.bin')
                output.parent.mkdir(parents=True, exist_ok=True)
                result = subprocess.run([compiler, '-f', str(shader), '-o', str(output), '--type', stage,
                                         '--platform', platform, '-p', profile, '-i', str(root / 'third_party/bgfx.cmake/bgfx/src'),
                                         '-i', str(source / 'include'), '--varyingdef', str(source / 'varying.def.sc'), '-O', '3'])
                if result.returncode:
                    failed.append(f'{shader.name} ({backend})')
    if failed:
        parser.exit(1, 'Shader compilation failed: ' + ', '.join(failed) + '\n')
    print('Engine shaders compiled successfully.')


if __name__ == '__main__':
    main()
