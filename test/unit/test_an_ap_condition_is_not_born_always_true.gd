extends GutTest

## Switching a condition's type to `ap` in the grid editor seeds `AP < 50`, and AP is clamped to
## -4..+4 everywhere in the engine (Combatant.gd:233,252). So the condition is PERMANENTLY TRUE,
## and autobattle rules are first-match-wins top-to-bottom: an always-true rule shadows every rule
## under it. The player authored one rule and silently disabled the rest of the script.
##
## 🔑 THE FIX ALREADY EXISTS FOUR LINES ABOVE IT, for the same defect. `volatility_band` is 0..3
## and got its own seeding arm with a comment naming this exact hazard — "the generic numeric
## default below is `< 50`, which here is permanently TRUE — and an always-true condition shadows
## every rule under it". `ap` has the identical shape and was not given the same treatment.
##
## ⚠️ The seed survives because _apply_condition_type only fills what is MISSING (`if not
## cond.has("value")`), and a condition always arrives from _add_and_condition already carrying
## hp_percent's `{"op": "<", "value": 50}`. So the `else` branch's defaults never apply on the
## path a player actually takes — the values are inherited from the type they switched AWAY from.
##
## Second defect, same file: _adjust_condition_value clamps EVERY numeric to `clamp(v, 0, 100)`.
## AP debt is a designed mechanic (CLAUDE.md: "can go into debt"; the LLM prompt says "negative is
## debt", and live llama3 composes debt rules at -4). A player cannot author, or repair, one.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _abs
var _profiles_backup: Dictionary = {}


func before_each() -> void:
	_abs = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(_abs, "CONTROL: AutobattleSystem autoload must exist")
	## Instantiating the editor registers a character profile on the AUTOLOAD, which outlives this
	## file and reaches every later one in a full-suite run. Measured: one entry left behind per
	## run. The WHOLE map is restored rather than the keys this file names — a profile created by
	## the editor is exactly the state I would not think to name.
	_profiles_backup = (_abs.character_profiles as Dictionary).duplicate(true)


func after_each() -> void:
	if _abs != null:
		var live: Dictionary = _abs.character_profiles
		live.clear()
		for k in _profiles_backup:
			live[k] = _profiles_backup[k]


func _pc(ap: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 400, "max_mp": 80,
		"attack": 20, "defense": 30, "magic": 30, "speed": 12})
	add_child_autofree(c)
	## _ready() sets current_hp/current_mp from the maxima, so every field this fixture
	## cares about is written AFTER the node enters the tree.
	c.current_ap = ap
	return c


