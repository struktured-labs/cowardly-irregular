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
	var src := _code_of("res://src/cutscene/CutsceneDirector.gd", "func _play_spotlight_retry_sting")
	assert_gt(src.length(), 10000, "CONTROL: CutsceneDirector CODE read back %d chars" % src.length())
	assert_true(src.contains('play_flourish("%s")' % DEFEAT_CUE),
		"the defeat sting is not played through play_flourish")
	assert_false(src.contains('play_battle("%s")' % DEFEAT_CUE),
		"the defeat sting is still routed through play_battle, where the retry battle's round cue cuts it")


func test_the_battle_scene_calls_the_flourish_path() -> void:
	## EXECUTION is not SELECTION: the three tests above prove the path works, none of them
	## proves BattleScene uses it. A call site left on play_battle is the whole defect, intact.
	var src := _code_of("res://src/battle/BattleScene.gd", "func _on_group_attack_executing")
	assert_gt(src.length(), 10000, "CONTROL: BattleScene CODE read back %d chars" % src.length())
	var on_battle: Array[String] = []
	for key in GROUP_CUES:
		assert_true(src.contains('play_flourish("%s")' % key),
			"%s is not played through play_flourish in BattleScene" % key)
		if src.contains('play_battle("%s")' % key):
			on_battle.append(key)
	assert_eq(on_battle, [],
		"group cues still routed through play_battle, where their own hits cut them (%d): %s" % [on_battle.size(), on_battle])


## Source arms read CODE, never prose. @cowir-music 2026-09-12 (`1d1d83ff`): a name in a module
## docstring satisfied a presence check with every real call renamed — EC=0, clean green, code gone.
## Mutation-tested here the same day: replacing the BattleScene call with
## `pass  ## was SoundManager.play_flourish("group_all_out")` left this file EC=0 · Passing 6.
## Both arms below reported the routing intact while the routing was deleted.
## Quote-aware because `play_battle("x") # see BATTLE #3` must cut at the SECOND #, and escape-aware
## because "a\\" really does end its string. Shape shared with _strip_comments in
## test_ambient_cues_actually_loop.gd, which carries the longer derivation.
func _code_of(path: String, must_survive: String) -> String:
	return _code_only(FileAccess.get_file_as_string(path), must_survive)


## TWO halves, and which one a guard needs is decided by WHAT ITS ASSERTION IS SATISFIED BY
## (@cowir-overworld). `#` comments are line-based and stateless — nothing to desync. `"""`
## docstrings are NOT line-addressable and need a region strip. These arms are PRESENCE asserts, so
## a docstring naming the call satisfies them: @cowir-music's 1d1d83ff verbatim, and my own .325 fix
## closed only the `#` half. BattleScene carries 133 `"""` lines, CutsceneDirector 23.
## `must_survive` is REQUIRED so no call site can read prose by accident, and it is asserted here
## rather than returned, because an over-stripping stripper and a correct one are the same green
## (@cowir-adhoc, whose over-strip produced five confident false positives).
func _code_only(text: String, must_survive: String) -> String:
	var out: PackedStringArray = []
	var in_doc := false
	for raw_line in text.split("\n"):
		var line: String = raw_line
		var fences := line.count("\"\"\"")
		if in_doc:
			if fences % 2 == 1:
				in_doc = false
			continue
		if fences >= 2:
			line = line.substr(0, line.find("\"\"\"")) + line.substr(line.rfind("\"\"\"") + 3)
		elif fences == 1:
			line = line.substr(0, line.find("\"\"\""))
			in_doc = true
		var quote := ""
		var cut := -1
		var i := 0
		while i < line.length():
			var c := line[i]
			if quote != "":
				if c == "\\":
					i += 2
					continue
				if c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
			i += 1
		out.append(line.substr(0, cut) if cut > -1 else line)
	var result: String = "\n".join(out)
	if must_survive != "":
		assert_true(result.contains(must_survive),
			"OVER-STRIPPED: %s did not survive — an over-eager stripper and a correct one are the same green" % must_survive)
	return result


func test_the_stripper_keeps_calls_and_drops_prose() -> void:
	## @cowir-music 2026-09-12 (`da523860`): the stripper is what every arm here rests on, and
	## proving it by hand is an experiment that does not survive into the future. Neutering
	## _code_only to a pass-through must RED — it did, but only via the length control, while
	## this case table called a SECOND COPY of the logic (`_strip_line`) and so measured a
	## function no arm uses. Every case below now drives _code_only itself.
	var raw := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var src := _code_of("res://src/battle/BattleScene.gd", "func _on_group_attack_executing")
	assert_gt(src.length(), 10000, "CONTROL: stripped BattleScene is %d chars" % src.length())
	assert_lt(src.length(), raw.length(),
		"CONTROL: stripping removed nothing from %d chars — the stripper is a pass-through" % raw.length())
	assert_true(raw.contains("\n#") or raw.contains("\t#"),
		"ANTI-VACUITY: BattleScene holds no comment line, so this arm would pass with nothing to do")
	assert_true(src.contains('play_flourish("group_all_out")'),
		"the stripper ate a real call — every arm in this file would then fail for the wrong reason")
	assert_false(_code_only("\tpass  ## was SoundManager.play_flourish(\"group_all_out\")", "").contains("play_flourish"),
		"a call named in a trailing comment still reads as a call")
	## This pair used to be ONE assert claiming "cuts at the first # not the last" while only
	## checking the call survived — which a last-# cut also satisfies. Mutation-tested 2026-09-12
	## (drop the `break`, cut at the LAST #): EC=0, green, message unchanged. @cowir-overworld via
	## @cowir-music: a pass-through neuter cannot tell a real assert from a tautology.
	var trailing := _code_only('\tSoundManager.play_flourish("x")  # BATTLE #3', "")
	assert_true(trailing.contains('play_flourish("x")'), "the stripper ate a real call")
	assert_false(trailing.contains("BATTLE"),
		"cut at the LAST # — everything between the first # and the last survived as code")
	## ESCAPE BRANCH — @cowir-sprites: their escape branch survived every over-strip mutation because
	## no case row contained a backslash. Mine had ZERO backslash rows across four files while a
	## COMMENT in this very helper named the escaped-backslash case as the reason the branch exists.
	## Two rows, because the branch does two jobs and one row cannot fail for both.
	## MEASURED to discriminate: `"a\\"  # gone` does NOT — skipping 1 char or 2 gives the identical
	## result, so that row exists and can fail for nothing (@cowir-sprites' third level: applied,
	## well-aimed, semantically unable to fail). An escaped QUOTE followed by a `#` INSIDE the string
	## is the input where the two differ: correct keeps the whole line, a 1-char skip closes the
	## string early and cuts at the `#`.
	assert_true(_code_only('\tvar s := "a\\"  # inside"', "").contains("# inside"),
		"the escape branch let the string close early — a `#` INSIDE a string was read as a comment")
	## DOCSTRING REGION — the half .325 left open. A presence assert is satisfied by prose.
	assert_false(_code_only('"""\nplay_flourish("group_all_out")\n"""', "").contains("play_flourish"),
		"a call named inside a triple-quoted docstring still reads as a call")
	assert_true(_code_only('play_flourish("x")\n"""doc"""\nplay_flourish("y")', "").contains('play_flourish("y")'),
		"code AFTER a docstring block was swallowed — the region walk did not resume")
	assert_true(_code_only('\tvar s := "see #3"  # gone', "").contains('"see #3"'),
		"a # inside a string literal is not a comment")
