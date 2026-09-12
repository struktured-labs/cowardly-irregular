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


func test_the_victory_loot_strip_does_not_clip_its_own_coins() -> void:
	## SECOND instance, found by extending the scan to every player. The loot strip reveals chips
	## on a TIMER, not in one frame: _build_loot_strip staggers each chip by `li * 0.22` and fires
	## its cue from a tween_callback. Chips are ordered gold -> items -> bonuses -> injuries, so on
	## any victory with gold AND an item the 1.00s coin cue started at t=1.75 and the 0.25s
	## loot_pop replaced it at t=1.97 — 0.22s in, both on _battle_player.
	##
	## The lexical same-frame scan CANNOT see this: the branches are `if kind == "gold" / elif
	## "item"`, mutually exclusive, and the collision is between two LOOP ITERATIONS. It showed up
	## only because the two calls happen to sit near each other in the file.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("loot_pop"), "CONTROL: the item cue must exist to do the cutting")
	sm._sfx_cooldowns.erase("gold_pickup")
	sm.play_pickup("gold_pickup")
	var coins = sm._pickup_player.stream
	assert_not_null(coins, "CONTROL: the coin cue must have loaded")
	if coins == null:
		return
	sm._sfx_cooldowns.clear()
	sm.play_battle("loot_pop")
	assert_eq(sm._pickup_player.stream, coins,
		"the item chip replaced the coin cue — the loot strip is clipping its own gold")
	assert_ne(sm._battle_player.stream, coins,
		"CONTROL: loot_pop must genuinely have played somewhere, or the assert above is vacuous")


func test_the_victory_overlay_calls_the_pickup_path() -> void:
	## EXECUTION is not SELECTION, and it also pins the CONSISTENCY: after .327 the chest routed
	## gold_pickup to the pickup player while the victory overlay still played the same key on the
	## battle player. One key, one channel.
	var raw := FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	var src := _code_only(raw)
	assert_gt(src.length(), 10000, "CONTROL: VictoryOverlay CODE read back %d chars" % src.length())
	assert_lt(src.length(), raw.length(), "CONTROL: stripping removed nothing")
	assert_true(src.contains('play_pickup("gold_pickup")'),
		"the loot strip no longer routes its coins through play_pickup — the item chip clips them again")
	assert_false(src.contains('play_battle("gold_pickup")'),
		"the coins are back on the battle player, where the next loot chip replaces them 0.22s later")
	## MEASURED and left alone: loot_pop is 0.25s on a 0.22s cadence, so consecutive ITEM chips clip
	## each other by 0.03s. ⚠️ This pin used to justify itself with "that is the staccato the strip
	## is built around — a design call" — which I INFERRED from the cadence and never confirmed with
	## the overlay's owner. A guard that forbids a change while citing an intent nobody stated is
	## defending a preference dressed as a constraint (@cowir-music 2026-09-12, the same shape as a
	## pin that required "Back (Minus)"). So the honest version: I did not evaluate whether item
	## chips should layer, and this pin exists to make that change DELIBERATE, not to call the
	## current routing correct. Move it and update this line with the reason — you cannot silence
	## it green, only explain it green.
	assert_true(src.contains('play_battle("loot_pop")'),
		"loot_pop left the battle player. That may well be right — consecutive item chips clip each other by 0.03s and nobody has ruled on whether they should layer. Update this pin with the reason; it is here so the change is deliberate, not because the current routing is known correct")

