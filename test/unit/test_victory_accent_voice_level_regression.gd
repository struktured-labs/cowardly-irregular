extends GutTest

## cowir-main 2026-08-19 routed the victory accents onto _death_player rather than adding
## a third voice: deaths precede victory, so the two windows cannot overlap. That reuse is
## only safe if a per-cue offset CANNOT persist on the shared voice — otherwise the first
## victory at 0 dB retunes every later death cry, and the symptom (quiet scorch) appears in
## a battle that had no victory in it.
##
## The obvious implementation is the trap: pass the offset as _try_play_sfx_from_manifest's
## volume_db_override. That ASSIGNS player.volume_db and never restores it, and its cooldown
## early-return skips the assignment entirely — so the level would depend on how recently the
## same key played. play_death sets the level itself, every call, before dispatching.


func test_a_victory_accent_does_not_retune_the_death_voice() -> void:
	SoundManager.play_death("levelup_flourish", SoundManager.VICTORY_ACCENT_OFFSET_DB)
	assert_almost_eq(SoundManager._death_player.volume_db,
		SoundManager.SFX_BATTLE_BASE_DB + SoundManager.VICTORY_ACCENT_OFFSET_DB, 0.01,
		"victory accent plays at its own offset")

	SoundManager.play_death("enemy_death")
	assert_almost_eq(SoundManager._death_player.volume_db,
		SoundManager.SFX_BATTLE_BASE_DB + SoundManager.DEATH_CRY_OFFSET_DB, 0.01,
		"THE LEAK: a death cry after a victory accent must play at the DEATH level, not the accent's")


func test_the_two_offsets_actually_differ_or_the_leak_test_is_vacuous() -> void:
	assert_ne(SoundManager.VICTORY_ACCENT_OFFSET_DB, SoundManager.DEATH_CRY_OFFSET_DB,
		"if these ever converge the leak test above passes on a broken implementation — re-point it at a cue that still differs")


func test_the_shipped_death_cry_level_is_unchanged_by_the_accent_wiring() -> void:
	# bfe8c6da set the death voice to SFX_BATTLE_BASE_DB + 2.0; the const must preserve it.
	assert_almost_eq(SoundManager.DEATH_CRY_OFFSET_DB, 2.0, 0.001,
		"the +2 lift is struktured's shipped death-cry level, not a value the victory wiring may retune")
	SoundManager.play_death("enemy_death")
	assert_almost_eq(SoundManager._death_player.volume_db, SoundManager.SFX_BATTLE_BASE_DB + 2.0, 0.01,
		"default play_death still lands at the shipped level")


func test_play_death_sets_the_level_itself_rather_than_delegating_the_override() -> void:
	# Source-level: a refactor to the volume_db_override path reintroduces both the stickiness
	# and the cooldown-skip, and neither shows up as a failure in a single-play test.
	var sm := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var fn := sm.find("func play_death")
	assert_gt(fn, -1, "play_death present")
	var body := sm.substr(fn, sm.find("\nfunc ", fn + 1) - fn)
	assert_true("_death_player.volume_db = SFX_BATTLE_BASE_DB + offset_db" in body,
		"play_death assigns the level on entry")
	assert_false("_try_play_sfx_from_manifest(_death_player, sound_key, offset_db" in body,
		"the offset must NOT be passed as volume_db_override — it is sticky and cooldown-skipped")


func test_the_levelup_flourish_call_site_uses_the_accent_voice() -> void:
	var vo := FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	assert_true('play_death("levelup_flourish", SoundManager.VICTORY_ACCENT_OFFSET_DB)' in vo,
		"the level-up flourish routes through the accent voice with an explicit offset")
	assert_false('play_battle("levelup_flourish")' in vo,
		"and no longer through the shared battle player")
