extends GutTest

## A FOE'S all_enemies ABILITY HIT ONE PARTY MEMBER INSTEAD OF THE PARTY, IN THE ENGINE THAT RUNS
## AUTOGRIND. `HeadlessBattleResolver._select_enemy_action` returned `{"targets": [focus]}` whatever
## `target_type` said, while live's `BattleManager._utility_targets` expands `all_enemies` to
## `alive_enemies.duplicate()`. Player AoE was never affected — `AutobattleSystem` hands this engine
## a PRE-EXPANDED list — so only foe actions, built in-file, stayed single. Found by cowir-music
## 2026-10-27 after I had published two conclusions drawn from the broken side.
##
## 🚨 `GameLoop:6707` runs this resolver for the player-facing AUTOGRIND path, so a grind against any
## AoE carrier was easier than the same fight live. firaga/blizzaga/thundaga are 5.0x `all_enemies`
## and Mordaine and the Calibrant carry three each.
##
## ⛔ THE ARM ASSERTS CARDINALITY, NOT DAMAGE, AND THAT IS THE WHOLE DESIGN (cowir-music's note).
## PER-MEMBER DAMAGE AGREES BETWEEN THE ENGINES — the one member the resolver did hit took exactly
## the right amount — so every arm phrased as "the hit landed" or "the damage is within tolerance of
## live" is GREEN ON THE DEFECT. The only quantity the bug moves is how many members are targeted.
##
## ✅ AND THE `single_enemy` ROW IS THE CONTROL, in the same fixture, for the overcorrection this fix
## invites: fanning out EVERYTHING would also make an all_enemies arm pass. The single-target row
## must stay at 1 while the AoE row reaches the party.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")

const PARTY_SIZE := 5


func _resolver_with_party(size: int) -> Array:
	var r = RESOLVER.new()
	var party: Array = []
	for i in range(size):
		var c := Combatant.new()
		c.combatant_name = "PC%d" % i
		c.max_hp = 500 + i * 10
		c.current_hp = c.max_hp
		c.is_alive = true
		add_child_autofree(c)
		party.append(c)
	r._player_party = party
	return [r, party]


## `_find_attack_ability` picks the HIGHEST damage_multiplier among magic/physical rows, so a foe
## given exactly one ability is guaranteed to select it. That is why each fixture holds one.
func _foe(ability_id: String) -> Combatant:
	var e := Combatant.new()
	e.combatant_name = "Foe"
	e.max_hp = 9000
	e.current_hp = 9000
	e.max_mp = 900
	e.current_mp = 900
	e.is_alive = true
	e.learned_abilities = [ability_id]
	add_child_autofree(e)
	return e


func test_the_subject_exposes_what_these_arms_drive() -> void:
	var r = RESOLVER.new()
	assert_true(r.has_method("_select_enemy_action"),
		"_select_enemy_action is the subject; a rename would abort each arm below silently")
	assert_true(r.has_method("_foe_ability_targets"),
		"_foe_ability_targets is the fix; without it the AoE arm cannot distinguish engines")
	assert_not_null(JobSystem, "JobSystem must exist — the target_type comes from it")
	assert_eq(str(JobSystem.get_ability("firaga").get("target_type", "")), "all_enemies",
		"CONTROL: firaga must still be an all_enemies row, or the AoE arm proves nothing")
	assert_eq(str(JobSystem.get_ability("fira").get("target_type", "")), "single_enemy",
		"CONTROL: fira must still be single_enemy, or the control arm proves nothing")
	r.free()


func test_an_all_enemies_ability_targets_every_living_member() -> void:
	var pair := _resolver_with_party(PARTY_SIZE)
	var r = pair[0]
	var action: Dictionary = r._select_enemy_action(_foe("firaga"))
	assert_eq(str(action.get("ability_id", "")), "firaga",
		"the foe must actually select firaga, else the cardinality below is about a basic attack")
	assert_eq((action.get("targets", []) as Array).size(), PARTY_SIZE,
		"firaga is all_enemies: it must target all %d living members, not one" % PARTY_SIZE)
	r.free()


## THE CONTROL. Same shape, same caster, a single_enemy row — this must NOT fan out, or the fix
## has become "every foe ability hits everyone" and the arm above would pass for the wrong reason.
func test_a_single_enemy_ability_still_targets_exactly_one() -> void:
	var pair := _resolver_with_party(PARTY_SIZE)
	var r = pair[0]
	var action: Dictionary = r._select_enemy_action(_foe("fira"))
	assert_eq(str(action.get("ability_id", "")), "fira", "the foe must select fira")
	assert_eq((action.get("targets", []) as Array).size(), 1,
		"fira is single_enemy: fanning it out would mean the fix widened every foe ability")
	r.free()


## The cardinality that a player actually feels: how many members a single foe turn damages.
func test_a_foe_turn_damages_the_party_not_a_member() -> void:
	var pair := _resolver_with_party(PARTY_SIZE)
	var r = pair[0]
	var party: Array = pair[1]
	var before: Array = []
	for c in party:
		before.append(c.current_hp)
	r._execute_action({"combatant": _foe("firaga"), "type": "ability", "ability_id": "firaga",
		"targets": r._select_enemy_action(_foe("firaga")).get("targets", [])})
	var hurt: int = 0
	for i in range(party.size()):
		if party[i].current_hp < before[i]:
			hurt += 1
	assert_eq(hurt, PARTY_SIZE,
		"one firaga must damage all %d members; it damaged %d" % [PARTY_SIZE, hurt])
	r.free()


func test_the_target_list_shrinks_with_the_living_party() -> void:
	var pair := _resolver_with_party(PARTY_SIZE)
	var r = pair[0]
	var party: Array = pair[1]
	party[0].is_alive = false
	party[1].is_alive = false
	var action: Dictionary = r._select_enemy_action(_foe("firaga"))
	assert_eq((action.get("targets", []) as Array).size(), PARTY_SIZE - 2,
		"all_enemies is the LIVING party, not the roster — a dead member must not be targeted")
	r.free()
