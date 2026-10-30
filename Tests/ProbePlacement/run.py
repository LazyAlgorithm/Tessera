#!/usr/bin/env python3
"""Probe placement picture checks (docs/probe-placement.md). Needs a graphics card, a display and Pillow.

Runs this fixture's CPU checks, then works on a copy of the Sandbox's ProbePlacement scene (a closed room with a red
wall, a polished floor, a lamp and a loose ball, seen from inside): bakes it as it is, and bakes it again after
--place-probes, saving each copy (--save-scene) and drawing it in the game. Checks that placing put a reflection
probe in the room and light probe volumes round it; that the polished floor, which mirrors the blue sky without a
probe, mirrors the room instead (darker, warmer, redder by the red wall); and that the loose ball, lit by the scene's
coarse grid of probes before, is lit by the room's volume after. The copies are removed afterwards.
"""
import math, shutil, subprocess, sys, tempfile
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parent.parent
sandbox = root / 'Samples' / 'Sandbox'
scenes = sandbox / 'src' / 'Scenes'
failures = 0

# The scene's camera: at (0, 1.7, 0.4), turned 15 degrees down, 75 degrees high.
CAMERA = (0.0, 1.7, 0.4)
PITCH = math.radians(15)
FOV = math.radians(75)


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


def patch(picture, point, radius=8):
    """The average colour round a point of the world."""
    px, py = screen(point, *picture.size)
    colours = [picture.getpixel((int(px) + dx, int(py) + dy))[:3] for dx in range(-radius, radius + 1) for dy in range(-radius, radius + 1)]
    return [sum(c[i] for c in colours) / len(colours) for i in range(3)]


def draw(binary, name, place, folder):
    """Bakes a copy of the scene (placing probes first if asked), saves it, and draws it in the game."""
    scene = scenes / f'{name}.tscene'
    shutil.copy(scenes / 'ProbePlacement.tscene', scene)
    editor = [str(binary), '--editor', '--scene', f'Scenes/{name}.tscene', '--bake-lighting', '--save-scene', '--frames', '40']
    if place:
        editor.insert(4, '--place-probes')
    run = subprocess.run(editor, cwd=sandbox, capture_output=True, text=True, timeout=600)
    log = run.stdout
    shot = Path(folder) / f'{name}.png'
    game = subprocess.run([str(binary), '--scene', f'Scenes/{name}.tscene', '--frames', '40', '--screenshot', str(shot)],
                          cwd=sandbox, capture_output=True, text=True, timeout=180)
    if game.returncode != 0 or not shot.exists():
        print(f'FAIL: drawing the scene ({name})\n{game.stdout[-500:]}{game.stderr[-500:]}')
        return None, log
    from PIL import Image
    return Image.open(shot).convert('RGB'), log


def main():
    if subprocess.run(['BeefBuild', '-config=Debug', '-run'], cwd=here).returncode != 0:
        print('FAIL: CPU checks')
        return 1
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        print('Pillow is needed (pip install pillow).')
        return 1
    if subprocess.run(['BeefBuild', '-config=Debug'], cwd=sandbox).returncode != 0:
        print('FAIL: Sandbox build')
        return 1
    binary = sandbox / 'build' / 'Debug_Linux64' / 'Sandbox' / 'Sandbox'
    names = ('ProbePlacementBefore', 'ProbePlacementAfter')
    try:
        with tempfile.TemporaryDirectory() as folder:
            before, _ = draw(binary, names[0], False, folder)
            after, log = draw(binary, names[1], True, folder)
            if before is None or after is None:
                return 1
            place = next((l for l in log.splitlines() if 'PLACE:' in l), '')
            bake = next((l for l in log.splitlines() if 'BAKE:' in l), '')
            check('1 Room' in place and 'light probe volume' in place, f'the editor places probes: {place.strip() or log[-300:]}')
            check('volume' in bake, f'and bakes the volumes: {bake.strip()}')
            saved = (scenes / f'{names[1]}.tscene').read_text()
            check('Reflection Probe (Room 1)' in saved and 'Light Probe Volume (Room 1)' in saved and 'tags "Placed Probe"' in saved,
                  'the saved scene has them, tagged as placed')

            middle_before = patch(before, (0.0, 0.02, 3.5))
            middle_after = patch(after, (0.0, 0.02, 3.5))
            blueness = lambda c: c[2] - c[0]
            check(blueness(middle_before) > 20 and blueness(middle_after) < blueness(middle_before) - 20 and sum(middle_after) < sum(middle_before),
                  f'the polished floor mirrors the room, not the sky ({middle_after[0]:.0f}, {middle_after[1]:.0f}, {middle_after[2]:.0f} against {middle_before[0]:.0f}, {middle_before[1]:.0f}, {middle_before[2]:.0f} with the sky)')
            red_before = patch(before, (-3.0, 0.02, 4.0))
            red_after = patch(after, (-3.0, 0.02, 4.0))
            redness = lambda c: c[0] - c[2]
            check(redness(red_after) > redness(red_before) + 20,
                  f'by the red wall it mirrors red ({redness(red_after):.0f} redder than blue, against {redness(red_before):.0f})')
            ball_before = patch(before, (2.9, 0.5, 4.6), 4)
            ball_after = patch(after, (2.9, 0.5, 4.6), 4)
            check(abs(sum(ball_after) - sum(ball_before)) > 15,
                  f'the loose ball is lit by the room\'s volume, not the coarse grid ({sum(ball_after) / 3:.0f} against {sum(ball_before) / 3:.0f})')
    finally:
        for name in names:
            (scenes / f'{name}.tscene').unlink(missing_ok=True)
            shutil.rmtree(scenes / f'{name}_Baked', ignore_errors=True)

    print('All probe placement picture checks passed.' if failures == 0 else f'{failures} probe placement picture check(s) failed.')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
