"""
Smart Energy Meter - 5-module DIN-rail enclosure (DIN 43880 built-in size 1 profile)
FDM 3D-printable. All units mm.

Enclosure frame:  X = along the DIN rail (width), Y = up (height), Z = out of the panel (depth).
Z = 0 is the rail contact plane (top of the TS35 flanges).
Board frame -> enclosure frame:  X = bx + OX,  Y = by + OY,  Z = bz + ZB  (bz = 0 at PCB bottom face)
"""
import cadquery as cq
import math

# ---------------- global parameters ----------------
W, H = 87.5, 90.0          # 5 modules x 17.5 mm, DIN height
WALL = 2.0
Z_FOOT = 2.5               # DIN foot plate thickness (Z 0..2.5)
Z_BACK = Z_FOOT            # base back wall bottom face
Z_BACK_IN = Z_BACK + WALL  # 4.5 inner face of back wall
Z_SH = 44.0                # shoulder (panel-cover) plane  - DIN 43880
Z_FRONT = 55.0             # front of the 45 mm window      - DIN 43880 size 1
Z_TOPWALL = Z_SH - WALL    # 42 : top of the Y walls, cover strips sit here
HUMP_Y0, HUMP_Y1 = 22.5, 67.5
OX, OY, ZB = 8.7, 7.5, 10.0   # PCB placement (board bottom at Z=10)
PCB_T = 1.6
CL = 0.15                  # sliding clearance for printed fits

FONT_B = '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf'
FONT_M = '/usr/share/fonts/truetype/google-fonts/Poppins-Medium.ttf'

def b2e(bx, by):
    return (bx + OX, by + OY)

def box(x0, x1, y0, y1, z0, z1):
    return cq.Workplane('XY').box(x1 - x0, y1 - y0, z1 - z0, centered=False).translate((x0, y0, z0))

def cyl(x, y, z0, z1, d):
    return cq.Workplane('XY').circle(d / 2).extrude(z1 - z0).translate((x, y, z0))

# ---------------- key positions (enclosure coords) ----------------
PCB_HOLES = [b2e(2.5, 72.5), b2e(72.5, 2.5)]                     # M2 board screws
FOOT_SCREWS = [b2e(4.5, 17.5), b2e(5.0, 61.5), b2e(28.0, 8.0), b2e(66.0, 9.0)]  # SELV zone, >=7 mm from mains copper
SUPPORT_POSTS = [b2e(68.5, 64.0), b2e(72.0, 66.0), b2e(23.5, 72.0), b2e(32.0, 66.0)]  # under P1 / J1
COVER_SCREWS = [(20.0, 3.9), (67.5, 3.9), (8.0, 86.1), (30.0, 86.1)]  # top-right kept away from mains (F1/P1)
LED_D1, LED_D2 = b2e(3.70, 33.0), b2e(3.80, 42.0)
P1_L, P1_N = b2e(66.0, 70.4)[0], b2e(71.0, 70.4)[0]          # X of L and N terminal entries
P1_SCREW_Y = b2e(0, 70.4)[1]
J1_X = b2e(28.75, 0)[0]
SLOT_X = b2e(35.25, 0)[0]                                       # PCB isolation slot (34.5..36 x 68.25..73.25)
WIRE_Z = ZB + PCB_T + 4.5
CT_Z = 27.0


