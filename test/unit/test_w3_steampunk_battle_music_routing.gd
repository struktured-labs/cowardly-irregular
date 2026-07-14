extends GutTest

## tick 91 regression: W3 Steampunk battles must play the
## battle_steampunk music track, not generic battle music. Pre-fix,
## _get_terrain_battle_track had arms for suburban/urban/industrial/
## digital/void but NOT for steampunk — even though SoundManager had
## a dedicated _start_urban_battle_music helper that actually played
## the manifest's battle_steampunk.ogg. So W3 battles fell through
## to the default "battle" generic track, silently dropping the
## world's intended theme.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _terrain_battle_track_body() -> String:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _get_terrain_battle_track")
	assert_gt(idx, -1, "_get_terrain_battle_track must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_steampunk_terrain_maps_to_battle_steampunk_track() -> void:
	# Pin the new arm exactly. A future refactor renaming this would
	# silently drop W3 back to generic battle music.
	var body := _terrain_battle_track_body()
	assert_true(body.contains("\"steampunk\":\n\t\t\treturn \"battle_steampunk\""),
		"_get_terrain_battle_track must have 'steampunk' arm returning 'battle_steampunk' — otherwise W3 Steampunk battles fall through to generic 'battle' track")


func test_existing_terrain_arms_preserved() -> void:
	# Don't regress the other W2/W4/W5/W6 routing while adding W3.
	var body := _terrain_battle_track_body()
	for entry in [
		["suburban",  "battle_suburban"],
		["urban",     "battle_urban"],
		["industrial","battle_industrial"],
		["digital",   "battle_digital"],
		["void",      "battle_void"],
	]:
		var terrain: String = entry[0]
		var track: String = entry[1]
		var pattern: String = "\"" + terrain + "\":\n\t\t\treturn \"" + track + "\""
		assert_true(body.contains(pattern),
			"_get_terrain_battle_track must keep '%s' → '%s' arm" % [terrain, track])


func test_sound_manager_handles_battle_steampunk_key() -> void:
	# Pin: SoundManager match must route 'battle_steampunk' through
	# _start_urban_battle_music (which actually plays the
	# battle_steampunk.ogg manifest track).
	var src := _read(SOUND_MANAGER)
	# Match arm grouping both keys onto the same handler.
	assert_true(src.contains("\"battle_steampunk\", \"battle_urban\":\n\t\t\t_start_urban_battle_music()"),
		"SoundManager match must group 'battle_steampunk' and 'battle_urban' onto _start_urban_battle_music — the helper plays the battle_steampunk.ogg track from manifest")


func test_start_urban_battle_music_still_plays_steampunk_manifest_key() -> void:
	# Sanity: the helper still tries manifest key 'battle_steampunk'
	# first. If a future refactor renames that key, the routing
	# above silently breaks.
	var src := _read(SOUND_MANAGER)
	var idx: int = src.find("func _start_urban_battle_music")
	assert_gt(idx, -1, "_start_urban_battle_music helper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_try_play_from_manifest(\"battle_steampunk\")"),
		"_start_urban_battle_music must try manifest key 'battle_steampunk' first — that's the .ogg this helper is named for")
