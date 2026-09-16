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
	var src := _code_only(raw, "func _resolve_footstep_terrain")
	assert_gt(src.length(), 10000, "CONTROL: OverworldPlayer CODE read back %d chars" % src.length())
	assert_lt(src.length(), raw.length(),
		"CONTROL: stripping removed nothing — the stripper is inert and this arm is a raw read again")
	assert_true(raw.contains("\n#") or raw.contains("\t#"),
		"ANTI-VACUITY: OverworldPlayer holds no comment line, so the control above proves nothing")
	## STRUCTURAL, so a reworded comment cannot change the verdict (@cowir-music `da523860`).
	assert_false(_code_only("\tpass  ## was sm.play_footstep(x)", "").contains("play_footstep"),
		"a call named in a trailing comment still reads as a call")
	## The needle must be ABSENT from the call itself: this read `# step #2` / not-contains "step"
	## and went RED on a clean tree, because `play_footstep` contains "step". A negative assert
	## needs a token that only the comment can supply.
	var trailing := _code_only('\tsm.play_footstep(t)  # cadence #2', "")
	assert_true(trailing.contains("play_footstep(t)"), "the stripper ate a real call")
	assert_false(trailing.contains("cadence"),
		"cut at the LAST # — the comment body survived as code")
	## Quote-awareness had no case here until 2026-09-12: dropping the quote arm left this file
	## GREEN while its two siblings redded. A shared helper needs the same case table in each
	## copy, or the copies certify different functions.
	assert_true(_code_only('\tvar s := "has #hash"  # gone', "").contains('"has #hash"'),
		"a # inside a string literal is not a comment — live code was truncated")
	assert_true(src.contains("play_footstep("),
		"the walk loop no longer calls play_footstep — footsteps are silent, which this test would otherwise call 'not cutting anything'")


## TWO halves: `#` comments are line-based and stateless; `"""` docstrings need a REGION strip.
## Which a guard needs is decided by what its assertion is SATISFIED BY (@cowir-overworld) — these
## are PRESENCE asserts, so a docstring naming the call satisfies them. My .325 fix closed only the
## `#` half. `must_survive` is REQUIRED so no call site reads prose by accident (@cowir-adhoc).
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


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## A direct `sm._x` on a RENAMED member raises at runtime and ABORTS the arm. An abort after
	## that arm's last assert scores PASSING — measured 2026-09-16: renaming the dedicated voice
	## this file exists to defend gave EXIT=0, Failing 0, NO Risky line, and moved only the assert
	## count. `get()` returns null for an absent name instead of raising, so the rename fails loudly
	## here and names itself before any other arm gets the chance to go quiet.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## Methods are NOT properties: get() returns null for a method name, so the loop below cannot
	## see a renamed METHOD. has_method ANSWERS instead of raising, same reason.
	## ⚠️ BOTH LISTS ARE A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT a
	## live derivation. Add a new sm. reach to this file and it is NOT covered until you add it here.
	## A runtime derivation would self-maintain but would read this arm's own body as corpus
	## (cowir-sprites' tautology class), needing cowir-ai's bare-Object exclusion to stay honest.
	## Convert it the next time this file gains a reach; until then the list is correct by being fresh.
	for method_name in ["play_footstep", "play_ui"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it, and whether that shows as Risky or as a silent pass is decided by arm ORDER, not by care" % method_name)
	## ⚠️ get() CANNOT DISTINGUISH ABSENT FROM LEGITIMATELY NULL (@cowir-sprites): it returns null
	## for both. Every member below is a player, a Dictionary or a String — none is ever null once
	## _ready has run — so the check is sound HERE. If you add a nullable member to this list
	## (_crossfade_tween and the other _*_tween members are EXAMPLES, not an exhaustive list — check
	## the declaration), switch to get_property_list(), which answers about existence rather than value.
	for member_name in ["_footstep_player", "_sfx_cooldowns", "_sfx_manifest", "_ui_player"]:
		## assert_true on an explicit `!= null`: assert_ne deep-compares, and three of these members
		## are Dictionaries, which it refuses with "Only Arrays and Dictionaries are supported".
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort its arms SILENTLY" % member_name)
