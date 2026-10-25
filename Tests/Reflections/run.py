#!/usr/bin/env python3
"""Reflection picture checks (docs/reflections.md). Needs a graphics card, a display and Pillow.

Runs this fixture's CPU checks, then draws the Sandbox's Reflections scene (five metal spheres from smooth to rough
under the sky, and a red, green and blue room with a reflection probe, a polished floor and a chrome sphere) and
checks: the sky and the probe were captured; the smooth outdoor sphere mirrors the sky above (blue) and the ground
colour below, and a rougher one a pale blur; the room's sphere shows the red wall on its left and the green on its
right (the cube faces the right way); the polished floor mirrors the walls beside it; --no-reflections draws the old
look; and with Ambient From Surroundings the room's ceiling is lit by the room.
"""
import subprocess, sys, tempfile
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parent.parent
sandbox = root / 'Samples' / 'Sandbox'
failures = 0


def check(passed, label):
    global failures
    print(f'{"PASS" if passed else "FAIL"}: {label}')
    failures += 0 if passed else 1


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
    with tempfile.TemporaryDirectory() as folder:
        pictures, logs = {}, {}
        for name, extra in (('on', []), ('off', ['--no-reflections'])):
            shot = Path(folder) / f'{name}.png'
            run = subprocess.run([str(binary), '--scene', 'Scenes/Reflections.tscene', '--frames', '60', '--screenshot', str(shot), *extra],
                                 cwd=sandbox, capture_output=True, text=True, timeout=180)
            logs[name] = run.stdout + run.stderr
            if not shot.exists():
                print(f'FAIL: no picture\n{logs[name]}')
                return 1
            pictures[name] = Image.open(shot).convert('RGB').resize((1600, 900))
        if 'cannot draw into cube maps' in logs['on']:
            print('SKIP: this graphics card cannot draw into cube maps')
            return 0
        check('Reflections: 1 of the sky and 1 of probes captured' in logs['on'], 'the sky and the room\'s probe were captured')
        check('Reflections:' not in logs['off'], '--no-reflections captures nothing')
        on = pictures['on']

        def mean(image, box):
            region = image.crop(box)
            pixels = region.get_flattened_data() if hasattr(region, 'get_flattened_data') else list(region.getdata())
            return tuple(sum(p[i] for p in pixels) / len(pixels) for i in range(3))

        # The smooth sphere outdoors (left of the row): the sky above its middle, the ground colour below.
        top, bottom = mean(on, (40, 445, 120, 480)), mean(on, (40, 560, 120, 590))
        check(top[2] > top[0] + 40 and top[2] > bottom[2] + 40, f'the smooth sphere mirrors the blue sky above and the ground below (top {tuple(round(c) for c in top)}, bottom {tuple(round(c) for c in bottom)})')
        # The spheres at a quarter and three quarters rough, second and fourth in the row: near its top the smoother
        # one mirrors the deep blue sky, the rougher one a pale blur of sky, sun and horizon.
        smooth, rough = mean(on, (372, 440, 452, 460)), mean(on, (1147, 440, 1227, 460))
        check(smooth[2] - smooth[0] > 2 * (rough[2] - rough[0]) + 40, f'smooth to rough: the smoother sphere mirrors the blue sky sharply, the rougher a pale blur ({tuple(round(c) for c in smooth)} against {tuple(round(c) for c in rough)})')
        # The room's chrome sphere, at the middle of the picture.
        left, right = mean(on, (762, 385, 778, 405)), mean(on, (822, 385, 838, 405))
        check(left[0] > left[1] * 2 and left[0] > 60, f'the room\'s sphere shows the red wall on its left ({tuple(round(c) for c in left)})')
        check(right[1] > right[0] * 2 and right[1] > 40, f'and the green wall on its right ({tuple(round(c) for c in right)})')
        off_left = mean(pictures['off'], (762, 385, 778, 405))
        check(off_left[0] < off_left[1] * 2, f'without reflections it does not ({tuple(round(c) for c in off_left)})')
        # The polished floor either side of the sphere mirrors the walls beside it: red on the left, green on the right.
        floor_left, floor_right = mean(on, (570, 440, 690, 470)), mean(on, (910, 440, 1030, 470))
        check(floor_left[0] > floor_left[1] * 1.5 and floor_right[1] > floor_right[0] * 1.5, f'the room\'s polished floor mirrors its walls, red on the left and green on the right ({tuple(round(c) for c in floor_left)}, {tuple(round(c) for c in floor_right)})')
        # Image-based ambient light: a copy of the scene with Ambient From Surroundings on. The room's ceiling, which
        # no light shines on directly, gets light back from the room (the probe) instead of the ambient colours.
        scene = (sandbox / 'src/Scenes/Reflections.tscene').read_text()
        copy = sandbox / 'src/Scenes/_ReflectionsAmbient.tscene'
        copy.write_text(scene.replace('env shadowDistance 60\n', 'env shadowDistance 60\nenv ambientFromSurroundings 1\n', 1))
        try:
            shot = Path(folder) / 'ambient.png'
            subprocess.run([str(binary), '--scene', 'Scenes/_ReflectionsAmbient.tscene', '--frames', '60', '--screenshot', str(shot)], cwd=sandbox, capture_output=True, timeout=180)
        finally:
            copy.unlink(missing_ok=True)
        if shot.exists():
            ambient = Image.open(shot).convert('RGB').resize((1600, 900))
            ceiling = (540, 218, 640, 232)
            before, after = sum(mean(on, ceiling)), sum(mean(ambient, ceiling))
            check(after > before * 1.1, f'ambient from surroundings lights the ceiling with the room\'s own light ({after:.0f} against {before:.0f} from the ambient colours)')
        else:
            check(False, 'a picture with ambient light from the surroundings')
    print(f'\n{failures} failure(s)')
    return 0 if failures == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
