-- ============================================================
-- Battle Village Background Generator (Aseprite Lua script)
-- Usage: aseprite -b --script tools/gen_battle_village_bg.lua
--
-- Canvas: 320x180 px, RGB, "Layer 1" frame 1
-- Theme: SNES-style village at dusk
--   1. Dusk sky gradient (top 80px)
--   2. Building silhouettes (y=80-130)
--   3. Cobblestone ground (bottom 60px)
--   4. Warm window glow (6-8 windows)
--   5. Lampposts with glow
--   6. Ground light spill near buildings
-- ============================================================

local REPO = "/home/struktured/projects/cowardly-irregular-sprite-gen"
local SRC  = REPO .. "/tmp/pixel-mcp/sprite-1774580076224993054.aseprite"
local OUT_ASE = REPO .. "/tmp/battle-backgrounds/battle_village.aseprite"
local OUT_PNG = "/home/struktured/projects/cowir-cutscenes/assets/battle_backdrops/battle_village.png"

-- -------------------------------------------------------
-- Open source file
-- -------------------------------------------------------
local spr = app.open(SRC)
if not spr then
  error("Could not open: " .. SRC)
end

local W = spr.width   -- 320
local H = spr.height  -- 180

-- -------------------------------------------------------
-- Helper: get layer 1 image for frame 1
-- -------------------------------------------------------
local layer = spr.layers[1]
local cel   = layer:cel(1)
if not cel then
  error("Layer 1 / frame 1 has no cel")
end
local img = cel.image

-- -------------------------------------------------------
-- Helper: set pixel (clamp to canvas)
-- -------------------------------------------------------
local function px(x, y, r, g, b)
  if x < 0 or x >= W or y < 0 or y >= H then return end
  img:putPixel(x, y, Color{r=r, g=g, b=b, a=255})
end

-- -------------------------------------------------------
-- Helper: filled rectangle
-- -------------------------------------------------------
local function rect(x1, y1, x2, y2, r, g, b)
  for y = y1, y2 do
    for x = x1, x2 do
      px(x, y, r, g, b)
    end
  end
end

-- -------------------------------------------------------
-- Helper: horizontal line
-- -------------------------------------------------------
local function hline(y, x1, x2, r, g, b)
  for x = x1, x2 do
    px(x, y, r, g, b)
  end
end

-- -------------------------------------------------------
-- Helper: lerp integer
-- -------------------------------------------------------
local function lerpi(a, b, t)
  return math.floor(a + (b - a) * t + 0.5)
end

-- -------------------------------------------------------
-- Helper: draw a dithered gradient band between two rows
-- using two colours in a checkerboard (4x1 scanline dither)
-- -------------------------------------------------------
local function dither_band(y1, y2, r1,g1,b1, r2,g2,b2)
  local rows = y2 - y1
  if rows <= 0 then rows = 1 end
  for y = y1, y2 do
    local t = (y - y1) / rows
    local mr = lerpi(r1, r2, t)
    local mg = lerpi(g1, g2, t)
    local mb = lerpi(b1, b2, t)
    -- dither: alternate pixel with slightly lighter shade on even cols
    local dr = math.min(255, mr + 8)
    local dg = math.min(255, mg + 8)
    local db = math.min(255, mb + 8)
    for x = 0, W-1 do
      if (x + y) % 2 == 0 then
        px(x, y, mr, mg, mb)
      else
        px(x, y, dr, dg, db)
      end
    end
  end
end

-- ============================================================
-- 1. DUSK SKY GRADIENT  (y = 0..79)
--    #2A1F3D (42,31,61) → #4A3050 (74,48,80) → #6A4048 (106,64,72)
-- ============================================================
-- Band 1: deep purple top → mid-purple  (y 0..39)
dither_band(0,  39,  42,31,61,  74,48,80)
-- Band 2: mid-purple → warm orange-pink horizon  (y 40..79)
dither_band(40, 79,  74,48,80,  106,64,72)

-- Thin horizon glow line just above buildings (y=78,79)
hline(78, 0, W-1, 130,80,70)
hline(79, 0, W-1, 118,72,64)

-- ============================================================
-- 2. BUILDING SILHOUETTES  (y = 80..130)
--    Color: dark warm brown #2A2028 (42,32,40)
-- ============================================================

-- Building wall fill helper
local SILL_R, SILL_G, SILL_B = 42, 32, 40      -- #2A2028
local SILL2_R, SILL2_G, SILL2_B = 34, 26, 32   -- slightly darker

