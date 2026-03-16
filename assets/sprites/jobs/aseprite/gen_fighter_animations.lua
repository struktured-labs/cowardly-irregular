-- extend_animations_v3.lua
-- CORRECT approach using Aseprite Lua API properly:
--   spr:newFrame() appends a new frame at the end, copying cels from the LAST frame.
--   There is no newFrameAt() in this version.
--   To copy from a specific source frame, we must manually copy cels.
--
-- Strategy: append frames one by one, manually copy cel images+positions from source.
-- spr:newFrame() creates blank frame OR copies from previous; we'll use it to get
-- the frame object, then overwrite each cel manually.

local SRC = "/home/struktured/projects/cowardly-irregular/assets/sprites/jobs/aseprite/Main Fighter animations.aseprite"
local DST = "/home/struktured/projects/cowardly-irregular-sprite-gen/tmp/Fighter_extended.aseprite"

-- Open the source fresh
local spr = app.open(SRC)
if not spr then
  print("ERROR: Cannot open " .. SRC)
  return
end
print("Opened source: " .. SRC)
print("Frames: " .. #spr.frames)

-- Helper: get layer by name
local function getLayer(name)
  for _, l in ipairs(spr.layers) do
    if l.name == name then return l end
  end
  return nil
end

-- Store original frame data (positions) before we modify anything
-- We'll snapshot the source frame cel positions
local function snapshotFrame(fi)
  local snap = {}
  for _, layer in ipairs(spr.layers) do
    local cel = layer:cel(fi)
    if cel then
      snap[layer.name] = {
        image = cel.image:clone(),
        x = cel.position.x,
        y = cel.position.y,
        opacity = cel.opacity
      }
    end
  end
  return snap
end

print("Snapshotting original frames...")
local origF1 = snapshotFrame(1)
local origF2 = snapshotFrame(2)
local origF3 = snapshotFrame(3)
print("  Snapshots done.")

-- Helper: append a new frame and fill it from a snapshot
-- Returns the new frame index
local function appendFrameFromSnap(snap)
  local newFrame = spr:newFrame()
  local fi = newFrame.frameNumber
  -- Clear all existing cels on this new frame first, then repopulate
  for _, layer in ipairs(spr.layers) do
    local cel = layer:cel(fi)
    if cel then
      spr:deleteCel(layer, fi)
    end
  end
  -- Now fill from snapshot
  for _, layer in ipairs(spr.layers) do
    local s = snap[layer.name]
    if s then
      spr:newCel(layer, fi, s.image:clone(), Point(s.x, s.y))
      -- set opacity
      local cel = layer:cel(fi)
      if cel then cel.opacity = s.opacity end
    end
  end
  return fi
end

-- Helper: shift a specific layer's cel on a given frame
local function shiftCel(layerName, frameIdx, dx, dy)
  local layer = getLayer(layerName)
  if not layer then return end
  local cel = layer:cel(frameIdx)
  if not cel then return end
  local p = cel.position
  cel.position = Point(p.x + dx, p.y + dy)
end

local function shiftMany(names, frameIdx, dx, dy)
  for _, n in ipairs(names) do
    shiftCel(n, frameIdx, dx, dy)
  end
end

-- ==============================================================
-- SET DURATIONS ON ORIGINAL 3 FRAMES
-- ==============================================================
spr.frames[1].duration = 150  -- idle neutral
spr.frames[2].duration = 80   -- attack pose (source data frame)
spr.frames[3].duration = 120  -- hit/recoil pose (source data frame)

-- ==============================================================
-- BUILD IDLE FRAMES (append as frames 4, 5)
-- idle tag: frames 1-5 pingpong (1=neutral, 4=rise, 5=peak)
-- We will tag 1,4,5 as idle. But tags need contiguous ranges...
-- Since frames 2,3 (attack/hit sources) will be REMOVED after,
-- after removal: F1=neutral, F4->F2, F5->F3 etc.
-- Let's just build all frames and delete F2,F3 at the end.
-- ==============================================================
print("\nBuilding idle frames...")

-- Frame 4: idle rise (head+body up 1px)
local idle_rise = appendFrameFromSnap(origF1)
shiftMany({"Head", "Body", "L Shoulder", "R shoulder"}, idle_rise, 0, -1)
spr.frames[idle_rise].duration = 150
print("  idle_rise = frame " .. idle_rise)

-- Frame 5: idle peak (head+body up 2px, arms up 1px)
local idle_peak = appendFrameFromSnap(origF1)
shiftMany({"Head", "Body", "L Shoulder", "R shoulder"}, idle_peak, 0, -2)
shiftMany({"L Arm", "R Arm"}, idle_peak, 0, -1)
spr.frames[idle_peak].duration = 150
print("  idle_peak = frame " .. idle_peak)

-- ==============================================================
-- BUILD ATTACK FRAMES (append as 6, 7, 8, 9)
-- wind-up → lunge → extend → recover
-- ==============================================================
print("\nBuilding attack frames...")

-- Frame 6: wind-up (arms pull back)
local atk_windup = appendFrameFromSnap(origF1)
shiftMany({"R Arm", "R shoulder"}, atk_windup, -2, 0)
shiftMany({"L Arm", "L Shoulder"}, atk_windup, -1, 0)
shiftMany({"Body"}, atk_windup, -1, 0)
spr.frames[atk_windup].duration = 80
print("  atk_windup = frame " .. atk_windup)

-- Frame 7: lunge (= original F2 pose)
local atk_lunge = appendFrameFromSnap(origF2)
spr.frames[atk_lunge].duration = 60
print("  atk_lunge = frame " .. atk_lunge)

-- Frame 8: full extension (F2 + arms further forward)
local atk_extend = appendFrameFromSnap(origF2)
shiftMany({"R Arm", "R shoulder"}, atk_extend, 2, 0)
shiftMany({"L Arm", "L Shoulder"}, atk_extend, 1, 0)
shiftMany({"Body"}, atk_extend, 1, 0)
spr.frames[atk_extend].duration = 60
print("  atk_extend = frame " .. atk_extend)

-- Frame 9: recovery (neutral + slight arm forward)
local atk_recover = appendFrameFromSnap(origF1)
shiftMany({"R Arm"}, atk_recover, 1, 0)
shiftMany({"Body"}, atk_recover, 0, 1)
spr.frames[atk_recover].duration = 100
print("  atk_recover = frame " .. atk_recover)

-- ==============================================================
-- BUILD WALK FRAMES (append 6 frames: 10-15)
-- ==============================================================
print("\nBuilding walk frames...")

local walkDefs = {
  { legs={ 2,  0}, body={0,  0}, head={0,  0} },  -- right stride
  { legs={ 3, -1}, body={0, -1}, head={0, -1} },  -- right peak
  { legs={ 1,  0}, body={0,  0}, head={0,  0} },  -- crossing
  { legs={-2,  0}, body={0,  0}, head={0,  0} },  -- left stride
  { legs={-3, -1}, body={0, -1}, head={0, -1} },  -- left peak
  { legs={-1,  0}, body={0,  0}, head={0,  0} },  -- near-neutral
}

local walkFrames = {}
for i, def in ipairs(walkDefs) do
  local wf = appendFrameFromSnap(origF1)
  shiftMany({"Legs"}, wf, def.legs[1], def.legs[2])
  shiftMany({"Body"}, wf, def.body[1], def.body[2])
  shiftMany({"Head", "L Shoulder", "R shoulder"}, wf, def.head[1], def.head[2])
  spr.frames[wf].duration = 120
  table.insert(walkFrames, wf)
end
print("  walk frames: " .. walkFrames[1] .. "-" .. walkFrames[6])

-- ==============================================================
-- BUILD HIT FRAMES (append 2 frames: 16-17)
-- ==============================================================
print("\nBuilding hit frames...")

-- Frame 16: recoil (= original F3 pose)
local hit_recoil = appendFrameFromSnap(origF3)
spr.frames[hit_recoil].duration = 120
print("  hit_recoil = frame " .. hit_recoil)

-- Frame 17: recovery (F3 shifting back toward neutral)
local hit_recover = appendFrameFromSnap(origF3)
shiftMany({"Head", "Body", "L Arm", "R Arm", "L Shoulder", "R shoulder", "Legs"}, hit_recover, 2, -1)
spr.frames[hit_recover].duration = 100
print("  hit_recover = frame " .. hit_recover)

-- ==============================================================
-- BUILD DEAD FRAMES (append 2 frames: 18-19)
-- ==============================================================
print("\nBuilding dead frames...")

-- Frame 18: falling
local dead_fall = appendFrameFromSnap(origF1)
shiftMany({"Head"}, dead_fall, 4, 6)
shiftMany({"Body"}, dead_fall, 3, 8)
shiftMany({"L Arm", "L Shoulder"}, dead_fall, 2, 10)
shiftMany({"R Arm", "R shoulder"}, dead_fall, 5, 8)
shiftMany({"Legs"}, dead_fall, 1, 12)
shiftMany({"Shadow"}, dead_fall, 2, 0)
spr.frames[dead_fall].duration = 150
print("  dead_fall = frame " .. dead_fall)

-- Frame 19: flat
local dead_flat = appendFrameFromSnap(origF1)
shiftMany({"Head"}, dead_flat, 8, 14)
shiftMany({"Body"}, dead_flat, 6, 16)
shiftMany({"L Arm", "L Shoulder"}, dead_flat, 4, 18)
shiftMany({"R Arm", "R shoulder"}, dead_flat, 10, 15)
shiftMany({"Legs"}, dead_flat, 3, 20)
shiftMany({"Shadow"}, dead_flat, 4, 2)
spr.frames[dead_flat].duration = 200
print("  dead_flat = frame " .. dead_flat)

-- ==============================================================
-- DELETE ORIGINAL FRAMES 2 AND 3 (source-only frames)
-- Must delete highest index first.
-- After deletion, all frames >= 4 shift down by 2.
-- ==============================================================
print("\nTotal frames before cleanup: " .. #spr.frames)
print("Deleting source-only frames 3 and 2...")
spr:deleteFrame(3)
spr:deleteFrame(2)
print("Total frames after cleanup: " .. #spr.frames)

-- Adjust all stored indices (everything >= 4 is now -= 2)
local function adj(n)
  if n == 1 then return 1 end
  return n - 2
end

-- ==============================================================
-- CREATE ANIMATION TAGS
-- ==============================================================
print("\nCreating animation tags...")

-- Compute final frame positions
local IDLE_FROM  = 1
local IDLE_TO    = adj(idle_peak)     -- pingpong: 1 → adj(idle_rise) → adj(idle_peak)
local ATK_FROM   = adj(atk_windup)
local ATK_TO     = adj(atk_recover)
local WALK_FROM  = adj(walkFrames[1])
local WALK_TO    = adj(walkFrames[6])
local HIT_FROM   = adj(hit_recoil)
local HIT_TO     = adj(hit_recover)
local DEAD_FROM  = adj(dead_fall)
local DEAD_TO    = adj(dead_flat)

local total = #spr.frames
print(string.format("  Total frames: %d", total))
print(string.format("  idle:   %d-%d", IDLE_FROM, IDLE_TO))
print(string.format("  attack: %d-%d", ATK_FROM,  ATK_TO))
print(string.format("  walk:   %d-%d", WALK_FROM, WALK_TO))
print(string.format("  hit:    %d-%d", HIT_FROM,  HIT_TO))
print(string.format("  dead:   %d-%d", DEAD_FROM, DEAD_TO))

-- Validate
local ok = true
local function checkRange(name, a, b)
  if a < 1 or b > total or a > b then
    print("ERROR: '" .. name .. "' range " .. a .. "-" .. b .. " invalid (total=" .. total .. ")")
    ok = false
  end
end
checkRange("idle",   IDLE_FROM, IDLE_TO)
checkRange("attack", ATK_FROM,  ATK_TO)
checkRange("walk",   WALK_FROM, WALK_TO)
checkRange("hit",    HIT_FROM,  HIT_TO)
checkRange("dead",   DEAD_FROM, DEAD_TO)

if not ok then
  print("ABORTING: tag range errors found")
  return
end

local t1 = spr:newTag(IDLE_FROM, IDLE_TO)
t1.name = "idle"; t1.aniDir = AniDir.PING_PONG

local t2 = spr:newTag(ATK_FROM, ATK_TO)
t2.name = "attack"; t2.aniDir = AniDir.FORWARD

local t3 = spr:newTag(WALK_FROM, WALK_TO)
t3.name = "walk"; t3.aniDir = AniDir.FORWARD

local t4 = spr:newTag(HIT_FROM, HIT_TO)
t4.name = "hit"; t4.aniDir = AniDir.FORWARD

local t5 = spr:newTag(DEAD_FROM, DEAD_TO)
t5.name = "dead"; t5.aniDir = AniDir.FORWARD

print("\nFinal tags:")
for _, tag in ipairs(spr.tags) do
  print(string.format("  '%s': frames %d-%d dir=%s",
    tag.name, tag.fromFrame.frameNumber, tag.toFrame.frameNumber, tostring(tag.aniDir)))
end

-- ==============================================================
-- VERIFY: check for empty frames within tag ranges
-- ==============================================================
print("\nVerifying frames for empty cels...")
local visLayers = {}
for _, l in ipairs(spr.layers) do
  if l.isVisible then table.insert(visLayers, l) end
end
local emptyCount = 0
for fi = 1, #spr.frames do
  local count = 0
  for _, l in ipairs(visLayers) do
    if l:cel(fi) then count = count + 1 end
  end
  if count == 0 then
    print("  WARNING: Frame " .. fi .. " has NO visible cels")
    emptyCount = emptyCount + 1
  end
end
if emptyCount == 0 then
  print("  All frames have visible cels. OK.")
end

-- ==============================================================
-- SAVE
-- ==============================================================
print("\nSaving to " .. DST .. "...")
spr:saveAs(DST)
print("Saved OK.")
print("\n=== COMPLETE: " .. #spr.frames .. " frames, 5 animation tags ===")
