extends GutTest

## Regression: footstep_wood shipped UNREACHABLE (2026-07-30).
##
## assets/audio/sfx/footstep_wood.ogg + _v2 + _v3 were authored, registered, and
## selectable by nothing — no terrain in _FOOTSTEP_TERRAIN_MAP resolved to "wood",
## so taverns walked on stone. struktured ruled #16 "if sfx wants to do wooden steps
## so be it"; cowir-main gated the shared-file change.
##
## WHY THE OVERRIDE IS KEYED BY MAP, NOT TERRAIN: `_current_terrain` also drives
## battle backgrounds (BattleScene:518), terrain battle music (BattleScene:2516) and
## autogrind (GameLoop:4899). Re-pointing tavern_interior from "village" to a new
## terrain would have changed the tavern's battle background and music as a side
## effect — measured before implementing, which is why this is one file and not two.

const OP := "res://src/exploration/OverworldPlayer.gd"
const GL := "res://src/GameLoop.gd"


func _consts() -> Script:
	return load(OP) as Script


func test_wood_is_selectable_at_all() -> void:
	## The defect verbatim: nothing could ever choose "wood".
	var s: Script = _consts()
	var terrain_map: Dictionary = s.get("_FOOTSTEP_TERRAIN_MAP")
	var overrides: Dictionary = s.get("_FOOTSTEP_MAP_OVERRIDE")
	var selectable: Array[String] = []
	for v in terrain_map.values():
		if not selectable.has(str(v)):
			selectable.append(str(v))
	for v in overrides.values():
		if not selectable.has(str(v)):
			selectable.append(str(v))
	assert_gt(selectable.size(), 0, "control: no surface is selectable at all — the read is broken")
	assert_true(selectable.has("wood"),
		"footstep_wood.ogg is authored and registered but NOTHING selects it — that is the shipped defect this test exists for. Selectable surfaces: %s" % [selectable])


func test_every_selectable_surface_has_an_authored_cue() -> void:
	## Derived both ways: a surface with no .ogg plays silence (play_footstep discards
	## the manifest return), and a cue nothing selects is dead weight like wood was.
	var s: Script = _consts()
	var selectable: Array[String] = []
	for v in (s.get("_FOOTSTEP_TERRAIN_MAP") as Dictionary).values():
		if not selectable.has(str(v)):
			selectable.append(str(v))
	for v in (s.get("_FOOTSTEP_MAP_OVERRIDE") as Dictionary).values():
		if not selectable.has(str(v)):
			selectable.append(str(v))
	assert_gt(selectable.size(), 0, "control: nothing selectable — the sweep below ran on zero surfaces")
	var missing: Array[String] = []
	for surface in selectable:
		if not FileAccess.file_exists("res://assets/audio/sfx/footstep_%s.ogg" % surface):
			missing.append(surface)
	assert_eq(missing.size(), 0,
		"selectable surface(s) with no authored cue — the player walks in silence there: %s" % [missing])


func test_the_override_does_not_disturb_battle_terrain() -> void:
	## THE POINT OF KEYING BY MAP. _get_terrain_for_map must still hand tavern_interior
	## to the battle systems as "village"; only the FLOOR differs.
	var src: String = FileAccess.get_file_as_string(GL)
	assert_gt(src.length(), 0, "control: GameLoop.gd unreadable")
	var idx: int = src.find("\"harmonia_village\", \"tavern_interior\"")
	assert_gt(idx, -1,
		"tavern_interior no longer shares the village terrain arm — if that was deliberate, this test's premise is stale and the override may now be redundant")
	## Find the NEXT return after the arm rather than guessing a window — that arm lists
	## five map ids and a fixed 120-char span fell short of it, which is the
	## proximity-is-not-scope trap inside the test written to avoid guessing.
	var ret: int = src.find("return \"", idx)
	assert_gt(ret, -1, "control: no return follows the tavern_interior arm — the parse is broken")
	var close: int = src.find("\"", ret + 8)
	var terrain: String = src.substr(ret + 8, close - ret - 8)
	assert_eq(terrain, "village",
		"tavern_interior must still resolve to the 'village' battle terrain (got '%s'); the wooden floor is a FOOTSTEP override, not a terrain change" % terrain)


func test_every_terrain_the_resolver_can_receive_is_mapped() -> void:
	## cowir-main's requested pin: 18/18 today, and it stays provable. An unmapped
	## terrain silently defaults to grass, which is how a wrong floor ships unnoticed.
	var src: String = FileAccess.get_file_as_string(GL)
	var start: int = src.find("func _get_terrain_for_map")
	assert_gt(start, -1, "control: _get_terrain_for_map not found — the sweep below is vacuous")
	var stop: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (stop - start) if stop > -1 else 4000)
	var returned: Array[String] = []
	var cursor: int = 0
	while true:
		var r: int = body.find("return \"", cursor)
		if r < 0:
			break
		var q: int = body.find("\"", r + 8)
		if q < 0:
			break
		var t: String = body.substr(r + 8, q - r - 8)
		if not returned.has(t):
			returned.append(t)
		cursor = q + 1
	assert_gt(returned.size(), 10,
		"control: parsed only %d returned terrains — the walk is broken, so the assert below checked almost nothing" % returned.size())
	var terrain_map: Dictionary = (_consts().get("_FOOTSTEP_TERRAIN_MAP") as Dictionary)
	var unmapped: Array[String] = []
	for t in returned:
		if not terrain_map.has(t):
			unmapped.append(t)
	assert_eq(unmapped.size(), 0,
		"terrain(s) _get_terrain_for_map returns with no footstep mapping — they silently default to grass: %s" % [unmapped])
