#!/usr/bin/env python3
"""Lighting picture checks (docs/lighting.md). Needs a graphics card, a display and Pillow.

Runs this fixture's CPU checks, then draws the Sandbox's Lighting scene (a dark floor with a grid of 64 small coloured
point lights, a point light beside a pillar and a spot light over a box, both casting shadows) and checks: every one
of the 64 lights shows on the floor (a view used to draw 16); the pillar's shadow is dark beside an equally distant
lit spot, and so is the box's; with --shadowed-lights 0 both shadows are gone; and lit parts of the floor look the
same either way (shadows only take light away).
"""
import math, subprocess, sys, tempfile, colorsys
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parent.parent
sandbox = root / 'Samples' / 'Sandbox'
failures = 0

# The scene's camera: at (0, 9, -9), turned 30 degrees down, 60 degrees high.
CAMERA = (0.0, 9.0, -9.0)
PITCH = math.radians(30)
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
    pictures = {}
    with tempfile.TemporaryDirectory() as folder:
        for name, extra in (('on', []), ('off', ['--shadowed-lights', '0'])):
            shot = Path(folder) / f'{name}.png'
            run = subprocess.run([str(binary), '--scene', 'Scenes/Lighting.tscene', '--frames', '30', '--screenshot', str(shot), *extra],
                                 cwd=sandbox, capture_output=True, text=True, timeout=180)
            if not shot.exists():
                print(f'FAIL: no picture\n{run.stdout}{run.stderr}')
                return 1
            pictures[name] = Image.open(shot).convert('RGB')
    on, off = pictures['on'], pictures['off']
    width, height = on.size

    def brightness(image, point, radius=3):
        cx, cy = screen(point, width, height)
        total, count = 0.0, 0
        for x in range(int(cx) - radius, int(cx) + radius + 1):
            for y in range(int(cy) - radius, int(cy) + radius + 1):
                if 0 <= x < width and 0 <= y < height:
                    total += sum(image.getpixel((x, y))) / 3
                    count += 1
        return total / max(count, 1)

    def colour(image, point):
        cx, cy = screen(point, width, height)
        return image.getpixel((int(cx), int(cy)))

    # The 64 lights: each lights the floor under it, in about its own colour.
    dark = brightness(on, (-8, 0, -1.5))
    lit, matched = 0, 0
    for row in range(8):
        for col in range(8):
            spot = (-14 + col * 1.5, 0, 2 + row * 2)
            if brightness(on, spot, 1) > dark * 3 + 20:
                lit += 1
            r, g, b = colorsys.hsv_to_rgb(((row * 8 + col) * 0.13) % 1.0, 0.75, 1.0)
            seen = colour(on, spot)
            if max(range(3), key=lambda i: seen[i]) == max(range(3), key=lambda i: (r, g, b)[i]):
                matched += 1
    check(lit == 64, f'all 64 point lights light the floor ({lit} lit; the floor between them {dark:.0f})')
    check(matched >= 56, f'each light is its own colour ({matched} of 64 match)')

    # The pillar's shadow (the point light at (4, 1, 3), the pillar at x 6): the floor behind it against the floor as
    # far away on the other side.
    shade, open_ = brightness(on, (8.5, 0, 3)), brightness(on, (-0.5, 0, 3))
    check(shade < open_ * 0.35, f'the pillar casts a point light shadow ({shade:.0f} against {open_:.0f})')
    shade_off, open_off = brightness(off, (8.5, 0, 3)), brightness(off, (-0.5, 0, 3))
    check(shade_off > open_off * 0.75, f'without shadowed lights the floor behind the pillar is lit ({shade_off:.0f} against {open_off:.0f})')
    # Every side of the cube: lit floor round the lamp, away from the pillar, the same with or without shadows.
    # Rings near (the downward face) and farther out (the side faces), every 15 degrees but towards the pillar.
    sides = [(4 + r * math.cos(a), 0, 3 + r * math.sin(a)) for r in (0.6, 0.9, 1.0, 1.1, 1.5, 2.5)
             for a in (math.pi * k / 12 for k in range(4, 21))]
    worst = max(abs(brightness(on, p) - brightness(off, p)) for p in sides)
    check(worst < 12, f'no false shadows round the point light, across its cube\'s faces (largest difference {worst:.0f})')

    # The box's shadow (the spot light at (5, 6, 13) shining down towards the camera).
    shade, open_ = brightness(on, (5, 0, 10.3)), brightness(on, (3.2, 0, 10.3))
    check(shade < open_ * 0.35, f'the box casts a spot light shadow ({shade:.0f} against {open_:.0f})')
    shade_off, open_off = brightness(off, (5, 0, 10.3)), brightness(off, (3.2, 0, 10.3))
    check(shade_off > open_off * 0.75, f'without shadowed lights the floor before the box is lit ({shade_off:.0f} against {open_off:.0f})')

    print('All lighting picture checks passed.' if failures == 0 else f'{failures} lighting picture check(s) failed.')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
