-- Rename aseprite animation tags to the agreed action-verb convention.
--
-- Idempotent: tags already in the new naming are left alone; only old
-- variants are renamed. Saves the file in place.
--
-- Run via: aseprite -b --script tools/rename_aseprite_tags.lua <file.aseprite>

local renames = {
  -- universal
  ["IDLE"] = "idle",
  ["Idle"] = "idle",

  -- per-class action verbs
  ["Attack"] = "slash",     -- fighter
  ["ATK"]    = "stab",      -- rogue
  ["Atk 1"]  = "cast",      -- mage (generic spell-cast covers all his abilities for now)
  ["Cast"]   = "cast",      -- cleric (generic spell-cast — large ornate staff motion)

  -- approach / lunge
  ["Dash"]   = "dash",
}

local sprite = app.activeSprite
if not sprite then
  print("ERROR: no active sprite")
  return
end

local file = sprite.filename
local changed = 0

for _, tag in ipairs(sprite.tags) do
  local new = renames[tag.name]
  if new and tag.name ~= new then
    print(string.format("  rename: %-10s -> %s", tag.name, new))
    tag.name = new
    changed = changed + 1
  end
end

if changed == 0 then
  print(string.format("  no renames in %s", file))
else
  sprite:saveAs(file)
  print(string.format("  saved %d rename(s) to %s", changed, file))
end
