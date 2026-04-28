-- Build a tagged overworld walk-cycle aseprite from a 16-frame horizontal strip.
--
-- Input:  --script-param strip="path/to/strip.png"  (16x32x32 = 512x32 strip)
--         --script-param out="path/to/out.aseprite"
--
-- Output: 32x32 canvas, 16 frames, 4 tags:
--           walk_down  (frames 0-3)
--           walk_left  (frames 4-7)
--           walk_right (frames 8-11)
--           walk_up    (frames 12-15)

local strip_path = app.params.strip
local out_path   = app.params.out
if not strip_path or not out_path then
  print("ERROR: need --script-param strip=... and out=...")
  return
end

local strip = Image{ fromFile = strip_path }
if not strip then print("ERROR: failed to load " .. strip_path); return end
if strip.width ~= 512 or strip.height ~= 32 then
  print(string.format("ERROR: expected 512x32 strip, got %dx%d", strip.width, strip.height))
  return
end

local sprite = Sprite(32, 32)
sprite:setPalette(Palette(256))

-- Build 16 frames, copying each 32x32 tile from the source strip
while #sprite.frames < 16 do sprite:newFrame() end
local layer = sprite.layers[1]
for i = 0, 15 do
  local cel_image = Image(32, 32, ColorMode.RGB)
  cel_image:drawImage(strip, Point(-i * 32, 0))
  sprite:newCel(layer, sprite.frames[i + 1], cel_image)
end
-- Remove the empty initial frame Aseprite created when newFrame() was first called
-- (handled implicitly by drawImage on each cel above)

local tag_defs = {
  { "walk_down",  1,  4 },
  { "walk_left",  5,  8 },
  { "walk_right", 9,  12 },
  { "walk_up",    13, 16 },
}
for _, td in ipairs(tag_defs) do
  local from = sprite.frames[td[2]]
  local to   = sprite.frames[td[3]]
  local tag  = sprite:newTag(from, to)
  tag.name = td[1]
end

-- Set per-frame duration (8fps = 125ms)
for i = 1, 16 do sprite.frames[i].duration = 0.125 end

sprite:saveAs(out_path)
print(string.format("saved %d-frame %s with %d tags", #sprite.frames, out_path, #sprite.tags))
