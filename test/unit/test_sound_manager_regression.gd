extends GutTest

## Regression: SoundManager volume setters must be safe to call before
## _setup_audio_players() has created the AudioStreamPlayer children.
##
## Prior to the fix:
##   SCRIPT ERROR: Invalid assignment of property 'volume_db' ... on a
##   base object of type 'Nil'. at: SoundManagerClass.set_music_volume
##
## SaveSystem.load_settings() runs during SaveSystem._ready() and fires
## set_music_volume / set_sfx_volume. Autoload order can put that
## before SoundManager._ready() has finished creating the players.


func test_set_music_volume_safe_before_players_exist():
	var sm = load("res://src/audio/SoundManager.gd").new()
	# Do NOT call _ready() — we want the pre-ready state where
	# _music_player is still null.
	assert_null(sm.get("_music_player"), "precondition: _music_player should be null")
	# This would have crashed before the null-guard fix.
	sm.set_music_volume(0.5)
	# And the base db should still have been latched.
	# Updated 2026-05-02: ceiling lowered -6 → -10 after user said music
	# was still too loud. At slider=0.5: db = -10 + linear_to_db(0.5) ≈ -16.
	assert_ne(sm._music_base_db, -12.0, "base db should have been updated by setter")
	assert_lt(sm._music_base_db, sm.MUSIC_VOLUME_CEILING_DB,
		"0.5 slider should be below the music ceiling")


func test_set_sfx_volume_safe_before_players_exist():
	var sm = load("res://src/audio/SoundManager.gd").new()
	assert_null(sm.get("_ui_player"), "precondition: _ui_player should be null")
	assert_null(sm.get("_battle_player"), "precondition: _battle_player should be null")
	assert_null(sm.get("_ability_player"), "precondition: _ability_player should be null")
	# Would have crashed before the null-guard fix.
	sm.set_sfx_volume(0.5)
	# No side effects to assert — reaching this line without a crash
	# is the test.
	pass_test("set_sfx_volume did not crash on nil players")


func test_set_music_volume_normal_path_still_works():
	# A ready instance should still apply the db to the player.
	var sm = load("res://src/audio/SoundManager.gd").new()
	add_child_autofree(sm)
	await get_tree().process_frame
	sm.set_music_volume(1.0)
	# Music ceiling is the constant — even at slider=1.0 we cap there so
	# battle SFX punches through. Source value moved -6 → -10 dB on
	# 2026-05-02 after a second pass of user feedback ("music too loud").
	# Read the constant rather than hard-coding so the test self-adjusts
	# if the ceiling is tuned again.
	assert_almost_eq(sm._music_player.volume_db, sm.MUSIC_VOLUME_CEILING_DB, 0.01,
		"music volume should hit MUSIC_VOLUME_CEILING_DB at slider=1.0")

	sm.set_music_volume(0.0)
	assert_eq(sm._music_player.volume_db, -80.0, "music volume should hit silence at 0.0")


func test_music_ceiling_keeps_music_below_battle_sfx():
	# Regression: the user reported "battle music is a bit loud compared to sfx".
	# Root cause was that slider=100% pushed music to 0 dB while battle SFX
	# also flattened to 0 dB — losing the design intent of battle SFX
	# punching above music. The MUSIC_VOLUME_CEILING_DB cap restores this.
	var sm = load("res://src/audio/SoundManager.gd").new()
	add_child_autofree(sm)
	await get_tree().process_frame
	# After _ready, battle player has its design base offset.
	var battle_db = sm._battle_player.volume_db
	sm.set_music_volume(1.0)
	var music_db = sm._music_player.volume_db
	assert_lte(music_db, battle_db,
		"At slider=1.0, music (%f dB) must be <= battle SFX (%f dB) so battle hits punch through" %
		[music_db, battle_db])


func test_play_attack_hit_handles_empty_and_unknown_weapon():
	# play_attack_hit must not crash for empty weapon_type (no weapon
	# equipped) or for an unknown weapon_type. Both should silently fall
	# back to the generic attack_hit / critical_hit entry.
	var sm = load("res://src/audio/SoundManager.gd").new()
	add_child_autofree(sm)
	await get_tree().process_frame
	sm.play_attack_hit("", false)
	sm.play_attack_hit("", true)
	sm.play_attack_hit("nonexistent_weapon_type", false)
	sm.play_attack_hit("nonexistent_weapon_type", true)
	pass_test("play_attack_hit handled empty + unknown weapon types without crashing")


func test_play_attack_hit_resolves_known_weapon_types():
	# Every weapon_type in equipment.json must resolve via the manifest (or the
	# procedural fallback) without raising.
	#
	# DERIVED 2026-07-29. This hand-listed the five types that existed when it was
	# written, under a comment saying "known weapon_types from equipment.json" — so
	# it claimed to cover that file while being a snapshot of it. The list happens to
	# be complete today (5 of 5), which is exactly why it would have gone unnoticed:
	# a sixth weapon type would ship with no audio coverage and this test would stay
	# green. Same class as the crit/base pairs in the weapon-strike guard, which I
	# derived from disk earlier today and then left this sibling hand-listed.
	var text: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "equipment.json must parse")
	var types: Array[String] = []
	var stack: Array = [parsed]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if node is Dictionary:
			for k in node.keys():
				if str(k) == "weapon_type" and node[k] is String and not types.has(str(node[k])):
					types.append(str(node[k]))
				stack.append(node[k])
		elif node is Array:
			for x in node:
				stack.append(x)
	types.sort()

	## Vacuity control: an empty walk would run the loop zero times and pass.
	assert_gt(types.size(), 0,
		"control: found no weapon_type in equipment.json — the walk is broken, so the calls below never happened")

	var sm = load("res://src/audio/SoundManager.gd").new()
	add_child_autofree(sm)
	await get_tree().process_frame
	for wt in types:
		sm.play_attack_hit(wt, false)
		sm.play_attack_hit(wt, true)
	pass_test("play_attack_hit resolved all %d weapon_types in equipment.json: %s" % [types.size(), types])
