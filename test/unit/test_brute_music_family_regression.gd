extends GutTest

## Goblin/brute music split (struktured 2026-08-22): "the goblin battle music is too
## barbarian sounding, could be better for like an actual barbarian/ogre".
##
## The audio was not bad, it was miscast. battle_goblin.ogg is now battle_brute.ogg and
## serves troll/cave_troll/ogre/barbarian. Goblins fall to the PROCEDURAL theme, which
## carried the identical brief - "tribal", 140 BPM A minor, generator comments reading
## "war drums, primal" and "war chant" - so re-pointing the OGG alone would have swapped
## one war-drum bed for another and he would have heard no difference. Both were changed.
##
## The routing arms are explicit ON PURPOSE. The fallback at the bottom of the match in
## _play_music_by_key is gated on `parts.size() > 1`, so one-word ids (ogre, barbarian,
## troll) never reach it. A battle_brute key alone would have been a silent no-op whose
## only symptom is "wrong music", which nobody files as a bug.

const SM_SRC: String = "res://src/audio/SoundManager.gd"
const BRUTE_KEYS: Array[String] = ["battle_brute", "battle_troll", "battle_cave_troll", "battle_ogre", "battle_barbarian"]


func _sm_source() -> String:
	var s: String = FileAccess.get_file_as_string(SM_SRC)
	assert_gt(s.length(), 10000, "SCOPE control: SoundManager.gd read back %d chars" % s.length())
	return s


func test_the_brute_track_exists_and_the_goblin_ogg_is_gone() -> void:
	assert_true(ResourceLoader.exists("res://assets/audio/music/battle_brute.ogg"),
		"battle_brute.ogg is missing - the brute family has no theme and falls to generic battle music")
	assert_false(ResourceLoader.exists("res://assets/audio/music/battle_goblin.ogg"),
		"battle_goblin.ogg is back. If a NEW goblin track was generated this is correct and this arm should be inverted - but if it is the OLD barbarian bed restored, the thing he complained about is playing on goblins again.")


func test_every_brute_key_routes_to_the_brute_theme() -> void:
	## Source-pinned rather than behavioural: play_music writes a real AudioStreamPlayer and
	## the assert that matters is WHICH key reaches _start_monster_music("brute"), which is a
	## routing fact, not an audio one.
	## Reads the ARM, not the file. A bare src.contains() passes on the key appearing
	## anywhere - and these keys also appear in the `known` fallback array, so a whole-file
	## search stays green with the routing arm deleted. Mutation-proven: removing
	## "battle_ogre" from the arm left the naive version 5/5 green.
	var src: String = _sm_source()
	var lines: PackedStringArray = src.split("\n")
	var idx: int = -1
	for i in range(lines.size()):
		if lines[i].contains('_start_monster_music("brute")'):
			idx = i
			break
	assert_gt(idx, 0, "nothing routes to the brute theme at all")
	var arm: String = ""
	for j in range(idx - 1, maxi(idx - 5, -1), -1):
		if lines[j].strip_edges().ends_with(":"):
			arm = lines[j]
			break
	assert_ne(arm, "", "SCOPE control: no match arm found in the 4 lines above _start_monster_music(\"brute\")")
	assert_true(arm.contains("battle_"), "SCOPE control: the line found above the call is not a battle_ arm: %s" % arm)
	for key in BRUTE_KEYS:
		assert_true(arm.contains('"%s"' % key),
			"%s is not in the arm that routes to the brute theme. It may still appear in the `known` fallback array, which does NOT route it: one-word ids never reach the parts.size() > 1 fallback, so this plays generic battle music." % key)
func test_CONTROL_the_fallback_really_is_gated_on_multiword_ids() -> void:
	## The whole reason the arms above must be explicit. If this precondition ever relaxes,
	## the arms become redundant rather than load-bearing - and someone should know that
	## before deleting them as duplication.
	var src: String = _sm_source()
	assert_true(src.contains("parts.size() > 1"),
		"the family fallback is no longer gated on a multi-word id. Re-check whether the explicit brute arms are still required, rather than assuming either way.")


func test_the_procedural_goblin_is_no_longer_a_war_chant() -> void:
	## The OGG move is only half the fix. On any machine that does not load a goblin OGG -
	## which after this change is EVERY machine - the procedural theme IS the goblin music.
	var src: String = _sm_source()
	var at: int = src.find('"goblin": {')
	assert_gt(at, 0, "the goblin proc-gen params are gone")
	var params: String = src.substr(at, 140)
	assert_gt(params.length(), 100, "SCOPE control: extracted %d chars of goblin params" % params.length())
	assert_false(params.contains('"style": "tribal"'),
		"the procedural goblin is tribal again - the same war-drum character he objected to, reached by the other of the two sources")
	assert_false(params.contains('"bass_style": "drums"'),
		"the procedural goblin bass is war drums again")


func test_no_war_chant_language_survives_in_the_goblin_generator_arms() -> void:
	## Belt to the params braces: the note arrays are keyed on monster name, so a params
	## change alone leaves a pentatonic war chant playing through a different filter.
	var src: String = _sm_source()
	for phrase in ["TRIBAL A MINOR", "Pentatonic war harmony", "Tribal bass"]:
		assert_false(src.contains(phrase),
			"'%s' is back in the goblin generator - the melodic material is the war chant again, whatever the params say" % phrase)