# =====================================================================
# BASE  (printed back-face down, no supports)
# =====================================================================
def make_base():
    # outer shell up to the shoulder
    outer = box(0, W, 0, H, Z_BACK, Z_SH).edges('|Z').fillet(2.5)
    inner = box(WALL, W - WALL, WALL, H - WALL, Z_BACK_IN, Z_SH + 1).edges('|Z').fillet(0.8)
    base = outer.cut(inner)
    # Y walls (top/bottom) stop at Z=42 so the cover strips sit on them
    base = base.cut(box(WALL, W - WALL, -1, H + 1, Z_TOPWALL, Z_SH + 1))
    # X end-walls continue up to the front in the hump zone (DIN profile)
    for x0 in (0, W - WALL):
        cheek = box(x0, x0 + WALL, HUMP_Y0, HUMP_Y1, Z_SH - 0.01, Z_FRONT)
        cheek = cheek.edges('|X').fillet(1.0)
        base = base.union(cheek)
    # soften outer top edges of the cheeks
    try:
        base = base.faces('>Z').edges('|Y').fillet(0.8)
    except Exception:
        pass

    # --- cover screw columns with M3 heat-set inserts ---
    for (x, y) in COVER_SCREWS:
        col = cyl(x, y, Z_BACK_IN - 0.01, Z_TOPWALL, 6.4)
        clip = box(x - 4, x + 4, 0 if y < 45 else 83.0, 7.0 if y < 45 else H, 0, 50)
        col = col.intersect(clip)
        base = base.union(col)
        base = base.cut(cyl(x, y, Z_TOPWALL - 5.5, Z_TOPWALL + 1, 4.0))   # insert M3x5.7 (OD 4.6 -> 4.0 hole)

    # --- PCB bosses (M2 thread-forming screws) ---
    for (x, y) in PCB_HOLES:
        base = base.union(cyl(x, y, Z_BACK_IN - 0.01, ZB, 6.0))
        base = base.cut(cyl(x, y, ZB - 6.0, ZB + 1, 1.7))

    # --- DIN-foot screw bosses (M3 insert from the back) also support the PCB ---
    for (x, y) in FOOT_SCREWS:
        base = base.union(cyl(x, y, Z_BACK_IN - 0.01, ZB, 7.0))
        base = base.cut(cyl(x, y, Z_BACK - 1, Z_BACK + 6.0, 4.0))

    # --- plain support posts under terminal block / CT connector ---
    for (x, y) in SUPPORT_POSTS:
        base = base.union(cyl(x, y, Z_BACK_IN - 0.01, ZB, 4.0))

    # --- isolation barrier: passes through the PCB slot between J1 (CT, SELV) and F1 (mains) ---
    rib_t = 1.1
    base = base.union(box(SLOT_X - rib_t / 2, SLOT_X + rib_t / 2, b2e(0, 68.45)[1], b2e(0, 73.05)[1], Z_BACK_IN - 0.01, Z_TOPWALL - 4))
    # second piece beyond the PCB edge (board must slide past it during assembly -> no rib over board copper)
    base = base.union(box(SLOT_X - rib_t / 2, SLOT_X + rib_t / 2, OY + 75.0 + 0.4, H - WALL + 0.01, Z_BACK_IN - 0.01, Z_TOPWALL - 4))

    # --- top wall: mains wire entries (L, N) and CT cable exit ---
    for x in (P1_L, P1_N):
        base = base.cut(cq.Workplane('XZ').center(x, WIRE_Z).circle(2.25).extrude(-10).translate((0, H - 4, 0)))
    base = base.cut(cq.Workplane('XZ').center(J1_X, CT_Z).circle(2.6).extrude(-10).translate((0, H - 4, 0)))

    # --- ventilation slots (bottom wall: full width; top wall: SELV side only) ---
    for i in range(6):
        x = 26 + i * 7.0
        base = base.cut(box(x - 0.8, x + 0.8, -1, WALL + 1, 18, 34).edges('|Y').fillet(0.75))
    for x in (14, 19, 24):
        base = base.cut(box(x - 0.8, x + 0.8, H - WALL - 1, H + 1, 18, 34).edges('|Y').fillet(0.75))

    # --- foot screw through-holes in back wall are part of the insert holes above ---
    # --- side rating-label recess (left end wall, outside) 0.3 mm ---
    base = base.cut(box(-1, 0.3, 30, 76, 8, 40))
    return base


