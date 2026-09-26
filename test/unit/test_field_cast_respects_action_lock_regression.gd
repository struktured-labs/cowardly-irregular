extends GutTest

## A stunned, asleep, or held caster can still spend MP between fights.
##
## Those statuses stay on the party after the battle that applied them, until
## the next battle starts — the same gap Silence already occupies. Battle skips
## the turn (stun, then cannot_act, then sleep). Member Casts run in that gap
## and only refused Silence, so the rule still matched, the MP still left, and
## the heal still landed. The refusal must not spend the action clock: the next
## fight is what honors it.

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
	assert_false(matched.is_empty(), "the rule still matches — a lock is not a condition, it blocks the cast")
	_system.apply_autogrind_actions(matched.get("actions", []))


func _assert_locked(status: String, needle: String) -> void:
	_party[1].current_hp = 200
	_party[0].add_status(status, 2)
	var mp_before: int = _party[0].current_mp
	var clock_before: int = int(_party[0].status_durations.get(status, 0))
	_cast_cure()
	assert_eq(_party[1].current_hp, 200, "%s must stop the heal — the mage was hurt, so a cast would have shown" % status)
	assert_eq(_party[0].current_mp, mp_before, "%s must not spend the MP" % status)
	assert_true(_party[0].has_status(status), "refusing the cast must leave %s on for the next fight" % status)
	assert_eq(int(_party[0].status_durations.get(status, 0)), clock_before, "the gap must not spend the %s clock" % status)
	var info: Dictionary = _system._member_ability_apply(_party[0], "cure", "mage")
	assert_false(bool(info.get("ok", true)), "the direct cast must refuse while %s" % status)
	assert_true(str(info.get("reason", "")).to_lower().contains(needle),
		"the refusal must name %s, got '%s'" % [status, str(info.get("reason", ""))])
	assert_eq(_party[0].current_mp, mp_before, "the direct cast must not spend MP either")


func test_a_stunned_cleric_does_not_cast_cure_between_fights() -> void:
	_assert_locked("stun", "stun")


func test_an_asleep_cleric_does_not_cast_cure_between_fights() -> void:
	_assert_locked("sleep", "asleep")


func test_a_held_cleric_does_not_cast_cure_between_fights() -> void:
	_assert_locked("cannot_act", "cannot act")


func test_the_same_cure_lands_when_the_cleric_can_act() -> void:
	## Without this, a change that refuses every between-battle cast would pass the arms above.
	_party[1].current_hp = 200
	var mp_before: int = _party[0].current_mp
	_cast_cure()
	assert_gt(_party[1].current_hp, 200, "a cleric who can act must still heal the hurt mage")
	assert_lt(_party[0].current_mp, mp_before, "and must still pay the MP")


func test_stun_blocks_a_free_mp_restore_too() -> void:
	## Channel costs 0. A guard that only wraps a paid Cure would miss it.
	_party[0].current_mp = 10
	_party[0].add_status("stun", 2)
	var info: Dictionary = _system._member_ability_apply(_party[0], "channel", "")
	assert_false(bool(info.get("ok", true)), "Channel is still an action — stun blocks it")
	assert_eq(_party[0].current_mp, 10, "the free restore must not land while stunned")
	assert_true(_party[0].has_status("stun"), "the free restore must not spend the stun either")
