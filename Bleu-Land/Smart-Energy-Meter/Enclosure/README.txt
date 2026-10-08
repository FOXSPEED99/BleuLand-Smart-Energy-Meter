SEM-1 ENCLOSURE  -  Rev A  (4 Oct 2026)
5-module DIN-rail case (DIN 43880 size 1: 87.5 x 90 x 55 mm), FDM 3D-printed.

PRINT  (STL files are already in print orientation - place as-is)
  01_base          back face down          PETG V-0 / ASA-FR, anthracite
  02_cover         standing on its end     same material, 6 mm brim
  03_din_foot      rail side up            PETG (must flex), 100 % infill on latch beam
  04_lightpipe     upright                 any opaque filament
  0.2 mm layers, 4 perimeters, 30 % gyroid, 0.4 mm nozzle. Do NOT use PLA (mains enclosure).

HARDWARE
  8x heat-set insert M3 x 5.7 (hole 4.0)   4 cover columns (from front) + 4 foot bosses (from back)
  4x M3 x 6 button head ISO 7380            cover -> base
  4x M3 x 8 countersunk ISO 10642           DIN foot -> base
  2x M2 x 6 thread-forming for plastics     PCB -> base
  2x clear PMMA rod D3.0 x 36.7 mm          light pipes (polish ends)
  Labels: front 80x41 mm, rating 46x32 mm (matte polyester + laminate, LED holes die-cut D3.2)

ASSEMBLY
  1 inserts  2 PCB (rib goes through PCB slot), 2x M2  3 CT lead out through CT hole, light-pipe carrier on D1/D2
  4 cover 4x M3x6, push rods in  5 DIN foot 4x M3x8  6 labels + S/N  7 hipot + function test

SOURCE
  Source/enclosure.py  parametric CadQuery model (python3 enclosure.py -> STEP files)
  Source/board.py      rebuilds the PCB + component 3D models from Energy-Meter.PcbDoc
