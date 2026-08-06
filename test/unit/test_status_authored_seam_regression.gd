extends GutTest

## Seam for buff/debuff audio: play_status_if_authored must NEVER fall back (2026-08-05).
##
## struktured ruling #15: "generic blip is not even close to good." play_status() ends in a
## procedural descending blip for any unauthored key, and add_buff/add_debuff fire constantly
## — wiring them to play_status would ship that blip on every Protect, Berserk and Armor Break,
## which is louder than the proposal he already rejected. This seam plays a manifest cue or
## nothing, so cowir-battle's call sites light up exactly as fast as the cues get authored.
##
## The load-bearing test is the SILENCE one: a wrapper that quietly gained a fallback would
## pass every "does it play the right cue" assertion while violating the ruling.

const AUTHORED: String = "status_poison"
const UNAUTHORED: String = "status_zz_not_authored_control"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_the_seam_exists_and_returns_bool() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload must exist")
	assert_true(sm.has_method("play_status_if_authored"),
		"play_status_if_authored is a READY SEAM with ZERO production callers, deliberately. This message previously said add_buff/add_debuff call it; they do not, and Combatant.gd contains no SoundManager reference at all. Buff audio is emitted a layer up, in BattleScene._on_action_executed's effect match.")
	assert_true(sm.play_status_if_authored(UNAUTHORED) is bool,
		"must return bool so the caller can tell authored from silent")


func test_premise_the_two_keys_differ_in_the_manifest() -> void:
	## Every assertion below is vacuous if these premises break.
	var sm: Node = _sm()
	assert_true(sm._sfx_manifest.has(AUTHORED),
		"PREMISE: %s must BE in the manifest, else the 'plays when authored' test proves nothing" % AUTHORED)
	assert_false(sm._sfx_manifest.has(UNAUTHORED),
		"PREMISE: %s must NOT be in the manifest, else the silence test is satisfied trivially" % UNAUTHORED)


func test_unauthored_key_is_SILENT_not_a_blip() -> void:
	## THE RULING GUARD. Observable is the SFX cooldown stamp: a manifest miss provably does
	## not stamp, so an unstamped key means nothing was emitted on that channel.
	var sm: Node = _sm()
	sm._sfx_cooldowns.erase(UNAUTHORED)
	assert_false(sm._sfx_cooldowns.has(UNAUTHORED), "control: key must start unstamped")
	var played: bool = sm.play_status_if_authored(UNAUTHORED)
	assert_false(played,
		"play_status_if_authored('%s') returned true for a key that is not in the manifest" % UNAUTHORED)
	assert_false(sm._sfx_cooldowns.has(UNAUTHORED),
		"an unauthored key stamped a cooldown — the seam emitted something, which is the procedural blip struktured rejected (ruling #15)")


func test_authored_key_still_plays() -> void:
	## NEGATIVE CONTROL on the guard above: if the seam were broken to always return false,
	## the silence test would pass and the feature would never work.
	var sm: Node = _sm()
	sm._sfx_cooldowns.erase(AUTHORED)
	assert_false(sm._sfx_cooldowns.has(AUTHORED), "control: key must start unstamped")
	var played: bool = sm.play_status_if_authored(AUTHORED)
	assert_true(played,
		"play_status_if_authored('%s') returned false for a key that IS in the manifest — the seam is inert" % AUTHORED)
	assert_true(sm._sfx_cooldowns.has(AUTHORED),
		"an authored key did not stamp — nothing was emitted")


func test_play_status_DOES_still_fall_back() -> void:
	## Pins the distinction the seam exists for. play_status keeps its blip for afflictions
	## (deliberate); if someone "simplifies" the two into one function, this fails.
	var sm: Node = _sm()
	assert_true(sm.has_method("play_status"),
		"play_status must still exist — the seam supplements it, never replaces it")
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 0, "control: source read returned nothing")
	assert_true(src.contains("\"type\": \"descending\""),
		"play_status' procedural fallback is gone — if that was deliberate, this test is what should have told you")
