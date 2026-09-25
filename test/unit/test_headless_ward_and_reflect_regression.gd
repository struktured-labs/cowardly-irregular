extends GutTest

## Five statuses an ability can inflict and the grind used to ignore.
##
## barrier (guardian_wall) nullifies one hit — basic attack, physical ability, or spell — then
## breaks. magic_block (access_denied) cancels one spell and breaks; a swing is not a spell.
## reflect (magic_reflect, reflect_shield) and physical_reflect (port_block) bounce a physical
## hit onto the attacker and stay up until the duration ticks. prismatic_reflect bounces a spell
## onto the caster and stays up.
##
## Live's tooltips disagree with two of those rules. magic_reflect says it reflects spells;
## BattleManager bounces `reflect` on physical hits only, and future_sight's own comment calls
## that the physical counter. prismatic_reflect says "a random target, friend or foe"; live
## sends the spell back to the caster. This file pins the code, not the tooltip.
##
## Group attacks, formations and combo magic are not warded on either engine. The check stays
## out of Combatant.take_damage so a grind Limit Break does not start bouncing.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 50000,
		"max_mp": 80,
		"attack": 80,
		"defense": 0,
		"magic": 40,
		"speed": 40,
	})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _ability(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func _ready_parties(caster, target) -> void:
	_res._player_party = [caster]
	_res._enemy_party = [target]


func test_barrier_nullifies_one_basic_attack_then_breaks() -> void:
	var attacker := _make("Striker")
	var warded := _make("Warded")
	var plain := _make("Plain")
	var spent := false
	for s in range(1, 40):
		warded.current_hp = warded.max_hp
		plain.current_hp = plain.max_hp
		warded.add_status("barrier", 2)
		seed(s)
		var open: int = _res._resolve_attack(attacker, plain)
		seed(s)
		var blocked: int = _res._resolve_attack(attacker, warded)
		if open <= 0:
			assert_eq(blocked, 0)
			assert_true(warded.has_status("barrier"), "a miss must not spend the ward — seed %d" % s)
			continue
		assert_eq(blocked, 0, "the swing that would have landed must be nullified")
		assert_eq(warded.current_hp, warded.max_hp)
		assert_false(warded.has_status("barrier"), "one hit spends barrier")
		spent = true
		var follow := false
		for t in range(1, 40):
			seed(t)
			if _res._resolve_attack(attacker, warded) > 0:
				follow = true
				break
		assert_true(follow, "CONTROL: after the ward breaks, a later swing must be able to land")
		break
	assert_true(spent, "CONTROL: 39 seeds at a 10% miss rate must include a hit")


func test_barrier_nullifies_one_physical_ability_and_one_spell() -> void:
	var strike: Dictionary = _ability("power_strike")
	var spell: Dictionary = _ability("fire")
	if strike.is_empty() or spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	_ready_parties(caster, target)
	target.add_status("barrier", 2)
	_res._resolve_ability(caster, "power_strike", [target])
	assert_eq(target.current_hp, target.max_hp, "barrier must eat the physical ability")
	assert_false(target.has_status("barrier"), "the physical hit spends the ward")
	target.add_status("barrier", 2)
	var caster_hp: int = caster.current_hp
	_res._resolve_ability(caster, "fire", [target])
	assert_eq(target.current_hp, target.max_hp, "barrier must eat the spell")
	assert_eq(caster.current_hp, caster_hp, "a nullified spell must not hurt the caster")
	assert_false(target.has_status("barrier"))
	_res._resolve_ability(caster, "fire", [target])
	assert_lt(target.current_hp, target.max_hp, "CONTROL: the next spell, with the ward gone, must land")


func test_magic_block_cancels_one_spell_and_not_a_swing() -> void:
	var strike: Dictionary = _ability("power_strike")
	var spell: Dictionary = _ability("fire")
	if strike.is_empty() or spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	_ready_parties(caster, target)
	target.add_status("magic_block", 1)
	_res._resolve_ability(caster, "power_strike", [target])
	assert_lt(target.current_hp, target.max_hp, "magic_block must not stop a physical ability")
	assert_true(target.has_status("magic_block"), "a swing must not spend magic_block")
	target.current_hp = target.max_hp
	_res._resolve_ability(caster, "fire", [target])
	assert_eq(target.current_hp, target.max_hp, "the first spell must be cancelled")
	assert_false(target.has_status("magic_block"), "one spell spends magic_block")
	_res._resolve_ability(caster, "fire", [target])
	assert_lt(target.current_hp, target.max_hp, "CONTROL: the spell after the block must land")


func test_magic_block_is_checked_before_barrier() -> void:
	## Live cancels the spell and leaves the ward. Spending both on one cast would be a new rule.
	var spell: Dictionary = _ability("fire")
	if spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	_ready_parties(caster, target)
	target.add_status("magic_block", 1)
	target.add_status("barrier", 2)
	_res._resolve_ability(caster, "fire", [target])
	assert_eq(target.current_hp, target.max_hp)
	assert_false(target.has_status("magic_block"))
	assert_true(target.has_status("barrier"), "the ward stays, because the spell never reached it")


func test_a_heal_ignores_magic_block() -> void:
	var cure: Dictionary = _ability("cure")
	if cure.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Cleric")
	var ally := _make("Ally")
	ally.current_hp = 40
	ally.add_status("magic_block", 1)
	_res._player_party = [caster, ally]
	_res._enemy_party = []
	_res._resolve_ability(caster, "cure", [ally])
	assert_gt(ally.current_hp, 40, "magic_block is a spell cancel, not a heal cancel")
	assert_true(ally.has_status("magic_block"))


func test_reflect_and_physical_reflect_bounce_physical_hits_and_stay() -> void:
	var strike: Dictionary = _ability("power_strike")
	if strike.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	for status_name in ["reflect", "physical_reflect"]:
		var attacker := _make("Striker")
		var warded := _make("Warded")
		var plain := _make("Plain")
		_ready_parties(attacker, warded)
		warded.add_status(status_name, 2)
		var found := false
		for s in range(1, 40):
			attacker.current_hp = attacker.max_hp
			warded.current_hp = warded.max_hp
			plain.current_hp = plain.max_hp
			seed(s)
			var open: int = _res._resolve_attack(attacker, plain)
			seed(s)
			var bounced: int = _res._resolve_attack(attacker, warded)
			if open <= 0:
				assert_eq(bounced, 0)
				assert_eq(attacker.current_hp, attacker.max_hp, "a miss must not bounce")
				continue
			assert_eq(bounced, 0)
			assert_eq(warded.current_hp, warded.max_hp, "%s must keep the swing off the target" % status_name)
			assert_lt(attacker.current_hp, attacker.max_hp, "%s must put the swing on the attacker" % status_name)
			assert_true(warded.has_status(status_name), "%s is not spent by the bounce" % status_name)
			found = true
			break
		assert_true(found, "CONTROL: %s needs a swing that would have landed" % status_name)
		var before: int = attacker.current_hp
		_res._resolve_ability(attacker, "power_strike", [warded])
		assert_eq(warded.current_hp, warded.max_hp, "%s must bounce the physical ability too" % status_name)
		assert_lt(attacker.current_hp, before)
		assert_true(warded.has_status(status_name))


func test_reflect_does_not_bounce_a_spell() -> void:
	## magic_reflect's description says it reflects spells. Live bounces the status on steel only.
	var spell: Dictionary = _ability("fire")
	if spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	_ready_parties(caster, target)
	target.add_status("reflect", 2)
	var caster_hp: int = caster.current_hp
	_res._resolve_ability(caster, "fire", [target])
	assert_lt(target.current_hp, target.max_hp, "a spell must still hit a reflect target")
	assert_eq(caster.current_hp, caster_hp, "reflect must not bounce the spell onto the caster")
	assert_true(target.has_status("reflect"))


func test_prismatic_reflect_bounces_a_spell_onto_the_caster_and_stays() -> void:
	var spell: Dictionary = _ability("fire")
	var strike: Dictionary = _ability("power_strike")
	if spell.is_empty() or strike.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	_ready_parties(caster, target)
	target.add_status("prismatic_reflect", 2)
	_res._resolve_ability(caster, "power_strike", [target])
	assert_lt(target.current_hp, target.max_hp, "prismatic_reflect must not bounce a physical ability")
	assert_eq(caster.current_hp, caster.max_hp)
	assert_true(target.has_status("prismatic_reflect"))
	target.current_hp = target.max_hp
	_res._resolve_ability(caster, "fire", [target])
	assert_eq(target.current_hp, target.max_hp, "the spell must not land on the warded target")
	assert_lt(caster.current_hp, caster.max_hp, "the spell must land on the caster")
	assert_true(target.has_status("prismatic_reflect"), "the bounce does not spend prismatic_reflect")
	var mid: int = caster.current_hp
	_res._resolve_ability(caster, "fire", [target])
	assert_eq(target.current_hp, target.max_hp)
	assert_lt(caster.current_hp, mid, "a second spell bounces too — the status is still up")


func test_both_engines_gate_these_wards_at_the_same_sites() -> void:
	var expected := {
		"barrier": 3,
		"magic_block": 1,
		"reflect": 2,
		"physical_reflect": 2,
		"prismatic_reflect": 1,
	}
	var live := FileAccess.get_file_as_string(LIVE)
	var head := FileAccess.get_file_as_string(RESOLVER)
	assert_gt(live.length(), 1000, "CONTROL: live battle source was read")
	assert_gt(head.length(), 1000, "CONTROL: headless resolver source was read")
	for status_name in expected:
		var re := RegEx.new()
		assert_eq(re.compile("has_status\\(\"%s\"\\)" % status_name), OK)
		var live_n: int = re.search_all(live).size()
		var head_n: int = re.search_all(head).size()
		assert_eq(live_n, int(expected[status_name]),
			"live's %s gate count changed — the grind pin is about that number" % status_name)
		assert_eq(head_n, live_n,
			"the grind and live disagree on how many %s gates they have" % status_name)
