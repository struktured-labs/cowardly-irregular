-- Hide canvas-color background layers in artist aseprite files.
--
-- Idempotent: only flips visibility on layers that are currently visible
-- AND match the bg-layer name pattern.
--
-- Default match: "Layer 1" (the artist's typical convention for canvas-fill).
-- Override via --script-param layers="Layer 1,bg parts" if needed.
--
-- Run via: aseprite -b file.aseprite --script tools/hide_bg_layers.lua

local sprite = app.activeSprite
if not sprite then print("ERROR: no active sprite"); return end

local target_names = {}
local param = app.params and app.params.layers
if param and #param > 0 then
  for n in string.gmatch(param, "[^,]+") do
    table.insert(target_names, n:gsub("^%s+", ""):gsub("%s+$", ""))
  end
else
  target_names = { "Layer 1" }
end

local function in_targets(name)
  for _, t in ipairs(target_names) do
    if name == t then return true end
  end
  return false
end

local changed = 0
for _, layer in ipairs(sprite.layers) do
  if in_targets(layer.name) and layer.isVisible then
    layer.isVisible = false
    print(string.format("  hide layer: %s", layer.name))
    changed = changed + 1
  end
end

if changed > 0 then
  sprite:saveAs(sprite.filename)
  print(string.format("  saved %d hide(s) to %s", changed, sprite.filename))
else
  print("  no bg layers needed hiding")
end
