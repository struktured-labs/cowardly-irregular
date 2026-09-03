extends GutTest

## BattleScene drives BOTH the size bump and sprite.flip_h off frame height alone, so a sheet whose flip is BAKED into its pixels is only correct above that threshold — move it below and it double-flips silently.

const MANIFEST := "res://data/sprite_manifest.json"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"

# phrases the ingest pipeline writes when it bakes a horizontal flip into the pixels
const BAKED_MARKERS := ["FLIP IS BAKED", "flip baked", "FLIPPED on ingest", "flipped on ingest"]


func _threshold() -> int:
	var src := FileAccess.get_file_as_string(BATTLE_SCENE)
	assert_ne(src, "", "BattleScene must be readable — the threshold is read from it, not copied")
	var re := RegEx.new()
	re.compile("ENEMY_SMALL_FRAME_THRESHOLD\\s*:\\s*int\\s*=\\s*(\\d+)")
	var m := re.search(src)
	assert_not_null(m, "ENEMY_SMALL_FRAME_THRESHOLD must still be declared in BattleScene")
	return int(m.get_string(1)) if m else -1


func _sheets() -> Dictionary:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(txt, "", "sprite_manifest.json must be readable")
	var parsed = JSON.parse_string(txt)
	return (parsed as Dictionary).get("monster_sheets", {}) if parsed is Dictionary else {}


func _is_baked(entry: Dictionary) -> bool:
	var src := str(entry.get("source", ""))
	for marker in BAKED_MARKERS:
		if src.findn(marker) != -1:
			return true
	return false


func test_a_baked_flip_only_ships_above_the_engine_threshold() -> void:
	var threshold := _threshold()
	assert_gt(threshold, 0, "CONTROL: threshold must parse to a real number, got %d" % threshold)
	var sheets := _sheets()
	assert_gt(sheets.size(), 50, "CONTROL: manifest must carry the monster roster (%d)" % sheets.size())
	var baked: Array = []
	var offenders: Array = []
	for id in sheets:
		var e: Dictionary = sheets[id]
		if not _is_baked(e):
			continue
		baked.append(id)
		var fh := int(e.get("frame_height", 0))
		if fh <= threshold:
			offenders.append("%s: flip is baked but frame_height %d <= %d, so the engine flips it AGAIN" % [id, fh, threshold])
	# a known-present member: the scan is worthless if it finds no baked sheet at all
	assert_true(baked.has("cave_rat"), "CONTROL: cave_rat's source declares a baked flip — scan found %s" % [baked])
	assert_eq(offenders, [], "a baked flip below the threshold double-flips and faces the monster away from the party: %s" % [offenders])
