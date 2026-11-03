"""Add the 2EDGR-5.08-02P footprint to Energy-Meter.PcbLib by cloning the
record formats of TE_282837-2 (same library, same Altium version).

Geometry: Phoenix MSTBA 2,5/2-G-5,08 pattern (the design 2EDGR headers copy),
from KiCad's official PhoenixContact_MSTBA_2,5_2-G-5,08 footprint:
pins 1x2, pitch 5.08, drill 1.4, pads 2.08 x 3.6 oval; body 12.16 x 12.0,
pins 2.0 mm from the back, 10.0 mm from the mating (plug) face.
Origin between the pins (like TE_282837-2), plug face toward +Y.
"""
import struct, uuid, random, string, sys
import cfb

NAME = '2EDGR-5.08-02P'
DESC = ('Pluggable terminal block header 2EDGR, 2 pos, 5.08 mm, right angle, '
        '1.4 mm holes (Phoenix MSTBA 2,5/2-G-5,08 pattern); mates with 2EDGK plug')
HEIGHT_MM = 8.6


def U(mm):  # mm -> Altium internal units (1/10000 mil)
    return int(round(mm / 0.0254 * 10000))


def mil(mm):
    return '%.4fmil' % (mm / 0.0254)


def records(d):
    """Split a footprint Data stream into (type, payload-or-subblocks)."""
    n = struct.unpack_from('<I', d, 0)[0]
    i, out = 4 + n, []
    while i < len(d):
        t = d[i]; i += 1
        if t == 2:
            subs = []
            for _ in range(6):
                L = struct.unpack_from('<I', d, i)[0]; subs.append(d[i + 4:i + 4 + L]); i += 4 + L
            out.append((t, subs))
        else:
            L = struct.unpack_from('<I', d, i)[0]; out.append((t, d[i + 4:i + 4 + L])); i += 4 + L
    return out


def block(b):
    return struct.pack('<I', len(b)) + b


