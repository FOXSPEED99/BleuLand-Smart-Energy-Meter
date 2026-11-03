"""Minimal compound-file (OLE / CFB v3) reader-tree + writer, for Altium files.

read_tree(path)  -> root dict {name: bytes | dict}, plus clsids/state kept per node
write_tree(root, path)
A storage is a dict (ordered); a stream is bytes. Node metadata (CLSID) is kept
in a side table keyed by path so a round trip keeps everything readers care about.
"""
import struct
import olefile

SECT = 512
MINI = 64
MINI_CUTOFF = 4096
FREE, ENDOFCHAIN, FATSECT, DIFSECT = 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFFD, 0xFFFFFFFC
NOSTREAM = 0xFFFFFFFF


class Storage(dict):
    clsid = b'\0' * 16


def read_tree(path):
    import uuid
    o = olefile.OleFileIO(path)

    def clsid(p):
        c = o.getclsid(p) if p else o.root.clsid
        return uuid.UUID(c).bytes_le if c else b'\0' * 16

    root = Storage()
    root.clsid = clsid('')
    for parts in o.listdir(streams=True, storages=True):
        node = root
        for k, name in enumerate(parts):
            p = '/'.join(parts[:k + 1])
            last = k == len(parts) - 1
            if name not in node:
                if o.get_type(p) == olefile.STGTY_STORAGE:
                    st = Storage()
                    st.clsid = clsid(p)
                    node[name] = st
                else:
                    node[name] = o.openstream(p).read()
            if not last:
                node = node[name]
    o.close()
    return root


def _key(name):
    # CFB sibling order: shorter name first, then upper-cased UTF-16 code units
    return (len(name), name.upper())


def write_tree(root, path):
    # ---- flatten into directory entries
    entries = []  # dicts: name, type, data/children, clsid

    def add(name, node, typ):
        e = {'name': name, 'type': typ, 'node': node, 'left': NOSTREAM, 'right': NOSTREAM,
             'child': NOSTREAM, 'color': 1, 'start': ENDOFCHAIN, 'size': 0,
             'clsid': getattr(node, 'clsid', b'\0' * 16) if typ != 2 else b'\0' * 16}
        entries.append(e)
        idx = len(entries) - 1
        if typ in (1, 5):
            kids = []
            for k in sorted(node.keys(), key=_key):
                v = node[k]
                kids.append(add(k, v, 1 if isinstance(v, dict) else 2))
            e['child'] = _tree(entries, kids)
        return idx

    add('Root Entry', root, 5)

    # ---- data: small streams into the mini stream, big ones into sectors
    mini = bytearray()
    minifat = []
    big = []  # (entry index, data)
    for e in entries:
        if e['type'] != 2:
            continue
        data = e['node']
        e['size'] = len(data)
        if len(data) == 0:
            e['start'] = ENDOFCHAIN
        elif len(data) < MINI_CUTOFF:
            n = (len(data) + MINI - 1) // MINI
            first = len(minifat)
            e['start'] = first
            for k in range(n):
                minifat.append(first + k + 1 if k < n - 1 else ENDOFCHAIN)
            mini += data + b'\0' * (n * MINI - len(data))
        else:
            big.append((e, data))

    def nsect(nbytes):
        return (nbytes + SECT - 1) // SECT

    dir_sectors = nsect(len(entries) * 128)
    minifat_sectors = nsect(len(minifat) * 4)
    mini_sectors = nsect(len(mini))
    data_sectors = sum(nsect(len(d)) for _, d in big)
    payload = dir_sectors + minifat_sectors + mini_sectors + data_sectors
    # FAT sectors needed (each holds 128 entries, including the FAT sectors themselves)
    fat_sectors = 1
    while fat_sectors * 128 < payload + fat_sectors:
        fat_sectors += 1
    if fat_sectors > 109:
        raise ValueError('file too large for this writer (needs DIFAT)')

    fat = []
    sec = 0

    def chain(n, mark=None):
        nonlocal sec
        start = sec
        for k in range(n):
            fat.append(mark if mark is not None else (sec + 1 if k < n - 1 else ENDOFCHAIN))
            sec += 1
        return start if n else ENDOFCHAIN

    fat_start = chain(fat_sectors, FATSECT)
    dir_start = chain(dir_sectors)
    minifat_start = chain(minifat_sectors)
    mini_start = chain(mini_sectors)
    for e, d in big:
        e['start'] = chain(nsect(len(d)))
    fat += [FREE] * (fat_sectors * 128 - len(fat))

    root_e = entries[0]
    root_e['start'] = mini_start if mini_sectors else ENDOFCHAIN
    root_e['size'] = len(mini)

    # ---- header
    hdr = bytearray(512)
    hdr[0:8] = bytes.fromhex('D0CF11E0A1B11AE1')
    struct.pack_into('<HHHHH', hdr, 24, 0x003E, 0x0003, 0xFFFE, 9, 6)
    struct.pack_into('<I', hdr, 44, fat_sectors)
    struct.pack_into('<I', hdr, 48, dir_start)
    struct.pack_into('<I', hdr, 56, MINI_CUTOFF)
    struct.pack_into('<I', hdr, 60, minifat_start if minifat_sectors else ENDOFCHAIN)
    struct.pack_into('<I', hdr, 64, minifat_sectors)
    struct.pack_into('<I', hdr, 68, ENDOFCHAIN)  # no DIFAT sectors
    struct.pack_into('<I', hdr, 72, 0)
    difat = [fat_start + k for k in range(fat_sectors)] + [FREE] * (109 - fat_sectors)
    struct.pack_into('<109I', hdr, 76, *difat)

    out = bytearray(hdr)
    out += struct.pack('<%dI' % len(fat), *fat)
    d = bytearray()
    for e in entries:
        d += _dirent(e)
    while len(d) % SECT:
        d += _dirent(None)
    out += d
    mf = struct.pack('<%dI' % len(minifat), *minifat) if minifat else b''
    out += mf + b'\xff' * (minifat_sectors * SECT - len(mf))
    out += mini + b'\0' * (mini_sectors * SECT - len(mini))
    for _, dat in big:
        out += dat + b'\0' * (nsect(len(dat)) * SECT - len(dat))
    with open(path, 'wb') as f:
        f.write(out)