# =====================================================================
# COVER  (shoulder strips + 45 mm window hump) - a constant profile along X,
# printed standing on its end face (X) -> zero supports.
# =====================================================================
def make_cover():
    x0, x1 = WALL + CL, W - WALL - CL
    L = x1 - x0
    t = WALL
    # 2D profile in the YZ plane
    pts = [
        (0, Z_TOPWALL), (HUMP_Y0, Z_TOPWALL),            # bottom strip underside
        (HUMP_Y0, Z_FRONT - t),                           # hump inner bottom wall
        (HUMP_Y1, Z_FRONT - t),                           # inner front
        (HUMP_Y1, Z_TOPWALL),                             # down to top strip
        (H, Z_TOPWALL), (H, Z_SH),                        # top strip
        (HUMP_Y1 + t, Z_SH), (HUMP_Y1 + t, Z_FRONT),       # outer hump top wall
        (HUMP_Y0 - t, Z_FRONT), (HUMP_Y0 - t, Z_SH),       # outer front, outer hump bottom wall
        (0, Z_SH),
    ]
    # the hump walls are 2 mm: inner hump spans HUMP_Y0..HUMP_Y1, outer HUMP_Y0-2..HUMP_Y1+2
    # -> 49 mm outside. DIN43880 asks for max 45 mm, so shrink: inner 20.5..69.5 is too big; use outer = 45.
    pts = [
        (0, Z_TOPWALL), (HUMP_Y0 + t, Z_TOPWALL),
        (HUMP_Y0 + t, Z_FRONT - t), (HUMP_Y1 - t, Z_FRONT - t),
        (HUMP_Y1 - t, Z_TOPWALL), (H, Z_TOPWALL), (H, Z_SH),
        (HUMP_Y1, Z_SH), (HUMP_Y1, Z_FRONT), (HUMP_Y0, Z_FRONT), (HUMP_Y0, Z_SH), (0, Z_SH),
    ]
    prof = cq.Workplane('YZ').polyline(pts).close().extrude(L).translate((x0, 0, 0))
    # round the front edges of the window and the shoulder corners
    prof = prof.edges('|X').edges(cq.selectors.BoxSelector((x0 - 1, HUMP_Y0 - 0.1, Z_FRONT - 0.1), (x1 + 1, HUMP_Y1 + 0.1, Z_FRONT + 0.1))).fillet(1.6)
    cover = prof

    # registration lips that drop inside the top/bottom walls
    for (y0, y1) in ((WALL + 0.25, WALL + 1.45), (H - WALL - 1.45, H - WALL - 0.25)):
        lip = box(x0 + 1, x1 - 1, y0, y1, Z_TOPWALL - 3.0, Z_TOPWALL + 0.01)
        cover = cover.union(lip)
    # clear lips around the screw columns
    for (x, y) in COVER_SCREWS:
        cover = cover.cut(cyl(x, y, Z_TOPWALL - 4, Z_TOPWALL, 7.6))

    # screw holes M3 button head (ISO 7380) + 0.4 deep spot-face
    for (x, y) in COVER_SCREWS:
        cover = cover.cut(cyl(x, y, Z_TOPWALL - 1, Z_SH + 1, 3.4))
        cover = cover.cut(cyl(x, y, Z_SH - 0.4, Z_SH + 1, 6.4))

    # screwdriver access to the mains terminal screws (P1)
    for x in (P1_L, P1_N):
        cover = cover.cut(cyl(x, P1_SCREW_Y, Z_TOPWALL - 1, Z_SH + 1, 4.6))

    # light-pipe holes for the two LEDs (3 mm PMMA rod, press fit)
    for (x, y) in (LED_D1, LED_D2):
        cover = cover.cut(cyl(x, y, Z_FRONT - t - 1, Z_FRONT + 1, 3.05))

    # front label recess 0.3 mm (label 80 x 41 mm)
    cx = W / 2
    cover = cover.cut(box(cx - 40.1, cx + 40.1, 45 - 20.6, 45 + 20.6, Z_FRONT - 0.3, Z_FRONT + 1).edges('|Z').fillet(1.5))

    # debossed markings on the top shoulder strip (0.5 mm)
    def deboss(text, x, y, size, font=FONT_B):
        txt = (cq.Workplane('XY').workplane(offset=Z_SH - 0.5)
               .center(x, y).text(text, size, 1.0, combine=False, fontPath=font, halign='center', valign='center'))
        return txt
    cover = cover.cut(deboss('L', P1_L, P1_SCREW_Y - 5.5, 3.2))
    cover = cover.cut(deboss('N', P1_N, P1_SCREW_Y - 5.5, 3.2))
    cover = cover.cut(deboss('CT', J1_X, 80.0, 3.0))
    # mains hazard triangle next to terminals
    tri = (cq.Workplane('XY').workplane(offset=Z_SH - 0.5).center(58.0, P1_SCREW_Y)
           .polyline([(-3.2, -2.6), (3.2, -2.6), (0, 3.0)]).close().extrude(1))
    tri_in = (cq.Workplane('XY').workplane(offset=Z_SH - 0.5).center(58.0, P1_SCREW_Y)
              .polyline([(-1.9, -1.75), (1.9, -1.75), (0, 1.55)]).close().extrude(1))
    cover = cover.cut(tri.cut(tri_in))
    cover = cover.cut(deboss('230V~', 58.0, P1_SCREW_Y - 5.5, 2.4, FONT_M))
    # model text on bottom strip
    cover = cover.cut(deboss('SEM-1', W / 2, 12.0, 3.2, FONT_B))
    return cover


# =====================================================================
# LIGHT-PIPE CARRIER  (sits on PCB over D1/D2, holds two 3 mm PMMA rods)
# =====================================================================
def make_lightpipe_carrier():
    (x1, y1), (x2, y2) = LED_D1, LED_D2
    xc = (x1 + x2) / 2
    z0 = ZB + PCB_T + 0.05
    z1 = Z_FRONT - WALL - 0.2
    blk = box(xc - 3.3, xc + 3.3, y1 - 3.4, y2 + 3.4, z0, z1).edges('|Z').fillet(1.2)
    for (x, y) in (LED_D1, LED_D2):
        blk = blk.cut(cyl(x, y, z0 - 1, z0 + 6.6, 3.9))     # LED pocket (3 mm LED, 5.6 mm tall)
        blk = blk.cut(cyl(x, y, z0 + 6.4, z1 + 1, 3.15))    # rod bore
    # relief for LED leads/pads at the bottom
    blk = blk.cut(box(xc - 3.4, xc + 3.4, y1 - 2.0, y2 + 2.0, z0 - 1, z0 + 0.6))
    return blk