def build(tree):
    te = tree['TE_282837-2']
    recs = records(te['Data'])
    arc_t = next(p for t, p in recs if t == 1)
    pads_t = [p for t, p in recs if t == 2]
    tracks_t = {p[0]: p for t, p in recs if t == 4}          # one template per layer
    body_t = next(p for t, p in recs if t == 12)

    prims = []  # (type, bytes-without-type)

    # pin-1 dot on the assembly layer (Mechanical 13), like the TE footprint
    a = bytearray(arc_t)
    struct.pack_into('<iii', a, 13, U(-2.54), U(-2.6), U(0.1))
    prims.append((1, block(bytes(a))))

    # pads: 1 rectangular (pin 1), 2 oval
    for k, (x, shape) in enumerate(((-2.54, 2), (2.54, 1))):
        subs = list(pads_t[k])
        m = bytearray(subs[4])
        struct.pack_into('<ii', m, 13, U(x), 0)
        struct.pack_into('<6i', m, 21, U(2.08), U(3.6), U(2.08), U(3.6), U(2.08), U(3.6))
        struct.pack_into('<i', m, 45, U(1.4))
        m[49] = m[50] = m[51] = shape
        subs[4] = bytes(m)
        prims.append((2, b''.join(block(s) for s in subs)))

    def track(layer, x1, y1, x2, y2, w):
        t = bytearray(tracks_t[layer])
        struct.pack_into('<5i', t, 13, U(x1), U(y1), U(x2), U(y2), U(w))
        prims.append((4, block(bytes(t))))

    def rect(layer, x1, y1, x2, y2, w):
        track(layer, x1, y1, x2, y1, w); track(layer, x2, y1, x2, y2, w)
        track(layer, x2, y2, x1, y2, w); track(layer, x1, y2, x1, y1, w)

    SILK, ASSY, CRTYD = 0x21, 0x45, 0x47
    # silkscreen: body outline, the plug-face lip, pin-1 arrow behind pad 1
    rect(SILK, -6.19, -2.11, 6.19, 10.11, 0.127)
    track(SILK, -6.19, 8.61, 6.19, 8.61, 0.127)
    track(SILK, -2.84, -2.91, -2.24, -2.91, 0.127)
    track(SILK, -2.24, -2.91, -2.54, -2.41, 0.127)
    track(SILK, -2.54, -2.41, -2.84, -2.91, 0.127)
    # assembly outline = body; courtyard = body + 0.5 mm
    rect(ASSY, -6.08, -2.0, 6.08, 10.0, 0.1)
    rect(CRTYD, -6.58, -2.5, 6.58, 10.5, 0.05)

    # extruded 3D body: header 12.16 x 12.0 x 8.6 mm, green
    p = body_t
    j = p.find(b'V7_LAYER')
    head = bytearray(p[:j - 4])
    txt = ('V7_LAYER=MECHANICAL13|NAME= |KIND=0|SUBPOLYINDEX=-1|UNIONINDEX=0|ARCRESOLUTION=0.5mil|'
           'ISSHAPEBASED=FALSE|CAVITYHEIGHT=0mil|STANDOFFHEIGHT=0mil|OVERALLHEIGHT=%s|BODYPROJECTION=0|'
           'ARCRESOLUTION=0.5mil|BODYCOLOR3D=%d|BODYOPACITY3D=1.000|IDENTIFIER=|TEXTURE=|TEXTURECENTERX=0mil|'
           'TEXTURECENTERY=0mil|TEXTURESIZEX=0mil|TEXTURESIZEY=0mil|TEXTUREROTATION= 3.60000000000000E+0002|'
           'MODELID={%s}|MODEL.CHECKSUM=0|MODEL.EMBED=FALSE|MODEL.NAME=|MODEL.2D.X=0mil|MODEL.2D.Y=0mil|'
           'MODEL.2D.ROTATION=0.000|MODEL.3D.ROTX=0.000|MODEL.3D.ROTY=0.000|MODEL.3D.ROTZ=0.000|MODEL.3D.DZ=0mil|'
           'MODEL.MODELTYPE=0|MODEL.EXTRUDED.MINZ=0mil|MODEL.EXTRUDED.MAXZ=%s'
           % (mil(HEIGHT_MM), 0x50A000, str(uuid.uuid4()).upper(), mil(HEIGHT_MM))).encode() + b'\0'
    verts = [(-6.08, -2.0), (6.08, -2.0), (6.08, 10.0), (-6.08, 10.0)]
    tail = struct.pack('<I', len(verts)) + b''.join(struct.pack('<dd', U(x), U(y)) for x, y in verts)
    body = bytes(head) + struct.pack('<I', len(txt)) + txt + tail
    prims.append((12, block(body)))

    data = block(bytes([len(NAME)]) + NAME.encode())
    for t, b in prims:
        data += bytes([t]) + b

    fp = cfb.Storage()
    fp.clsid = te.clsid
    fp['Data'] = data
    fp['Header'] = struct.pack('<I', len(prims))
    ptxt = ('|PATTERN=%s|HEIGHT=%s|DESCRIPTION=%s|ITEMGUID=|REVISIONGUID=' % (NAME, mil(HEIGHT_MM), DESC)).encode() + b'\0'
    fp['Parameters'] = struct.pack('<I', len(ptxt)) + ptxt
    fp['WideStrings'] = te['WideStrings']

    # primitive GUIDs: (kind, index, guid) like the TE footprint
    kinds = {1: 1, 2: 2, 4: 4, 12: 0x5A}
    g = struct.pack('<II', 0x55, 0) + uuid.uuid4().bytes
    for i, (t, _) in enumerate(prims):
        g += struct.pack('<II', kinds[t], i) + uuid.uuid4().bytes
    pg = cfb.Storage(); pg.clsid = te['PrimitiveGuids'].clsid
    pg['Data'] = g; pg['Header'] = struct.pack('<I', len(prims) + 1)
    fp['PrimitiveGuids'] = pg

    rnd = random.Random(NAME)
    uid = ''
    for k in (1, 2):
        s = ('|PRIMITIVEINDEX=%d|PRIMITIVEOBJECTID=Pad|UNIQUEID=%s' % (k, ''.join(rnd.choice(string.ascii_uppercase) for _ in range(8)))).encode() + b'\0'
        uid += struct.pack('<I', len(s)).decode('latin1') + s.decode('latin1')
    ui = cfb.Storage(); ui.clsid = te['UniqueIDPrimitiveInformation'].clsid
    ui['Data'] = uid.encode('latin1'); ui['Header'] = struct.pack('<I', 2)
    fp['UniqueIDPrimitiveInformation'] = ui
    tree[NAME] = fp

    # library index: footprint list at the end of Library/Data
    lib = tree['Library']
    ld = lib['Data']
    hl = struct.unpack_from('<I', ld, 0)[0]
    pos = 4 + hl
    count = struct.unpack_from('<I', ld, pos)[0]
    names, i = [], pos + 4
    for _ in range(count):
        L = struct.unpack_from('<I', ld, i)[0]; names.append(ld[i + 5:i + 4 + L].decode('latin1')); i += 4 + L
    assert i == len(ld), (i, len(ld))
    assert NAME not in names
    entry = bytes([len(NAME)]) + NAME.encode()
    lib['Data'] = ld[:pos] + struct.pack('<I', count + 1) + ld[pos + 4:] + block(entry)

    toc = lib['ComponentParamsTOC']['Data']
    line = ('Name=%s|Pad Count=2|Height=%.4f|Description=%s\r\n' % (NAME, HEIGHT_MM / 0.0254, DESC)).encode()
    body_toc = toc[4:-1] + line + b'\0' if toc.endswith(b'\0') else toc[4:] + line  # keep the closing null last
    lib['ComponentParamsTOC']['Data'] = struct.pack('<I', len(body_toc)) + body_toc
    return names


if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    t = cfb.read_tree(src)
    names = build(t)
    cfb.write_tree(t, dst)
    print('footprints before:', len(names), '-> added', NAME)
