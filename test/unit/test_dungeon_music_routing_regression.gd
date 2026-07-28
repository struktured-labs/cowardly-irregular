extends GutTest

## Every DragonCave subclass must route to a music area key SoundManager
## actually matches (2026-07-28).
##
## The four W1 dragon caves never overrode `_get_music_area_id()`, so they
## inherited "cave" -> _start_dungeon_music("medieval") and all four played
## the generic dungeon bed. Meanwhile SoundManager carried four dedicated
## arms ("fire_dragon_cave" etc.) and two composed tracks sat on disk
## (dungeon_dragon_fire 139s, dungeon_dragon_ice 178s) that NOTHING reached
## on the normal path — the only live route was GameLoop._stop_autogrind,
## which passes _current_map_id, so the bespoke themes played solely if you
## started and then stopped an autogrind session inside the cave.
##
## The second half matters as much as the first: play_area_music's default
## arm is _start_overworld_music(), NOT a cave fallback. So a subclass
## returning an unmatched key plays OVERWORLD music inside a dungeon — worse
## than the bug being fixed. That is why this asserts the key RESOLVES
## rather than merely asserting each subclass overrides.

const DUNGEON_DIR := "res://src/maps/dungeons/"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


## Area keys SoundManager's play_area_music match actually handles, parsed
## from the source rather than listed here — a maintained copy would drift
## the first time someone adds a dungeon.
func _matched_area_keys() -> Array:
	var src := _read(SOUND_MANAGER)
	var start := src.find("func play_area_music")
	assert_true(start > -1, "play_area_music must exist")
	var body := src.substr(start)
	var keys: Array = []
	var re := RegEx.new()
	re.compile('"([a-z0-9_]+)"[,:]')
	for m in re.search_all(body.substr(0, body.find("\nfunc _start_overworld_music"))):
		keys.append(m.get_string(1))
	return keys


func _dungeon_scripts() -> Array:
	var out: Array = []
	var d := DirAccess.open(DUNGEON_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(f)
		f = d.get_next()
	return out


func test_positive_control_parser_sees_the_dispatch() -> void:
	## A sweep that silently parsed nothing would make every assertion below
	## vacuously true.
	var keys := _matched_area_keys()
	assert_gt(keys.size(), 15,
		"parsed too few area keys from play_area_music — the parser broke, so an empty offender list proves nothing")
	assert_true(keys.has("fire_dragon_cave"),
		"positive control: the fire dragon arm must be visible to the parser")
	assert_gt(_dungeon_scripts().size(), 8, "expected to find the dungeon scripts on disk")


func test_every_dungeon_music_key_resolves() -> void:
	var keys := _matched_area_keys()
	var offenders: Array = []
	for f in _dungeon_scripts():
		var src := _read(DUNGEON_DIR + f)
		var idx := src.find("func _get_music_area_id")
		if idx == -1:
			continue  # base-class default; covered by the dragon-cave test below
		var body := src.substr(idx, 220)
		var re := RegEx.new()
		re.compile('return\\s+"([a-z0-9_]+)"')
		var m := re.search(body)
		if m == null:
			continue
		var key := m.get_string(1)
		if not keys.has(key):
			offenders.append("%s returns \"%s\" — unmatched, so play_area_music falls to _start_overworld_music() and plays OVERWORLD music inside a dungeon" % [f, key])
	assert_eq(offenders, [], "\n".join(offenders))


func test_w1_dragon_caves_route_to_their_own_theme() -> void:
	## The regression proper. Each must override, and to its own arm.
	var expected := {
		"FireDragonCave.gd": "fire_dragon_cave",
		"IceDragonCave.gd": "ice_dragon_cave",
		"LightningDragonCave.gd": "lightning_dragon_cave",
		"ShadowDragonCave.gd": "shadow_dragon_cave",
	}
	var keys := _matched_area_keys()
	for f in expected:
		var src := _read(DUNGEON_DIR + f)
		assert_true(src.find("func _get_music_area_id") > -1,
			"%s must override _get_music_area_id — inheriting \"cave\" plays the generic medieval bed and its own composed theme never reaches the player" % f)
		assert_true(src.find('return "%s"' % expected[f]) > -1,
			"%s must route to \"%s\"" % [f, expected[f]])
		assert_true(keys.has(expected[f]),
			"SoundManager must carry an arm for \"%s\"" % expected[f])