-- Helper: draw a simple peaked building
--   bx=left edge, bw=width, wall_top=top of wall, roof_peak_dy=roof height above wall
local function building(bx, bw, wall_top, wall_bot, roof_h, has_chimney)
  -- Roof triangle
  local apex_x = bx + math.floor(bw / 2)
  local apex_y = wall_top - roof_h
  for y = apex_y, wall_top do
    local t = (y - apex_y) / roof_h
    local half = math.floor(t * (bw / 2))
    local rx1 = apex_x - half
    local rx2 = apex_x + half
    hline(y, rx1, rx2, SILL_R, SILL_G, SILL_B)
  end
  -- Wall body
  rect(bx, wall_top, bx+bw-1, wall_bot, SILL_R, SILL_G, SILL_B)

  -- Chimney (1 per building on right side of roof)
  if has_chimney then
    local cx = bx + math.floor(bw * 0.7)
    rect(cx, apex_y - 8, cx+4, apex_y + 4, SILL2_R, SILL2_G, SILL2_B)
  end
end

-- Helper: church steeple
local function steeple(bx, bw, wall_top, wall_bot, steeple_h)
  -- Tall narrow spire
  local apex_x = bx + math.floor(bw / 2)
  local apex_y = wall_top - steeple_h
  for y = apex_y, wall_top do
    local t = (y - apex_y) / steeple_h
    local half = math.max(1, math.floor(t * (bw / 2)))
    hline(y, apex_x - half, apex_x + half, SILL_R, SILL_G, SILL_B)
  end
  -- Main church body (wider, shorter)
  local body_w = bw + 20
  local body_x = bx - 10
  rect(body_x, wall_top, body_x+body_w-1, wall_bot, SILL_R, SILL_G, SILL_B)
  -- Bell tower cross (just 2 pixels lighter)
  px(apex_x,   apex_y + 4, 60, 46, 54)
  px(apex_x-1, apex_y + 6, 60, 46, 54)
  px(apex_x+1, apex_y + 6, 60, 46, 54)
  px(apex_x,   apex_y + 6, 60, 46, 54)
  px(apex_x,   apex_y + 8, 60, 46, 54)
end

-- Building layout (ground line = y=120, buildings touch horizon y=80)
-- Left cluster: tavern-like two-story building
building(  0, 54, 88, 120, 18, true)   -- leftmost wide building
building( 58, 36, 95, 120, 14, false)  -- adjacent narrower

-- Center: church steeple (dominant silhouette)
steeple(148, 24, 70, 120, 50)

-- Right cluster
building(220, 42, 90, 120, 16, true)   -- right inn
building(265, 50, 84, 120, 20, false)  -- far right tall building

-- Fill sky gap that might remain between buildings at ground level
rect(0, 121, W-1, 121, SILL_R, SILL_G, SILL_B)

-- ============================================================
-- 3. COBBLESTONE GROUND  (y = 121..179)
--    Base: warm brown #3A2828 (58,40,40)
--    Stone lines: lighter #4A3838 (74,56,56) and darker #2A2020 (42,32,32)
-- ============================================================
local GND_R,  GND_G,  GND_B  = 58, 40, 40   -- #3A2828
local GND2_R, GND2_G, GND2_B = 74, 56, 56   -- #4A3838 stone highlight
local GND3_R, GND3_G, GND3_B = 42, 32, 32   -- #2A2020 stone shadow

-- Fill ground base
rect(0, 121, W-1, H-1, GND_R, GND_G, GND_B)

-- Cobblestone grid: horizontal mortar lines every ~10px
for y = 124, H-1, 10 do
  hline(y, 0, W-1, GND3_R, GND3_G, GND3_B)
end

-- Vertical mortar lines (offset every other row for brick pattern)
local row = 0
for y = 121, H-1, 10 do
  local offset = (row % 2 == 0) and 0 or 8
  local x = offset
  while x < W do
    px(x, y,   GND3_R, GND3_G, GND3_B)
    px(x, y+1, GND3_R, GND3_G, GND3_B)
    px(x, y+2, GND3_R, GND3_G, GND3_B)
    x = x + 18
  end
  row = row + 1
end

-- Top edge of cobblestones: lighter highlight row
hline(122, 0, W-1, GND2_R, GND2_G, GND2_B)

-- ============================================================
-- 4. WARM WINDOW GLOW  (on building faces)
--    Colors: #CC9944 (204,153,68) inner glow, #FFAA44 (255,170,68) bright
-- ============================================================
local WIN_R,  WIN_G,  WIN_B  = 255, 170,  68  -- bright warm yellow
local WIN2_R, WIN2_G, WIN2_B = 204, 153,  68  -- amber outer

