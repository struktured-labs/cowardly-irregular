extends GutTest

## The Rogue's basic attack strikes twice (struktured 2026-11-13): the dagger on frame 1, the bolt on frame 4. Outside spotlight
## pace both land within 0.22 s, and on the one battle voice the bolt replaced the dagger, so two hits sounded as one.
## play_second_hit gives the second hit its own voice; the CONTROL arm shows the shared-voice route really does cut.

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const FIRST := "attack_hit_dagger"
const BOLT := "attack_hit_bolt"
const BOLT_CRIT := "attack_hit_bolt_crit"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	var sm: Node = _sm()
	if sm != null:
		sm._sfx_cooldowns.clear()
		sm.reset_hit_chain()


func after_each() -> void:
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm != null:
		sm._sfx_cooldowns.clear()
		sm.reset_hit_chain()


func _path(stream) -> String:
	return "" if stream == null else str((stream as Resource).resource_path)


func test_the_bolt_layers_over_the_dagger() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	sm.play_attack_hit("dagger", false)
	var first: String = _path(sm._battle_player.stream)
	assert_true(first.ends_with(FIRST + ".ogg"), "CONTROL: the dagger hit must be on the battle voice, got '%s'" % first)
	sm.play_second_hit(BOLT)
	assert_eq(_path(sm._battle_player.stream), first, "the bolt replaced the dagger on the battle voice, so the two hits sound as one")
	assert_true(_path(sm._second_hit_player.stream).ends_with(BOLT + ".ogg"), "the bolt must sound on its own voice")


func test_the_shared_voice_route_does_cut_and_that_is_the_control() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_attack_hit("dagger", false)
	sm.play_attack_hit("bolt", false)
	assert_true(_path(sm._battle_player.stream).ends_with(BOLT + ".ogg"),
		"CONTROL: a second play_attack_hit lands on the same voice and replaces the first, which is the defect the arm above guards")


func test_the_crit_bolt_plays_its_own_cue() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_second_hit(BOLT_CRIT)
	assert_true(_path(sm._second_hit_player.stream).ends_with(BOLT_CRIT + ".ogg"), "a critical bolt must play the crit cue")


func test_the_pair_counts_as_one_hit_chain() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_attack_hit("dagger", false)
	sm.play_second_hit(BOLT)
	assert_eq(sm._combo_step, 2, "both hits of one action must advance the hit chain, so the bolt ramps like a combo's next hit")


func test_both_cues_are_registered_with_their_generator() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	for k in [BOLT, BOLT_CRIT]:
		var e: Dictionary = sm._sfx_manifest.get(k, {})
		assert_false(e.is_empty(), "%s must be in the sfx manifest" % k)
		assert_true(FileAccess.file_exists(str(e.get("file", ""))), "%s must name a file that exists" % k)
		assert_eq(str(e.get("source", "")), "tools/gen_bolt_cues.py " + k, "%s must name the script that regenerates it" % k)


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	for method_name in ["play_second_hit", "play_attack_hit", "reset_hit_chain"]:
		assert_true(sm.has_method(method_name), "SoundManager has no %s — this file calls it" % method_name)
	for member_name in ["_battle_player", "_second_hit_player", "_sfx_cooldowns", "_sfx_manifest", "_combo_step"]:
		assert_true(sm.get(member_name) != null, "SoundManager has no %s — this file reaches for it directly" % member_name)
