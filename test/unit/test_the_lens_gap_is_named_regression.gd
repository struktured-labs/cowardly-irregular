extends GutTest

## data/lenses.json sat outside EVERY grind parity registry. They census abilities.json (70 keys)
## and equipment.json; lenses are a third data file, so a whole equippable subsystem fell between
## three thorough guards. A registry cannot report a file it never opens — this one opens it.
##
## ⛔ AND "THE GRIND MODELS NO LENS EFFECTS" WAS WRONG, WHICH IS WHY THE TABLE BELOW HAS THREE
## STATUSES AND NOT TWO. Two of the six are implemented in Combatant — a class BOTH engines route
## through — so the grind inherits them free. Measured rather than assumed: the resolver calls
## take_damage 14x and add_debuff 14x, and both arms are gated on is_inside_tree(), which holds
## because GameLoop parents every party member (_create_party_from_customizations:2723 and
## _restore_party_from_save_data:2896). An effect hosted in the SHARED class is not a parity gap;
## only a BattleManager-hosted one is.
##
## The set may SHRINK freely — that is someone closing a gap. It may not GROW without the new key
## being named here, which is the whole point of censusing the file.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const COMBATANT := "res://src/battle/Combatant.gd"

## Ported into HeadlessBattleResolver itself.
const IMPLEMENTED_IN_THE_GRIND := {
	"lens_execute_bonus": "_apply_lens_execute_bonus, all three damage paths",
	"lens_execute_threshold": "same helper — reads target HP before the hit",
}

## Implemented in Combatant, which both engines call. NOT a gap; the grind gets these free.
const INHERITED_VIA_COMBATANT := {
	"lens_lethal_floor": "Combatant.take_damage — resolver calls it 14x",
	"lens_debuff_resist": "Combatant.add_debuff — resolver calls it 14x",
}

## Assessed and deliberately NOT ported, with the reason. You cannot silence an entry here, only
## explain it — and the explanation is what a later reader needs in order to retire it.
const DECLARED_GAPS := {
	"lens_ap_echo": "BattleManager-hosted: _rearm_lens_ap_echo per round + a refund in _execute_next_action. The grind runs its own AP model with no round-boundary rearm seam, so this is a port of the mechanism, not of a number",
	"lens_mp_tithe": "BattleManager._apply_lens_mp_tithe, a refund AFTER the spend. The grind's MP spend is a different site; porting it is cheap but unmeasured, and an unmeasured MP refund changes how long a grind sustains casting",
}


func before_each() -> void:
	if AutogrindSystem:
		AutogrindSystem._test_disable_persistence = true


