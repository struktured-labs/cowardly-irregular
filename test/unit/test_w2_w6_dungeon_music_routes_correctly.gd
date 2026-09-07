extends GutTest

## tick 93 regression: every W2-W6 dungeon subclass must override
## _get_music_area_id to return their per-world manifest key.
## Pre-fix, DragonCave hardcoded SoundManager.play_area_music("cave")
## and SoundManager grouped "cave" + "whispering_cave" onto
## _start_dungeon_music("medieval") — so all W2-W6 dungeons
## (SuburbanUnderground, SteampunkMechanism, AssemblyCore,
## RootProcess, NullChamber) played the W1 medieval dungeon track.
##
## The "suburban_dungeon" / "steampunk_dungeon" / "industrial_dungeon"
## / "digital_dungeon" / "abstract_dungeon" match arms existed in
## SoundManager but were never reached.

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


const W2_W6_DUNGEONS: Array[Array] = [
	["res://src/maps/dungeons/SuburbanUnderground.gd",  "suburban_dungeon"],
	["res://src/maps/dungeons/SteampunkMechanism.gd",   "steampunk_dungeon"],
	["res://src/maps/dungeons/AssemblyCore.gd",         "industrial_dungeon"],
	["res://src/maps/dungeons/RootProcess.gd",          "digital_dungeon"],
	["res://src/maps/dungeons/NullChamber.gd",          "abstract_dungeon"],
]


## The W1 dragon caves were pinned here as deliberately keeping the default
## "cave" key. That was wrong, and this file's own header says why: it fixed
## W2-W6 because "the match arms existed in SoundManager but were never
## reached" — equally true of the four caves it exempted. SoundManager carries
## "fire_dragon_cave" -> _start_dungeon_music("dragon_fire") and three
## siblings, and dungeon_dragon_fire (139s) / dungeon_dragon_ice (178s) are
## composed and on disk. Nobody writes a 178-second Ice Dragon theme and a
## routing arm intending neither to run. Pin flipped 2026-07-28; the caves now
## override, and test_dungeon_music_routing_regression carries the general
## invariant (every key must resolve against the dispatch).
const W1_DRAGON_CAVES: Array[String] = [
	"res://src/maps/dungeons/FireDragonCave.gd",
	"res://src/maps/dungeons/IceDragonCave.gd",
	"res://src/maps/dungeons/LightningDragonCave.gd",
	"res://src/maps/dungeons/ShadowDragonCave.gd",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_dragon_cave_uses_virtual_hook_not_hardcoded_key() -> void:
	var src := _read(DRAGON_CAVE)
	assert_true(src.contains("SoundManager.play_area_music(_get_music_area_id())"),
		"DragonCave must call play_area_music(_get_music_area_id()) — hardcoded 'cave' makes W2-W6 dungeons play medieval dungeon music")
	assert_false(src.contains("SoundManager.play_area_music(\"cave\")"),
		"DragonCave must NOT pass hardcoded 'cave' — regression class is back if this string appears")


func test_dragon_cave_hook_defaults_to_cave() -> void:
	# Default ensures W1 dragon caves continue routing through the
	# medieval dungeon track.
	var src := _read(DRAGON_CAVE)
	var idx: int = src.find("func _get_music_area_id")
	assert_gt(idx, -1, "_get_music_area_id virtual hook must exist on DragonCave")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("return \"cave\""),
		"_get_music_area_id default must return 'cave' — preserves W1 dragon cave routing")


func test_every_w2_w6_dungeon_overrides_music_hook() -> void:
	for entry in W2_W6_DUNGEONS:
		var path: String = entry[0]
		var expected_key: String = entry[1]
		var src := _read(path)
		assert_true(src.contains("func _get_music_area_id() -> String"),
			"%s must override _get_music_area_id" % path)
		assert_true(src.contains("return \"" + expected_key + "\""),
			"%s _get_music_area_id must return '%s'" % [path, expected_key])


func test_each_expected_key_maps_to_a_play_area_music_arm() -> void:
	var src := _read(SOUND_MANAGER)
	for entry in W2_W6_DUNGEONS:
		var expected_key: String = entry[1]
		var quoted: String = "\"" + expected_key + "\":"
		assert_true(src.contains(quoted),
			"SoundManager._start_area_music_deferred must have arm '%s' — without it, the call falls through to overworld default" % expected_key)


func test_w1_dragon_caves_route_to_their_own_arm() -> void:
	# Was a negative pin asserting these must NOT override. It locked in the
	# same defect this file fixed for W2-W6: all four played the generic
	# medieval bed while their own arms and themes sat unreached.
	var sm := _read(SOUND_MANAGER)
	for path in W1_DRAGON_CAVES:
		var src := _read(path)
		assert_true(src.contains("func _get_music_area_id()"),
			"%s must override _get_music_area_id — inheriting \"cave\" plays the generic medieval bed" % path)
		var key: String = path.get_file().replace(".gd", "").to_snake_case().replace("_dragon_cave", "")
		var expected: String = key + "_dragon_cave"
		assert_true(src.contains('return "%s"' % expected),
			"%s must route to \"%s\"" % [path, expected])
		assert_true(sm.contains('"%s"' % expected),
			"SoundManager must carry an arm for \"%s\" — without it play_area_music falls to the overworld default" % expected)
