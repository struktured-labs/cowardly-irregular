extends GutTest

## A buff played the DESCENDING blip (2026-08-06).
##
## BattleScene._on_action_executed matches an ability's `effect` and picks a cue. Four
## beneficial effects were not in the buff arm, so they fell to `_:` -> play_status(effect)
## -> manifest miss -> the procedural DESCENDING tone, which is the debuff-shaped sound:
##   magic_defense_up (Shell) · regen (Regen, Regenerate) · barrier (Guardian Wall)
##   · cleanse (Esuna, Garbage Collect)
##
## Not silence, and worse than it: play_ability() fires on the ability channel at the same
## time, so Shell played its correct cast cue with a wrong-polarity blip layered on top.
##
## The tell was structural, not audible: `magic_defense_down` was in the DEBUFF arm and its
## own opposite was in no arm at all. Someone listed one direction of a pair. So the guard
## below asserts the PAIR RELATIONSHIP rather than a list of effect names — a hand-list would
## need editing every time an ability is added, and would go stale silently the same way.

const SCENE_SRC: String = "res://src/battle/BattleScene.gd"
const ABILITIES: String = "res://data/abilities.json"
const ANCHOR: String = "func _on_action_executed"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## Extracts effect -> cue for every match arm in _on_action_executed.
func _routed_effects() -> Dictionary:
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	var lines: PackedStringArray = src.split("\n")
	var start: int = -1
	for i in range(lines.size()):
		if lines[i].begins_with(ANCHOR):
			start = i
			break
	if start < 0:
		return {}
	var stop: int = lines.size()
	for i in range(start + 1, lines.size()):
		if lines[i].begins_with("func "):
			stop = i
			break

	var arm := RegEx.create_from_string("^\\s*\"[a-z_]+\"(\\s*,\\s*\"[a-z_]+\")*\\s*:\\s*$")
	var key := RegEx.create_from_string("\"([a-z_]+)\"")
	var call := RegEx.create_from_string("play_\\w+\\(\"([a-z_]+)\"\\)")

	var routed: Dictionary = {}
	var pending: Array[String] = []
	for i in range(start, stop):
		var line: String = lines[i]
		if arm.search(line) != null:
			pending.clear()
			for m in key.search_all(line):
				pending.append(m.get_string(1))
			continue
		if pending.is_empty():
			continue
		if line.contains("play_battle(") or line.contains("play_status(\""):
			var c: RegExMatch = call.search(line)
			if c != null:
				for k in pending:
					routed[k] = c.get_string(1)
			pending.clear()
	return routed


func _ability_effects() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	if not (parsed is Dictionary):
		return {}
	var abilities: Variant = parsed.get("abilities", parsed)
	var out: Dictionary = {}
	for aid in abilities.keys():
		var a: Variant = abilities[aid]
		if not (a is Dictionary):
			continue
		var e: String = str(a.get("effect", ""))
		if not e.is_empty():
			out[e] = out.get(e, []) + [str(aid)]
	return out


func test_premise_the_extraction_has_BOTH_controls() -> void:
	## A range-scoped probe has two failure modes and only one is usually guarded: the pattern
	## can be wrong, OR the scope can be empty. My first cut of this extraction anchored on a
	## line that occurs twice and silently read the wrong 62 lines — the pattern was fine and
	## the answer was meaningless. Both controls, or the counts below prove nothing.
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_gt(src.length(), 1000, "SCOPE control: BattleScene.gd read back empty")
	assert_eq(src.split("\n").count(ANCHOR + "(combatant: Combatant, action: Dictionary, targets: Array) -> void:"), 1,
		"SCOPE control: '%s' must occur EXACTLY once — if it moved or gained an overload, this extraction is reading an arbitrary region" % ANCHOR)

	var routed: Dictionary = _routed_effects()
	assert_gt(routed.size(), 10,
		"SCOPE control: extracted only %d routed effects. A non-empty region is not implied by a valid pattern — this is the control that catches a range collapsing onto its own first line." % routed.size())
	assert_true(routed.values().has("buff"),
		"STRING control: no arm routes to the 'buff' cue, so the extraction did not reach the match block even if it found lines")


func test_premise_the_ability_catalog_parses() -> void:
	var effects: Dictionary = _ability_effects()
	assert_gt(effects.size(), 40,
		"PREMISE: only %d distinct ability effects parsed — every pairing below would be vacuous" % effects.size())


