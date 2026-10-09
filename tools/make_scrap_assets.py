#!/usr/bin/env python3
"""Generates the low-poly sample models for the vehicle building game as GLB files.

Usage: make_scrap_assets.py <output folder>
Models are one unit in size, vertex coloured and flat shaded. glTF is right-handed with +Z
towards the viewer; Tessera flips Z on import, so "back" in the engine is +Z here.
"""
import json, math, struct, sys, os

class Mesh:
    def __init__(self):
        self.pos, self.nrm, self.col, self.idx = [], [], [], []

    def tri(self, a, b, c, color, center):
        # Wind counter-clockwise as seen from outside the piece this triangle belongs to.
        n = cross(sub(b, a), sub(c, a))
        mid = [(a[i] + b[i] + c[i]) / 3 for i in range(3)]
        if dot(n, sub(mid, center)) < 0:
            b, c = c, b
            n = [-x for x in n]
        l = math.sqrt(dot(n, n)) or 1.0
        n = [x / l for x in n]
        base = len(self.pos)
        linear = [pow(ch / 255.0, 2.2) for ch in color] + [1.0]
        for p in (a, b, c):
            self.pos.append(p); self.nrm.append(n); self.col.append(linear)
        self.idx += [base, base + 1, base + 2]

    def quad(self, a, b, c, d, color, center):
        self.tri(a, b, c, color, center); self.tri(a, c, d, color, center)

    def box(self, center, size, color):
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        v = [[center[0] + sx * hx, center[1] + sy * hy, center[2] + sz * hz]
             for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.quad(v[f[0]], v[f[1]], v[f[2]], v[f[3]], color, center)

    def cylinder(self, center, axis, r0, r1, length, segments, color, cap_color=None):
        """Frustum along an axis (0 x, 1 y, 2 z) from radius r0 to r1."""
        cap_color = cap_color or color
        def point(t, r, angle):
            p = [0, 0, 0]
            p[axis] = (t - 0.5) * length
            p[(axis + 1) % 3] = math.cos(angle) * r
            p[(axis + 2) % 3] = math.sin(angle) * r
            return [p[i] + center[i] for i in range(3)]
        ends = [list(center), list(center)]
        ends[0][axis] -= length / 2; ends[1][axis] += length / 2
        for s in range(segments):
            a0 = s / segments * math.tau; a1 = (s + 1) / segments * math.tau
            self.quad(point(0, r0, a0), point(0, r0, a1), point(1, r1, a1), point(1, r1, a0), color, center)
            if r0 > 0: self.tri(ends[0], point(0, r0, a0), point(0, r0, a1), cap_color, center)
            if r1 > 0: self.tri(ends[1], point(1, r1, a0), point(1, r1, a1), cap_color, center)

    def write(self, path):
        def pack(rows, fmt): return b''.join(struct.pack(fmt, *r) for r in rows)
        chunks = [pack(self.pos, '<3f'), pack(self.nrm, '<3f'), pack(self.col, '<4f'), struct.pack('<%dI' % len(self.idx), *self.idx)]
        views, offset = [], 0
        for i, c in enumerate(chunks):
            views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(c), "target": 34963 if i == 3 else 34962})
            offset += len(c)
        n = len(self.pos)
        mins = [min(p[i] for p in self.pos) for i in range(3)]
        maxs = [max(p[i] for p in self.pos) for i in range(3)]
        doc = {
            "asset": {"version": "2.0", "generator": "Tessera make_scrap_assets"},
            "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": os.path.basename(path)[:-4]}],
            "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0.9}}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
            "buffers": [{"byteLength": offset}], "bufferViews": views,
            "accessors": [
                {"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": mins, "max": maxs},
                {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
                {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC4"},
                {"bufferView": 3, "componentType": 5125, "count": len(self.idx), "type": "SCALAR"}],
        }
        text = json.dumps(doc, separators=(',', ':')).encode()
        text += b' ' * (-len(text) % 4)
        binary = b''.join(chunks); binary += b'\0' * (-len(binary) % 4)
        with open(path, 'wb') as f:
            f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(text) + 8 + len(binary)))
            f.write(struct.pack('<I4s', len(text), b'JSON')); f.write(text)
            f.write(struct.pack('<I4s', len(binary), b'BIN\0')); f.write(binary)

def sub(a, b): return [a[i] - b[i] for i in range(3)]
def dot(a, b): return sum(a[i] * b[i] for i in range(3))
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

