extends GutTest

## Regression test for tavern walk-speed bug (2026-05-20).
##
## Bug: User reported "character walks too fast in tavern". Root cause was
## that TavernInterior._setup_player relied on OverworldPlayer's parent-name
## keyword scan to detect interior context (which matches "tavern" via the
## INTERIOR_KEYWORDS list), but the scan ALSO falls back to
## MapSystem.current_map_id — and nothing in the codebase ever calls
## MapSystem.set_map() to populate that field. So the player ran at the
## overworld move_speed (240) instead of interior_speed (120).
##
## Fix: TavernInterior._setup_player now sets `player._is_interior = true`
## explicitly before add_child, matching the pattern BaseVillage uses.
## DragonCave and WhisperingCave already set the flag.
##
## Tests guard the explicit-flag pattern in source for each interior so a
## refactor that removes it (and reintroduces the heuristic-dependence
## bug) fails immediately.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_tavern_interior_sets_is_interior_flag_explicitly() -> void:
	"""TavernInterior._setup_player MUST set _is_interior = true on the
	player before add_child. Without this, the player runs at overworld
	speed in the tavern (parent-name heuristic + missing MapSystem wiring)."""
	var text = _read("res://src/maps/interiors/TavernInterior.gd")
	assert_true(text.find("player._is_interior = true") != -1,
		"TavernInterior must set _is_interior=true explicitly (regression: tavern walk speed too fast)")


func test_base_village_still_sets_interior_flag() -> void:
	"""Sanity check: BaseVillage was the original site of the explicit
	flag pattern. If this assertion breaks, every village inherits the
	bug because BaseVillage._setup_player is what they all use."""
	var text = _read("res://src/maps/villages/BaseVillage.gd")
	assert_true(text.find("player._is_interior = true") != -1,
		"BaseVillage._setup_player must set _is_interior=true (regression: village speed)")


func test_dungeons_set_interior_flag() -> void:
	"""Cave/dungeon scripts must also set the flag explicitly. The parent-
	name heuristic should be defense-in-depth, not the primary mechanism."""
	for path in [
		"res://src/maps/dungeons/DragonCave.gd",
		"res://src/maps/dungeons/WhisperingCave.gd",
	]:
		var text = _read(path)
		assert_true(text.find("_is_interior") != -1,
			"%s must reference _is_interior (regression: dungeon walk speed)" % path)


func test_overworld_player_interior_speed_lower_than_overworld() -> void:
	"""Defensive: interior_speed export must remain meaningfully slower
	than move_speed, or interior detection becomes cosmetic. The fix is
	useless if both speeds are the same."""
	var text = _read("res://src/exploration/OverworldPlayer.gd")
	# Source-level check (script not instantiable headless without a scene)
	var move_idx = text.find("@export var move_speed: float =")
	var interior_idx = text.find("@export var interior_speed: float =")
	assert_gt(move_idx, -1, "move_speed export must exist")
	assert_gt(interior_idx, -1, "interior_speed export must exist")
	# Pull numeric values from each line
	var move_line = text.substr(move_idx, text.find("\n", move_idx) - move_idx)
	var interior_line = text.substr(interior_idx, text.find("\n", interior_idx) - interior_idx)
	# crude float extraction — find "= NN.N"
	var move_val = float(move_line.split("=")[-1].strip_edges().split(" ")[0])
	var interior_val = float(interior_line.split("=")[-1].strip_edges().split(" ")[0])
	assert_gt(move_val, interior_val,
		"move_speed (%f) must be greater than interior_speed (%f) — otherwise the fix is cosmetic" % [move_val, interior_val])