func test_polarity_pairs_are_routed_to_OPPOSITE_cues() -> void:
	## THE LOAD-BEARING GUARD. For any effect pair X_up / X_down that both exist as real
	## ability effects, both must be routed and to DIFFERENT cues. This is what failed:
	## magic_defense_down was in the debuff arm, magic_defense_up was in no arm.
	##
	## Derived from the source and the catalog on every run, so a new ability with a new
	## polarity pair is covered the day it lands and nothing here needs editing.
	var routed: Dictionary = _routed_effects()
	var effects: Dictionary = _ability_effects()
	var pairs: int = 0
	var broken: Array[String] = []
	for up in effects.keys():
		if not str(up).ends_with("_up"):
			continue
		var down: String = str(up).substr(0, str(up).length() - 3) + "_down"
		if not effects.has(down):
			continue
		pairs += 1
		var a: String = str(routed.get(up, ""))
		var b: String = str(routed.get(down, ""))
		if a.is_empty() or b.is_empty() or a == b:
			broken.append("%s -> '%s' vs %s -> '%s'" % [up, a, down, b])
	assert_gt(pairs, 0,
		"control: found no X_up/X_down pairs at all — the pairing logic is broken, not the routing")
	assert_eq(broken.size(), 0,
		"%d polarity pair(s) route asymmetrically. One direction of a stat pair has a cue and its opposite does not, which means a buff is falling to `_:` and drawing the DESCENDING procedural blip on top of its own cast cue: %s" % [broken.size(), broken])


## effect -> [ability ids] for abilities whose own target_type says they help the caster's side.
func _ally_targeted_effects() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	if not (parsed is Dictionary):
		return {}
	var abilities: Variant = parsed.get("abilities", parsed)
	var ally: Array[String] = ["self", "ally", "single_ally", "all_allies", "party"]
	var out: Dictionary = {}
	for aid in abilities.keys():
		var a: Variant = abilities[aid]
		if not (a is Dictionary):
			continue
		var e: String = str(a.get("effect", ""))
		if e.is_empty() or not (str(a.get("target_type", "")) in ally):
			continue
		out[e] = out.get(e, []) + [str(aid)]
	return out


func test_a_beneficial_effect_with_no_polarity_TWIN_still_avoids_the_blip() -> void:
	## SECOND CORPUS, SAME DEFECT, AND THIS FILE WAS GREEN ACROSS IT THE WHOLE TIME.
	## The pair arm above can only see an effect that HAS an X_up/X_down twin. Measured
	## ⛔ NO COUNT PINNED HERE ON PURPOSE — the assert below DERIVES it and prints it on failure.
	## The first draft of this comment said "24", which was ability ROWS; distinct EFFECTS were 22,
	## and the correction that moved dispel_and_self_buff to the debuff arm made it 21 the same
	## hour. Three figures for one fact, in prose, inside a file whose arms were correct throughout
	## (@cowir-music's third rung, 2026-09-18). Examples, which is what prose is for:
	## mp_restore_and_ap (Inspiring Melody),
	## reflect (Magic Reflect), invisible (Vanish), evasion (Burrow), brave_actions (Brave),
	## damage_absorb (Fill the Void) — so they fall straight to `_:` -> play_status -> manifest
	## miss -> the DESCENDING blip, on top of their own cast cue. Fourteen are literally
	## animation:"buff". A guard installed FOR this defect, passing on its next instance.
	##
	## ⛔ NOT A THIRD HAND-LIST. The buff arm was hand-extended once for four effects and 24
	## more arrived behind it; the file's own header predicted that ("would go stale silently
	## the same way") and then picked a derivation — polarity pairs — that this corpus escapes.
	## target_type is the ability's OWN statement of who it helps, so a buff authored tomorrow
	## is covered without editing anything here.
	var routed: Dictionary = _routed_effects()
	var ally: Dictionary = _ally_targeted_effects()
	assert_gt(ally.size(), 5,
		"PREMISE: only %d ally-targeted effects parsed — every assert below would be vacuous" % ally.size())

	var unrouted: Array[String] = []
	for e in ally.keys():
		## DEFERRED effects are not unrouted: cleanse has an explicit arm that plays nothing here
		## because its executor owns the cue. Counting it would name it in a message that says it
		## draws the descending blip, which is false and sends the reader to the wrong file.
		if e == "cleanse":
			continue
		if not routed.has(e):
			unrouted.append("%s (%s)" % [e, str(ally[e][0])])
	assert_gt(unrouted.size(), 0,
		"ANTI-VACUITY: every ally-targeted effect now has an explicit arm, so the catch-all pin below defends nothing. If that is deliberate, delete this arm and say why.")

	## ⛔ THE CODE HALF, AND A CALL SHAPE RATHER THAN A BARE TOKEN. Both asserts below read RAW
	## source and matched `target_type` in the first draft — which my OWN comment in that function
	## names twice, so the pin was satisfied by my prose. PRODUCED 2026-09-18: swap the live
	## `ability.get("target_type", ...)` for a different field, leave the comment, and this arm
	## returned EC=0 · 8 passing with the mechanism gone (@cowir-deploy's *what it argued vs what
	## it pinned*; @cowir-controller's *a source guard keyed to a token certifies spelling*).
	var code: String = GdSource.code_of(SCENE_SRC)
	assert_ne(code, "", "CONTROL: BattleScene code must survive the comment strip")
	var at: int = code.find("func _on_action_executed")
	assert_gt(at, -1, "CONTROL: the handler must survive the strip, or both asserts below read nothing")
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, nxt - at) if nxt > at else code.substr(at)
	assert_true(body.contains("ability.get(\"target_type\""),
		"%d ally-targeted effect(s) reach the `_:` catch-all and it does not READ target_type off the ability, so each draws the DESCENDING debuff blip over its own cast cue: %s" % [unrouted.size(), unrouted])
	assert_true(body.contains("SoundManager.play_status(effect)"),
		"ANTI-OVERCORRECTION: the catch-all must still send ENEMY-targeted effects to play_status — routing everything to the buff cue is the same defect wearing the other sign")


