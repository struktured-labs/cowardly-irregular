extends GutTest

## Autogrind enemies never cast and never healed — two dead keys (2026-07-31).
##
## `HeadlessBattleResolver._select_enemy_action` has three arms: heal when hurt,
## cast when it has MP, else basic attack. Both ability-finding helpers read keys
## that `abilities.json` has NEVER authored:
##
##     _find_heal_ability     ability.get("category","") == "healing"
##     _find_attack_ability   cat in ["magic","physical"] ; power > best_power
##
##     category   0 of 289 authored   (the field is `type`)
##     power      0 of 289 authored   (the field is `damage_multiplier`)
##     CONTROL    type 289 of 289
##
## Both guards were therefore constant-false, both helpers returned "" on every
## call, and every enemy in every autogrind battle fell through to a plain
## attack for the whole fight — never casting one of the 156 magic/physical
## abilities, never using one of the 7 heals.
##
## This is NOT test-only code: HeadlessBattleResolver is used by GameLoop and
## AutogrindSystem, and `_select_enemy_action` runs at :166 and :230.
##
## I originally reported this function as "dead code with no callers" and left
## it. That was wrong twice: I searched a function name that does not exist
## (`_get_best_offensive_ability`), got a zero that matched what I expected, and
## published it. The real name is `_find_attack_ability` and it is called at :519.
##
## These tests assert the SELECTED ACTION, not the field names — the defect is
## behavioural, and a source pin would pass against a helper that still returns "".

const HBR := "res://src/autogrind/HeadlessBattleResolver.gd"


func _resolver() -> Object:
	var r: Object = load(HBR).new()
	if r is Node:
		add_child_autofree(r)
	return r


func _enemy(hp: int, max_hp: int, mp: int, abilities: Array) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Enemy"
	c.is_alive = true
	c.max_hp = max_hp
	c.current_hp = hp
	c.max_mp = 100
	c.current_mp = mp
	for a in abilities:
		c.learned_abilities.append(str(a))
	return c


func _player() -> Combatant:
	var p: Combatant = autofree(Combatant.new())
	p.combatant_name = "PC"
	p.is_alive = true
	p.max_hp = 500
	p.current_hp = 500
	return p


## ── the premise: the keys really are dead, the real ones really are live ──

func test_the_dead_keys_are_still_dead_and_type_is_still_live() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ab: Dictionary = raw.get("abilities", raw)
	var n_cat: int = 0
	var n_pow: int = 0
	var n_type: int = 0
	for id in ab:
		var a: Dictionary = ab[id]
		if a.has("category"):
			n_cat += 1
		if a.has("power"):
			n_pow += 1
		if a.has("type"):
			n_type += 1
	assert_eq(n_cat, 0, "if abilities start authoring `category`, the fallback order needs revisiting")
	assert_eq(n_pow, 0, "if abilities start authoring `power`, same")
	assert_eq(n_type, ab.size(),
		"POSITIVE CONTROL: every ability must author `type`, or the fix reads a key as dead as the one it replaced")


## ── the behaviour, driven ────────────────────────────────────────────

func test_a_healthy_enemy_with_mp_casts_instead_of_swinging() -> void:
	# Pre-fix _find_attack_ability returned "" for every input, so this arm was
	# unreachable and the resolver always fell through to {"type": "attack"}.
	var r: Object = _resolver()
	r._player_party = [_player()]
	var e: Combatant = _enemy(100, 100, 50, ["fire"])
	var action: Dictionary = r._select_enemy_action(e)
	assert_eq(str(action.get("type", "")), "ability",
		"an enemy with MP and an offensive ability must choose it — 'attack' means the finder still returns \"\"")
	assert_eq(str(action.get("ability_id", "")), "fire", "and it must be the ability it actually knows")


func test_a_wounded_enemy_heals() -> void:
	# The other dead helper. Below 30% HP the resolver reaches for a heal first.
	var r: Object = _resolver()
	r._player_party = [_player()]
	var e: Combatant = _enemy(10, 100, 50, ["cure"])
	var action: Dictionary = r._select_enemy_action(e)
	assert_eq(str(action.get("ability_id", "")), "cure",
		"a wounded enemy holding a heal must cast it — pre-fix `category` was constant \"\" and it never did")
	assert_eq(action.get("targets", [] as Array), [e] as Array, "and heal itself")


func test_the_strongest_offensive_ability_wins() -> void:
	# `power` was the second dead key: with it constant 0, `power > best_power`
	# never fired and best_id stayed "" even once the category guard passed.
	var r: Object = _resolver()
	r._player_party = [_player()]
	var e: Combatant = _enemy(100, 100, 99, ["fire", "firaga"])
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ab: Dictionary = raw.get("abilities", raw)
	# ASSERT, don't skip. A `pass_test` here would register a passing assertion and retire this test silently the day either id is renamed — the shape three lanes closed on 2026-07-31. Asserting makes a rename LOUD and hands the next reader the two names to re-point.
	assert_true(ab.has("fire") and ab.has("firaga"),
		"this ranking test is written against fire/firaga — if either was renamed, re-point it rather than letting it skip")
	var strongest: String = "firaga" if float((ab["firaga"] as Dictionary).get("damage_multiplier", 0.0)) \
		> float((ab["fire"] as Dictionary).get("damage_multiplier", 0.0)) else "fire"
	assert_eq(str(r._find_attack_ability(e)), strongest,
		"the finder must rank by real damage weight, not a constant")


## ── the failure mode itself ──────────────────────────────────────────

func test_finder_returns_something_for_a_normal_kit() -> void:
	# The compact statement of the bug: "" for every input.
	var r: Object = _resolver()
	var e: Combatant = _enemy(100, 100, 50, ["fire", "cure"])
	assert_ne(str(r._find_attack_ability(e)), "",
		"an enemy knowing an offensive ability must yield one")
	assert_ne(str(r._find_heal_ability(e)), "",
		"an enemy knowing a heal must yield one")


func test_no_ability_still_falls_back_to_attack() -> void:
	# The fallback must survive the fix — an enemy with no kit still acts.
	var r: Object = _resolver()
	r._player_party = [_player()]
	var e: Combatant = _enemy(100, 100, 50, [])
	assert_eq(str(r._select_enemy_action(e).get("type", "")), "attack",
		"an enemy with no abilities must still take its basic attack")


func test_zero_mp_enemy_does_not_cast() -> void:
	# The MP gate is upstream of the finder and must keep working.
	var r: Object = _resolver()
	r._player_party = [_player()]
	var e: Combatant = _enemy(100, 100, 0, ["fire"])
	assert_eq(str(r._select_enemy_action(e).get("type", "")), "attack",
		"no MP means no cast, regardless of what the finder returns")
