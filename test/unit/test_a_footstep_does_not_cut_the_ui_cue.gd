extends GutTest

## A step cut every UI cue longer than a step.
##
## MEASURED 2026-09-11, before the fix: play_ui("quest_complete") then play_footstep("grass")
## left _ui_player holding footstep_grass_v2.ogg. quest_complete is 1.53s and portal_activate
## 2.00s, against a footstep that fires on every `moved` emit while walking — so the quest
## jingle survived until the player's next step, which is immediately.
##
## Fourth instance of one class (death cries 2026-08-15, party voice lines, the group flourish,
## this) and the FIRST where the fix moves the CUTTER rather than the cue: the UI player carries
## 41 cues, so enumerating the long ones would need extending for every future one. Footsteps are
## the single frequent member.

## Cues on the UI channel that outlast a footstep. DERIVED would be circular here — the manifest
## cannot say which cues share a player — so this is a floor naming the two measured members.
const LONG_UI_CUES := ["quest_complete", "portal_activate"]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_footsteps_have_their_own_player() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_not_null(sm._footstep_player, "footsteps need their own AudioStreamPlayer")
	assert_not_null(sm._ui_player, "CONTROL: the UI player must exist for this comparison to mean anything")
	assert_ne(sm._footstep_player, sm._ui_player,
		"footsteps are back on the UI player — every cue longer than a step dies on the next step")


func test_a_step_does_not_replace_a_ui_cue() -> void:
	## THE regression, exactly as the pre-fix probe measured it.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_gte(LONG_UI_CUES.size(), 2,
		"LONG_UI_CUES holds %d, was 2 — it is the subject of the loop below; a cue leaving it stops being checked rather than failing" % LONG_UI_CUES.size())
	assert_true(LONG_UI_CUES.has("quest_complete"),
		"CONTROL: quest_complete is the measured case and must stay named")
	var cut: Array[String] = []
	for key in LONG_UI_CUES:
		assert_true(sm._sfx_manifest.has(key), "CONTROL: %s must exist to be cut" % key)
		sm._sfx_cooldowns.erase(key)
		sm.play_ui(key)
		var cue = sm._ui_player.stream
		if cue == null:
			cut.append("%s (did not load — 'not replaced' would be vacuous)" % key)
			continue
		sm._sfx_cooldowns.clear()
		sm.play_footstep("grass")
		if sm._ui_player.stream != cue:
			cut.append("%s -> %s" % [key, str(sm._ui_player.stream.resource_path).get_file()])
	assert_eq(cut, [], "UI cues a footstep replaced (%d): %s" % [cut.size(), cut])
	## CONTROL: the footstep must genuinely have played somewhere, or the assert above passes
	## because play_footstep did nothing at all.
	assert_not_null(sm._footstep_player.stream, "CONTROL: the footstep must have loaded on its own player")
	assert_true(str(sm._footstep_player.stream.resource_path).contains("footstep"),
		"CONTROL: the footstep player holds %s" % str(sm._footstep_player.stream.resource_path))


func test_the_walk_loop_still_reaches_play_footstep() -> void:
	## EXECUTION is not SELECTION: the asserts above prove the path works, none of them proves
	## OverworldPlayer still calls it. A step that plays nothing is silent, not merely uncut.
	## Was a RAW source read until 2026-09-12. Mutation-tested that day on the sibling group-attack
	## guard: a call replaced by `pass  ## was ...play_flourish(...)` left it EC=0 · Passing 6 —
	## the same shape @cowir-music hit in `1d1d83ff`. A commented-out call is a deleted call.
	var raw := FileAccess.get_file_as_string("res://src/exploration/OverworldPlayer.gd")
	var src := _code_only(raw)
	assert_gt(src.length(), 10000, "CONTROL: OverworldPlayer CODE read back %d chars" % src.length())
	assert_lt(src.length(), raw.length(),
		"CONTROL: stripping removed nothing — the stripper is inert and this arm is a raw read again")
	assert_true(raw.contains("\n#") or raw.contains("\t#"),
		"ANTI-VACUITY: OverworldPlayer holds no comment line, so the control above proves nothing")
	## STRUCTURAL, so a reworded comment cannot change the verdict (@cowir-music `da523860`).
	assert_false(_code_only("\tpass  ## was sm.play_footstep(x)").contains("play_footstep"),
		"a call named in a trailing comment still reads as a call")
	## The needle must be ABSENT from the call itself: this read `# step #2` / not-contains "step"
	## and went RED on a clean tree, because `play_footstep` contains "step". A negative assert
	## needs a token that only the comment can supply.
	var trailing := _code_only('\tsm.play_footstep(t)  # cadence #2')
	assert_true(trailing.contains("play_footstep(t)"), "the stripper ate a real call")
	assert_false(trailing.contains("cadence"),
		"cut at the LAST # — the comment body survived as code")
	## Quote-awareness had no case here until 2026-09-12: dropping the quote arm left this file
	## GREEN while its two siblings redded. A shared helper needs the same case table in each
	## copy, or the copies certify different functions.
	assert_true(_code_only('\tvar s := "has #hash"  # gone').contains('"has #hash"'),
		"a # inside a string literal is not a comment — live code was truncated")
	assert_true(src.contains("play_footstep("),
		"the walk loop no longer calls play_footstep — footsteps are silent, which this test would otherwise call 'not cutting anything'")


func _code_only(text: String) -> String:
	## Presence checks read CODE, never prose. Quote- and escape-aware; the derivation and its
	## case table live in test_group_attack_cue_survives_its_own_hits.gd.
	var out: PackedStringArray = []
	for line in text.split("\n"):
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
	return "\n".join(out)