## An editor holding ONE rule with ONE condition, exactly as _add_and_condition leaves it.
func _editor_on_a_fresh_condition() -> Node:
	var ed: Node = load(EDITOR).new()
	add_child_autofree(ed)
	await get_tree().process_frame
	var rules: Array = ed.get("rules") as Array
	rules.clear()
	rules.append({"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "attack"}], "enabled": true})
	ed.set("cursor_row", 0)
	ed.set("cursor_col", 0)
	return ed


func _seeded(ed: Node) -> Dictionary:
	return ((ed.get("rules") as Array)[0] as Dictionary)["conditions"][0] as Dictionary


# ── the defect ────────────────────────────────────────────────────────────────

func test_switching_a_condition_to_ap_does_not_make_it_always_true() -> void:
	## THE ARM, and it is behavioural: the seeded condition is evaluated by the REAL evaluator at
	## both ends of the engine's own AP range. A condition true at BOTH is true always.
	var ed: Node = await _editor_on_a_fresh_condition()
	assert_true(ed.has_method("_apply_condition_type"),
		"FLOOR: the editor must define _apply_condition_type, or this arm drives nothing")
	ed.call("_apply_condition_type", "ap")
	var cond: Dictionary = _seeded(ed)
	assert_eq(str(cond.get("type", "")), "ap", "CONTROL: the type must actually have changed")
	var at_full: bool = _abs._evaluate_grid_condition(_pc(4), cond)
	var at_debt: bool = _abs._evaluate_grid_condition(_pc(-4), cond)
	assert_false(at_full and at_debt,
		"the editor seeded %s — true at AP=+4 AND at AP=-4, so it matches every turn and shadows every rule below it" % [cond])


func test_a_player_can_author_an_ap_debt_condition() -> void:
	## AP debt is a designed mechanic and the composer emits it at -4. The editor's value stepper
	## clamps every numeric to 0..100, so a debt rule cannot be authored OR repaired by hand.
	var ed: Node = await _editor_on_a_fresh_condition()
	ed.call("_apply_condition_type", "ap")
	assert_true(ed.has_method("_adjust_condition_value"),
		"FLOOR: the editor must define _adjust_condition_value, or this arm drives nothing")
	## Press DOWN far more times than any legal range needs.
	for _i in range(120):
		ed.call("_adjust_condition_value", -1)
	var reached: int = int(_seeded(ed).get("value", 999))
	assert_lt(reached, 0,
		"stepping down 120 times reached AP %d — negative AP is unreachable, so no debt rule can be authored" % reached)


func test_an_ap_value_the_engine_can_never_reach_is_not_offered() -> void:
	## The other end: AP caps at +4, so any seeded or stepped value above it is a rule that
	## validates, displays, and never fires.
	var ed: Node = await _editor_on_a_fresh_condition()
	ed.call("_apply_condition_type", "ap")
	for _i in range(120):
		ed.call("_adjust_condition_value", 1)
	var reached: int = int(_seeded(ed).get("value", -999))
	assert_lte(reached, 4,
		"stepping up 120 times reached AP %d, and the engine clamps current_ap to +4 — every value above 4 is a condition that can never be true" % reached)


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_already_fixed_sibling_still_passes_this(): 
	## volatility_band is the same defect, fixed. If it fails here the arms above are measuring
	## something other than the seeding bug.
	var ed: Node = await _editor_on_a_fresh_condition()
	ed.call("_apply_condition_type", "volatility_band")
	var cond: Dictionary = _seeded(ed)
	assert_eq(str(cond.get("type", "")), "volatility_band", "CONTROL: type changed")
	assert_eq(int(cond.get("value", -1)), 2, "CONTROL: band is seeded to its signature play, not 50")


func test_the_arm_can_tell_an_ordinary_condition_apart() -> void:
	## CONTROL: hp_percent < 50 is NOT always true, so "true at both ends" is a real discriminator
	## and not something every condition would satisfy.
	var lo := Combatant.new()
	lo.initialize({"name": "Lo", "max_hp": 400, "max_mp": 80, "attack": 20, "defense": 30, "magic": 30, "speed": 12})
	add_child_autofree(lo)
	lo.current_hp = 1
	var hi := Combatant.new()
	hi.initialize({"name": "Hi", "max_hp": 400, "max_mp": 80, "attack": 20, "defense": 30, "magic": 30, "speed": 12})
	add_child_autofree(hi)
	var cond := {"type": "hp_percent", "op": "<", "value": 50}
	assert_true(_abs._evaluate_grid_condition(lo, cond), "CONTROL: true at 1 HP")
	assert_false(_abs._evaluate_grid_condition(hi, cond), "CONTROL: false at full HP")


func test_a_percentage_number_survives_a_switch_to_another_percentage() -> void:
	## The repair resets the value when the SCALE changes, not on every type change. 30 means the
	## same thing as an HP percent and as an MP percent, so a player who dialled it keeps it —
	## otherwise the fix trades a silent always-true rule for a silently discarded edit.
	var ed: Node = await _editor_on_a_fresh_condition()
	_seeded(ed)["value"] = 30
	ed.call("_apply_condition_type", "mp_percent")
	assert_eq(int(_seeded(ed).get("value", -1)), 30,
		"a percentage number must survive a switch to another percentage condition")


func test_a_number_does_not_survive_a_switch_to_another_scale() -> void:
	## The other half, and the one the defect was made of: 30 as an HP percent is "badly hurt",
	## and as an AP bank it is a number the engine clamps to 4 — a rule that matches every turn.
	var ed: Node = await _editor_on_a_fresh_condition()
	_seeded(ed)["value"] = 30
	ed.call("_apply_condition_type", "ap")
	assert_lte(int(_seeded(ed).get("value", 999)), 4,
		"an HP percentage carried onto the AP scale is a permanently-true rule")


func test_the_nullary_set_is_derived_and_not_empty() -> void:
	## FLOOR on the derivation itself. It is read from AutobattleSystem's own list, and an empty
	## return is indistinguishable from "no type is nullary" — which silently restores the exact
	## defect this branch removes, with every arm below still green.
	var ed: Node = await _editor_on_a_fresh_condition()
	var got: Array = ed.call("_nullary_condition_types")
	assert_gt(got.size(), 0, "an empty nullary set re-opens the defect and reds nothing")
	assert_eq(got, _abs.NULLARY_CONDITIONS as Array,
		"the editor's nullary set must BE the grammar owner's, not a copy of it")


func test_a_nullary_condition_keeps_no_operator_or_value() -> void:
	## ally_dead and is_night are nullary by the owner's list and were absent from the editor's
	## three hand-lists, so they were seeded `< 50` and the dial edited a number nothing reads.
	for t in ["ally_dead", "is_night"]:
		var ed: Node = await _editor_on_a_fresh_condition()
		ed.call("_apply_condition_type", t)
		var cond: Dictionary = _seeded(ed)
		assert_eq(str(cond.get("type", "")), t, "CONTROL: type changed to %s" % t)
		assert_false(cond.has("op"), "%s is nullary and must carry no op — got %s" % [t, cond])
		assert_false(cond.has("value"), "%s is nullary and must carry no value — got %s" % [t, cond])
