extends GutTest

## on_battle_defeat gated permadeath on `permadeath_staking_enabled OR permadeath_enabled`.
## The alias had zero UI readers despite its "for UI binding" comment — every UI surface binds
## the canonical flag or a private copy.
## NOT a live divergence when removed: all three writes to the alias sat on the line after a
## write of the canonical flag with the same value, and load re-derived it from the canonical
## one, so the OR was provably equivalent to the canonical flag alone (enumerated on main,
## 2026-08-22). This removes the HAZARD, not a firing bug: an OR means either flag arms
## PERMANENT character death, so the day someone adds an unpaired write the divergence is
## silent and irreversible. Deleting the alias makes that unwritable rather than unlikely.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_system.is_grinding = true
	_system.permadeath_staking_enabled = false
	_system.permadead_characters.clear()
	_party.clear()
	for i in range(4):
		var c = Combatant.new()
		c.initialize({
			"name": "PdChar%d" % i,
			"max_hp": 100,
			"max_mp": 20,
			"attack": 10,
			"defense": 10,
			"magic": 5,
			"speed": 10
		})
		c.current_hp = 10 * (i + 1)
		add_child_autofree(c)
		_party.append(c)
	_system.grind_party = _party


func _alive_count() -> int:
	var n := 0
	for m in _party:
		if m.is_alive:
			n += 1
	return n


func test_staking_off_does_not_permakill_on_defeat() -> void:
	_system.permadeath_staking_enabled = false
	_system.on_battle_defeat()
	assert_eq(_alive_count(), 4, "Defeat with staking OFF must not permanently kill anyone")
	assert_eq(_system.permadead_characters.size(), 0, "No character may be recorded permadead")


func test_staking_on_does_permakill_on_defeat() -> void:
	_system.permadeath_staking_enabled = true
	_system.on_battle_defeat()
	assert_lt(_alive_count(), 4, "ARM+: staking ON must kill someone, else the OFF arm is vacuous")
	assert_gt(_system.permadead_characters.size(), 0, "ARM+: a victim must be recorded permadead")


func test_only_the_canonical_flag_arms_permadeath() -> void:
	## `in` must be proven to SEE a property before its absence means anything — a broken
	## operator returns false for every name and this whole test passes on nothing.
	assert_true("permadeath_staking_enabled" in _system,
		"control: `in` must find the canonical flag, else the assertion below is vacuous")
	assert_false("permadeath_enabled" in _system,
		"The redundant alias must not exist — an OR on it lets either flag arm permanent death")
