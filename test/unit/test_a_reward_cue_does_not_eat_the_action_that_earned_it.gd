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
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## ⛔ THIS FILE HAD NO TEARDOWN AND MUTATES THE AUTOLOAD SEVEN TIMES. `_sfx_cooldowns` is a SHARED
## dict and a full-suite run is ONE process, so clearing it to observe a cue left the dedupe table
## wiped for every later file. Every arm here also PLAYS something, and a `stream` persists on the
## player after the cue ends — the exact leak sfx_state.gd was written for, measured across six of
## eight guards in this lane. This file was one of the six and I added two more playing arms to it
## in .442 without noticing (@cowir-music's fixture-strand finding, run against my own work).
var _saved_cooldowns: Dictionary = {}


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		_saved_cooldowns = sm._sfx_cooldowns.duplicate(true)


## ⚠️ RELEASE FIRST, restore second. A GDScript error in the restore below aborts after_each, and a
## release sitting at the bottom is then skipped — the sibling teardown in this lane carries the
## same ordering note for the same reason.
func after_each() -> void:
	SfxState.release_streams()
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	for k in _saved_cooldowns:
		sm._sfx_cooldowns[k] = _saved_cooldowns[k]


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
	var src := _code_only(raw, "func _open_chest")
	assert_gt(src.length(), 10000, "CONTROL: TreasureChest CODE read back %d chars" % src.length())
	assert_lt(src.length(), raw.length(),
		"CONTROL: stripping removed nothing — the stripper is a pass-through")
	assert_true(src.contains('play_pickup("gold_pickup")'),
		"the chest no longer routes its coins through play_pickup — the lid cue is eaten again")
	assert_false(src.contains('play_ui("gold_pickup")'),
		"the coins are back on the UI player, where they replace the lid cue above them")
	assert_true(src.contains('play_ui("chest_open")'),
		"CONTROL: the lid cue call must still be there, or this test defends nothing")


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


