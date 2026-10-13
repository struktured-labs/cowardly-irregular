extends GutTest

## 110 authored low_hp voice lines were effectively unreachable. Both damage handlers tested `big`
## FIRST and returned, so a blow taking a PC from healthy to critical spoke big_hit_taken instead —
## and low_hp is a one-shot EDGE (pre >= 25% and post < 25%) while big_hit_taken repeats, so the
## non-repeatable beat was the one destroyed. cowir-music measured ZERO low_hp in a 14,385-line
## session. Arithmetic: crossing costs at least (pre - 25) and anything over 30% of max is big, so
## low_hp was reachable only from pre in [25, 55] and never on a crit — the dramatic case, healthy
## to critical in one hit, was exactly the one that could never speak.
## Ruling (struktured via cowir-main, 2026-10-13): when one hit is both, low_hp wins.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _pc(nm: String, hp_pct: float) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = nm
	c.max_hp = 100
	c.current_hp = int(hp_pct)
	_bm.player_party.append(c)
	return c


func _fired(c: Combatant) -> String:
	return str(_bm._party_line_last_kind.get(str(c.combatant_name), ""))


# ── attack damage handler ────────────────────────────────────────────────

func test_a_big_hit_that_crosses_to_critical_speaks_low_hp() -> void:
	## The dramatic case: 90% -> 15% in one blow. Big AND crossing.
	var c := _pc("Mage", 15)
	_bm._on_damage_dealt_for_party_dialogue(c, 75, false, "", 1.0)
	assert_eq(_fired(c), "low_hp",
		"a blow from healthy to critical must speak the low-HP line, not big_hit_taken — " +
		"low_hp is a one-shot edge and big_hit_taken repeats")


func test_a_big_hit_that_does_not_cross_still_speaks_big_hit() -> void:
	## Unchanged behaviour: 100% -> 60%, big but nowhere near the edge.
	var c := _pc("Fighter", 60)
	_bm._on_damage_dealt_for_party_dialogue(c, 40, false, "", 1.0)
	assert_eq(_fired(c), "big_hit_taken", "a big hit well above the edge is still a big hit")


func test_a_small_hit_that_crosses_speaks_low_hp() -> void:
	## Unchanged behaviour: 30% -> 24%, crossing but not big.
	var c := _pc("Rogue", 24)
	_bm._on_damage_dealt_for_party_dialogue(c, 6, false, "", 1.0)
	assert_eq(_fired(c), "low_hp", "a small crossing hit still speaks low_hp")


func test_a_crit_that_crosses_speaks_low_hp() -> void:
	## is_crit alone makes a hit big, so before the fix NO crit could ever speak low_hp.
	var c := _pc("Bard", 20)
	_bm._on_damage_dealt_for_party_dialogue(c, 10, true, "", 1.0)
	assert_eq(_fired(c), "low_hp", "a crit that crosses the edge must still speak low_hp")


# ── status-tick (DoT) handler ───────────────────────────────────────────

func test_a_big_dot_tick_that_crosses_speaks_low_hp() -> void:
	var c := _pc("Cleric", 15)
	_bm._on_status_tick_damage_for_party_dialogue(75, "poison", c)
	assert_eq(_fired(c), "low_hp", "the DoT handler must agree with the attack handler")


func test_a_big_dot_tick_that_does_not_cross_still_speaks_big_hit() -> void:
	var c := _pc("Guardian", 60)
	_bm._on_status_tick_damage_for_party_dialogue(40, "burn", c)
	assert_eq(_fired(c), "big_hit_taken", "and must leave the non-crossing case alone")


# ── the edge re-arms ────────────────────────────────────────────────────

func test_the_edge_rearms_after_a_heal_back_over_the_threshold() -> void:
	## Nothing latches low_hp: the edge is computed from pre/post each hit, so healing back above
	## the threshold re-arms it. Proven rather than asserted, because the ruling asked for it.
	var c := _pc("Mage", 15)
	_bm._on_damage_dealt_for_party_dialogue(c, 75, false, "", 1.0)
	assert_eq(_fired(c), "low_hp", "CONTROL: it fired the first time")

	c.current_hp = 90
	_bm._party_line_last_kind.erase(str(c.combatant_name))
	_bm._party_line_cooldowns.erase(str(c.combatant_name))
	c.current_hp = 15
	_bm._on_damage_dealt_for_party_dialogue(c, 75, false, "", 1.0)
	assert_eq(_fired(c), "low_hp", "healed back over the threshold, the edge must speak again")


func test_already_below_the_threshold_does_not_refire_low_hp() -> void:
	## The guard the crossing test exists for: at 20% a further small hit is neither big nor a
	## crossing, so nothing should speak. Without this, "low_hp wins" could become "low_hp always".
	var c := _pc("Rogue", 18)
	_bm._on_damage_dealt_for_party_dialogue(c, 2, false, "", 1.0)
	assert_eq(_fired(c), "", "already critical and not a big hit — no line is the correct answer")
