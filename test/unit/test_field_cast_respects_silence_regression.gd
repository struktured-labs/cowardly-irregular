extends GutTest

## A silenced caster can still spend MP between fights.
##
## Silence stays on the party after the battle that applied it, until the next
## battle starts. The pause menu shows it. Member Casts, set from that same
## menu, is the cast that runs in the gap. Battle refuses the spell
## (JobSystem.can_use_ability). This path did not: the rule matched, the MP
## left, and the heal landed.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", 40], ["mage", 40]]:
		var c := Combatant.new()
		c.initialize({
			"name": str(spec[0]).capitalize(), "max_hp": 1000, "max_mp": int(spec[1]),
			"attack": 10, "defense": 10, "magic": 20, "speed": 10
		})
		c.job = {"id": str(spec[0])}
		add_child_autofree(c)
		_party.append(c)
	_party[0].learned_abilities.append("cure")
	_party[0].learned_abilities.append("channel")
	_system.grind_party = _party


func _cast_cure() -> void:
	_system.set_autogrind_rules([{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "member_ability", "member": "cleric", "ability": "cure", "target": "mage"}],
		"enabled": true
	}])
	var matched: Dictionary = _system.evaluate_autogrind_rules(_party)
	assert_false(matched.is_empty(), "the rule still matches — silence is not a condition, it blocks the cast")
	_system.apply_autogrind_actions(matched.get("actions", []))


func test_a_silenced_cleric_does_not_cast_cure_between_fights() -> void:
	_party[1].current_hp = 200
	_party[0].add_status("silence")
	var mp_before: int = _party[0].current_mp
	_cast_cure()
	assert_eq(_party[1].current_hp, 200, "Silence must stop the heal — the mage was hurt, so a cast would have shown")
	assert_eq(_party[0].current_mp, mp_before, "and the MP must stay — a blocked cast is not a paid one")
	var info: Dictionary = _system._member_ability_apply(_party[0], "cure", "mage")
	assert_false(bool(info.get("ok", true)), "the direct cast must refuse too")
	assert_true(str(info.get("reason", "")).to_lower().contains("silenc"),
		"the refusal must name silence, got '%s'" % str(info.get("reason", "")))


func test_the_same_cure_lands_when_the_cleric_is_not_silenced() -> void:
	## Without this, a change that refuses every between-battle cast would pass the arm above.
	_party[1].current_hp = 200
	var mp_before: int = _party[0].current_mp
	_cast_cure()
	assert_gt(_party[1].current_hp, 200, "an unsilenced cleric must still heal the hurt mage")
	assert_lt(_party[0].current_mp, mp_before, "and must still pay the MP")


func test_silence_blocks_a_free_mp_restore_too() -> void:
	## Channel costs 0 and is not type "healing". A guard that only wraps Cure would miss it.
	_party[0].current_mp = 10
	_party[0].add_status("silence")
	var info: Dictionary = _system._member_ability_apply(_party[0], "channel", "")
	assert_false(bool(info.get("ok", true)), "Channel is still an ability — silence blocks it")
	assert_eq(_party[0].current_mp, 10, "the free restore must not land while silenced")