func test_an_ally_TARGETED_but_ally_HOSTILE_effect_keeps_the_debuff_cue() -> void:
	## ⛔ THE LIMIT OF THE DERIVATION ABOVE, PINNED BY VALUE SO IT CANNOT BE QUIETLY REMOVED.
	## target_type answers WHO IS AIMED AT, not WHO IS HELPED, and those diverge in exactly one
	## shipped row (measured 2026-09-18, every ally-targeted catch-all effect read against its
	## BattleManager handlers): `dispel_and_self_buff` is target_type single_ally and STRIPS that
	## ally's buffs — BattleManager's own comment calls it "(sacrifice)" and logs it in
	## penalty_bbcode. Its base effect `dispel` is already in the debuff arm, so the codebase had
	## ruled on this event; the composed name escaped the literal match.
	##
	## Caught by @cowir-adhoc against the branch, BEFORE the fold — the target_type fix would have
	## played the ASCENDING buff cue while the player's buffs were being stripped, which is the
	## original defect wearing the other sign.
	##
	## Two others tripped a hostility scan and are NOT hostile — read, not counted:
	## break_mind_swap logs cyan "breaks the mind swap!" (freeing yourself) and random_stat_change
	## is a 50/50 self-gamble emitting bonus_bbcode on the up-roll.
	var routed: Dictionary = _routed_effects()
	assert_eq(str(routed.get("dispel_and_self_buff", "<unrouted>")), "debuff",
		"Reduce Overhead strips a party member's buffs. It is aimed AT an ally and hostile TO them, so target_type routes it to the buff cue — an ascending fanfare over the player losing every buff they had")


func test_the_repaired_effects_route_to_the_BUFF_cue() -> void:
	## Pins VALUES, not presence. "the effect is routed somewhere" was true of the bug —
	## `_:` is a route. Only naming the expected cue catches a beneficial effect wired to
	## the debuff arm, which is the same defect wearing the other sign.
	##
	## ⚠️ WAS FOUR. `cleanse` left this list on 2026-10-12 — see the arm below. The name said
	## "four" and the list is three; a count in a test NAME is the same drift this file's own
	## header warns about in prose.
	var routed: Dictionary = _routed_effects()
	for effect in ["magic_defense_up", "regen", "barrier"]:
		assert_eq(str(routed.get(effect, "<unrouted>")), "buff",
			"'%s' is beneficial (Shell / Regen / Guardian Wall) and must play the ascending buff cue" % effect)


