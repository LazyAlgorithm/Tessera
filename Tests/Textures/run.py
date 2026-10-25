#!/usr/bin/env python3
"""Texture compression and picture checks (docs/textures.md). Needs texturec built, Pillow, a graphics card and a
display.

Runs this fixture's CPU checks; compresses a small project with tools/compress_textures.py and checks what it made
(BC1 for opaque pictures and BC3 for see-through ones, plain rather than sRGB, all mip levels; normal maps, excluded
folders and data maps handled); then draws the Sandbox's Textures scene with mip levels and without, and with the
sample's pictures compressed and not, and checks the compressed copies were used and look the same.
"""
import shutil, struct, subprocess, sys, tempfile
from pathlib import Path

here = Path(__file__).resolve().parent
root = here.parent.parent
sandbox = root / 'Samples' / 'Sandbox'
sys.path.insert(0, str(root / 'tools'))
import compress_textures

failures = 0


def check(passed, label):
    global failures
    print(f'{"PASS" if passed else "FAIL"}: {label}')
    failures += 0 if passed else 1


def header(path):
    data = path.read_bytes()[:64]
    internal, = struct.unpack('<I', data[28:32])
    width, height = struct.unpack('<2I', data[36:44])
    mips, = struct.unpack('<I', data[56:60])
    return internal, width, height, mips


def main():
    if subprocess.run(['BeefBuild', '-config=Debug', '-run'], cwd=here).returncode != 0:
        print('FAIL: CPU checks')
        return 1
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print('Pillow is needed (pip install pillow).')
        return 1
    if compress_textures.texturec_path(root) is None:
        print('FAIL: texturec is not built (cmake --build build/native --target texturec)')
        return 1
    with tempfile.TemporaryDirectory() as folder:
        project = Path(folder)
        for name in ('Textures', 'UI', 'Materials'):
            (project / name).mkdir()
        Image.new('RGB', (64, 32), (200, 120, 40)).save(project / 'Textures/wall.png')
        Image.new('RGBA', (32, 32), (255, 255, 255, 90)).save(project / 'Textures/glass.png')
        Image.new('RGB', (32, 32), (128, 128, 255)).save(project / 'Textures/wall_normal.png')
        Image.new('RGB', (32, 32), (128, 128, 255)).save(project / 'Textures/bumps.png')
        Image.new('RGB', (32, 32), (255, 140, 0)).save(project / 'Textures/wall_orm.png')
        Image.new('RGBA', (32, 32), (255, 0, 0, 255)).save(project / 'UI/button.png')
        (project / 'Materials/wall.tmat').write_text('material 1\nnormalMap "Textures/bumps.png"\nmetallicRoughnessMap "Textures/wall_orm.png"\n')
        made, skipped, errors = compress_textures.compress_folder(project, root)
        check(made == 3 and skipped == 3 and not errors, f'three pictures compressed, the two normal maps and the UI picture left alone ({made}, {skipped}, {errors})')
        wall = project / 'Textures/wall.png.ktx'
        check(wall.is_file() and header(wall)[0] == 0x83F1, 'an opaque picture is BC1, marked plain rather than sRGB (the shaders decode sRGB)')
        check(wall.is_file() and header(wall)[1:] == (64, 32, 7), f'with every mip level, 64 x 32 down to 1 x 1 ({header(wall)[1:] if wall.is_file() else None})')
        glass = project / 'Textures/glass.png.ktx'
        check(glass.is_file() and header(glass)[0] == 0x83F3, 'a see-through picture is BC3, keeping its alpha')
        check(not (project / 'Textures/wall_normal.png.ktx').exists() and not (project / 'Textures/bumps.png.ktx').exists(), 'normal maps, by name or by material, are not compressed')
        check(not (project / 'UI/button.png.ktx').exists(), 'excluded folders (UI) are not compressed')
        check((project / 'Textures/wall_orm.png.ktx').is_file(), 'a metal / roughness map is compressed, as data')
        check((project / 'Textures/wall.png').is_file(), 'the pictures themselves stay, for code that reads their pixels')

    if subprocess.run(['BeefBuild', '-config=Debug'], cwd=sandbox).returncode != 0:
        print('FAIL: Sandbox build')
        return 1
    binary = sandbox / 'build' / 'Debug_Linux64' / 'Sandbox' / 'Sandbox'
    textures = sandbox / 'src' / 'Textures'

    def draw(name, folder, *extra, camera=('--camera', '0 1.6 -40 0 25')):
        shot = Path(folder) / f'{name}.png'
        run = subprocess.run([str(binary), '--scene', 'Scenes/Textures.tscene', '--frames', '60', *camera, '--screenshot', str(shot), *extra],
                             cwd=sandbox, capture_output=True, text=True, timeout=180)
        return Image.open(shot).convert('RGB') if shot.exists() else None, run.stdout + run.stderr

    def difference(a, b, box=None):
        if box:
            a, b = a.crop(box), b.crop(box)
        d = ImageChops.difference(a, b).convert('L')
        values = list(d.getdata())
        return sum(values) / len(values)

    with tempfile.TemporaryDirectory() as folder:
        plain, log = draw('plain', folder)
        if plain is None:
            print(f'FAIL: no picture\n{log}')
            return 1
        # Shimmer: the camera moved 3 cm changes the far floor a lot without mip levels (the checks it samples jump
        # about) and little with them. A copy of the scene with its camera moved is drawn and compared.
        scene = (sandbox / 'src/Scenes/Textures.tscene').read_text()
        moved = sandbox / 'src/Scenes/_TexturesMoved.tscene'
        moved.write_text(scene.replace('transform 0 1.6 -40 ', 'transform 0 1.6 -39.97 ', 1))
        try:
            pictures = {}
            for name, scene_name, extra in (('still', 'Textures', ()), ('moved', '_TexturesMoved', ()), ('still-raw', 'Textures', ('--no-mipmaps',)), ('moved-raw', '_TexturesMoved', ('--no-mipmaps',))):
                shot = Path(folder) / f'{name}.png'
                subprocess.run([str(binary), '--scene', f'Scenes/{scene_name}.tscene', '--frames', '60', '--screenshot', str(shot), *extra], cwd=sandbox, capture_output=True, timeout=180)
                pictures[name] = Image.open(shot).convert('RGB') if shot.exists() else None
        finally:
            moved.unlink(missing_ok=True)
        if None in pictures.values():
            print('FAIL: no picture for the shimmer check')
            return 1
        height = pictures['still'].height
        far = (0, int(height * 0.46), pictures['still'].width, int(height * 0.49))
        with_mips = difference(pictures['still'], pictures['moved'], far)
        without = difference(pictures['still-raw'], pictures['moved-raw'], far)
        check(with_mips < without * 0.5, f'with mip levels the far floor hardly shimmers as the camera moves, without them it does ({with_mips:.1f} against {without:.1f})')
        made = []
        try:
            for picture in textures.glob('*.png'):
                if 'normal' not in picture.name:
                    compress_textures.compress(compress_textures.texturec_path(root), picture, False)
                    made.append(picture.with_name(picture.name + '.ktx'))
            compressed, log = draw('compressed', folder)
        finally:
            for file in made:
                file.unlink(missing_ok=True)
        check(compressed is not None and 'compressed' in log and ' 0 compressed' not in log, 'the compressed copies are used where they exist (the log counts them)')
        if compressed is not None:
            change = difference(plain, compressed)
            check(change < 3, f'and look the same as the pictures they were made from (average difference {change:.2f} of 255)')
    print(f'\n{failures} failure(s)')
    return 0 if failures == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
