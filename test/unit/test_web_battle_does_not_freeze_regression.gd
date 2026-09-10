extends GutTest

## Starting a battle in W4-W6 must not freeze the web build.
##
## MEASURED 2026-09-10, real path, world suffix actually set:
##
##     _start_battle_music   world=abstract/digital/industrial   ~8,550 ms
##     _start_boss_music     same                                ~2,150 ms
##     _start_industrial_battle_music                             1,574 ms
##     _start_digital_battle_music                                1,414 ms
##
## Per-sample GDScript on the main thread, at the battle transition. Battles are
## far more frequent than a W6 overworld visit, so this bites harder than the
## 19.9s overworld freeze fixed alongside it.
##
## 🛑 MY FIRST BENCHMARK SAID 5 ms AND WAS WRONG, which is the part worth
## keeping. It called _start_battle_music without setting
## _current_world_suffix, so the cached default "medieval" applied and
## battle_medieval — a bed that SHIPS — loaded instantly. The function reads
## `battle_ + _get_current_world_suffix()`, so a probe that does not set the
## world is not exercising the web condition at all; it measures W1 and reports
## it as W6. The control has to instantiate the measured quantity.
##
## 🔑 WHY WEB ONLY: the Web preset drops *industrial*, *digital*, *abstract*.
## On desktop tier 1 hits and no generator runs, so no desktop run reaches this.
##
## THE ROUTE IN, traced rather than assumed: a W4 monster has no bed of its own,
## so play_music("battle_rust_elemental") rewrites the MANIFEST ID to
## battle_industrial — but the `match` below still switches on the ORIGINAL
## track string, which has no arm, so `_:` sends it to _start_battle_music.
## That is the 8.5s path, and it is the ordinary case for every W4-W6 encounter.
##
## THE TRADE: on web those fights now use the medieval battle bed instead of a
## generated theme. Those worlds' authored music is already absent there by
## design; this swaps an 8.5-second freeze for the wrong-but-instant bed.

const SM := "res://src/audio/SoundManager.gd"

## The defect is 1,400-8,600 ms and the fallback is a load(). Two orders of
## margin, so this cannot go red for timing noise.
const NO_GENERATION_MS := 600

var _saved: Dictionary = {}


func before_each() -> void:
	SoundManager._load_music_manifest()
	SoundManager._music_cache.clear()


func after_each() -> void:
	for k in _saved.keys():
		SoundManager._music_manifest[k] = _saved[k]
	_saved = {}
	SoundManager._current_world_suffix = "medieval"
	SoundManager._current_area = ""
	SoundManager.stop_music()


func _hide(key: String) -> void:
	## _music_manifest is STATIC and shared across tests — restored above.
	if SoundManager._music_manifest.has(key):
		_saved[key] = SoundManager._music_manifest[key]
	SoundManager._music_manifest[key] = {"file": "assets/audio/music/zzq_not_in_this_build.ogg"}


func _played() -> String:
	if SoundManager._music_player.stream == null:
		return ""
	return str(SoundManager._music_player.stream.resource_path)


func test_control_the_probe_sets_the_world_it_claims_to_measure() -> void:
	## Guards against exactly the mistake that produced a false 5 ms reading:
	## if setting the suffix does not take, every timing arm below measures W1.
	SoundManager._current_world_suffix = "abstract"
	SoundManager._current_area = ""
	assert_eq(SoundManager._get_current_world_suffix(), "abstract",
		"CONTROL FAILED: the world suffix did not stick, so every arm below is measuring medieval and cannot see the defect")


func test_battle_in_an_excluded_world_falls_back_instead_of_generating() -> void:
	for world in ["abstract", "digital", "industrial"]:
		SoundManager._music_cache.clear()
		SoundManager._current_world_suffix = world
		SoundManager._current_area = ""
		_hide("battle_" + world)
		var t0: int = Time.get_ticks_msec()
		SoundManager._start_battle_music()
		var ms: int = Time.get_ticks_msec() - t0
		var path: String = _played()
		for k in _saved.keys():
			SoundManager._music_manifest[k] = _saved[k]
		_saved = {}
		assert_lt(ms, NO_GENERATION_MS,
			"a battle in the %s world took %d ms — the shipped-bed tier did not fire and the generator ran on the main thread at the battle transition (measured ~8,550 ms)" % [world, ms])
		assert_true(path.contains("battle_medieval"),
			"expected the shipped medieval battle bed in world %s, got %s" % [world, path])


