extends GutTest
## A grind that stops mid-session said LESS than the refusal to start one. Both read the same rules
## off the same party, and `_party_interrupt` computes the member for both — but the mid-session
## caller returned `str(party_stop["reason"])` and threw the name away, so after 40 battles the
## player got "HP threshold reached (20%)" with no way to tell WHICH of five characters to heal,
## while `_first_battle_refusal_text` had been naming them before the grind even began.
## The convention already exists in this file: the ability-validation reasons say "%s is down" and
## "%s lacks MP for %s". These two were the ones discarding a name they had already computed.
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _saved_rules: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_saved_rules = AutogrindSystem.interrupt_rules.duplicate(true)


func after_each() -> void:
	AutogrindSystem.interrupt_rules = _saved_rules
	AutogrindState.restore(_ag)


func _party(hurt_name: String, hp_pct: int, alive: bool = true) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for n in ["Rook", "Vesper", "Wren"]:
		var c := Combatant.new()
		autofree(c)
		c.initialize({"name": n, "max_hp": 100, "max_mp": 10})
		c.current_hp = (hp_pct if n == hurt_name else 100)
		c.is_alive = (alive if n == hurt_name else true)
		out.append(c)
	return out


func _stop_reason(party: Array[Combatant]) -> String:
	AutogrindSystem.grind_party = party
	return AutogrindSystem._check_interrupt_conditions()


func test_an_hp_stop_names_the_member_and_their_hp() -> void:
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	AutogrindSystem.interrupt_rules["party_death"] = false
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	var reason: String = _stop_reason(_party("Vesper", 14))
	assert_string_contains(reason, "HP threshold reached", "FLOOR: it must still say which rule stopped the grind")
	assert_string_contains(reason, "Vesper", "and WHICH of the party is below it -- otherwise you cannot tell who to heal")
	assert_string_contains(reason, "14%", "and how far below, so the number is actionable rather than a repeat of the rule")


func test_a_death_stop_names_the_member() -> void:
	AutogrindSystem.interrupt_rules["hp_threshold"] = 0.0
	AutogrindSystem.interrupt_rules["party_death"] = true
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	var reason: String = _stop_reason(_party("Wren", 0, false))
	assert_string_contains(reason, "Party member died", "FLOOR: the rule must still be named")
	assert_string_contains(reason, "Wren", "and the member who died -- 'Party member died' names nobody in a five-party grind")


## CONTROL: it must name the member who actually tripped the rule, not the first in the party.
func test_it_names_the_member_who_tripped_it_not_the_first() -> void:
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	AutogrindSystem.interrupt_rules["party_death"] = false
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	var reason: String = _stop_reason(_party("Wren", 9))
	assert_string_contains(reason, "Wren", "the third member tripped it, so the third must be named")
	assert_false(reason.contains("Rook"), "and the untouched first member must not be")


## CONTROL: a healthy party produces no stop at all, so the arms above cannot pass on a constant.
func test_a_healthy_party_is_not_stopped() -> void:
	AutogrindSystem.interrupt_rules["hp_threshold"] = 30.0
	AutogrindSystem.interrupt_rules["party_death"] = true
	AutogrindSystem.interrupt_rules["item_depleted"] = false
	assert_eq(_stop_reason(_party("Rook", 100)), "", "CONTROL: nothing is wrong, so nothing may be reported")
