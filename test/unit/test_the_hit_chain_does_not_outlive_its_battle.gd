extends GutTest

## SoundManager._combo_step ramps the hit pitch across a multi-hit action (+3% per hit, capped at
## +12%) and is reset in exactly ONE place: BattleScene._on_action_executed, i.e. when an ACTION
## completes. Nothing cleared it at the battle boundary, so any exit that skips that completion
## carries the ramp into the next battle and pitches its FIRST hit up by as much as two semitones.
## start_battle already clears six per-combatant fields for this reason, and says so:
## "edge cases (load-save mid-battle, flee, debug warps) can't leak +4 AP into the next encounter."
##
## ⚠️ LIMIT, stated rather than hidden: there is no behavioural arm through the real start_battle.
## It dies on "data.tree is null" in an isolated GUT run — test_battle_start_cleanup_regression
## documents the same wall and works around it identically. The boundary call is pinned at source;
## the ramp's own behaviour is driven for real below.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_the_ramp_actually_ramps_and_caps() -> void:
	# CONTROL for everything below: if the bias were flat, a leaked counter would be inaudible
	# and this whole file would be defending nothing.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var restore: int = sm._combo_step
	sm._combo_step = 0
	var flat: float = sm.get_combo_pitch_bias()
	sm._combo_step = 2
	var ramped: float = sm.get_combo_pitch_bias()
	sm._combo_step = 99
	var capped: float = sm.get_combo_pitch_bias()
	sm._combo_step = restore
	## Read through get(): a DIRECT `sm.COMBO_PITCH_CAP` aborts at runtime if the const is renamed,
	## and an abort after the asserts above scores PASSING — every cardinal clean but Asserts.
	var cap_v = sm.get("COMBO_PITCH_CAP")
	assert_ne(cap_v, null, "COMBO_PITCH_CAP is gone or renamed — the cap assert below cannot run")
	assert_almost_eq(flat, 1.0, 0.0001, "an unramped chain must be bit-identical to no ramp")
	assert_gt(ramped, flat, "the chain does not ramp — a leaked counter would be silent and harmless")
	assert_almost_eq(capped, 1.0 + float(cap_v if cap_v != null else 0.0), 0.0001, "the ramp does not cap where it says it does")


func test_resetting_the_chain_returns_it_to_flat() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._combo_step = 4
	assert_gt(sm.get_combo_pitch_bias(), 1.0, "CONTROL: the chain must be ramped before the reset means anything")
	sm.reset_hit_chain()
	assert_almost_eq(sm.get_combo_pitch_bias(), 1.0, 0.0001, "reset_hit_chain left the ramp standing")


func test_the_battle_boundary_clears_it() -> void:
	# THE fix. Bound to start_battle's body, not to the file: a reset somewhere else in
	# BattleManager is a different moment and would leave the boundary leaking.
	var code: String = GdSource.code_of(BATTLE_MANAGER)
	assert_ne(code, "", "CONTROL: BattleManager code must survive the comment strip")
	var start: int = code.find("func start_battle(")
	assert_gt(start, -1, "CONTROL: start_battle is gone — this arm no longer describes the boundary")
	var nxt: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, nxt - start) if nxt > start else code.substr(start)
	assert_true(body.contains("SoundManager.reset_hit_chain()"),
		"start_battle does not clear the hit chain — the previous battle's ramp pitches this one's first hit")
	assert_true(body.contains("current_ap = 0"),
		"CONTROL: start_battle's per-battle clearing block must still be here, or the arm above is vacuous")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## reset_hit_chain is reached ONCE, at :53, after the assert at :52 — rung 3, so renaming it
	## leaves this file GREEN while the .374 boundary fix stops being tested (measured 2026-09-17).
	## A SEPARATE arm on purpose: a precondition hoisted into an existing arm would make its first
	## call loud and every later call in that arm rung 3, changing cover instead of adding it.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it
	## here. The sibling floors in this lane carry the same disclaimer, for the same reason.
	## has_method ANSWERS; a direct read would abort alongside the arms this exists to catch.
	for method_name in ["get_combo_pitch_bias", "reset_hit_chain"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it, and whether that shows as Risky or as a silent pass is decided by arm ORDER, not by care" % method_name)
	## _combo_step is an int and never null once _ready has run, so get() is sound here.
	for member_name in ["_combo_step"]:
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort its arms SILENTLY" % member_name)
	## The cap is a CONST, not a property: the constant map answers about existence, get() about value.
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	assert_true(consts.has("COMBO_PITCH_CAP"),
		"SoundManager has no COMBO_PITCH_CAP — the cap assert at :44 would compare against a default")


func test_the_action_boundary_still_owns_the_per_action_reset() -> void:
	# Anti-overcorrection: the battle-level clear must not replace the per-ACTION one, or a
	# multi-hit ability would ramp across every action of the fight.
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	var start: int = code.find("func _on_action_executed(")
	assert_gt(start, -1, "CONTROL: _on_action_executed is gone")
	var nxt: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, nxt - start) if nxt > start else code.substr(start)
	assert_true(body.contains("SoundManager.reset_hit_chain()"),
		"the per-action reset is gone — chains would ramp across separate actions")
