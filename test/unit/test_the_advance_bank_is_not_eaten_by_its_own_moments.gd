extends GutTest

## At every full bank, BattleManager emitted the flourish and the unleash back-to-back onto _battle_player, so advance_flourish_5 was replaced same-frame and never heard.
## Sixth instance of the shared-player class. The new charge and refusal cues land on a sounding fifth rung by construction, so the bank gets its own voices.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const STARTERS := ["fighter", "rogue", "cleric", "mage", "bard"]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _holds(player: AudioStreamPlayer, key: String) -> bool:
	return player != null and player.stream != null and str(player.stream.resource_path).contains(key)


## ⛔ THE ERASE BELOW TAKES A REAL CUE OUT OF A SHARED AUTOLOAD. It was restored INLINE two lines
## later, so a GDScript error in play_advance_state aborts the arm between the two and leaves
## `advance_queue_full` MISSING for every later file in the process — Win98Menu plays it.
## Held here instead, because after_each runs even when the arm aborts (@cowir-music, 2026-09-18).
var _erased: Dictionary = {}
var _saved_cooldowns: Dictionary = {}
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		## Snapshot BEFORE the clear. The clear is deliberate per-arm setup — cues must be able to
		## fire — but the table is the SHARED autoload's, and this file never put back what it
		## found. Second strand shape in this file, and not the one the catcher below was built for
		## (@cowir-music: mutate a catcher against a shape you did NOT design it for).
		_saved_cooldowns = sm._sfx_cooldowns.duplicate(true)
		sm._sfx_cooldowns.clear()


## ⚠️ RELEASE FIRST, restore second: an error in the restore aborts after_each, and a release
## sitting at the bottom is then skipped. Same ordering note as the sibling teardowns in this lane.
func after_each() -> void:
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm == null:
		return
	for k in _erased:
		sm._sfx_manifest[k] = _erased[k]
	_erased = {}
	sm._sfx_cooldowns.clear()
	for k in _saved_cooldowns:
		sm._sfx_cooldowns[k] = _saved_cooldowns[k]


func test_the_bank_has_its_own_voices() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	for p in [sm._bank_player, sm._refuse_player]:
		assert_not_null(p, "an advance-bank voice is missing")
		assert_ne(p, sm._battle_player, "an advance-bank cue is back on _battle_player — it replaces whatever is sounding")
	assert_ne(sm._bank_player, sm._refuse_player, "the refusal shares the bank's voice — a momentum press would cut the charge it follows")


func test_the_unleash_no_longer_replaces_flourish_five() -> void:
	# THE live bug, in BattleManager's emit order: action_executing, then full_bank_unleashed.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle("advance_flourish_5")
	var flourish = sm._battle_player.stream
	assert_true(_holds(sm._battle_player, "advance_flourish_5"), "CONTROL: flourish 5 must have loaded, or 'not replaced' is vacuous")
	sm.play_advance_state("full_bank_unleash")
	assert_eq(sm._battle_player.stream, flourish, "full_bank_unleash replaced advance_flourish_5 — the full-bank flourish is silent again")
	assert_true(_holds(sm._bank_player, "full_bank_unleash"), "CONTROL: the unleash must genuinely have played on the bank voice")


func test_reaching_five_does_not_eat_a_jobs_fifth_rung() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var checked := 0
	for job in STARTERS:
		var rung := "advance_%s_5" % job
		if not sm._sfx_manifest.has(rung):
			continue
		sm._sfx_cooldowns.clear()
		sm._bank_player.stream = null
		sm.play_battle(rung)
		var voice = sm._battle_player.stream
		assert_true(_holds(sm._battle_player, rung), "CONTROL: %s must have loaded" % rung)
		sm.play_advance_state("full_bank_charged")
		assert_eq(sm._battle_player.stream, voice, "full_bank_charged replaced %s — the job's own voice at its biggest press" % rung)
		assert_true(_holds(sm._bank_player, "full_bank_charged"), "CONTROL: the charge must have played for %s" % rung)
		checked += 1
	assert_gt(checked, 0, "CONTROL: no starter has a fifth rung, so this arm checked nothing")


func test_a_refused_press_cuts_neither_the_rung_nor_the_charge() -> void:
	# The refusal is a momentum press straight after 5/5, while both are still sounding.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle("advance_cleric_5")
	var rung = sm._battle_player.stream
	sm.play_advance_state("full_bank_charged")
	var charge = sm._bank_player.stream
	assert_true(_holds(sm._battle_player, "advance_cleric_5") and _holds(sm._bank_player, "full_bank_charged"),
		"CONTROL: the rung and the charge must both be sounding before the refusal")
	sm.play_advance_state("advance_queue_full")
	assert_eq(sm._battle_player.stream, rung, "the refusal cut the cleric's 3.6s fifth rung")
	assert_eq(sm._bank_player.stream, charge, "the refusal cut the charge the player just earned")
	assert_true(_holds(sm._refuse_player, "advance_queue_full"), "CONTROL: the refusal must genuinely have played")


func test_an_absent_cue_is_silent_not_a_fallback() -> void:
	# The manifest-has guard the callers rely on: no authored file means no sound, never a stray procedural one.
	var sm: Node = _sm()
	if sm == null:
		return
	var saved = sm._sfx_manifest.get("advance_queue_full")
	assert_not_null(saved, "CONTROL: the cue must be authored, or erasing it proves nothing")
	_erased["advance_queue_full"] = saved
	sm._sfx_manifest.erase("advance_queue_full")
	sm._refuse_player.stream = null
	sm.play_advance_state("advance_queue_full")
	assert_null(sm._refuse_player.stream, "an absent advance cue still played something")


func test_the_unleash_handler_routes_through_the_bank_voice() -> void:
	var code := GdSource.code_of(BATTLE_SCENE)
	var at := code.find("func _on_full_bank_unleashed(")
	assert_gt(at, -1, "CONTROL: the handler must survive the comment strip, or both asserts below read nothing")
	if at == -1:
		return
	var end := code.find("\nfunc ", at + 1)
	var body := code.substr(at, (end - at) if end > at else -1)
	assert_true(body.contains('play_advance_state("full_bank_unleash")'), "the unleash no longer plays through the bank voice")
	assert_false(body.contains('play_battle("full_bank_unleash")'), "the unleash is back on _battle_player — it replaces advance_flourish_5 in the same frame")


## ⚠️ NO CATCHER FOR THE COOLDOWN TABLE, AND THAT IS STRUCTURAL RATHER THAN AN OMISSION: before_each
## CLEARS it before every arm, including this one, so by the time any arm could look the table has
## already been reset for that arm. A strand catcher can only observe state that before_each does
## not touch. The manifest key qualifies; the dedupe table cannot.
##
## ⛔ DECLARED LAST ON PURPOSE — declaration order is run order, so this is the only arm that can
## see a fixture the arms above failed to hand back. Without it the strand and its repair look
## IDENTICAL on screen: an arm that aborts after its first assert still reports PASSING (CLAUDE.md's
## rung 3), so the erase above could go unrestored with every cardinal clean.
func test_zz_the_manifest_fixture_was_handed_back() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("advance_queue_full"),
		"advance_queue_full was left ERASED from the shared manifest — every later file in this process now sees the cue as unauthored, and Win98Menu plays it")