def make_rods():
    rods = None
    for (x, y) in (LED_D1, LED_D2):
        z0 = ZB + PCB_T + 0.05 + 6.6
        r = cyl(x, y, z0, Z_FRONT - 0.05, 3.0)
        rods = r if rods is None else rods.union(r)
    return rods


# =====================================================================
# DIN FOOT  (TS35 / EN 60715). Fixed top hooks + compliant bottom latch.
# Printed rail-side UP (flat face on bed). PETG recommended for the spring.
# =====================================================================
FLANGE_TOP = (58.5, 62.5)   # TS35 centred on Y=45 -> flanges 27.5..31.5 and 58.5..62.5, 1 mm thick
FLANGE_BOT = (27.5, 31.5)

def make_foot():
    fx0, fx1, fy0, fy1 = 7.0, 80.5, 0.0, 76.0
    plate = box(fx0, fx1, fy0, fy1, 0, Z_FOOT).edges('|Z').fillet(2.0)
    # --- latch cut-out (beam + hook block + pull arm, 0.6 mm gap) ---
    bx0, bx1, by0, by1 = 20.0, 50.0, 22.0, 25.0          # cantilever beam
    hx0, hx1, hy0, hy1 = 50.0, 62.0, 22.0, 27.4          # hook block
    ax0, ax1 = 53.0, 59.0                                # pull arm (down to Y=-3.5)
    g = 0.6
    plate = plate.cut(box(bx0 - g, hx1 + g, by0 - 2.6, hy1 + g, -1, Z_FOOT + 1))
    plate = plate.cut(box(ax0 - g, ax1 + g, -5, by0, -1, Z_FOOT + 1))
    zt = Z_FOOT - 0.25   # moving parts 0.25 thinner -> no rubbing on the base
    beam = box(bx0 - 0.01, bx1 + 0.01, by0, by1, 0, zt)
    block = box(hx0, hx1, hy0, hy1, 0, zt)
    arm = box(ax0, ax1, -3.5, hy0 + 0.01, 0, zt)
    eye = box(ax0 + 1.2, ax1 - 1.2, -2.8, -0.8, -1, 5)      # screwdriver slot
    latch = beam.union(block).union(arm).cut(eye)
    # hook lip behind the bottom flange, with an entry ramp
    lip_pts = [(hy1 - 0.01, 0.0), (hy1 - 0.01, -1.1), (29.0, -1.1), (29.0, -1.35), (27.4, -2.7), (hy0 + 1.0, -2.7), (hy0 + 1.0, 0.0)]
    lip = cq.Workplane('YZ').polyline(lip_pts).close().extrude(hx1 - hx0 - 2).translate((hx0 + 1, 0, 0))
    latch = latch.union(lip)
    foot = plate.union(latch)
    # --- fixed top hooks ---
    for (x0, x1) in ((14.0, 30.0), (57.5, 73.5)):
        pts = [(62.6, 0.0), (62.6, -1.1), (61.0, -1.1), (61.0, -2.0), (61.7, -2.7), (64.8, -2.7), (64.8, 0.0)]
        hook = cq.Workplane('YZ').polyline(pts).close().extrude(x1 - x0).translate((x0, 0, 0))
        foot = foot.union(hook)
    # --- countersunk M3 screw holes (heads on the rail side, flush) ---
    for (x, y) in FOOT_SCREWS:
        foot = foot.cut(cyl(x, y, -1, Z_FOOT + 1, 3.4))
        cone = cq.Workplane('XY').circle(3.2).workplane(offset=1.7).circle(1.7).loft().translate((x, y, -0.01))
        foot = foot.cut(cone)
    return foot


def make_pcb_placeholder():
    import cadquery as cq
    pcb = cq.importers.importStep('/tmp/w/enc/pcb_only.step')
    return pcb.translate((OX, OY, ZB))


if __name__ == '__main__':
    import time
    t = time.time()
    parts = {
        'base': make_base(),
        'cover': make_cover(),
        'lightpipe_carrier': make_lightpipe_carrier(),
        'din_foot': make_foot(),
        'light_rods_PMMA': make_rods(),
    }
    for k, v in parts.items():
        bb = v.val().BoundingBox()
        print(k, 'valid', v.val().isValid(), 'bbox', [round(a, 2) for a in (bb.xmin, bb.xmax, bb.ymin, bb.ymax, bb.zmin, bb.zmax)], 'vol', round(v.val().Volume() / 1000, 1), 'cm3')
        cq.exporters.export(v, f'/tmp/w/enc/{k}.step')
    print('time', time.time() - t)
