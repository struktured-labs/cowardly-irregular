extends GutTest

## tick 68 regression: every W2-W6 interior must override
## _get_music_track() to return a key SoundManager.play_area_music
## actually maps to the matching world music.
##
## Original silent bug (caught in tick 68 audit): BaseInterior's
## default _get_music_track() returns "village" which the
## SoundManager match arm routes to medieval Harmonia music. Without
## per-interior overrides, the W2 arcade / W3 clockwork loft / etc
## would all play medieval music — clearly wrong for each world's
## tone. W1 interiors keep the default (medieval village music IS
## right for them).

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


## Each entry: [interior path, expected music key (must match a
## play_area_music match arm in SoundManager.gd)]
const W2_TO_W6_INTERIOR_MUSIC: Array[Array] = [
	["res://src/maps/interiors/MapleHeightsArcadeInterior.gd",   "maple_heights_village"],
	["res://src/maps/interiors/BrasstonClockworkLoftInterior.gd", "brasston_village"],
	["res://src/maps/interiors/RivetRowUnionHallInterior.gd",     "rivet_row_village"],
	["res://src/maps/interiors/NodePrimeDaemonLoungeInterior.gd", "node_prime_village"],
	["res://src/maps/interiors/VertexThresholdInterior.gd",       "vertex_village"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_each_w2_w6_interior_overrides_music_track() -> void:
	for entry in W2_TO_W6_INTERIOR_MUSIC:
		var path: String = entry[0]
		var expected: String = entry[1]
		var src := _read(path)
		assert_true(src.contains("func _get_music_track() -> String"),
			"%s must override _get_music_track — default 'village' plays medieval music in the wrong world" % path)
		assert_true(src.contains("return \"" + expected + "\""),
			"%s must return %s — matches the SoundManager play_area_music arm for the right world" % [path, expected])


func test_expected_music_keys_resolve_in_sound_manager() -> void:
	# The interior overrides reference keys SoundManager.play_area_music
	# must recognize. Otherwise the override is for nothing.
	var src := _read(SOUND_MANAGER)
	for entry in W2_TO_W6_INTERIOR_MUSIC:
		var expected: String = entry[1]
		var quoted: String = "\"" + expected + "\""
		assert_true(src.contains(quoted),
			"SoundManager.play_area_music must have a case for '%s' — interior override depends on it" % expected)


func test_w1_interiors_keep_default_village_music() -> void:
	# W1 interiors should NOT override — they correctly use the
	# default 'village' music. This negative assertion catches a
	# regression where someone copies the W2-W6 pattern into a W1
	# interior and accidentally points it at the wrong world.
	for path in [
		"res://src/maps/interiors/HarmoniaChapelInterior.gd",
		"res://src/maps/interiors/HarmoniaLibraryInterior.gd",
		"res://src/maps/interiors/EldertreeHollowTreeInterior.gd",
		"res://src/maps/interiors/FrostholdWardenHutInterior.gd",
		"res://src/maps/interiors/SandriftGlassmakerInterior.gd",
		"res://src/maps/interiors/GrimhollowWitchHutInterior.gd",
		"res://src/maps/interiors/IronhavenWatchtowerInterior.gd",
	]:
		var src := _read(path)
		assert_false(src.contains("func _get_music_track() -> String"),
			"%s must NOT override _get_music_track — W1 interiors use BaseInterior's default 'village' music (correct for medieval world)" % path)
