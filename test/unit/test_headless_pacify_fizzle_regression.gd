extends GutTest

## peace_sign applies "pacify". Live refuses a basic attack, a physical ability and a magic
## ability, spends the MP those abilities already committed, and still lets a heal through.
## The grind applied the status and then ignored it, so a pacified fighter kept swinging.
## The status was on the grind-ignores census for that reason.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _make(cname: String, hp: int = 400) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": hp,
		"max_mp": 40,
		"attack": 30,
		"defense": 5,
		"magic": 20,
		"speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


func _ability(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func test_a_pacified_basic_attack_deals_nothing_and_keeps_the_status() -> void:
	var attacker := _make("Dove")
	var target := _make("Target")
	attacker.add_status("pacify", 2)
	var hp_before: int = target.current_hp
	for _i in 12:
		assert_eq(_res._resolve_attack(attacker, target), 0, "a pacified swing must fizzle")
	assert_eq(target.current_hp, hp_before, "twelve pacified swings must not chip the target")
	assert_true(attacker.has_status("pacify"), "fizzling must not consume pacify — duration ticks it off")


func test_an_unpacified_swing_still_lands() -> void:
	## Without this the arm above passes on a resolver that deals no damage at all.
	var attacker := _make("Fighter")
	var target := _make("Target")
	var hp_before: int = target.current_hp
	for _i in 12:
		_res._resolve_attack(attacker, target)
	assert_lt(target.current_hp, hp_before, "CONTROL: twelve ordinary swings must land — all missing is ~1e-12")


func test_pacify_fizzles_physical_and_magic_after_spending_mp() -> void:
	var strike: Dictionary = _ability("power_strike")
	var spell: Dictionary = _ability("fire")
	if strike.is_empty() or spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	caster.add_status("pacify", 2)
	_res._player_party = [caster]
	_res._enemy_party = [target]
	var mp_before: int = caster.current_mp
	var hp_before: int = target.current_hp
	_res._resolve_ability(caster, "power_strike", [target])
	assert_eq(target.current_hp, hp_before, "a pacified power_strike must not land")
	assert_eq(caster.current_mp, mp_before - int(strike.get("mp_cost", 0)),
		"live spends the MP and then fizzles the strike")
	mp_before = caster.current_mp
	_res._resolve_ability(caster, "fire", [target])
	assert_eq(target.current_hp, hp_before, "a pacified fire must fizzle")
	assert_eq(caster.current_mp, mp_before - int(spell.get("mp_cost", 0)),
		"live spends the MP and then fizzles the spell")
	assert_true(caster.has_status("pacify"), "neither fizzle consumes pacify")


func test_the_unpacified_casts_actually_land() -> void:
	var strike: Dictionary = _ability("power_strike")
	var spell: Dictionary = _ability("fire")
	if strike.is_empty() or spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Caster")
	var target := _make("Target")
	_res._player_party = [caster]
	_res._enemy_party = [target]
	var hp_before: int = target.current_hp
	_res._resolve_ability(caster, "power_strike", [target])
	assert_lt(target.current_hp, hp_before, "CONTROL: power_strike must land when not pacified")
	hp_before = target.current_hp
	_res._resolve_ability(caster, "fire", [target])
	assert_lt(target.current_hp, hp_before, "CONTROL: fire must land when not pacified")


func test_a_pacified_heal_still_lands() -> void:
	## Live gates attack, physical and magic only. A pacified cleric can still cure.
	var cure: Dictionary = _ability("cure")
	if cure.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _make("Cleric")
	var ally := _make("Ally", 200)
	ally.current_hp = 40
	caster.add_status("pacify", 2)
	_res._player_party = [caster, ally]
	_res._enemy_party = []
	_res._resolve_ability(caster, "cure", [ally])
	assert_gt(ally.current_hp, 40, "pacify must not silence a heal")
	assert_true(caster.has_status("pacify"), "healing must not clear pacify")


func test_both_engines_read_pacify_the_same_number_of_times() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("has_status\\(\"pacify\"\\)"), OK)
	var live := FileAccess.get_file_as_string(LIVE)
	var head := FileAccess.get_file_as_string(RESOLVER)
	assert_gt(live.length(), 1000, "CONTROL: live battle source was read")
	assert_gt(head.length(), 1000, "CONTROL: headless resolver source was read")
	assert_eq(re.search_all(head).size(), re.search_all(live).size(),
		"the grind and live disagree on how many pacify gates they have")
	assert_eq(re.search_all(live).size(), 3, "live gates attack, physical and magic — a fourth site is a new rule")
