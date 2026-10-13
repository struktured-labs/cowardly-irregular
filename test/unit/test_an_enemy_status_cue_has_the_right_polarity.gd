extends GutTest

## An enemy-targeted effect with no authored status cue played the DESCENDING blip (2026-10-13).
##
## BattleScene._on_action_executed's `_:` catch-all splits on target_type. The ALLY branch got a
## polarity-correct fallback (play_status_if_authored -> play_battle("buff")); the ENEMY branch
## calls play_status(effect), whose terminal fallback is the generic descending blip — struktured
## ruling 15, "not even close to good". So an enemy effect named in no arm, with no cue on disk,
## layered that blip over its own cast cue.
##
## EVIDENCE: struktured's 2026-10-12 session played it 22 times. freq=350 discriminates it from
## the debuff/autobattle_off/grind_stop_manual synths at 400/500/600, and all 22 were 350. Steal
## (14) and overexpose (1) are fixed since 658e834f0; taunt (Lure/Provoke/Taunt), scan,
## press_the_edge and erase (Null Touch) were still live — all six abilities single_enemy.
##
## THE GUARD IS THE DERIVATION, NOT THE REPAIR. The repair routes those four into the debuff arm,
## which is what the codebase already did for dispel_one and volatility_up_enemy. A hand-list
## cannot stay correct, so this asserts the SET IS EMPTY and names any member — the next unrouted
## enemy effect reds here instead of shipping a blip. Membership in that arm is enemy-DIRECTED,
## not BattleManager.SUPPORT_DEBUFFS: volatility_up is in no const and has always sat there.
##
## Deliberately NOT pinning the call shape. Three sibling guards assert the literal
## "SoundManager.play_status(effect)"; that is what a repair has to edit around, and the set-is-
## empty form says the same thing about behaviour without constraining how it is written.

const SCENE_SRC: String = "res://src/battle/BattleScene.gd"
const ABILITIES: String = "res://data/abilities.json"
const ANCHOR: String = "func _on_action_executed"
const ALLY_TARGETS: Array[String] = ["self", "ally", "single_ally", "all_allies", "party"]

var _sm = null


func before_each() -> void:
	_sm = SoundManager


## Every member this file drives. A rename reds here by name rather than aborting an arm that has
## already asserted, which would score Passing.
func test_the_members_this_file_drives_exist() -> void:
	assert_not_null(_sm, "SoundManager autoload missing")
	assert_true(_sm.has_method("play_status"), "SoundManager.play_status is gone")
	assert_true("_sfx_manifest" in _sm, "the _sfx_manifest this guard reads is gone")
	## no floor for Combatant.resolve_status_alias: a class_name static resolves at PARSE time, so a missing member is EC=3 (nothing ran), not a silent abort


## THE DEFECT. Empty, or it names every effect that still reaches the blip.
func test_no_enemy_effect_is_left_to_the_descending_blip() -> void:
	var naked: Array[String] = _unrouted_enemy_effects()
	naked.sort()
	assert_eq(naked.size(), 0,
		("%d enemy-targeted effect(s) are named in no match arm and have no authored status cue even "
		+ "after Combatant.STATUS_ALIASES, so each lays the ruling-15 descending blip over its own "
		+ "cast cue: %s") % [naked.size(), ", ".join(naked)])


## The four live ones route to a cue that is actually ON DISK — "routed" must not mean "routed to
## another miss". Pinned by value because these are the abilities struktured heard.
func test_the_effects_he_heard_route_to_an_authored_cue() -> void:
	var routed: Dictionary = _arm_cues()
	for eff in ["taunt", "scan", "press_the_edge", "erase"]:
		assert_true(routed.has(eff), "%s is no longer named in any arm — it falls to the blip again" % eff)
		var cue: String = str(routed.get(eff, ""))
		assert_true(_sm._sfx_manifest.has(cue),
			"%s routes to \"%s\", which is not an authored cue" % [eff, cue])


## NEGATIVE CONTROL, matching the sibling guards' intent: the repair must not have been "delete the
## blip". It is the designed fallback for weapon procs and BattleManager._cue_status, which pass no
## polarity and must not land silently.
func test_the_blip_still_exists_for_callers_that_have_no_arm() -> void:
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_true(src.contains("SoundManager.play_status(effect)"),
		"the catch-all's play_status(effect) is gone — narrowing which effects reach it was never a reason to remove it")
	var sm_src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	## the WHOLE literal, not just the type: "descending" also names autobattle_off, grind_stop_manual
	## and debuff in SOUNDS, so a file-wide contains() passes while the fallback itself is changed
	assert_true(sm_src.contains('"freq": 350, "duration": 0.2, "type": "descending"'),
		"play_status's terminal fallback is gone or retuned — an unauthored affliction would land silently or sound like something else")


## effect -> cue, for every explicit match arm in _on_action_executed.
func _arm_cues() -> Dictionary:
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
	var arm := RegEx.create_from_string("^\\s*\"[a-z_]*\"(\\s*,\\s*\"[a-z_]*\")*\\s*:\\s*$")
	var key := RegEx.create_from_string("\"([a-z_]*)\"")
	var call := RegEx.create_from_string("play_\\w+\\(\"([a-z_]+)\"\\)")
	var routed: Dictionary = {}
	var pending: Array[String] = []
	for i in range(start, stop):
		var line: String = lines[i]
		if line.strip_edges().begins_with("#"):
			continue
		if arm.search(line) != null:
			pending.clear()
			for m in key.search_all(line):
				pending.append(m.get_string(1))
			continue
		if pending.is_empty():
			continue
		var c = call.search(line)
		if c != null:
			for k in pending:
				routed[k] = c.get_string(1)
			pending.clear()
		elif line.strip_edges() == "pass":
			for k in pending:
				routed[k] = "pass"
			pending.clear()
	return routed


## Shipped effects that are enemy/neutral-targeted, in no explicit arm, and resolve to no authored
## status cue even after the alias map — exactly the path to the blip.
func _unrouted_enemy_effects() -> Array[String]:
	var out: Array[String] = []
	var txt: String = FileAccess.get_file_as_string(ABILITIES)
	if txt == "":
		return out
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		return out
	var rows = parsed["abilities"] if (parsed is Dictionary and parsed.has("abilities")) else parsed
	var routed: Dictionary = _arm_cues()
	for k in (rows.keys() if rows is Dictionary else range(rows.size())):
		var a = rows[k]
		if not (a is Dictionary):
			continue
		var eff: String = str(a.get("effect", "")).to_lower()
		if eff == "" or out.has(eff) or routed.has(eff):
			continue
		if str(a.get("target_type", "")) in ALLY_TARGETS:
			continue
		var canonical: String = Combatant.resolve_status_alias(eff)
		if _sm._sfx_manifest.has("status_" + eff) or _sm._sfx_manifest.has("status_" + canonical):
			continue
		out.append(eff)
	return out
