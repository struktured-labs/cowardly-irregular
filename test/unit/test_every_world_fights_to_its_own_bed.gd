extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const SM_PATH := "res://src/audio/SoundManager.gd"

## ⛔ THE FOUR GENERIC MUSIC KEYS ARE REWRITTEN PER WORLD INSIDE play_music, AND NOTHING DROVE THAT
## REWRITE. `play_music("boss")`, `("victory")` and `("danger")` are what BattleScene actually calls —
## the world never appears at the call site — and `play_music` maps each onto `<key>_<suffix>` from the
## cached world. The ancestor of this is recorded in `_get_current_world_suffix`'s own docstring: a
## `_current_world_suffix` initialised to "medieval" once made EVERY battle in worlds 2-6 play World
## 1's music, and the fallthrough that caused it is still the designed behaviour of that function.
##
## 🔑 VILLAGES, INTERIORS AND DUNGEONS ALL HAVE PER-WORLD GUARDS. This family had none: existing
## coverage drives `play_area_music`, and these four go through the OTHER entry point with a different
## resolver. 24 pairs, and every one of them is a bed a player hears in a fight.
##
## Derived on both axes — the suffixes from WeatherSystem.WORLD_IDS (the canonical vocabulary) and the
## keys from play_music's own `match generic_id:` arms — so a fifth generic key or a seventh world is
## covered when it is declared rather than when somebody remembers this file.

var _suffixes: Dictionary = {}
var _generic_keys: Array = []
var _saved_world: int = 1


func before_all() -> void:
	_suffixes = WeatherSystem.WORLD_IDS.duplicate()
	_generic_keys = _generic_arms()
	_saved_world = int(GameState.current_world)


func after_all() -> void:
	GameState.current_world = _saved_world
	SoundState.restore()


## The keys play_music itself rewrites: the arms of `match generic_id:`. Read from source because the
## rewrite is a private detail of that function and a hand list goes stale the day a fifth is added.
func _generic_arms() -> Array:
	var code: String = FileAccess.get_file_as_string(SM_PATH)
	var i: int = code.find("match generic_id:")
	if i < 0:
		return []
	var out: Array = []
	for line in code.substr(i, 700).split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("\"") and s.ends_with("\":"):
			out.append(s.substr(1, s.length() - 3))
		elif out.size() > 0 and not s.begins_with("manifest_track_id") and s != "":
			break
	return out


func test_floor_both_axes_were_derived() -> void:
	assert_gt(_suffixes.size(), 5,
		"FLOOR: WeatherSystem.WORLD_IDS yielded %d worlds — the canonical vocabulary moved" % _suffixes.size())
	assert_gt(_generic_keys.size(), 3,
		"FLOOR: only %d generic keys extracted from play_music's `match generic_id:` (%s) — the rewrite was renamed and this file would be about nothing" % [_generic_keys.size(), str(_generic_keys)])
	for k in _generic_keys:
		assert_false(str(k).contains("_"),
			"FLOOR: '%s' is not a GENERIC key — the extractor picked up the wrong block" % k)


## The link my other arm deliberately skips: it WRITES `_current_world_suffix` to isolate play_music's
## rewrite, so the resolver that fills that cache is not in its path — proved by mutation, stubbing
## `_get_current_world_suffix` to a constant left it green. This arm drives the real chain instead:
## an overworld AREA sets the cache through the resolver, and a battle then reads it.
##
## The area->suffix pairs are read from the resolver's OWN match arms, which is also where the one
## mismatch a hand list gets wrong lives: World 5's area key is `overworld_futuristic` and its suffix
## is `digital`.
func test_the_area_a_player_left_is_what_the_fight_inherits() -> void:
	var code: String = FileAccess.get_file_as_string(SM_PATH)
	var i: int = code.find("\tmatch _current_area:")
	assert_gt(i, -1, "FLOOR: _get_current_world_suffix's `match _current_area:` was not found")
	var pending: Array = []
	var pairs: Dictionary = {}
	for line in code.substr(i, 1800).split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("\"") and t.ends_with(":"):
			pending = []
			for m in RegEx.create_from_string('"([^"]+)"').search_all(t):
				if m.get_string(1).begins_with("overworld"):
					pending.append(m.get_string(1))
		elif t.begins_with("return \"") and not pending.is_empty():
			var suf: String = t.substr(8, t.length() - 9)
			for a in pending:
				pairs[a] = suf
			pending = []
		elif t.begins_with("_:"):
			break
	assert_gt(pairs.size(), 5,
		"FLOOR: only %d overworld area ids extracted from the resolver (%s) — its match was reshaped" % [pairs.size(), str(pairs)])

	for area in pairs.keys():
		SoundState.restore()
		SoundManager._current_world_suffix = "medieval"
		SoundManager.play_area_music(str(area))
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(str(SoundManager._current_world_suffix), str(pairs[area]),
			"standing in '%s' must cache '%s' — the cache is the ONLY world source once play_music clears the area, so a wrong one scores every fight in that world from somewhere else" % [area, str(pairs[area])])
		SoundManager.play_music("battle")
		var want_id: String = "battle_%s" % str(pairs[area])
		if not SoundManager._music_manifest.has(want_id):
			continue
		var want: String = str(SoundManager._music_manifest[want_id].get("file", "")).get_file()
		assert_not_null(SoundManager._music_player.stream,
			"FLOOR: a fight after '%s' loaded no stream at all" % area)
		var got: String = SoundManager._music_player.stream.resource_path.get_file() if SoundManager._music_player.stream else "<none>"
		assert_eq(got, want,
			"a fight entered from '%s' played %s instead of %s" % [area, got, want])


func test_every_world_fights_to_its_own_bed() -> void:
	SoundManager._load_music_manifest()
	var pairs: int = 0
	for world_num in _suffixes.keys():
		var suffix: String = str(_suffixes[world_num])
		for key in _generic_keys:
			var want_id: String = "%s_%s" % [key, suffix]
			## Only worlds that AUTHORED this bed make a claim; anywhere else the code degrades on
			## purpose and pinning the degraded answer would be pinning today's manifest.
			if not SoundManager._music_manifest.has(want_id):
				continue
			var want_file: String = str(SoundManager._music_manifest[want_id].get("file", "")).get_file()
			assert_ne(want_file, "",
				"FLOOR: manifest entry '%s' names no file, so the comparison below is vacuous" % want_id)

			SoundState.restore()
			GameState.current_world = int(world_num)
			SoundManager._current_world_suffix = suffix
			SoundManager._current_area = ""
			SoundManager.play_music(key)

			## ⛔ PER-PAIR FLOOR, INSIDE THE LOOP. A null stream makes the path assert vacuously true
			## for that world and reads exactly like a pair that passed.
			assert_not_null(SoundManager._music_player.stream,
				"FLOOR: play_music(\"%s\") in %s loaded no stream at all" % [key, suffix])
			var got: String = SoundManager._music_player.stream.resource_path.get_file() if SoundManager._music_player.stream else "<none>"
			assert_eq(got, want_file,
				"play_music(\"%s\") in world %d (%s) played %s — the manifest authors %s for this world, so a fight here is scored by somewhere else" % [key, int(world_num), suffix, got, want_file])
			pairs += 1

	## Aggregate anti-vacuity, on top of the per-pair floors rather than instead of them: this catches a
	## total failure (no manifest, an empty vocabulary) and is structurally blind to one world going dark.
	assert_gt(pairs, 20,
		"FLOOR: only %d (world, key) pairs were judged — %d worlds x %d keys should give far more" % [pairs, _suffixes.size(), _generic_keys.size()])
