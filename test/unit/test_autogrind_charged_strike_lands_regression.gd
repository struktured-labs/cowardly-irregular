extends GutTest

## `next_attack_multiplier` stores a bonus on the caster for its NEXT swing. Live SETS it in
## _execute_support_ability (:6326) and CONSUMES it on TWO paths — the basic attack (:4374) and the
## magic arm (:4969). The resolver had none of the three, so `burrow` was a wasted turn:
## `ironback_beetle` (POOLED) telegraphed and then hit for exactly the same damage.
##
##   burrow            support, next_attack_multiplier 1.5   ironback_beetle (POOLED)
##   storm_gathering   support, 1.8                          Voltharion (boss, not pooled)
##
## ⚠️ THIS IS THE FIRST GAP IN THIS FILE THAT SPANS TURNS. Everything before it was resolvable inside
## one cast; this one stores state on the caster and spends it later, so the arms have to prove the
## bonus SURVIVES to the next action and is gone after — a fix that applies it every swing is worse
## than the bug, and no single-cast arm can tell the two apart.
##
## ⛔ ONE PRODUCER, TWO CONSUMERS, and the clear lives in the helper rather than at each call site, so
## a third consumer cannot forget it. That is deliberate: live's two consumers each clear their own,
## which works and would not survive a third being added by someone reading only one of them.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func _combatant(name: String, hp: int = 99999) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 40, "defense": 10, "magic": 40, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


func test_a_charge_reaches_the_next_swing() -> void:
	var ab: Dictionary = _authored("burrow")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var mult: float = float(ab.get("next_attack_multiplier", 0.0))
	assert_gt(mult, 1.0, "CONTROL: burrow must still author a next_attack_multiplier above 1")
	var beetle := _combatant("Ironback Beetle")
	var hero := _combatant("Hero")
	_res._player_party = [hero]
	_res._enemy_party = [beetle]

	## Seeded, because _resolve_attack carries variance and a crit roll — without this the comparison
	## is noise and the arm would flake rather than measure.
	seed(0x5EED)
	var plain: int = _res._resolve_attack(beetle, hero)
	seed(0x5EED)
	_res._resolve_ability(beetle, "burrow", [beetle])
	var charged: int = _res._resolve_attack(beetle, hero)
	gut.p("    burrow x%.1f: plain swing %d -> charged swing %d" % [mult, plain, charged])
	assert_gt(plain, 0, "CONTROL: the unbuffed swing must land something")
	assert_gt(charged, plain,
		"the swing after burrow dealt %d against an unbuffed %d — the telegraph is still a wasted turn" % [charged, plain])


func test_the_charge_is_spent_once_and_not_kept() -> void:
	## The direction a naive fix gets wrong. Applying the bonus on every subsequent swing is a bigger
	## defect than never applying it, and the arm above cannot tell the two apart.
	var ab: Dictionary = _authored("burrow")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var beetle := _combatant("Ironback Beetle")
	var hero := _combatant("Hero")
	_res._player_party = [hero]
	_res._enemy_party = [beetle]
	_res._resolve_ability(beetle, "burrow", [beetle])
	seed(0x5EED)
	var first: int = _res._resolve_attack(beetle, hero)
	seed(0x5EED)
	var second: int = _res._resolve_attack(beetle, hero)
	gut.p("    after burrow: first %d, second %d" % [first, second])
	assert_gt(first, second,
		"the second swing after burrow also got the bonus (%d vs %d) — the charge was never cleared" % [second, first])
	assert_eq(float(beetle.get_meta("_next_attack_multiplier", 0.0)), 0.0,
		"the stored charge survived its own consumption")


func test_a_support_ability_without_the_key_stores_nothing() -> void:
	## A producer that fired unconditionally would charge the caster on every support cast.
	var ab: Dictionary = _authored("protect")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("next_attack_multiplier"), "CONTROL: protect must author no charge")
	var hero := _combatant("Hero")
	_res._player_party = [hero]
	_res._enemy_party = []
	_res._resolve_ability(hero, "protect", [hero])
	assert_eq(float(hero.get_meta("_next_attack_multiplier", 0.0)), 0.0,
		"a support ability authoring no charge stored one anyway")


func test_the_magic_path_consumes_it_too_and_only_once() -> void:
	## Live consumes on BOTH paths and clears BEFORE the target loop, so an AoE gets the boost on every
	## target and spends the charge a single time. A per-target consume would boost only the first.
	var caster := _combatant("Caster")
	var party: Array = [_combatant("A"), _combatant("B")]
	_res._player_party = party
	_res._enemy_party = [caster]
	caster.set_meta("_next_attack_multiplier", 2.0)
	_res._resolve_ability(caster, "fire", [party[0], party[1]])
	var a_lost: int = party[0].max_hp - party[0].current_hp
	var b_lost: int = party[1].max_hp - party[1].current_hp
	gut.p("    charged AoE: A lost %d, B lost %d" % [a_lost, b_lost])
	assert_gt(a_lost, 0, "CONTROL: the cast must land on the first target")
	assert_eq(a_lost, b_lost,
		"the charge was consumed per target — A took %d and B took %d, so only the first got the boost" % [a_lost, b_lost])
	assert_eq(float(caster.get_meta("_next_attack_multiplier", 0.0)), 0.0,
		"the charge survived a magic cast that consumed it")


func test_live_still_sets_on_support_and_consumes_on_both_paths() -> void:
	## Axis 2 for a three-site mechanic: one producer, two consumers. If live moves any of them the
	## grind mirrors the wrong shape, and no behavioural arm here would notice.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var set_at: int = live.find('set_meta("_next_attack_multiplier", nam)')
	assert_gt(set_at, 0, "CONTROL: live must still store the charge")
	var owner: int = live.substr(0, set_at).rfind("func _execute_")
	assert_true(live.substr(owner, 46).begins_with("func _execute_support_ability"),
		"live no longer stores the charge from the support executor — the grind stores it there")
	assert_gte(live.count('get_meta("_next_attack_multiplier"'), 2,
		"live no longer consumes the charge on two paths — the grind consumes on the attack and magic paths to match")
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_eq(code.count("_take_charged_multiplier("), 3,
		"the grind must have exactly one helper and two consumers — found %d occurrences" % code.count("_take_charged_multiplier("))