func test_the_stripper_actually_strips() -> void:
	assert_false(_code_only('\tpass  ## was play_pickup("gold_pickup")', "").contains("play_pickup"),
		"a call named in a trailing comment still reads as a call")
	var trailing := _code_only('\tplay_pickup("x")  # coins #2', "")
	assert_true(trailing.contains('play_pickup("x")'), "the stripper ate a real call")
	assert_false(trailing.contains("coins"), "cut at the LAST # — the comment body survived as code")
	assert_true(_code_only('\tvar s := "has #hash"  # gone', "").contains('"has #hash"'),
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
	var src := _code_only(raw, "func _build_loot_strip")
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


func test_the_level_up_flourish_is_not_cut_by_a_loot_chip() -> void:
	## THIRD instance in this strip, and a different victim from the coins. .327 moved gold to
	## _pickup_player; the level-up flourish stayed on _battle_player beside loot_pop and nothing
	## looked. _level_up_flare fires at 0.5 + i*0.15 + 0.15 + steps*0.04 + 0.35 — about 1.56s for
	## the first card — and item chips land at 1.5 + 0.25 + li*0.22. The flourish is 0.88s, so a
	## chip at 1.97 replaces it 0.41s in, on any victory with a level-up AND an item drop.
	## PRODUCED before fixing: play_battle both ways left two different streams on the player.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("levelup_flourish"), "CONTROL: the flourish must exist to be cut")
	assert_true(sm._sfx_manifest.has("loot_pop"), "CONTROL: the item cue must exist to do the cutting")
	## ⛔ DRIVES THE METHOD THE OVERLAY ACTUALLY CALLS, not the one the fix chose. The first
	## version of this arm called play_flourish directly — so it passed on the shipped fix AND
	## on a revert of it, because the test, not the overlay, picked the voice. It proved the two
	## voices are separate and nothing about the routing (@cowir-music 2026-09-18: a driven arm
	## is not load-bearing unless it drives the case where the mechanisms disagree).
	var vo_src := FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	var m := RegEx.create_from_string("SoundManager\\.(\\w+)\\(\"levelup_flourish\"\\)").search(vo_src)
	assert_ne(m, null, "CONTROL: VictoryOverlay must still cue levelup_flourish, or this arm tests nothing")
	if m == null:
		return
	var cue_method: String = m.get_string(1)
	var voice: String = str({"play_battle": "_battle_player", "play_flourish": "_flourish_player",
		"play_ui": "_ui_player", "play_death": "_death_player", "play_pickup": "_pickup_player"}.get(cue_method, ""))
	assert_ne(voice, "",
		"the overlay cues the level-up through %s and this arm does not know its voice — add it, do not delete the assert" % cue_method)
	if voice == "":
		return
	assert_true(sm.has_method(cue_method), "SoundManager has no method %s — the overlay calls it" % cue_method)
	sm._sfx_cooldowns.clear()
	sm.call(cue_method, "levelup_flourish")
	var flourish = sm.get(voice).stream
	assert_not_null(flourish, "CONTROL: the flourish must have loaded on %s" % voice)
	if flourish == null:
		return
	sm._sfx_cooldowns.clear()
	sm.play_battle("loot_pop")
	assert_eq(sm.get(voice).stream, flourish,
		"an item chip replaced the level-up flourish on %s — the loudest moment on the victory screen, cut 0.41s in" % voice)


func test_the_victory_overlay_routes_the_level_up_through_its_own_voice() -> void:
	## The load-bearing half: the arm above only proves the two voices are SEPARATE. This proves
	## the overlay uses the separate one. Same shape as the coins pin directly above.
	## levelup_flourish carries no _BATTLE_VOLUME_TRIM_DB entry and play_flourish passes
	## SFX_BATTLE_BASE_DB, so this moves the CHANNEL without moving the mix level.
	var raw := FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	var src := _code_only(raw, "func _level_up_flare")
	assert_gt(src.length(), 10000, "CONTROL: VictoryOverlay CODE read back %d chars" % src.length())
	assert_true(src.contains('play_flourish("levelup_flourish")'),
		"the level-up flourish is back on the shared battle player, where the next loot chip replaces it 0.41s in")
	assert_false(src.contains('play_battle("levelup_flourish")'),
		"the level-up flourish is back on the shared battle player, where the next loot chip replaces it 0.41s in")
	assert_false(src.contains('play_battle("level_up")'),
		"the FALLBACK level-up cue is on the battle player too — it is unreachable while levelup_flourish ships, so it would rot there unnoticed")


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
	## ⚠️ IF YOU REGENERATE THIS LIST, STRIP COMMENTS FIRST (test/unit/helpers/gd_source.gd). The
	## generator that produced it read RAW source, so a trailing `# was sm.old_name()` — precisely
	## what a rename commit writes — becomes a listed member that never existed, and the floor then
	## REDS ON CORRECT CODE. cowir-music demonstrated that false red in their own floors 2026-09-16.
	## This list is ghost-free only because no such comment existed when it was generated.
	for method_name in ["play_battle", "play_flourish", "play_pickup", "play_ui"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it, and whether that shows as Risky or as a silent pass is decided by arm ORDER, not by care" % method_name)
	## ⚠️ get() CANNOT DISTINGUISH ABSENT FROM LEGITIMATELY NULL (@cowir-sprites): it returns null
	## for both. Every member below is a player, a Dictionary or a String — none is ever null once
	## _ready has run — so the check is sound HERE. If you add a nullable member to this list
	## (_crossfade_tween and the other _*_tween members are EXAMPLES, not an exhaustive list — check
	## the declaration), switch to get_property_list(), which answers about existence rather than value.
	for member_name in ["_battle_player", "_flourish_player", "_pickup_player", "_sfx_cooldowns", "_sfx_manifest", "_ui_player"]:
		## assert_true on an explicit `!= null`: assert_ne deep-compares, and three of these members
		## are Dictionaries, which it refuses with "Only Arrays and Dictionaries are supported".
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort its arms SILENTLY" % member_name)