def framed_block(frame, panel, bolt):
    m = Mesh()
    m.box((0, 0, 0), (1, 1, 1), frame)
    for axis in range(3):
        for side in (-1, 1):
            c = [0, 0, 0]; c[axis] = side * 0.5
            s = [0.78, 0.78, 0.78]; s[axis] = 0.04
            m.box(c, s, panel)
            if bolt:
                for u in (-1, 1):
                    for v in (-1, 1):
                        b = list(c); b[(axis + 1) % 3] = u * 0.43; b[(axis + 2) % 3] = v * 0.43
                        bs = [0.07, 0.07, 0.07]; bs[axis] = 0.05
                        m.box(b, bs, bolt)
    return m

def block_plastic(): return framed_block((176, 132, 52), (232, 190, 96), None)
def block_metal(): return framed_block((96, 100, 108), (158, 164, 172), (60, 62, 68))
def block_glass(): return framed_block((120, 150, 170), (176, 222, 240), None)

def block_wood():
    m = Mesh()
    m.box((0, 0, 0), (1, 1, 1), (112, 76, 44))
    # three planks on every face, running along a different axis per face pair
    for axis in range(3):
        along = (axis + 1) % 3
        across = (axis + 2) % 3
        for side in (-1, 1):
            for i, shade in enumerate(((168, 118, 70), (150, 104, 60), (176, 126, 78))):
                c = [0, 0, 0]; c[axis] = side * 0.5; c[across] = (i - 1) * 0.31
                s = [0, 0, 0]; s[axis] = 0.04; s[along] = 0.9; s[across] = 0.27
                m.box(c, s, shade)
    return m

def block_concrete():
    m = Mesh()
    m.box((0, 0, 0), (1, 1, 1), (150, 150, 146))
    # a few shallow chips so the faces are not perfectly flat grey
    for axis in range(3):
        for side in (-1, 1):
            for (u, v, size, shade) in ((-0.22, 0.2, 0.3, (168, 168, 164)), (0.24, -0.18, 0.36, (136, 136, 132)), (0.1, 0.3, 0.16, (176, 176, 172))):
                c = [0, 0, 0]; c[axis] = side * 0.5; c[(axis + 1) % 3] = u; c[(axis + 2) % 3] = v
                s = [size, size, size]; s[axis] = 0.03
                m.box(c, s, shade)
    return m

def wheel():
    m = Mesh()
    m.cylinder((0, 0, 0), 0, 0.75, 0.75, 0.42, 14, (44, 44, 50), (58, 58, 64))      # tyre, axle along X
    m.cylinder((0, 0, 0), 0, 0.42, 0.42, 0.48, 10, (196, 198, 204), (170, 172, 180))  # rim
    m.cylinder((0, 0, 0), 0, 0.14, 0.14, 0.56, 6, (228, 172, 60))                      # hub cap
    for i in range(5):                                                                 # lug nuts on both sides
        a = i / 5 * math.tau
        for side in (-1, 1):
            m.box((side * 0.25, math.cos(a) * 0.27, math.sin(a) * 0.27), (0.05, 0.08, 0.08), (90, 92, 98))
    return m

def thruster():
    m = Mesh()
    m.box((0, -0.3, -0.05), (0.7, 0.4, 0.8), (96, 100, 110))                 # mount
    m.cylinder((0, 0.05, -0.1), 2, 0.34, 0.34, 0.7, 10, (150, 154, 162))     # chamber
    m.cylinder((0, 0.05, 0.38), 2, 0.3, 0.46, 0.3, 10, (196, 72, 60))        # nozzle flares towards the back (+Z here)
    m.cylinder((0, 0.05, 0.45), 2, 0.22, 0.3, 0.12, 10, (255, 170, 60))      # hot inner ring
    m.cylinder((0, 0.05, -0.48), 2, 0.0, 0.34, 0.14, 10, (120, 124, 132))    # nose cone at the front
    return m

def seat():
    m = Mesh()
    cloth, dark, metal = (66, 118, 200), (44, 84, 150), (92, 96, 104)
    m.box((0, -0.38, 0), (0.9, 0.24, 0.9), metal)            # base plate
    m.box((0, -0.14, -0.05), (0.72, 0.24, 0.72), cloth)      # cushion
    m.box((0, 0.22, 0.34), (0.72, 0.7, 0.16), cloth)         # backrest (behind the driver)
    m.box((0, 0.6, 0.34), (0.4, 0.14, 0.14), dark)           # headrest
    for side in (-1, 1):
        m.box((side * 0.4, 0.04, 0.02), (0.1, 0.12, 0.6), dark)  # armrests
    return m

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    for name, build in (('block_plastic', block_plastic), ('block_wood', block_wood), ('block_metal', block_metal),
                        ('block_concrete', block_concrete), ('block_glass', block_glass),
                        ('wheel', wheel), ('thruster', thruster), ('seat', seat)):
        mesh = build()
        mesh.write(os.path.join(out, name + '.glb'))
        print(name, len(mesh.idx) // 3, 'triangles')
