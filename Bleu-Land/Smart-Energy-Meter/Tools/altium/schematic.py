"""Point P1 (SchDoc) and its library part (SchLib) at the 2EDGR header."""
import struct, sys
import cfb

OLD_LIB, NEW_LIB = '282837-2', '2EDGR-5.08-02P'
OLD_FP, NEW_FP = 'TE_282837-2', '2EDGR-5.08-02P'
DESC = ('Pluggable terminal block, PCB header 2EDGR, 2 positions, 5.08 mm, right angle, '
        '300 V 15 A (mates with 2EDGK plug)')
MFR, MPN = 'Cixi Kefa Elec', 'KF2EDGR-5.08-2P'


def split(d):
    out, i = [], 0
    while i < len(d):
        L = struct.unpack_from('<I', d, i)[0]
        out.append([L >> 24, d[i + 4:i + 4 + (L & 0xFFFFFF)]]); i += 4 + (L & 0xFFFFFF)
    return out


def join(recs):
    return b''.join(struct.pack('<I', (t << 24) | len(r)) + r for t, r in recs)


def edit(rec, sets=None, drop=()):
    """rec: b'|K=V|K=V\\0'. Replace values of existing keys, drop keys; keeps order."""
    assert rec.endswith(b'\0')
    parts = rec[:-1].split(b'|')
    out, seen = [], set()
    for p in parts:
        k = p.split(b'=', 1)[0].decode('latin1') if b'=' in p else None
        if k in drop:
            continue
        if k is not None and sets and k in sets:
            p = (k + '=' + sets[k]).encode('latin1'); seen.add(k)
        out.append(p)
    missing = set(sets or {}) - seen
    assert not missing, missing
    return b'|'.join(out) + b'\0'


def fix_component(recs, first, last):
    """Edit one component's records (first..last inclusive)."""
    n = 0
    for k in range(first, last + 1):
        t, r = recs[k]
        if t != 0:
            continue
        if b'|RECORD=1|' in r:
            sets = {'LibReference': NEW_LIB, 'ComponentDescription': DESC}
            if b'|DesignItemId=' in r: sets['DesignItemId'] = NEW_LIB
            if b'|SourceLibraryName=' in r: sets['SourceLibraryName'] = 'Smart-Energy-Meter.SCHLIB'
            # the Russian description is stored twice (UTF-8 copy + ANSI copy): keep one, in English
            r = edit(r, sets, drop={'%UTF8%ComponentDescription'})
            r = r.replace(b'|||', b'|')  # empty fields left by the dropped UTF-8 copy
            n += 1
        elif b'|Name=Manufacturer|' in r:
            r = edit(r, {'Text': MFR}); n += 1
        elif b'|Name=Manufacturer Part Number|' in r:
            r = edit(r, {'Text': MPN}); n += 1
        elif b'|RECORD=45|' in r and OLD_FP.encode() in r:
            r = edit(r, {'ModelName': NEW_FP, 'ModelDatafileEntity0': NEW_FP}); n += 1
        recs[k][1] = r
    return n


def schdoc(tree):
    recs = split(tree['FileHeader'])
    comp = next(k for k, (t, r) in enumerate(recs) if t == 0 and r.startswith(b'|RECORD=1|LibReference=' + OLD_LIB.encode() + b'|'))
    # children: everything after it up to the next component record
    end = next(k for k in range(comp + 1, len(recs)) if recs[k][1].startswith(b'|RECORD=1|')) - 1
    assert any(b'|Text=P1|' in r for _, r in recs[comp:end + 1])
    n = fix_component(recs, comp, end)
    assert n == 4, n
    tree['FileHeader'] = join(recs)
    return comp, end


def schlib(tree):
    st = tree.pop(OLD_LIB)
    recs = split(st['Data'])
    n = fix_component(recs, 0, len(recs) - 1)
    assert n == 4, n
    st['Data'] = join(recs)
    tree[NEW_LIB] = st
    fh = split(tree['FileHeader'])
    t, r = fh[0]
    parts = r[:-1].split(b'|')
    idx = next(p.split(b'=')[0][6:] for p in parts if p.startswith(b'LibRef') and p.endswith(b'=' + OLD_LIB.encode()))
    i = idx.decode()
    r = edit(r, {'LibRef' + i: NEW_LIB, 'CompDescr' + i: DESC}, drop={'%UTF8%CompDescr' + i})
    r = r.replace(b'|||', b'|')
    fh[0][1] = r
    tree['FileHeader'] = join(fh)


if __name__ == '__main__':
    base, out = sys.argv[1], sys.argv[2]
    t = cfb.read_tree(base + '/Energy-Meter.SchDoc'); print('SchDoc P1 records', schdoc(t)); cfb.write_tree(t, out + '/new_Energy-Meter.SchDoc')
    t = cfb.read_tree(base + '/Smart-Energy-Meter.SCHLIB'); schlib(t); cfb.write_tree(t, out + '/new_Smart-Energy-Meter.SCHLIB')
    print('done')
