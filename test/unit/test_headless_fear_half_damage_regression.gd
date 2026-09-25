extends GutTest

## howl (and the rest of the fear kit) applies "fear". Live skips some turns and, on a turn
## that still swings, halves the base stat of a basic attack and of a physical ability before
## the rest of the formula. Magic is not halved. The grind already had the skip/overcome roll
## and then dealt full damage on the swing that proceeded.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _make(cname: String, attack: int = 80) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 50000,
		"max_mp": 80,
		"attack": attack,
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


func test_a_feared_swing_still_lands_at_half() -> void:
	var plain_attacker := _make("Plain")
	var feared := _make("Feared")
	feared.add_status("fear", 3)
	var target_a := _make("A")
	var target_b := _make("B")
	var saw_hit := false
	for s in range(1, 40):
		target_a.current_hp = target_a.max_hp
		target_b.current_hp = target_b.max_hp
		seed(s)
		var full: int = _res._resolve_attack(plain_attacker, target_a)
		seed(s)
		var half: int = _res._resolve_attack(feared, target_b)
		if full <= 1:
			continue
		saw_hit = true
		assert_gt(half, 0, "the swing that is not skipped must still deal damage")
		assert_almost_eq(float(half), float(full) * 0.5, 1.0,
			"seed %d dealt %d feared against %d plain — live halves the base stat" % [s, half, full])
		assert_true(feared.has_status("fear"), "a half-damage swing must not consume fear")
		break
	assert_true(saw_hit, "CONTROL: 39 seeds at a 10% miss rate must land at least once")


func test_a_feared_physical_ability_is_halved_and_magic_is_not() -> void:
	var strike: Dictionary = _ability("power_strike")
	var spell: Dictionary = _ability("fire")
	if strike.is_empty() or spell.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(float(strike.get("crit_chance", 0.0)), 0.0, "CONTROL: power_strike must stay deterministic")
	var plain := _make("Plain")
	var feared := _make("Feared")
	feared.add_status("fear", 3)
	var victim_a := _make("A")
	var victim_b := _make("B")
	_res._player_party = [plain, feared]
	_res._enemy_party = [victim_a, victim_b]
	var before_a: int = victim_a.current_hp
	var before_b: int = victim_b.current_hp
	_res._resolve_ability(plain, "power_strike", [victim_a])
	_res._resolve_ability(feared, "power_strike", [victim_b])
	var full_strike: int = before_a - victim_a.current_hp
	var half_strike: int = before_b - victim_b.current_hp
	assert_gt(full_strike, 1, "CONTROL: power_strike must land")
	assert_eq(half_strike, int(full_strike / 2),
		"a feared power_strike dealt %d against %d — live halves the base stat before power" % [half_strike, full_strike])
	assert_true(feared.has_status("fear"), "the physical hit must not consume fear")
	victim_a.current_hp = victim_a.max_hp
	victim_b.current_hp = victim_b.max_hp
	before_a = victim_a.current_hp
	before_b = victim_b.current_hp
	_res._resolve_ability(plain, "fire", [victim_a])
	_res._resolve_ability(feared, "fire", [victim_b])
	var full_spell: int = before_a - victim_a.current_hp
	var feared_spell: int = before_b - victim_b.current_hp
	assert_gt(full_spell, 0, "CONTROL: fire must land")
	assert_eq(feared_spell, full_spell, "live does not halve magic, so a feared fire must match")


func test_half_factor_matches_live_on_both_physical_paths() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("has_status\\(\"fear\"\\)[\\s\\S]{0,160}?\\* 0\\.5"), OK)
	var live := FileAccess.get_file_as_string(LIVE)
	var head := FileAccess.get_file_as_string(RESOLVER)
	assert_gt(live.length(), 1000, "CONTROL: live battle source was read")
	assert_gt(head.length(), 1000, "CONTROL: headless resolver source was read")
	var live_hits: int = re.search_all(live).size()
	var head_hits: int = re.search_all(head).size()
	assert_eq(head_hits, live_hits, "the two engines disagree on how many fear-half sites they have")
	assert_eq(live_hits, 2, "live halves a basic attack and a physical ability — magic is the path that must stay out")