func test_boss_in_an_excluded_world_falls_back_too() -> void:
	for world in ["abstract", "digital", "industrial"]:
		SoundManager._music_cache.clear()
		SoundManager._current_world_suffix = world
		SoundManager._current_area = ""
		_hide("boss_" + world)
		var t0: int = Time.get_ticks_msec()
		SoundManager._start_boss_music()
		var ms: int = Time.get_ticks_msec() - t0
		var path: String = _played()
		for k in _saved.keys():
			SoundManager._music_manifest[k] = _saved[k]
		_saved = {}
		assert_lt(ms, NO_GENERATION_MS,
			"a boss fight in the %s world took %d ms — the generator ran (measured ~2,150 ms)" % [world, ms])
		assert_true(path.contains("boss_medieval"),
			"expected the shipped medieval boss bed in world %s, got %s" % [world, path])


func test_the_two_per_world_battle_variants_fall_back_too() -> void:
	## These were inconsistent with their own generic sibling, which has always
	## had a shipped tier.
	for pair in [["battle_industrial", "_start_industrial_battle_music"],
				 ["battle_digital", "_start_digital_battle_music"]]:
		SoundManager._music_cache.clear()
		_hide(pair[0])
		var t0: int = Time.get_ticks_msec()
		SoundManager.call(pair[1])
		var ms: int = Time.get_ticks_msec() - t0
		for k in _saved.keys():
			SoundManager._music_manifest[k] = _saved[k]
		_saved = {}
		assert_lt(ms, NO_GENERATION_MS,
			"%s took %d ms with %s hidden — it generated instead of falling back" % [pair[1], ms, pair[0]])


func test_a_present_bed_still_wins_so_desktop_is_unchanged() -> void:
	## The tier must be a FALLBACK. Nothing about a desktop run may change.
	SoundManager._current_world_suffix = "industrial"
	SoundManager._current_area = ""
	SoundManager._start_battle_music()
	assert_true(_played().contains("battle_industrial"),
		"with its own bed present the industrial world played %s — the fallback tier is jumping the queue and would change every desktop run" % _played())


func test_world_one_is_untouched() -> void:
	## suffix == "medieval" must take tier 1 and never consult the new tier;
	## the guard exists so it cannot re-try the key it just tried.
	SoundManager._current_world_suffix = "medieval"
	SoundManager._current_area = ""
	SoundManager._start_battle_music()
	assert_true(_played().contains("battle_medieval"),
		"W1 battle played %s instead of its own bed" % _played())

	var src: String = FileAccess.get_file_as_string(SM)
	assert_gt(src.find("suffix != \"medieval\" and _try_play_from_manifest(\"battle_medieval\")"), 0,
		"the medieval guard is gone — in W1 the new tier would re-try the key tier 1 just failed, which is a wasted load and a misleading log line")


func test_the_fallback_is_ordered_before_the_generator() -> void:
	## Ordering is the fix. After the generate call it prevents nothing, and no
	## timing assert would notice because the freeze already happened.
	var src: String = FileAccess.get_file_as_string(SM)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	for fn in ["_start_battle_music", "_start_boss_music",
			   "_start_industrial_battle_music", "_start_digital_battle_music"]:
		var start: int = src.find("func %s()" % fn)
		assert_gt(start, 0, "SCOPE control: %s not found" % fn)
		var body: String = src.substr(start, 2200)
		var guard: int = body.find("_try_play_from_manifest(\"battle_medieval\")")
		if guard < 0:
			guard = body.find("_try_play_from_manifest(\"boss_medieval\")")
		var gen: int = body.find("_generate_")
		if gen < 0:
			gen = body.find("_music_cache.has(")
		assert_gt(guard, 0, "%s never tries a shipped medieval bed — on web it goes straight to the generator" % fn)
		assert_gt(gen, 0, "SCOPE control: %s no longer reaches a generator; this ordering check is anchored on nothing" % fn)
		assert_lt(guard, gen,
			"%s tries the shipped bed AFTER the generator — by then the main thread has already been held for seconds" % fn)