def _tree(entries, kids):
    """Balanced binary tree over sorted kids; red only on an incomplete last level."""
    if not kids:
        return NOSTREAM
    depth = {}

    def build(lo, hi, dep):
        if lo > hi:
            return NOSTREAM
        mid = (lo + hi) // 2
        i = kids[mid]
        depth[i] = dep
        entries[i]['left'] = build(lo, mid - 1, dep + 1)
        entries[i]['right'] = build(mid + 1, hi, dep + 1)
        return i

    r = build(0, len(kids) - 1, 0)
    maxd = max(depth.values())
    perfect = len(kids) == 2 ** (maxd + 1) - 1
    for i, dep in depth.items():
        entries[i]['color'] = 0 if (dep == maxd and not perfect and maxd > 0) else 1
    return r


def _dirent(e):
    b = bytearray(128)
    if e is None:
        struct.pack_into('<III', b, 68, NOSTREAM, NOSTREAM, NOSTREAM)
        return b
    nm = e['name'].encode('utf-16-le')
    if len(nm) > 62:
        raise ValueError('name too long: ' + e['name'])
    b[0:len(nm)] = nm
    struct.pack_into('<HBB', b, 64, len(nm) + 2, e['type'], e['color'])
    struct.pack_into('<III', b, 68, e['left'], e['right'], e['child'])
    b[80:96] = e['clsid']
    struct.pack_into('<III', b, 116, e['start'], e['size'] & 0xFFFFFFFF, 0)
    return b


def flatten(node, prefix=''):
    out = {}
    for k, v in node.items():
        p = prefix + k
        if isinstance(v, dict):
            out[p + '/'] = None
            out.update(flatten(v, p + '/'))
        else:
            out[p] = v
    return out
