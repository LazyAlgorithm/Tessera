#!/usr/bin/env python3
"""GPU skinning picture check (docs/gpu-skinning.md). Needs a graphics card and a display.

Builds this fixture's CPU checks and runs them, then draws the Sandbox sample's Skinning scene (three rigged models
holding a pose) twice, with GPU and with CPU skinning, and checks the two pictures match and that the GPU really did
the bending.
"""
import subprocess, sys, tempfile
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parent.parent
sandbox = root / 'Samples' / 'Sandbox'

def main():
    if subprocess.run(['BeefBuild', '-config=Debug', '-run'], cwd=here).returncode != 0:
        print('FAIL: CPU checks')
        return 1
    if subprocess.run(['BeefBuild', '-config=Debug'], cwd=sandbox).returncode != 0:
        print('FAIL: Sandbox build')
        return 1
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print('Pillow is needed for the picture check (pip install pillow).')
        return 1
    binary = sandbox / 'build' / 'Debug_Linux64' / 'Sandbox' / 'Sandbox'
    with tempfile.TemporaryDirectory() as folder:
        shots, logs = {}, {}
        for name, extra in (('gpu', []), ('cpu', ['--cpu-skinning'])):
            shot = Path(folder) / f'{name}.png'
            result = subprocess.run([str(binary), '--scene', 'Scenes/Skinning.tscene', '--frames', '40', '--screenshot', str(shot), *extra],
                                    cwd=sandbox, capture_output=True, text=True, timeout=180)
            logs[name] = result.stdout + result.stderr
            if not shot.exists():
                print(f'FAIL: no {name} picture\n{logs[name]}')
                return 1
            shots[name] = Image.open(shot).convert('RGB')
        ok = True
        if 'Skinning: on the GPU' not in logs['gpu'] or 'bends on the GPU' not in logs['gpu']:
            print('SKIP: this graphics card skins on the CPU, so there is nothing to compare' if 'on the CPU' in logs['gpu'] else 'FAIL: the GPU did no bending')
            return 0 if 'on the CPU' in logs['gpu'] else 1
        print('PASS: the GPU bent the models')
        if 'on the CPU (turned off)' in logs['cpu'] and 'bends on the GPU' not in logs['cpu']:
            print('PASS: --cpu-skinning bends them on the CPU')
        else:
            print('FAIL: --cpu-skinning still used the GPU')
            ok = False
        difference = ImageChops.difference(shots['gpu'], shots['cpu'])
        pixels = difference.get_flattened_data() if hasattr(difference, 'get_flattened_data') else difference.getdata()
        off = sum(1 for p in pixels if max(p) > 24)
        share = off / (difference.size[0] * difference.size[1])
        if share < 0.001:
            print(f'PASS: GPU and CPU skinning draw the same picture ({off} pixels differ)')
        else:
            print(f'FAIL: the pictures differ in {off} pixels')
            ok = False
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
