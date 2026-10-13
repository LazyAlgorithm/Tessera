#!/usr/bin/env python3
"""Checks a web build in a headless browser: the page loads, the game starts and draws, on a desktop screen and on
an emulated phone (touch, small landscape screen), where the on-screen controls must appear and move the player.

    python3 tools/web/test_web.py path/to/Game-Web [--screenshots folder] [--phone-only] [--desktop-only]

Needs Python's Playwright with Chromium (pip install playwright; playwright install chromium). Exits non-zero
when a check fails. Screenshots of each stage go to --screenshots, to look at the layout.
"""
import argparse
import functools
import http.server
import re
import socketserver
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

# WebGL in a headless browser on a machine without a graphics card: Chrome's software renderer.
BROWSER_ARGS = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
                '--autoplay-policy=no-user-gesture-required']


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = dict(http.server.SimpleHTTPRequestHandler.extensions_map, **{'.wasm': 'application/wasm', '.webmanifest': 'application/manifest+json'})

    def log_message(self, *args):
        pass


def serve(folder):
    handler = functools.partial(QuietHandler, directory=str(folder))
    server = socketserver.ThreadingTCPServer(('127.0.0.1', 0), handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class Run:
    def __init__(self, page, name, shots):
        self.page, self.name, self.shots = page, name, shots
        self.log, self.errors, self.failures = [], [], []
        self.watch()

    def watch(self):
        self.page.on('console', lambda message: self.log.append(f'[{message.type}] {message.text}'))
        self.page.on('pageerror', lambda error: self.errors.append(str(error)))

    def shot(self, stage):
        if self.shots:
            self.page.screenshot(path=str(self.shots / f'{self.name}-{stage}.png'), timeout=240000)

    def check(self, ok, what):
        print(f'  {"ok  " if ok else "FAIL"} {what}')
        if not ok:
            self.failures.append(what)

    def wait_for(self, condition, seconds):
        end = time.time() + seconds
        while time.time() < end:
            if condition():
                return True
            self.page.wait_for_timeout(250)
        return False

    def gate(self):
        return self.page.evaluate('document.getElementById("gate").className')

    def status(self):
        return self.page.evaluate('document.getElementById("status").textContent')


def start_game(run, url, stage):
    page = run.page
    page.goto(url)
    run.check(run.wait_for(lambda: 'ready' in run.gate() or 'failed' in run.gate(), 120), 'the game loads and says "Tap to play"')
    run.check('failed' not in run.gate(), f'no load error ({run.status()})')
    # The press goes straight to the page's overlay: headless Chrome hands a game the mouse lock without waiting
    # for a press, which then takes every click (a real browser waits).
    page.evaluate('document.getElementById("gate").dispatchEvent(new PointerEvent("pointerdown", {bubbles: true}))')
    run.check(run.wait_for(lambda: 'gone' in run.gate(), 5), 'the tap starts the game')
    page.wait_for_timeout(SETTLE_MS)
    run.shot(stage)


# A machine without a graphics card draws a frame or two a second; a phone or a desktop with one draws 60.
SETTLE_MS = 6000


def canvas_has_picture(page):
    return len(set(value >> 3 for value in canvas_digest(page)))


def canvas_digest(page):
    # What is on screen, small and grey. (The game's WebGL canvas cannot be read back from script: the browser
    # clears it after each frame.)
    from io import BytesIO
    from PIL import Image
    shot = Image.open(BytesIO(page.screenshot(timeout=240000))).convert('L').resize((96, 54))
    return list(shot.getdata())


def difference(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / max(len(a), 1)


def desktop(browser, url, shots, match):
    print('Desktop (960x540, mouse and keyboard)')
    context = browser.new_context(viewport={'width': 960, 'height': 540})
    run = Run(context.new_page(), 'desktop', shots)
    start_game(run, url, 'menu')
    colours = canvas_has_picture(run.page)
    run.check(colours > 12, f'the menu is drawn ({colours} colours on screen)')
    if match:
        # A new page: leaving one where a game runs can take longer than the browser waits.
        run.page.close()
        run.page = context.new_page()
        run.watch()
        start_game(run, url + '?' + match, 'match')
        colours = canvas_has_picture(run.page)
        run.check(colours > 12, f'a match is drawn ({colours} colours on screen)')
    run.check(not run.errors, 'no script errors' + (': ' + '; '.join(run.errors[:3]) if run.errors else ''))
    aborts = [line for line in run.log if 'Aborted' in line or 'RuntimeError' in line]
    run.check(not aborts, 'the game did not stop' + (': ' + aborts[0] if aborts else ''))
    context.close()
    return run


def phone(browser, playwright, url, shots, match):
    print('Phone (Pixel 7 in landscape, touch)')
    device = dict(playwright.devices['Pixel 7'])
    device['viewport'] = {'width': device['viewport']['height'], 'height': device['viewport']['width']}
    if 'screen' in device:
        device['screen'] = {'width': device['screen']['height'], 'height': device['screen']['width']}
    context = browser.new_context(**device)
    run = Run(context.new_page(), 'phone', shots)
    page = run.page
    start_game(run, url, 'menu')
    colours = canvas_has_picture(page)
    run.check(colours > 12, f'the menu is drawn ({colours} colours on screen)')
    if match:
        page.close()
        page = run.page = context.new_page()
        run.watch()
        start_game(run, url + '?' + match, 'match')
        width, height = page.viewport_size['width'], page.viewport_size['height']
        # Push the move stick forward and hold it: the view should move on.
        touch = context.new_cdp_session(page)
        before = canvas_digest(page)
        start = {'x': width * 0.2, 'y': height * 0.75}
        touch.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [start]})
        for step in range(1, 6):
            touch.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': start['x'], 'y': start['y'] - step * height * 0.03}]})
            page.wait_for_timeout(300)
        run.shot('stick-held')
        page.wait_for_timeout(SETTLE_MS)
        touch.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
        page.wait_for_timeout(1500)
        after = canvas_digest(page)
        run.shot('after-moving')
        change = difference(before, after)
        run.check(change > 2, f'holding the move stick moves the player (the picture changed by {change:.1f})')
        # Drag on the right half: the view turns.
        before = after
        start = {'x': width * 0.7, 'y': height * 0.4}
        touch.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [start]})
        for step in range(1, 8):
            touch.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': start['x'] - step * width * 0.04, 'y': start['y']}]})
            page.wait_for_timeout(400)
        touch.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
        page.wait_for_timeout(SETTLE_MS)
        after = canvas_digest(page)
        run.shot('after-looking')
        change = difference(before, after)
        run.check(change > 2, f'dragging on the right turns the view (the picture changed by {change:.1f})')
    run.check(not run.errors, 'no script errors' + (': ' + '; '.join(run.errors[:3]) if run.errors else ''))
    context.close()
    return run


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('build', type=Path)
    parser.add_argument('--screenshots', type=Path)
    parser.add_argument('--phone-only', action='store_true')
    parser.add_argument('--desktop-only', action='store_true')
    parser.add_argument('--log', action='store_true', help='Print the game\'s console output')
    parser.add_argument('--match', default='arg=--host&arg=--bots&arg=0', help='Address arguments that start a match (empty: menus only)')
    args = parser.parse_args()
    if not (args.build / 'index.html').is_file():
        parser.error(f'{args.build} is not a web build (no index.html).')
    if args.screenshots:
        args.screenshots.mkdir(parents=True, exist_ok=True)
    server = serve(args.build)
    url = f'http://127.0.0.1:{server.server_address[1]}/'
    runs = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=BROWSER_ARGS)
        if not args.phone_only:
            runs.append(desktop(browser, url, args.screenshots, args.match))
        if not args.desktop_only:
            runs.append(phone(browser, playwright, url, args.screenshots, args.match))
        browser.close()
    server.shutdown()
    failures = [f'{run.name}: {failure}' for run in runs for failure in run.failures]
    if args.log or failures:
        for run in runs:
            print(f'--- {run.name} console ---')
            print('\n'.join(run.log[-60:]))
    print('All checks passed.' if not failures else f'{len(failures)} check(s) failed.')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
