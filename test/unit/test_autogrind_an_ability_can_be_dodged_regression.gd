extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## A grinding party's PHYSICAL ABILITIES could never be dodged. power_strike, cleave and slash landed
## on an invisible target, on one that had stepped into shadow, and through an elven_cloak — all three
## of which stop an ordinary swing in this same file and in the real game.
##
## Live calls _target_dodges_physical from TWO sites — _execute_attack (:4391) and
## _execute_physical_ability (:4853) — gating the second on `ignores_evasion`. This resolver had the
## logic inline in _resolve_attack and the ability arm had no dodge at all.
##
## 🔑 FOUND BY @cowir-music's GENERALISATION, not by looking at this code: "was the first instance the
## only one". I had just wired an on-hit proc to the basic attack ONLY, correctly, and checking
## whether my other gear ports had the same one-site-vs-two question turned up evasion_bonus with two
## live call sites and one grind site. The near-miss was the finding.
##
## ⚠️ SCOPE: mirrors the three components the grind already modelled — invisible, shadow_step,
## equipment evasion_bonus. Live's version also rolls an `evasion` STATUS and a monster `phase_out`
## chance, and this file models NEITHER anywhere. Declared, not invented.

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(name: String, speed: int = 10) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 500,
		"attack": 40, "defense": 5, "magic": 40, "speed": speed})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


## ⚠️ MP IS RESTORED EVERY CAST, and that is a fixture fix rather than a convenience: _resolve_ability
## SPENDS mp and returns early when it cannot. The first version of this file drained a 500 MP caster
## in ~80 casts and then counted 238 of 300 MP failures as dodges — the speed-miss arm below caught
## it on the first run. A fixture that runs out mid-measurement reports the subject as working.
func _cast(caster: Combatant, ability_id: String, target: Combatant) -> void:
	caster.current_mp = caster.max_mp
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, ability_id, [target])


func test_an_invisible_target_is_not_hit_by_a_physical_ability() -> void:
	## Deterministic: invisible is a guaranteed dodge in both engines, and it is CONSUMED by the
	## attempt — so a second cast lands, which is what separates "dodged" from "immune".
	var caster := _fighter("Caster")
	var target := _fighter("Target")
	target.add_status("invisible", 3)
	var hp_before: int = target.current_hp
	_cast(caster, "power_strike", target)
	assert_eq(target.current_hp, hp_before,
		"a physical ability hit an INVISIBLE target — live gates this on _target_dodges_physical at :4853 and the grind's ability arm had no dodge at all")
	assert_false(target.has_status("invisible"),
		"the dodge must CONSUME invisible, as live consumes it — otherwise the target is permanently untouchable")
	_cast(caster, "power_strike", target)
	assert_lt(target.current_hp, hp_before,
		"the second cast must land once invisible is spent, or this is immunity rather than a dodge")


func test_a_shadow_stepped_target_is_not_hit_by_a_physical_ability() -> void:
	var caster := _fighter("Caster")
	var target := _fighter("Target")
	target.add_status("shadow_step", 3)
	var hp_before: int = target.current_hp
	_cast(caster, "power_strike", target)
	assert_eq(target.current_hp, hp_before,
		"a physical ability hit a target that had stepped into shadow")
	assert_false(target.has_status("shadow_step"), "shadow_step must be consumed by the attempt")


func test_an_elven_cloak_can_evade_a_physical_ability() -> void:
	## Statistical: 0.5 clamp on a 0.1 bonus means ~10% of casts are evaded. Over 400 casts that is
	## ~40 — a band no sampling can cross from zero.
	var caster := _fighter("Caster")
	var evaded: int = 0
	for i in 400:
		var target := _fighter("Target")
		target.equipped_accessory = "elven_cloak"
		var hp_before: int = target.current_hp
		_cast(caster, "power_strike", target)
		if target.current_hp == hp_before:
			evaded += 1
	gut.p("    elven_cloak evaded %d/400 physical ability casts (expect ~40)" % evaded)
	assert_gt(evaded, 10,
		"an elven_cloak never evaded a physical ability — equipment evasion_bonus reaches the basic attack and not the ability path")


func test_the_basic_attack_still_dodges_exactly_as_it_did() -> void:
	## ⛔ THE REFACTOR ARM. The dodge was EXTRACTED out of _resolve_attack to be shared; an extraction
	## that dropped a component would leave the ability path correct and silently weaken the basic
	## attack, which every other arm here would miss.
	var caster := _fighter("Caster")
	var invisible_target := _fighter("Invisible")
	invisible_target.add_status("invisible", 3)
	assert_eq(_res._resolve_attack(caster, invisible_target), 0,
		"the basic attack no longer misses an invisible target — the extraction dropped a component")
	var shadow_target := _fighter("Shadow")
	shadow_target.add_status("shadow_step", 3)
	assert_eq(_res._resolve_attack(caster, shadow_target), 0,
		"the basic attack no longer misses a shadow-stepped target")
	var cloaked := _fighter("Cloaked")
	cloaked.equipped_accessory = "elven_cloak"
	var dodged: int = 0
	for i in 600:
		if _res._resolve_attack(caster, cloaked) == 0:
			dodged += 1
	gut.p("    basic attack vs elven_cloak: %d/600 missed or evaded" % dodged)
	assert_gt(dodged, 60, "the basic attack lost its equipment dodge in the extraction")


func test_the_speed_miss_did_not_leak_onto_the_ability_path() -> void:
	## ⚠️ THE OTHER DIRECTION, and live is explicit about it: an ability is DODGED, never fumbled.
	## _target_dodges_physical holds no speed term in either engine. A slow caster's ability must land
	## on an unprotected target every time, or the extraction pulled the miss roll in with it.
	var slow := _fighter("Slow", 1)
	var fast := _fighter("Fast", 40)
	var misses: int = 0
	for i in 300:
		var hp_before: int = fast.current_hp
		_cast(slow, "power_strike", fast)
		if fast.current_hp == hp_before:
			misses += 1
	gut.p("    slow caster vs fast unprotected target: %d/300 ability casts failed (must be 0)" % misses)
	assert_eq(misses, 0,
		"a physical ability missed an unprotected target — the speed-based miss chance leaked into the shared dodge, making abilities harder to land in the grind than in the game")


func test_the_dodge_has_the_two_call_sites_live_has() -> void:
	## Structural, and it is the shape the whole finding is about: one site is what the bug WAS.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 10000, "CONTROL: the resolver was actually read")
	var calls: int = code.count("_target_dodges_physical(") - 1   ## minus its own declaration
	gut.p("    _target_dodges_physical call sites: %d (live has 2)" % calls)
	assert_eq(calls, 2,
		"the physical dodge is no longer reached from exactly two sites — live calls it from _execute_attack AND _execute_physical_ability, and one site is the defect this file was written for")
	assert_true(code.contains('ability.get("ignores_evasion", false)'),
		"the ability-side dodge is no longer gated on ignores_evasion the way live gates it at :4852")