## Full-line comments removed before any `contains` below. These pins assert against a WHOLE FILE,
## and this lane writes dense ## blocks about exactly these keys — @cowir-battle's sub-variant: a
## sliced pin can only be satisfied from inside its subject, a whole-file pin from anywhere in it.
## Only lines whose first non-space character is `#` are dropped, so no code can be cut; a trailing
## comment survives, which is the direction that fails toward a false GREEN and is recorded here
## rather than silently over-stripped ([[an_over_deleting_stripper_blinds_an_offender_scan]]).
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in GdSource.code_of(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			out.append(line)
	return "\n".join(out)


func _authored_keys() -> Array:
	var f := FileAccess.open("res://data/lenses.json", FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return []
	var out: Array = []
	for _id in parsed.get("lenses", {}):
		for k in (parsed["lenses"][_id].get("meta_effects", {}) as Dictionary):
			if not out.has(k):
				out.append(str(k))
	out.sort()
	return out


func test_every_authored_lens_effect_has_a_status() -> void:
	var keys: Array = _authored_keys()
	assert_gt(keys.size(), 3, "CONTROL: lenses.json must still author meta_effects, or this censuses nothing")
	var unnamed: Array = []
	for k in keys:
		if not (IMPLEMENTED_IN_THE_GRIND.has(k) or INHERITED_VIA_COMBATANT.has(k) or DECLARED_GAPS.has(k)):
			unnamed.append(k)
	gut.p("    %d authored · %d ported · %d inherited · %d declared gaps"
		% [keys.size(), IMPLEMENTED_IN_THE_GRIND.size(), INHERITED_VIA_COMBATANT.size(), DECLARED_GAPS.size()])
	assert_eq(unnamed, [],
		"a lens meta_effect exists that nothing in this file classifies: %s — say whether the grind ports it, inherits it, or declines it" % str(unnamed))


func test_no_status_names_a_key_that_no_lens_authors() -> void:
	var keys: Array = _authored_keys()
	if keys.is_empty():
		pass_test("lenses.json unavailable")
		return
	var stale: Array = []
	for d in [IMPLEMENTED_IN_THE_GRIND, INHERITED_VIA_COMBATANT, DECLARED_GAPS]:
		for k in d:
			if not keys.has(k):
				stale.append(k)
	assert_eq(stale, [], "this file classifies keys no lens authors any more: %s" % str(stale))


## ⛔ PINS THE CHAIN, NOT AN ADDRESS. The obvious form — "the resolver must contain the literal
## lens_execute_bonus" — certifies LOCATION, and an EXTRACTION is a correct change that moves the
## address without weakening anything. @cowir-battle red the .464 gate with exactly that shape an
## hour ago, and the reconciliation I have already announced (the grind delegating to live's
## lens_execute_multiplier) would have red THIS file next, by my own hand. So: the key is ported if
## the resolver reads it directly OR routes to the shared helper that reads it.
func test_the_ported_keys_are_reachable_from_the_resolver() -> void:
	var code: String = _code_only(RESOLVER)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	## ⛔ QUOTED, because the unquoted form is satisfied by the FUNCTION'S OWN NAME: the resolver
	## declares _apply_lens_execute_bonus, so a bare contains("lens_execute_bonus") stays true with
	## the body gutted to `return damage` — a clause that cannot fail, keyed to its own subject.
	## Measured: gutting the helper left that key at 5 occurrences and lens_execute_threshold at 0,
	## so one arm was load-bearing and its twin could never have spoken. A real read is `me.get("k")`.
	var delegates: bool = code.contains("lens_execute_multiplier")
	for k in IMPLEMENTED_IN_THE_GRIND:
		assert_true(code.contains('"%s"' % k) or delegates,
			"%s is listed as ported and the resolver neither reads it nor delegates to live's shared helper" % k)
	## And the port must still REACH the engine, whichever form it takes — a helper nobody calls is
	## the dead-feature shape this lane's ledger exists to catch.
	assert_true(code.contains("_apply_lens_execute_bonus(caster") and code.contains("_apply_lens_execute_bonus(attacker"),
		"the execute bonus is defined but no longer applied on both the ability and attack paths")


func test_the_inherited_keys_are_in_the_class_both_engines_share() -> void:
	var code: String = _code_only(COMBATANT)
	assert_gt(code.length(), 5000, "CONTROL: Combatant was actually read")
	## QUOTED for the same reason as the ported arm, and this one was measured failing: renaming
	## lens_lethal_floor -> lens_lethal_floor_MOVED left `contains(k)` TRUE, because the longer name
	## contains the shorter. Only the behavioural warden arm caught that mutation. I fixed the twin
	## of this line an hour ago and left this one — the sibling-shape blindness, on my own repair.
	for k in INHERITED_VIA_COMBATANT:
		assert_true(code.contains('"%s"' % k),
			"%s is listed as inherited via Combatant and is not there — it may have moved to BattleManager, which would make it a real grind gap" % k)


## The inheritance claim, behaviourally. A source pin above says WHERE it lives; this says it FIRES
## through the grind's own damage call, which is the thing the classification actually rests on.
func test_a_warden_survives_a_killing_blow_inside_the_grind() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var ls: Node = get_node_or_null("/root/LensSystem")
	if gs == null or ls == null:
		pass_test("GameState/LensSystem autoload unavailable")
		return
	var keep: Dictionary = (gs.lens_assignments as Dictionary).duplicate()
	var res = ResolverScript.new()
	var holder := Combatant.new()
	holder.initialize({"name": "Warden Holder", "max_hp": 500, "max_mp": 10,
		"attack": 10, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(holder)   # production parents every party member; the arm is gated on that
	var attacker := Combatant.new()
	attacker.initialize({"name": "Thug", "max_hp": 500, "max_mp": 10,
		"attack": 900, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(attacker)
	gs.lens_assignments["warden_holder"] = "warden"
	var me: Dictionary = ls.get_lens_meta_effects("warden_holder")
	if not bool(me.get("lens_lethal_floor", false)):
		gs.lens_assignments = keep
		pass_test("warden authors no lethal floor")
		return
	holder.current_hp = 40
	res._resolve_attack(attacker, holder)
	gut.p("    warden after a %d-attack killing blow: hp %d" % [attacker.attack, holder.current_hp])
	assert_eq(holder.current_hp, 1,
		"the Warden's lethal floor did not fire through the grind's own damage call — the inherited classification is wrong and it is a real gap")
	gs.lens_assignments = keep
