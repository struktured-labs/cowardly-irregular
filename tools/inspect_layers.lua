-- Print layer visibility for inspection.
local s = app.activeSprite
if not s then print("no sprite"); return end
print(string.format("=== %s (%dx%d, %d frames) ===", s.filename, s.width, s.height, #s.frames))
local function dump(layer, indent)
  local prefix = string.rep("  ", indent)
  local vis = layer.isVisible and "VIS" or "hid"
  print(string.format("%s[%s] %s", prefix, vis, layer.name))
  if layer.isGroup then
    for _, child in ipairs(layer.layers) do dump(child, indent+1) end
  end
end
for _, l in ipairs(s.layers) do dump(l, 0) end
