extends GutTest

## Regression pin (2026-07-16): battle_slime + battle_bat shipped with
## .import loop=false while music_manifest.json declared loop=true —
## slime battles cut to silence after 60.7s and bat battles after 160s.
##
## Root cause: SoundManager._start_monster_music bypasses the manifest
## entirely (loads OGG directly via ResourceLoader.exists), so the
## .import file is authoritative for runtime loop behavior. Manifest
## loop key + .import loop key MUST agree.
##
## This test walks the 9 monster tracks and asserts .import loop matches
## the manifest — catches both directions of drift (loop-should-be-true
## and loop-should-be-false) for every battle_<monster>.ogg.

const MANIFEST_PATH := "res://data/music_manifest.json"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _import_loop_flag(ogg_res_path: String) -> String:
	## Read `loop=` from an .import file. Returns "true", "false", or "" if absent.
	var text: String = _read(ogg_res_path + ".import")
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("loop="):
			return stripped.substr(len("loop=")).strip_edges().to_lower()
	return ""


func test_battle_monster_import_loop_matches_manifest() -> void:
	var text: String = _read(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary and parsed.has("tracks"),
		"music_manifest.json must parse into {tracks: {...}}")
	var tracks: Dictionary = parsed["tracks"]

	var checked: int = 0
	for key in tracks.keys():
		var k: String = str(key)
		if not k.begins_with("battle_"):
			continue
		# Skip world-scoped tracks (battle_medieval etc.) — this test only
		# covers the per-monster tracks _start_monster_music loads directly.
		var stripped: String = k.substr(len("battle_"))
		if stripped in ["medieval", "suburban", "steampunk", "industrial",
						"digital", "abstract"]:
			continue
		var entry: Dictionary = tracks[k]
		var ogg_path: String = entry.get("file", "")
		if ogg_path == "":
			continue  # placeholder-only entries
		if not ogg_path.begins_with("res://"):
			ogg_path = "res://" + ogg_path
		var manifest_loop: bool = bool(entry.get("loop", false))
		var import_loop_str: String = _import_loop_flag(ogg_path)
		assert_ne(import_loop_str, "",
			"battle track %s has no loop= in its .import (%s.import) — _start_monster_music loads via ResourceLoader so .import is authoritative" % [k, ogg_path])
		var import_loop: bool = import_loop_str == "true"
		assert_eq(import_loop, manifest_loop,
			"battle track %s: manifest.loop=%s but .import loop=%s — they MUST agree (SoundManager._start_monster_music bypasses the manifest, so the .import wins at runtime)" % [k, manifest_loop, import_loop_str])
		checked += 1
	assert_gt(checked, 0, "Expected at least one battle_<monster> track to check — walk over the manifest keys is broken if this trips")
