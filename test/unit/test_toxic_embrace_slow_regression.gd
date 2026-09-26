extends GutTest

## Toxic Embrace says it poisons and slows. The poison is the primary effect and lands from the
## physical executor. The slow is `secondary_effect: speed_down`, and that dispatcher used to run
## only from the support executor, so a landed embrace left the target at full speed.
## Toxic Sludge is in the industrial overworld pool and casts this. The grind models the same cast.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _bm_guard = null
var _res = null


func before_each() -> void:
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	_res = ResolverScript.new()


func after_each() -> void:
	if _bm_guard != null:
		_bm_guard.restore()


func _embrace() -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability("toxic_embrace")


func _combatant(who: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": who, "max_hp": 2000, "max_mp": 80,
		"attack": 30, "defense": 10, "magic": 10, "speed": 40})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	return c


func _speed_debuff(target: Combatant) -> Dictionary:
	for d in target.active_debuffs:
		if str(d.get("stat", "")) == "speed":
			return d
	return {}


func _assert_authored(ab: Dictionary) -> bool:
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return false
	assert_eq(str(ab.get("type", "")), "physical", "CONTROL: Toxic Embrace is a physical strike")
	assert_eq(str(ab.get("effect", "")), "poison", "CONTROL: the primary effect is still poison")
	assert_eq(str(ab.get("secondary_effect", "")), "speed_down",
		"CONTROL: the written slow is secondary_effect speed_down")
	assert_almost_eq(float(ab.get("secondary_modifier", 0.0)), 0.7, 0.001,
		"CONTROL: the authored slow is still 0.7x speed")
	return true


func test_a_landed_embrace_poisons_and_slows_in_a_live_battle() -> void:
	var ab: Dictionary = _embrace()
	if not _assert_authored(ab):
		return
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pass_test("BattleManager autoload unavailable")
		return
	var sludge := _combatant("Toxic Sludge")
	var hero := _combatant("Recruit")
	var speed_before: int = hero.get_buffed_stat("speed", hero.speed)
	bm._execute_physical_ability(sludge, ab, [hero])
	assert_true(hero.has_status("poison"),
		"CONTROL: the embrace still poisons — a miss would make the slow assert vacuous")
	var debuff: Dictionary = _speed_debuff(hero)
	assert_false(debuff.is_empty(),
		"Toxic Embrace poisoned %s but left their speed untouched — the written slow never landed" % hero.combatant_name)
	assert_almost_eq(float(debuff.get("modifier", 0.0)), float(ab.get("secondary_modifier", 0.0)), 0.001,
		"the slow must use the authored secondary_modifier, not a stand-in")
	assert_eq(int(debuff.get("duration", 0)), int(ab.get("duration", 0)),
		"the slow lasts the ability's authored duration")
	assert_lt(hero.get_buffed_stat("speed", hero.speed), speed_before,
		"the speed debuff must actually reduce speed")


func test_a_landed_embrace_poisons_and_slows_in_the_grind() -> void:
	var ab: Dictionary = _embrace()
	if not _assert_authored(ab):
		return
	var sludge := _combatant("Toxic Sludge")
	var hero := _combatant("Recruit")
	_res._player_party = [hero]
	_res._enemy_party = [sludge]
	var speed_before: int = hero.get_buffed_stat("speed", hero.speed)
	_res._resolve_ability(sludge, "toxic_embrace", [hero])
	assert_true(hero.has_status("poison"),
		"CONTROL: the grind still poisons on a landed embrace")
	var debuff: Dictionary = _speed_debuff(hero)
	assert_false(debuff.is_empty(),
		"the grind poisoned %s and did not slow them — autogrind fights an easier Toxic Sludge than the game" % hero.combatant_name)
	assert_almost_eq(float(debuff.get("modifier", 0.0)), float(ab.get("secondary_modifier", 0.0)), 0.001,
		"the grind's slow must use the authored secondary_modifier")
	assert_lt(hero.get_buffed_stat("speed", hero.speed), speed_before,
		"the grind's speed debuff must actually reduce speed")


func test_a_blocked_embrace_does_not_slow_in_a_live_battle() -> void:
	## A barrier eats the strike before poison. The slow is part of that same landing, not a
	## separate aura on the original target list.
	var ab: Dictionary = _embrace()
	if not _assert_authored(ab):
		return
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pass_test("BattleManager autoload unavailable")
		return
	var sludge := _combatant("Toxic Sludge")
	var hero := _combatant("Recruit")
	hero.add_status("barrier", 1)
	bm._execute_physical_ability(sludge, ab, [hero])
	assert_false(hero.has_status("barrier"), "CONTROL: the barrier must consume the strike")
	assert_false(hero.has_status("poison"), "a blocked embrace does not poison")
	assert_true(_speed_debuff(hero).is_empty(), "a blocked embrace does not slow")


func test_a_blocked_embrace_does_not_slow_in_the_grind() -> void:
	var ab: Dictionary = _embrace()
	if not _assert_authored(ab):
		return
	var sludge := _combatant("Toxic Sludge")
	var hero := _combatant("Recruit")
	hero.add_status("barrier", 1)
	_res._player_party = [hero]
	_res._enemy_party = [sludge]
	_res._resolve_ability(sludge, "toxic_embrace", [hero])
	assert_false(hero.has_status("barrier"), "CONTROL: the grind's barrier must consume the strike")
	assert_false(hero.has_status("poison"), "a blocked embrace does not poison in the grind")
	assert_true(_speed_debuff(hero).is_empty(), "a blocked embrace does not slow in the grind")
