extends GutTest

## tick 92 regression: every W2-W6 village subclass must override
## _get_music_area_id to return their per-world manifest key so
## SoundManager plays the right village music. Pre-fix, BaseVillage
## hardcoded SoundManager.play_area_music("village"), and the match
## arm at SoundManager line ~4021 grouped "village" + "harmonia_village"
## onto _start_village_location_music("harmonia", "medieval") — so
## EVERY village (Maple Heights / Brasston / Rivet Row / Node Prime /
## Vertex) played Harmonia medieval music instead of the suburban /
## steampunk / industrial / digital / abstract village tracks that
## were already composed and live in data/music_manifest.json.

const BASE_VILLAGE := "res://src/maps/villages/BaseVillage.gd"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const MANIFEST := "res://data/music_manifest.json"


const W2_W6_VILLAGES: Array[Array] = [
	["res://src/maps/villages/MapleHeightsVillage.gd",  "maple_heights_village"],
	["res://src/maps/villages/BrasstonVillage.gd",      "brasston_village"],
	["res://src/maps/villages/RivetRowVillage.gd",      "rivet_row_village"],
	["res://src/maps/villages/NodePrimeVillage.gd",     "node_prime_village"],
	["res://src/maps/villages/VertexVillage.gd",        "vertex_village"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_base_village_uses_virtual_hook_not_hardcoded_key() -> void:
	# Pin the BaseVillage path — must call _get_music_area_id, not
	# pass the literal "village" string.
	var src := _read(BASE_VILLAGE)
	assert_true(src.contains("SoundManager.play_area_music(_get_music_area_id())"),
		"BaseVillage must call play_area_music(_get_music_area_id()) — hardcoded 'village' makes W2-W6 villages play Harmonia music")
	assert_false(src.contains("SoundManager.play_area_music(\"village\")"),
		"BaseVillage must NOT pass hardcoded 'village' — the regression class is back if this string appears")


func test_base_village_hook_defaults_to_village() -> void:
	# Default ensures W1 sub-villages (Sandrift / Eldertree / Grimhollow /
	# Ironhaven / Frosthold) continue routing through the medieval
	# Harmonia track — they have no per-village music composed.
	var src := _read(BASE_VILLAGE)
	var idx: int = src.find("func _get_music_area_id")
	assert_gt(idx, -1, "_get_music_area_id virtual hook must exist on BaseVillage")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("return \"village\""),
		"_get_music_area_id default must return 'village' — covers W1 sub-villages without per-village music")


func test_every_w2_w6_village_overrides_music_hook() -> void:
	for entry in W2_W6_VILLAGES:
		var path: String = entry[0]
		var expected_key: String = entry[1]
		var src := _read(path)
		assert_true(src.contains("func _get_music_area_id() -> String"),
			"%s must override _get_music_area_id" % path)
		assert_true(src.contains("return \"" + expected_key + "\""),
			"%s _get_music_area_id must return '%s' — matches the manifest key" % [path, expected_key])


func test_each_expected_key_maps_to_a_play_area_music_arm() -> void:
	# Sanity: each per-village key must have a match arm in SoundManager
	# _start_area_music_deferred. Without the arm, the call falls
	# through to the default `_:` arm which calls _start_overworld_music.
	var src := _read(SOUND_MANAGER)
	for entry in W2_W6_VILLAGES:
		var expected_key: String = entry[1]
		var quoted: String = "\"" + expected_key + "\":"
		assert_true(src.contains(quoted),
			"SoundManager._start_area_music_deferred must have arm '%s' — otherwise call falls through to overworld music default" % expected_key)


func test_manifest_actually_has_each_village_track() -> void:
	# Pin: the manifest must have an entry for each W2-W6 village
	# track id (the keys passed to _start_village_location_music
	# inside SoundManager's arms). If the manifest entry is missing,
	# the music silently falls back to procedural generation.
	var src := _read(MANIFEST)
	for entry in W2_W6_VILLAGES:
		var village_key: String = entry[1]
		# SoundManager's _start_village_location_music takes a short
		# name + world suffix and looks up "village_<name>" in
		# manifest. The short name for each:
		var short: String = village_key.replace("_village", "")
		var manifest_quoted: String = "\"village_" + short + "\""
		assert_true(src.contains(manifest_quoted),
			"music_manifest.json must have entry %s — that's the track the village_location helper plays" % manifest_quoted)


func test_w1_main_harmonia_village_keeps_default_music() -> void:
	# Negative pin: the Harmonia village must NOT override
	# _get_music_area_id. It IS the medieval village; the default
	# "village" key correctly routes to Harmonia music.
	var harmonia := _read("res://src/maps/villages/HarmoniaVillage.gd")
	assert_false(harmonia.contains("func _get_music_area_id()"),
		"HarmoniaVillage must NOT override _get_music_area_id — the default 'village' key already maps to Harmonia's medieval music in SoundManager")
