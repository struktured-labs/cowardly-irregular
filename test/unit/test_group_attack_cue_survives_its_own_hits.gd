extends GutTest

## A group attack's own hits were cutting its signature cue.
##
## MEASURED 2026-09-11, before the fix: play_battle("group_limit_break") then
## play_attack_hit("sword") left _battle_player.stream == attack_hit_sword.ogg. The flourish is
## 2.48s (all_out 1.48s, combo_magic 2.00s, formation 1.48s); the lunges and their damage_dealt
## signals land a few tenths in, and EVERY one of the 3-5 targets fires a hit sound on the same
## player. The biggest move in the game was audible for about as long as it took to start.
##
## Third instance of one class — death cries (2026-08-15), party voice lines, this. A long cue
## sharing a player with a frequent short one is always the short one's to lose.

const GROUP_CUES := ["group_all_out", "group_combo_magic", "group_formation", "group_limit_break"]

## The spotlight-duel retry sting. Not a group cue, same defect: 3.00s on the battle player, and
## the retry battle's round_ap_gain landed ~0.7s in. Measured the same way.
const DEFEAT_CUE := "defeat"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_the_flourish_player_is_its_own_player() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_not_null(sm._flourish_player, "group cues need their own AudioStreamPlayer")
	assert_not_null(sm._battle_player, "CONTROL: the battle player must exist for this comparison to mean anything")
	assert_ne(sm._flourish_player, sm._battle_player,
		"the group cue is back on the battle player — its own hit sounds will cut it")


func test_a_hit_sound_no_longer_replaces_the_group_cue() -> void:
	## THE regression, as the pre-fix probe measured it: play the cue, then fire the hit sound
	## the attack itself triggers, and the cue must still be the stream on its player.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("group_limit_break"), "CONTROL: the cue must exist to be cut")
	sm._sfx_cooldowns.erase("group_limit_break")
	sm.play_flourish("group_limit_break")
	var cue = sm._flourish_player.stream
	assert_not_null(cue, "CONTROL: the cue must actually have loaded, or 'not replaced' is vacuous")
	if cue == null:
		return
	assert_true(str(cue.resource_path).contains("group_limit_break"),
		"CONTROL: the flourish player holds %s, not the cue" % str(cue.resource_path))
	sm._sfx_cooldowns.clear()
	sm.play_attack_hit("sword", false)
	assert_eq(sm._flourish_player.stream, cue,
		"a weapon hit replaced the group cue — the attack is cutting its own flourish")
	## CONTROL: the hit sound must genuinely have played somewhere, or the assert above passes
	## because nothing happened at all.
	assert_ne(sm._battle_player.stream, null, "CONTROL: the hit sound must have loaded on the battle player")
	assert_ne(sm._battle_player.stream, cue, "CONTROL: the hit must not have gone to the flourish player")


func test_every_group_cue_resolves_through_the_flourish_path() -> void:
	## DERIVED over all four cues, not just the one measured: a cue that fails to resolve here
	## falls back to play_battle and is cuttable again, silently.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_eq(GROUP_CUES.size(), 4,
		"GROUP_CUES holds %d, was 4 — this list is the subject of the loop below; a cue leaving it stops being checked rather than failing" % GROUP_CUES.size())
	var unresolved: Array[String] = []
	for key in GROUP_CUES:
		sm._sfx_cooldowns.erase(key)
		sm.play_flourish(key)
		var st = sm._flourish_player.stream
		if st == null or not str(st.resource_path).contains(key):
			unresolved.append(key)
	assert_eq(unresolved, [],
		"group cues that did not reach the flourish player (%d): %s" % [unresolved.size(), unresolved])


func test_the_defeat_sting_is_not_cut_by_the_retry_battle() -> void:
	## The sting exists so a spotlight-duel retry does not feel like a bug (CutsceneDirector).
	## Being cut a third of the way through is that bug, restored.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(DEFEAT_CUE), "CONTROL: the sting must exist to be cut")
	sm._sfx_cooldowns.erase(DEFEAT_CUE)
	sm.play_flourish(DEFEAT_CUE)
	var cue = sm._flourish_player.stream
	assert_not_null(cue, "CONTROL: the sting must have loaded, or 'not replaced' is vacuous")
	if cue == null:
		return
	sm._sfx_cooldowns.clear()
	sm.play_battle("round_ap_gain")
	assert_eq(sm._flourish_player.stream, cue,
		"the retry battle's round cue replaced the defeat sting — it is back on the battle player")


func test_the_cutscene_director_calls_the_flourish_path() -> void:
	## EXECUTION is not SELECTION, for the sting as for the group cues.
	var src: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_gt(src.length(), 10000, "CONTROL: CutsceneDirector source read back %d chars" % src.length())
	assert_true(src.contains('play_flourish("%s")' % DEFEAT_CUE),
		"the defeat sting is not played through play_flourish")
	assert_false(src.contains('play_battle("%s")' % DEFEAT_CUE),
		"the defeat sting is still routed through play_battle, where the retry battle's round cue cuts it")


func test_the_battle_scene_calls_the_flourish_path() -> void:
	## EXECUTION is not SELECTION: the three tests above prove the path works, none of them
	## proves BattleScene uses it. A call site left on play_battle is the whole defect, intact.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 10000, "CONTROL: BattleScene source read back %d chars" % src.length())
	var on_battle: Array[String] = []
	for key in GROUP_CUES:
		assert_true(src.contains('play_flourish("%s")' % key),
			"%s is not played through play_flourish in BattleScene" % key)
		if src.contains('play_battle("%s")' % key):
			on_battle.append(key)
	assert_eq(on_battle, [],
		"group cues still routed through play_battle, where their own hits cut them (%d): %s" % [on_battle.size(), on_battle])
