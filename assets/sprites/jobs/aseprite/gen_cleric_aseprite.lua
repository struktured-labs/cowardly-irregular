-- ============================================================
-- Cleric Animation Generator (Aseprite Lua script)
-- Usage: aseprite -b --script tools/gen_cleric_aseprite.lua
--
-- SOURCE: assets/sprites/jobs/aseprite/Cleric Main design.aseprite
--   - 630x400 canvas, 1 frame (artist's character design)
--   - 14 layers: Layer1, Layer2(hidden), Layer4, Hair2,
--                L Leg, R Leg, Skirt, weapon, L arm, Body,
--                head, Hood, R arm, Aura
--   - Character occupies top-left ~128x128 of canvas
--
-- OUTPUT: tmp/Cleric_extended.aseprite
--   - 16 frames, 3 animation tags
--   - idle (F1-4, pingpong, 200ms): gentle breathing/body bob
--   - cast (F5-10, forward, 150ms): staff raised, aura expands
--   - walk (F11-16, forward, 120ms): leg alternation, body bob
--
-- PIPELINE TIER: T1 (AI/automation-assisted, artist review needed)
-- DO NOT overwrite original .aseprite or artist-approved assets.
-- ============================================================

local REPO = "/home/struktured/projects/cowardly-irregular-sprite-gen"
local src_path = REPO .. "/tmp/Cleric_extended.aseprite"

-- Verify working copy exists (should have been created by:
--   cp "Cleric Main design.aseprite" tmp/Cleric_extended.aseprite)
local spr = app.open(src_path)
if not spr then
  error("Working copy not found: " .. src_path ..
        "\nRun: cp 'assets/sprites/jobs/aseprite/Cleric Main design.aseprite' tmp/Cleric_extended.aseprite")
end

-- -------------------------------------------------------
-- Layer name -> index map (1-based, probed from source file)
-- Layer 1  = 'Layer 1'  (bg, 128x128 fill at 0,0)
-- Layer 2  = 'Layer 2'  (hidden reference)
-- Layer 3  = 'Layer 4'  (misc detail)
-- Layer 4  = 'Hair 2'   (37,49 - 38x23)
-- Layer 5  = 'L Leg'    (52,67 - 13x29)
-- Layer 6  = 'R Leg'    (52,67 - 14x29)
-- Layer 7  = 'Skirt'    (33,67 - 46x26)
-- Layer 8  = 'weapon'   (68,24 - 22x72)
-- Layer 9  = 'L arm'    (60,55 - 18x16)
-- Layer 10 = 'Body'     (52,53 - 15x26)
-- Layer 11 = 'head'     (50,42 - 18x17)
-- Layer 12 = 'Hood'     (51,39 - 21x19)
-- Layer 13 = 'R arm'    (45,56 - 11x17)
-- Layer 14 = 'Aura'     (63,5  - 31x69)
-- -------------------------------------------------------
local L = {
  bg       = 1,
  layer2   = 2,
  layer4   = 3,
  hair2    = 4,
  l_leg    = 5,
  r_leg    = 6,
  skirt    = 7,
  weapon   = 8,
  l_arm    = 9,
  body     = 10,
  head     = 11,
  hood     = 12,
  r_arm    = 13,
  aura     = 14,
}

-- -------------------------------------------------------
-- Helper: copy all cels from frame src_f to frame dst_f
-- -------------------------------------------------------
local function copy_frame(spr, src_f, dst_f)
  for _, layer in ipairs(spr.layers) do
    local src_cel = layer:cel(src_f)
    if src_cel then
      local new_img = src_cel.image:clone()
      spr:newCel(layer, dst_f, new_img, src_cel.position)
    end
  end
end

-- -------------------------------------------------------
-- Helper: shift a cel's position on a specific frame
-- dx/dy in pixels (positive = right/down)
-- -------------------------------------------------------
local function shift_cel(spr, layer_idx, frame_idx, dx, dy)
  local layer = spr.layers[layer_idx]
  if not layer then return end
  local cel = layer:cel(frame_idx)
  if cel then
    cel.position = Point(cel.position.x + dx, cel.position.y + dy)
  end
end

-- -------------------------------------------------------
-- Helper: append one new empty frame, return its index
-- -------------------------------------------------------
local function add_frame(spr)
  spr:newEmptyFrame(#spr.frames + 1)
  return #spr.frames
end

-- ============================================================
-- BASELINE: frame 1 is the artist's design (neutral pose)
-- ============================================================
spr.frames[1].duration = 0.2

-- ============================================================
-- IDLE ANIMATION: frames 1-4, pingpong loop
-- Simulates gentle breathing: upper body rises and settles.
-- Hood and hair follow head. Aura pulses on frame 4.
--
-- Frame 1: neutral (artist's original)
-- Frame 2: head/hood/hair +1px up (inhale begins)
-- Frame 3: head/hood/hair +2px up, body/arms +1px up (peak)
-- Frame 4: head/hood/hair +1px up, aura +1px up (exhale)
-- ============================================================

local f2 = add_frame(spr)
copy_frame(spr, 1, f2)
shift_cel(spr, L.head,  f2, 0, -1)
shift_cel(spr, L.hood,  f2, 0, -1)
shift_cel(spr, L.hair2, f2, 0, -1)
spr.frames[f2].duration = 0.2

local f3 = add_frame(spr)
copy_frame(spr, 1, f3)
shift_cel(spr, L.head,  f3, 0, -2)
shift_cel(spr, L.hood,  f3, 0, -2)
shift_cel(spr, L.hair2, f3, 0, -2)
shift_cel(spr, L.body,  f3, 0, -1)
shift_cel(spr, L.l_arm, f3, 0, -1)
shift_cel(spr, L.r_arm, f3, 0, -1)
spr.frames[f3].duration = 0.2

local f4 = add_frame(spr)
copy_frame(spr, 1, f4)
shift_cel(spr, L.head,  f4, 0, -1)
shift_cel(spr, L.hood,  f4, 0, -1)
shift_cel(spr, L.hair2, f4, 0, -1)
shift_cel(spr, L.aura,  f4, 0, -1)
spr.frames[f4].duration = 0.2

-- ============================================================
-- CAST ANIMATION: frames 5-10, forward loop
-- Cleric raises staff to channel a healing spell.
-- R arm and weapon rise together; aura expands at peak.
-- Head tilts forward slightly as she concentrates.
--
-- Frame 5:  neutral (cast starts)
-- Frame 6:  r_arm/weapon +3px up, head/hood lean +1px right
-- Frame 7:  r_arm/weapon +6px up, aura +3px up, head leans
-- Frame 8:  r_arm/weapon +8px up, aura +5px up (peak cast)
-- Frame 9:  r_arm/weapon +4px up, aura +2px up (recovery)
-- Frame 10: neutral (complete)
-- ============================================================

local f5 = add_frame(spr)
copy_frame(spr, 1, f5)
spr.frames[f5].duration = 0.15

local f6 = add_frame(spr)
copy_frame(spr, 1, f6)
shift_cel(spr, L.r_arm,  f6, 0, -3)
shift_cel(spr, L.weapon, f6, 0, -3)
shift_cel(spr, L.head,   f6, 1,  0)
shift_cel(spr, L.hood,   f6, 1,  0)
spr.frames[f6].duration = 0.15

local f7 = add_frame(spr)
copy_frame(spr, 1, f7)
shift_cel(spr, L.r_arm,  f7, 0, -6)
shift_cel(spr, L.weapon, f7, 0, -6)
shift_cel(spr, L.aura,   f7, 0, -3)
shift_cel(spr, L.head,   f7, 1, -1)
shift_cel(spr, L.hood,   f7, 1, -1)
spr.frames[f7].duration = 0.15

local f8 = add_frame(spr)
copy_frame(spr, 1, f8)
shift_cel(spr, L.r_arm,  f8,  0, -8)
shift_cel(spr, L.weapon, f8,  0, -8)
shift_cel(spr, L.aura,   f8, -1, -5)
shift_cel(spr, L.head,   f8,  1, -2)
shift_cel(spr, L.hood,   f8,  1, -2)
shift_cel(spr, L.hair2,  f8,  1, -1)
spr.frames[f8].duration = 0.15

local f9 = add_frame(spr)
copy_frame(spr, 1, f9)
shift_cel(spr, L.r_arm,  f9, 0, -4)
shift_cel(spr, L.weapon, f9, 0, -4)
shift_cel(spr, L.aura,   f9, 0, -2)
spr.frames[f9].duration = 0.15

local f10 = add_frame(spr)
copy_frame(spr, 1, f10)
spr.frames[f10].duration = 0.15

-- ============================================================
-- WALK ANIMATION: frames 11-16, forward loop
-- 3-step walk cycle: step_L → mid → step_R → mid → step_L → mid
-- Legs alternate 2-3px per stride. Body bobs 1px on mid-frames.
-- Hood and hair trail slightly (shift opposite to stride direction).
--
-- Frame 11: step L  (L leg +2x+2y, R leg -2x-1y, skirt +1x)
-- Frame 12: mid     (upper body -1y, all torso/head/weapon up)
-- Frame 13: step R  (R leg +2x+2y, L leg -2x-1y, skirt -1x)
-- Frame 14: mid     (same as f12)
-- Frame 15: step L  (same as f11, cycle repeats)
-- Frame 16: mid     (same as f12)
-- ============================================================

local f11 = add_frame(spr)
copy_frame(spr, 1, f11)
shift_cel(spr, L.l_leg, f11,  2,  2)
shift_cel(spr, L.r_leg, f11, -2, -1)
shift_cel(spr, L.skirt, f11,  1,  0)
shift_cel(spr, L.hood,  f11,  0,  1)
shift_cel(spr, L.hair2, f11,  0,  1)
spr.frames[f11].duration = 0.12

local f12 = add_frame(spr)
copy_frame(spr, 1, f12)
shift_cel(spr, L.body,   f12, 0, -1)
shift_cel(spr, L.head,   f12, 0, -1)
shift_cel(spr, L.hood,   f12, 0, -1)
shift_cel(spr, L.hair2,  f12, 0, -1)
shift_cel(spr, L.l_arm,  f12, 0, -1)
shift_cel(spr, L.r_arm,  f12, 0, -1)
shift_cel(spr, L.weapon, f12, 0, -1)
spr.frames[f12].duration = 0.12

local f13 = add_frame(spr)
copy_frame(spr, 1, f13)
shift_cel(spr, L.r_leg, f13,  2,  2)
shift_cel(spr, L.l_leg, f13, -2, -1)
shift_cel(spr, L.skirt, f13, -1,  0)
shift_cel(spr, L.hood,  f13,  0,  1)
shift_cel(spr, L.hair2, f13,  0,  1)
spr.frames[f13].duration = 0.12

local f14 = add_frame(spr)
copy_frame(spr, 1, f14)
shift_cel(spr, L.body,   f14, 0, -1)
shift_cel(spr, L.head,   f14, 0, -1)
shift_cel(spr, L.hood,   f14, 0, -1)
shift_cel(spr, L.hair2,  f14, 0, -1)
shift_cel(spr, L.l_arm,  f14, 0, -1)
shift_cel(spr, L.r_arm,  f14, 0, -1)
shift_cel(spr, L.weapon, f14, 0, -1)
spr.frames[f14].duration = 0.12

local f15 = add_frame(spr)
copy_frame(spr, 1, f15)
shift_cel(spr, L.l_leg, f15,  2,  2)
shift_cel(spr, L.r_leg, f15, -2, -1)
shift_cel(spr, L.skirt, f15,  1,  0)
shift_cel(spr, L.hood,  f15,  0,  1)
shift_cel(spr, L.hair2, f15,  0,  1)
spr.frames[f15].duration = 0.12

local f16 = add_frame(spr)
copy_frame(spr, 1, f16)
shift_cel(spr, L.body,   f16, 0, -1)
shift_cel(spr, L.head,   f16, 0, -1)
shift_cel(spr, L.hood,   f16, 0, -1)
shift_cel(spr, L.hair2,  f16, 0, -1)
shift_cel(spr, L.l_arm,  f16, 0, -1)
shift_cel(spr, L.r_arm,  f16, 0, -1)
shift_cel(spr, L.weapon, f16, 0, -1)
spr.frames[f16].duration = 0.12

-- ============================================================
-- ANIMATION TAGS
-- ============================================================
local tag_idle = spr:newTag(1, 4)
tag_idle.name = "idle"
tag_idle.aniDir = AniDir.PING_PONG

local tag_cast = spr:newTag(5, 10)
tag_cast.name = "cast"
tag_cast.aniDir = AniDir.FORWARD

local tag_walk = spr:newTag(11, 16)
tag_walk.name = "walk"
tag_walk.aniDir = AniDir.FORWARD

-- ============================================================
-- SAVE
-- ============================================================
spr:saveAs(src_path)
print("Saved: " .. src_path)
print("Total frames: " .. #spr.frames)
print("Tags: idle(1-4 pingpong), cast(5-10 fwd), walk(11-16 fwd)")
