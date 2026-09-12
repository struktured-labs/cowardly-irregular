extends GutTest

## A gold chest played no chest sound. MEASURED 2026-09-12 by walking every same-function pair of
## play_ui calls with no await between them and crossing it with clip length:
##   TreasureChest._open_chest  chest_open (1.48s) then gold_pickup (1.00s), SAME FRAME
## chest_open is unconditional; gold_pickup sits in the "gold" arm of the match below it. So on
## the 15 gold chests in the game the lid sound was replaced at ~0s and never audible once.
##
## Fifth instance of the class (death cries, party voice, group attacks, footsteps, this). The new
## shape: a REWARD cue is always a consequence of the action that earned it, so it is structurally
## the cue most likely to land on top of one still playing. Reward cues get their own player.
##
## NOT fixed here, measured and left: ContrarianDepths `sw3` is {"flip", "trap"}, so door_open
## (1.00s) is cut by surprised_chime (0.29s) in activate_switch. One switch in the game, and the
## ambush chime arguably SHOULD win. Recorded so the next reader does not re-derive it.

const REWARD_CUES := ["gold_pickup", "item_obtain"]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_reward_cues_have_their_own_player() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_not_null(sm._pickup_player, "reward cues need their own AudioStreamPlayer")
	assert_not_null(sm._ui_player, "CONTROL: the UI player must exist for this comparison to mean anything")
	assert_ne(sm._pickup_player, sm._ui_player,
		"the reward cue is back on the UI player — it will replace whatever earned it")


func test_the_coins_no_longer_replace_the_lid() -> void:
	## THE regression, in the order _open_chest runs it.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("chest_open"), "CONTROL: the lid cue must exist to be eaten")
	sm._sfx_cooldowns.erase("chest_open")
	sm.play_ui("chest_open")
	var lid = sm._ui_player.stream
	assert_not_null(lid, "CONTROL: the lid cue must have loaded, or 'not replaced' is vacuous")
	if lid == null:
		return
	assert_true(str(lid.resource_path).contains("chest_open"),
		"CONTROL: the UI player holds %s, not the lid" % str(lid.resource_path))
	sm._sfx_cooldowns.clear()
	sm.play_pickup("gold_pickup")
	assert_eq(sm._ui_player.stream, lid,
		"the coins replaced the lid — a gold chest opens silently")
	## CONTROL: the coins must genuinely have played, or the assert above passes because the
	## reward cue did nothing at all.
	assert_not_null(sm._pickup_player.stream, "CONTROL: the coins must have loaded on the pickup player")
	assert_true(str(sm._pickup_player.stream.resource_path).contains("gold_pickup"),
		"CONTROL: the pickup player holds %s" % str(sm._pickup_player.stream.resource_path))


func test_every_reward_cue_resolves_through_the_pickup_path() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_eq(REWARD_CUES.size(), 2,
		"REWARD_CUES holds %d, was 2 — a cue leaving this list stops being checked rather than failing" % REWARD_CUES.size())
	var unresolved: Array[String] = []
	for key in REWARD_CUES:
		sm._sfx_cooldowns.erase(key)
		sm.play_pickup(key)
		var st = sm._pickup_player.stream
		if st == null or not str(st.resource_path).contains(key):
			unresolved.append(key)
	assert_eq(unresolved, [],
		"reward cues that did not reach the pickup player (%d): %s" % [unresolved.size(), unresolved])


func test_the_chest_calls_the_pickup_path() -> void:
	## EXECUTION is not SELECTION. Reads CODE, not prose: a call surviving only in a comment is a
	## deleted call (see test_group_attack_cue_survives_its_own_hits for the derivation).
	var raw := FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd")
	var src := _code_only(raw)
	assert_gt(src.length(), 10000, "CONTROL: TreasureChest CODE read back %d chars" % src.length())
	assert_lt(src.length(), raw.length(),
		"CONTROL: stripping removed nothing — the stripper is a pass-through")
	assert_true(src.contains('play_pickup("gold_pickup")'),
		"the chest no longer routes its coins through play_pickup — the lid cue is eaten again")
	assert_false(src.contains('play_ui("gold_pickup")'),
		"the coins are back on the UI player, where they replace the lid cue above them")
	assert_true(src.contains('play_ui("chest_open")'),
		"CONTROL: the lid cue call must still be there, or this test defends nothing")


func _code_only(text: String) -> String:
	## Quote- and escape-aware; case table and derivation in
	## test_group_attack_cue_survives_its_own_hits.gd.
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


func test_the_stripper_actually_strips() -> void:
	assert_false(_code_only('\tpass  ## was play_pickup("gold_pickup")').contains("play_pickup"),
		"a call named in a trailing comment still reads as a call")
	var trailing := _code_only('\tplay_pickup("x")  # coins #2')
	assert_true(trailing.contains('play_pickup("x")'), "the stripper ate a real call")
	assert_false(trailing.contains("coins"), "cut at the LAST # — the comment body survived as code")
	assert_true(_code_only('\tvar s := "has #hash"  # gone').contains('"has #hash"'),
		"a # inside a string literal is not a comment")