## `cleanse` (Esuna, Garbage Collect) is DEFERRED to BattleManager's cleanse executor, which is the
## only place that knows whether an ailment actually came off: `status_cured.ogg` was composed for
## this event and reached nothing, because the cue is keyed `cured` while the effect is named
## `cleanse`, so no `status_<effect>` lookup could find it. A cure that cured NOTHING must not sound
## like one, and BattleScene cannot tell. Cueing in both places would double it.
##
## So this arm replaces the buff-cue pin with the two halves that make the deferral honest: nothing
## cues it here, and the named owner DOES. A deferral nobody verifies is just a deletion.
func test_cleanse_is_deferred_to_its_executor_and_the_executor_cues_it() -> void:
	var routed: Dictionary = _routed_effects()
	assert_eq(str(routed.get("cleanse", "<unrouted>")), "<unrouted>",
		"cleanse plays a cue in BattleScene again, so a cure now sounds twice — once here and once from BattleManager's executor, and the 80 ms per-key cooldown hides the second from any log")
	var bm: String = GdSource.code_of("res://src/battle/BattleManager.gd")
	assert_ne(bm, "", "CONTROL: BattleManager code must survive the comment strip")
	assert_true(bm.contains("SoundManager.play_status(\"cured\")"),
		"cleanse is deferred out of BattleScene and NOTHING in BattleManager cues it, so every cure is now silent — the deferral must be honoured by its owner")
	assert_true(bm.contains("ESUNA_AILMENTS"),
		"CONTROL: the cleanse executor must still be the thing that reads ESUNA_AILMENTS, or the check above is pinned to an unrelated call site")


func test_an_effect_NAMED_after_an_authored_cue_must_route_to_it() -> void:
	## Second instance of the same defect, found by the same question asked wider. Seven
	## Masterite abilities carry the literal effect strings "buff" and "debuff" — both are
	## authored cues in the manifest. The catch-all asks for status_<effect>, so it looked up
	## status_buff, missed, and drew the procedural blip while buff.ogg sat right there.
	##
	## Derived, so it covers the NEXT one automatically: if an effect string is itself a
	## manifest key, the intent is unambiguous and it must be routed. No hand-list to go stale.
	var routed: Dictionary = _routed_effects()
	var effects: Dictionary = _ability_effects()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = parsed.get("sfx", {}) if parsed is Dictionary else {}
	assert_gt(sfx.size(), 200, "control: sfx manifest parsed to %d entries — implausible" % sfx.size())

	var matches: int = 0
	var unrouted: Array[String] = []
	for effect in effects.keys():
		if not sfx.has(effect):
			continue
		matches += 1
		if not routed.has(effect):
			unrouted.append("%s (abilities: %s)" % [effect, effects[effect]])
	assert_gt(matches, 0,
		"control: no ability effect string matches a manifest cue name at all — the join is broken, not the routing")
	assert_eq(unrouted.size(), 0,
		"%d effect(s) are spelled exactly like an authored cue and are still unrouted, so the lookup asks for 'status_<effect>', misses, and plays the procedural blip while the real cue sits in the manifest: %s" % [unrouted.size(), unrouted])


func test_the_descending_fallback_still_exists_for_afflictions() -> void:
	## NEGATIVE CONTROL. The fix must not have been "delete the fallback" — that arm is
	## deliberate (an unauthored affliction should not land silently). If someone removes it,
	## this fails and tells them the buff fix was never the reason to.
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_true(src.contains("SoundManager.play_status(effect)"),
		"the `_:` fallback arm is gone — the buff repair narrowed which effects reach it and never removed it")


