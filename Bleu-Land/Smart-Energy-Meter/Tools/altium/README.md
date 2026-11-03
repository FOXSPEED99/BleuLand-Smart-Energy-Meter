# Altium file tools

Small Python scripts that edit the Altium files in this folder without Altium
(Altium files are "compound files": a little file system of streams inside one file).

- `cfb.py`: reads and writes compound files (`read_tree`, `write_tree`). Round-trip
  tested on the SchDoc, SchLib and PcbLib: every stream comes back byte-identical.
  It can't write files over ~7 MB (the PcbDoc), so the PcbDoc is changed in Altium.
- `check.py`: strict validation of a written file (structure and directory tree).
- `footprint.py`: added `2EDGR-5.08-02P` to `Energy-Meter.PcbLib`.
- `schematic.py`: pointed P1 (SchDoc) and its SchLib part at that footprint.

Needs `pip install olefile`. Example: `python3 footprint.py ../../Energy-Meter.PcbLib out.PcbLib`.
