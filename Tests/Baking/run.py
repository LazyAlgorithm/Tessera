#!/usr/bin/env python3
"""Baked lighting picture checks (docs/baked-lighting.md). Needs a graphics card, a display and Pillow.

Runs this fixture's CPU checks, bakes the Sandbox's BakedLighting scene in the editor (--bake-lighting: the scene is
not saved, and the bake already saved with it is the same), then draws the scene with its baked lighting and with
--no-baked-lighting and checks: the roof's underside is lit by light bounced off the floor (the ambient colours leave
it dark); the floor takes red light from the red wall and blue from the blue one; the Baked Only lamp lights the back
wall about as much baked as it does live (it is not counted twice, nor lost); the back wall is smooth (no noise from
the rays); and the loose ball, which has no lightmap, is lit differently by the light probes.
"""
import math, subprocess, sys, tempfile
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parent.parent
sandbox = root / 'Samples' / 'Sandbox'
failures = 0

# The scene's camera: at (0, 3.2, -11.5), turned 12 degrees down, 60 degrees high.
CAMERA = (0.0, 3.2, -11.5)
PITCH = math.radians(12)
FOV = math.radians(60)


def check(passed, label):
    global failures
    print(f'{"PASS" if passed else "FAIL"}: {label}')
    failures += 0 if passed else 1


def screen(point, width, height):
    """Where a point of the world is in the picture, in pixels from the top left."""
    d = [point[i] - CAMERA[i] for i in range(3)]
    forward = (0, -math.sin(PITCH), math.cos(PITCH))
    up = (0, math.cos(PITCH), math.sin(PITCH))
    x = d[0]
    y = sum(d[i] * up[i] for i in range(3))
    z = sum(d[i] * forward[i] for i in range(3))
    t = math.tan(FOV / 2)
    return (0.5 + 0.5 * x / (z * t * width / height)) * width, (0.5 - 0.5 * y / (z * t)) * height


def patch(picture, point, radius=6):
    """The average colour round a point of the world, and how much its brightness varies."""
    px, py = screen(point, *picture.size)
    colours = [picture.getpixel((int(px) + dx, int(py) + dy))[:3] for dx in range(-radius, radius + 1) for dy in range(-radius, radius + 1)]
    mean = [sum(c[i] for c in colours) / len(colours) for i in range(3)]
    grey = [sum(c) / 3 for c in colours]
    average = sum(grey) / len(grey)
    spread = math.sqrt(sum((g - average) ** 2 for g in grey) / len(grey))
    return mean, spread


def main():
    if subprocess.run(['BeefBuild', '-config=Debug', '-run'], cwd=here).returncode != 0:
        print('FAIL: CPU checks')
        return 1
    try:
        from PIL import Image
    except ImportError:
        print('Pillow is needed (pip install pillow).')
        return 1
    if subprocess.run(['BeefBuild', '-config=Debug'], cwd=sandbox).returncode != 0:
        print('FAIL: Sandbox build')
        return 1
    binary = sandbox / 'build' / 'Debug_Linux64' / 'Sandbox' / 'Sandbox'
    bake = subprocess.run([str(binary), '--editor', '--scene', 'Scenes/BakedLighting.tscene', '--bake-lighting', '--frames', '20'],
                          cwd=sandbox, capture_output=True, text=True, timeout=600)
    line = next((l for l in bake.stdout.splitlines() if 'BAKE:' in l), '')
    check(bake.returncode == 0 and 'Baked 11 objects' in line, f'the editor bakes the scene: {line.strip() or bake.stdout[-300:]}')
    pictures = {}
    with tempfile.TemporaryDirectory() as folder:
        for name, extra in (('baked', []), ('live', ['--no-baked-lighting'])):
            shot = Path(folder) / f'{name}.png'
            run = subprocess.run([str(binary), '--scene', 'Scenes/BakedLighting.tscene', '--frames', '30', '--screenshot', str(shot), *extra],
                                 cwd=sandbox, capture_output=True, text=True, timeout=180)
            if run.returncode != 0 or not shot.exists():
                print(f'FAIL: drawing the scene ({name})\n{run.stdout[-500:]}{run.stderr[-500:]}')
                return 1
            pictures[name] = Image.open(shot).convert('RGB')
    baked, live = pictures['baked'], pictures['live']

    roof_baked, _ = patch(baked, (-3.3, 4.0, 0.5))
    roof_live, _ = patch(live, (-3.3, 4.0, 0.5))
    check(sum(roof_baked) > sum(roof_live) * 1.3, f'the roof\'s underside is lit by light bounced off the floor ({sum(roof_baked) / 3:.0f} against {sum(roof_live) / 3:.0f} without)')

    red_side, _ = patch(baked, (-4.4, 0.1, 2.5))
    blue_side, _ = patch(baked, (4.4, 0.1, 2.5))
    warmth = lambda c: c[0] - c[2]
    check(warmth(red_side) > warmth(blue_side) + 12, f'the floor takes the walls\' colours: redder by the red wall ({red_side[0]:.0f}, {red_side[2]:.0f}), bluer by the blue one ({blue_side[0]:.0f}, {blue_side[2]:.0f})')
    live_red, _ = patch(live, (-4.4, 0.1, 2.5))
    live_blue, _ = patch(live, (4.4, 0.1, 2.5))
    check(warmth(red_side) - warmth(blue_side) > (warmth(live_red) - warmth(live_blue)) + 8, 'more than without baked lighting')

    lamp_baked, _ = patch(baked, (-3.6, 3.0, 4.84), 4)
    lamp_live, _ = patch(live, (-3.6, 3.0, 4.84), 4)
    check(lamp_baked[0] > lamp_baked[2] + 15 and 0.7 < sum(lamp_baked) / max(sum(lamp_live), 1) < 1.5,
          f'the Baked Only lamp lights the wall baked about as it does live ({sum(lamp_baked) / 3:.0f} against {sum(lamp_live) / 3:.0f})')

    _, spread = patch(baked, (0.8, 2.4, 4.84), 10)
    check(spread < 4, f'the back wall is smooth ({spread:.1f} levels of noise)')

    ball_baked, _ = patch(baked, (-2.6, 0.45, -2.15), 3)
    ball_live, _ = patch(live, (-2.6, 0.45, -2.15), 3)
    check(abs(sum(ball_baked) - sum(ball_live)) > 15, f'the loose ball is lit by the light probes ({sum(ball_baked) / 3:.0f} against {sum(ball_live) / 3:.0f} without)')

    print('All baked lighting picture checks passed.' if failures == 0 else f'{failures} baked lighting picture check(s) failed.')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