## THIRD CORPUS, SAME DEFECT, AND BOTH DERIVATIONS ABOVE ARE BLIND TO IT BY CONSTRUCTION.
## The polarity-pair arm needs an X_up/X_down twin; the no-twin arm filters on `target_type` being
## ALLY-ish. An ENEMY-targeted effect with no arm takes the catch-all's `else` branch —
## play_status(effect) -> no status_<effect> on disk -> the generic DESCENDING blip — and nothing
## here looked. Two were sitting there, each with its own siblings already in the debuff arm:
##   dispel_one          (remove_element)  while dispel + dispel_and_self_buff route to debuff
##   volatility_up_enemy (overexpose)      while volatility_up routes to debuff, _self to buff
##
## ⛔ THE BLIP IS NOT ALWAYS WRONG, which is why this cannot be "every unrouted effect". It is the
## DESIGNED fallback for an unauthored affliction (pinned by the arm below this one), so `static`,
## `taunt`, `scan`, `steal`, `erase` and `press_the_edge` reach it legitimately — some are statuses,
## the rest are actions nobody has authored a cue for. Measured: 9 effects reach the blip, and only
## these 2 are defects.
##
## ✅ SO THE DISCRIMINATOR IS A FAMILY, NOT A COUNT: if a routed effect is a PREFIX of an unrouted
## one, they are the same mechanic and the unrouted one was forgotten. Derived from the source and
## the catalog, so the next `dispel_two` or `volatility_up_party` reds the day it lands. On today's
## catalog this admits exactly the two above and nothing else — verified by the anti-vacuity arm.
func _enemy_targeted_effects() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	if not (parsed is Dictionary):
		return {}
	var abilities: Variant = parsed.get("abilities", parsed)
	var ally: Array[String] = ["self", "ally", "single_ally", "all_allies", "party"]
	var out: Dictionary = {}
	for aid in abilities.keys():
		var a: Variant = abilities[aid]
		if not (a is Dictionary):
			continue
		var e: String = str(a.get("effect", ""))
		if e.is_empty() or str(a.get("target_type", "")) in ally:
			continue
		out[e] = out.get(e, []) + [str(aid)]
	return out


## Unrouted effects that share a stem with a ROUTED one, as [effect, the routed sibling].
func _orphaned_family_members() -> Array:
	var routed: Dictionary = _routed_effects()
	var enemy: Dictionary = _enemy_targeted_effects()
	var out: Array = []
	for e in enemy.keys():
		if routed.has(e):
			continue
		for r in routed.keys():
			if str(e).begins_with(str(r) + "_"):
				out.append([str(e), str(r)])
				break
	return out


func test_an_enemy_targeted_effect_whose_FAMILY_is_routed_must_be_routed_too() -> void:
	var routed: Dictionary = _routed_effects()
	var enemy: Dictionary = _enemy_targeted_effects()
	assert_gt(enemy.size(), 10,
		"PREMISE: only %d enemy-targeted effects parsed — this arm would be vacuous" % enemy.size())
	assert_true(routed.has("dispel"),
		"CONTROL: `dispel` is not routed, so no stem exists for the family rule to match against")

	var orphans: Array = _orphaned_family_members()
	var msg: Array[String] = []
	for o in orphans:
		msg.append("%s (sibling `%s` is routed to '%s')" % [o[0], o[1], str(routed.get(o[1], ""))])
	assert_eq(msg, [],
		"%d enemy-targeted effect(s) share a stem with a routed effect but have no arm, so they take the catch-all's else branch and draw the generic DESCENDING blip while their own family plays an authored cue: %s" % [msg.size(), msg])


func test_the_two_repaired_effects_route_to_the_DEBUFF_cue() -> void:
	## Named, because the family rule above is satisfied by routing them ANYWHERE. Both remove or
	## destabilise something on an enemy, so `debuff` is the cue their siblings already use — the
	## buff cue would be the original defect with the opposite sign.
	var routed: Dictionary = _routed_effects()
	for e in ["dispel_one", "volatility_up_enemy"]:
		assert_eq(str(routed.get(e, "")), "debuff",
			"%s must route to the debuff cue like the rest of its family, not '%s'" % [e, str(routed.get(e, ""))])


func test_the_family_rule_admits_only_what_was_actually_broken() -> void:
	## ⛔ ANTI-VACUITY IN THE OTHER DIRECTION: a prefix rule is cheap to write too wide, and a wide
	## one would demand an arm for every affliction that correctly reaches the blip. This pins the
	## rule's REACH rather than its verdict — if a future catalog makes it claim a third effect, the
	## claim is read before it is obeyed.
	var routed: Dictionary = _routed_effects()
	var enemy: Dictionary = _enemy_targeted_effects()
	var claimed: Array[String] = []
	for e in enemy.keys():
		for r in routed.keys():
			if str(e).begins_with(str(r) + "_"):
				claimed.append(str(e))
				break
	claimed.sort()
	assert_eq(claimed, ["dispel_one", "volatility_up_enemy"],
		"the family rule now reaches a different set than the two it was derived for: %s. Read them before routing them — the blip is CORRECT for an unauthored affliction." % [claimed])
