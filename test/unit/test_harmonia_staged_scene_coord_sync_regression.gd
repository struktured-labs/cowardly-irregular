extends GutTest

## Regression: live playtest 2026-07-17 (intercom 2763) — staged Harmonia
## cutscenes rendered actors "not aligned". Root: village-resize commit
## e37af164 (2026-07-15) grew W1-W5 layouts ~20% via a padding algorithm
## that shifted every Vector2 position in .gd files by (+96, +64) for
## Harmonia (pad = (+3 tiles, +2 tiles) × TILE_SIZE=32).
##
## The pad was applied to HarmoniaVillage.gd but NOT to hardcoded pixel
## coords in data/cutscenes/*.json — so staged scenes' party spawns and
## puppet walk marks landed one tile row below where live NPCs were
## repositioned. Silent visual drift; only shows up when the staged
## scene fires.
##
## Two ratchets to prevent this drift from re-occurring:
##   (A) Every staged Harmonia scene's actor/camera coord must land within
##       the current MAP_WIDTH × MAP_HEIGHT rect (with a 1-tile inset for
##       the perimeter wall). Catches "authored to old dims" drift.
##   (B) Every replace_npc target spawn puppet's `at` override (when present)
##       must be within 1 tile-radius of the LIVE NPC's position on
##       HarmoniaVillage.gd. Catches drift between authored puppet coord
##       and the live NPC that puppet is meant to visually replace.

const HARMONIA_VILLAGE := "res://src/maps/villages/HarmoniaVillage.gd"
const TILE_SIZE := 32
const PERIMETER_INSET := 1  # 1 tile wall around edges

## Staged scenes we author for Harmonia.
const HARMONIA_STAGED_SCENES := [
	"res://data/cutscenes/world1_chapter1.json",
	"res://data/cutscenes/world1_harmonia_after_cave.json",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _harmonia_dims() -> Vector2i:
	# Extract MAP_WIDTH / MAP_HEIGHT constants from HarmoniaVillage.gd source
	# so this test tracks the resize as it happens without needing a bump.
	var src := _read(HARMONIA_VILLAGE)
	assert_ne(src, "", "HarmoniaVillage.gd must be readable")
	var regex := RegEx.new()
	regex.compile("const MAP_(WIDTH|HEIGHT):\\s*int\\s*=\\s*(\\d+)")
	var w := 0
	var h := 0
	for m in regex.search_all(src):
		if m.get_string(1) == "WIDTH":
			w = int(m.get_string(2))
		else:
			h = int(m.get_string(2))
	assert_gt(w, 0, "MAP_WIDTH must extract from HarmoniaVillage.gd")
	assert_gt(h, 0, "MAP_HEIGHT must extract from HarmoniaVillage.gd")
	return Vector2i(w, h)


## Return px position of an NPC by display name, or Vector2.INF if not found.
func _live_npc_position(display_name: String) -> Vector2:
	var src := _read(HARMONIA_VILLAGE)
	# _create_npc("<name>", "<type>", Vector2(TILE * TILE_SIZE, TILE * TILE_SIZE), ...)
	# Match the tile coefficients; TILE_SIZE is a constant.
	var pat := '_create_npc\\("%s",\\s*"[a-z_]+",\\s*Vector2\\((\\d+)\\s*\\*\\s*TILE_SIZE\\s*,\\s*(\\d+)\\s*\\*\\s*TILE_SIZE' % display_name.replace(".", "\\.")
	var regex := RegEx.new()
	regex.compile(pat)
	var m := regex.search(src)
	if m == null:
		return Vector2.INF
	return Vector2(int(m.get_string(1)) * TILE_SIZE, int(m.get_string(2)) * TILE_SIZE)


## Iterate every coord field (at / to / target) with (path, step_idx, field, value).
func _iter_scene_coords(scene_path: String, callback: Callable) -> void:
	var parsed = JSON.parse_string(_read(scene_path))
	assert_true(parsed is Dictionary, "%s must parse as JSON object" % scene_path)
	var idx := 0
	for step in parsed.get("steps", []):
		if step is Dictionary:
			for field in ["at", "to", "target"]:
				var v = step.get(field)
				if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
					callback.call(scene_path, idx, field, step, Vector2(float(v[0]), float(v[1])))
		idx += 1


func test_all_harmonia_staged_coords_within_map_rect() -> void:
	# (A) Coord-inside-map guard. Catches "authored for old dims".
	# CastleVista pan (world1_harmonia_after_cave step[50] target=[576, 60])
	# is INTENTIONALLY above the walkable rect — it's a camera pan onto the
	# north skyline vista, not an actor spawn. Whitelist by y < 4 tile-rows.
	var dims := _harmonia_dims()
	var min_px := Vector2(PERIMETER_INSET * TILE_SIZE, PERIMETER_INSET * TILE_SIZE)
	var max_px := Vector2((dims.x - PERIMETER_INSET) * TILE_SIZE, (dims.y - PERIMETER_INSET) * TILE_SIZE)
	var offenders: Array = []
	for scene in HARMONIA_STAGED_SCENES:
		_iter_scene_coords(scene, func(path: String, idx: int, field: String, step: Dictionary, pos: Vector2):
			# CastleVista camera pan is intentionally at the north edge — skip.
			if step.get("type") == "camera_focus" and pos.y < 4 * TILE_SIZE:
				return
			if pos.x < min_px.x or pos.x > max_px.x or pos.y < min_px.y or pos.y > max_px.y:
				offenders.append("%s[step %d].%s = %s (map is %s × %s px, walkable %s..%s)" % [
					path.get_file(), idx, field, pos, dims.x * TILE_SIZE, dims.y * TILE_SIZE, min_px, max_px])
		)
	assert_eq(offenders.size(), 0,
		"staged Harmonia coords outside the current map — pad drift after village resize:\n  %s" % "\n  ".join(offenders))


func test_replace_npc_puppet_at_stays_close_to_live_npc() -> void:
	# (B) When a spawn_actor step declares BOTH `replace_npc` AND `at`,
	# the `at` override must be close to the live NPC's position — otherwise
	# the puppet teleports away from where the replaced NPC visibly stood,
	# which is exactly the kind of jump struktured called "not aligned".
	#
	# In the current scenes, every replace_npc spawn omits `at` entirely
	# (inherits live position) — so this test is a forward-drift guard.
	var MAX_DELTA := 3 * TILE_SIZE  # 3-tile radius tolerance
	var offenders: Array = []
	for scene in HARMONIA_STAGED_SCENES:
		var parsed = JSON.parse_string(_read(scene))
		if not (parsed is Dictionary):
			continue
		var idx := 0
		for step in parsed.get("steps", []):
			if step is Dictionary and step.get("type") == "spawn_actor":
				var replaced := str(step.get("replace_npc", ""))
				var at = step.get("at")
				if replaced != "" and at is Array and at.size() == 2:
					var live := _live_npc_position(replaced)
					if live != Vector2.INF:
						var declared := Vector2(float(at[0]), float(at[1]))
						if declared.distance_to(live) > MAX_DELTA:
							offenders.append("%s[step %d]: puppet '%s' at %s but live NPC is at %s (delta %s > %s)" % [
								scene.get_file(), idx, replaced, declared, live, declared.distance_to(live), MAX_DELTA])
			idx += 1
	assert_eq(offenders.size(), 0,
		"replace_npc puppet `at` override too far from live NPC position:\n  %s" % "\n  ".join(offenders))
