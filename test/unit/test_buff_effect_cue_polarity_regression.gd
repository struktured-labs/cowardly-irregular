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


func test_the_four_repaired_effects_route_to_the_BUFF_cue() -> void:
	## Pins VALUES, not presence. "the effect is routed somewhere" was true of the bug —
	## `_:` is a route. Only naming the expected cue catches a beneficial effect wired to
	## the debuff arm, which is the same defect wearing the other sign.
	var routed: Dictionary = _routed_effects()
	for effect in ["magic_defense_up", "regen", "barrier", "cleanse"]:
		assert_eq(str(routed.get(effect, "<unrouted>")), "buff",
			"'%s' is beneficial (Shell / Regen / Guardian Wall / Esuna) and must play the ascending buff cue" % effect)


func test_the_descending_fallback_still_exists_for_afflictions() -> void:
	## NEGATIVE CONTROL. The fix must not have been "delete the fallback" — that arm is
	## deliberate (an unauthored affliction should not land silently). If someone removes it,
	## this fails and tells them the buff fix was never the reason to.
	var src: String = FileAccess.get_file_as_string(SCENE_SRC)
	assert_true(src.contains("SoundManager.play_status(effect)"),
		"the `_:` fallback arm is gone — the buff repair narrowed which effects reach it and never removed it")