local function window(wx, wy)
  -- 2x2 core bright
  px(wx,   wy,   WIN_R,  WIN_G,  WIN_B)
  px(wx+1, wy,   WIN_R,  WIN_G,  WIN_B)
  px(wx,   wy+1, WIN_R,  WIN_G,  WIN_B)
  px(wx+1, wy+1, WIN_R,  WIN_G,  WIN_B)
  -- 1-pixel amber halo
  px(wx-1, wy,   WIN2_R, WIN2_G, WIN2_B)
  px(wx+2, wy,   WIN2_R, WIN2_G, WIN2_B)
  px(wx,   wy-1, WIN2_R, WIN2_G, WIN2_B)
  px(wx+1, wy-1, WIN2_R, WIN2_G, WIN2_B)
  px(wx,   wy+2, WIN2_R, WIN2_G, WIN2_B)
  px(wx+1, wy+2, WIN2_R, WIN2_G, WIN2_B)
  px(wx-1, wy+1, WIN2_R, WIN2_G, WIN2_B)
  px(wx+2, wy+1, WIN2_R, WIN2_G, WIN2_B)
end

-- Left building windows
window( 10, 100)
window( 22, 100)
window( 10, 110)
-- Second left building
window( 66, 102)
-- Church body windows (arched, tall — just normal windows here)
window(152, 98)
window(168, 98)
-- Right inn
window(228, 96)
window(240, 96)
window(228, 108)
-- Far right building
window(274, 90)
window(286, 90)
window(274, 103)

-- ============================================================
-- 5. LAMPPOSTS  (#AA8833 = 170,136,51 warm brass)
--    Two posts at x=105 and x=210, base y=120, pole to y=92
-- ============================================================
local LAMP_R, LAMP_G, LAMP_B = 170, 136, 51

local function lamppost(lx)
  -- Pole (2px wide)
  for y = 91, 120 do
    px(lx,   y, LAMP_R, LAMP_G, LAMP_B)
    px(lx+1, y, LAMP_R, LAMP_G, LAMP_B)
  end
  -- Lamp head (small bracket + globe)
  px(lx-2, 91, LAMP_R, LAMP_G, LAMP_B)
  px(lx-3, 90, LAMP_R, LAMP_G, LAMP_B)
  px(lx-3, 89, LAMP_R, LAMP_G, LAMP_B)
  px(lx-4, 89, WIN_R,  WIN_G,  WIN_B)   -- bright lamp
  px(lx-5, 89, WIN_R,  WIN_G,  WIN_B)
  px(lx-4, 88, WIN_R,  WIN_G,  WIN_B)
  px(lx-5, 88, WIN_R,  WIN_G,  WIN_B)
  -- amber halo around lamp
  px(lx-6, 88, WIN2_R, WIN2_G, WIN2_B)
  px(lx-6, 89, WIN2_R, WIN2_G, WIN2_B)
  px(lx-6, 90, WIN2_R, WIN2_G, WIN2_B)
  px(lx-5, 87, WIN2_R, WIN2_G, WIN2_B)
  px(lx-4, 87, WIN2_R, WIN2_G, WIN2_B)
  px(lx-3, 87, WIN2_R, WIN2_G, WIN2_B)
  px(lx-5, 90, WIN2_R, WIN2_G, WIN2_B)
  px(lx-4, 90, WIN2_R, WIN2_G, WIN2_B)
  -- Base foot
  rect(lx-2, 118, lx+3, 120, LAMP_R, LAMP_G, LAMP_B)
end

lamppost(105)
lamppost(210)

-- ============================================================
-- 6. WARM GROUND GLOW near buildings (light spill)
--    Soft orange tint on cobblestones directly below lit windows/lamps
-- ============================================================
local function ground_glow(cx, y_start, radius)
  -- radial fade: brightest at centre, falls off
  local GLO_R, GLO_G, GLO_B = 80, 54, 30
  for dy = 0, radius do
    local t = dy / radius
    local fr = lerpi(GLO_R, GND_R, t)
    local fg = lerpi(GLO_G, GND_G, t)
    local fb = lerpi(GLO_B, GND_B, t)
    local half_w = math.floor((1 - t) * radius * 2.5)
    if half_w > 0 then
      hline(y_start + dy, cx - half_w, cx + half_w, fr, fg, fb)
    end
  end
end

-- Glow pools under each lamppost
ground_glow(102, 119, 10)
ground_glow(207, 119, 10)
-- Ambient spill under windows on left building
ground_glow( 15, 119,  6)
-- Under church windows
ground_glow(160, 119,  8)
-- Under right building windows
ground_glow(234, 119,  7)

-- ============================================================
-- SAVE
-- ============================================================
-- Save modified aseprite
spr:saveAs(OUT_ASE)
print("Saved .aseprite: " .. OUT_ASE)

-- Export PNG from frame 1
-- Use app.command.ExportFile or spr:saveCopyAs
app.activeSprite = spr
spr:saveCopyAs(OUT_PNG)
print("Exported PNG: " .. OUT_PNG)

print("Done! Village battle background complete.")
print("Canvas: " .. W .. "x" .. H)
