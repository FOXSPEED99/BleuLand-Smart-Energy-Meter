import sys, olefile, cfb
src, dst = sys.argv[1], sys.argv[2]
t = cfb.read_tree(src)
cfb.write_tree(t, dst)
a, b = olefile.OleFileIO(src), olefile.OleFileIO(dst)
la = sorted('/'.join(x) for x in a.listdir(streams=True, storages=True))
lb = sorted('/'.join(x) for x in b.listdir(streams=True, storages=True))
assert la == lb, (set(la) ^ set(lb))
bad = [p for p in la if a.get_type(p) == olefile.STGTY_STREAM and a.openstream(p).read() != b.openstream(p).read()]
cl = [p for p in la if a.get_type(p) == olefile.STGTY_STORAGE and a.getclsid(p) != b.getclsid(p)]
print(src, 'entries', len(la), 'stream mismatches', len(bad), 'clsid mismatches', len(cl), 'root clsid', a.root.clsid == b.root.clsid)
