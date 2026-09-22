extends GutTest

## null_entity authors special_behavior.phase_out at 0.2 and sits in abstract_overworld, a pool
## the grind draws. Live misses a physical swing and a spell on that roll and does not spend
## Magic Block. The grind always connected.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 5000,
		"max_mp": 500,
		"attack": 80,
		"defense": 5,
		"magic": 80,
		"speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _null_entity() -> Combatant:
	var c := _fighter("Null Entity")
	c.set_meta("monster_type", "null_entity")
	return c


func _cast(caster: Combatant, ability_id: String, target: Combatant) -> void:
	caster.current_mp = caster.max_mp
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, ability_id, [target])


func test_the_database_still_authors_phase_out() -> void:
	var enc = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	assert_not_null(enc, "CONTROL: EncounterSystem is the database the grind reads")
	assert_true(enc.monster_database.has("null_entity"), "CONTROL: null_entity is in the database")
	var sb: Variant = enc.monster_database["null_entity"].get("special_behavior", {})
	assert_true(sb is Dictionary and bool((sb as Dictionary).get("phase_out", false)),
		"null_entity must still author phase_out — this file is about that flag")
	assert_eq(float((sb as Dictionary).get("phase_out_chance", -1.0)), 0.2,
		"null_entity's phase_out_chance drifted from the 0.2 live and the grind both default to")


func test_a_physical_swing_can_phase_through_and_a_slime_cannot() -> void:
	var attacker := _fighter("Fighter")
	var entity := _null_entity()
	var phased := 0
	var connected := 0
	for s in 80:
		seed(s)
		if _res._target_dodges_physical(attacker, entity):
			phased += 1
		else:
			connected += 1
	assert_gt(phased, 0, "80 swings at 20%% phase-out must miss at least once")
	assert_gt(connected, 0, "80 swings at 20%% phase-out must also connect — a guaranteed miss would be immunity")
	var slime := _fighter("Slime")
	slime.set_meta("monster_type", "slime")
	for s in 20:
		seed(s)
		assert_false(_res._target_dodges_physical(attacker, slime),
			"slime authors no phase_out, and a naked combatant has nothing else to dodge with")


func test_a_spell_that_connects_still_hurts_and_a_phase_out_does_not() -> void:
	var landed := false
	var missed := false
	for s in range(1, 80):
		var caster := _fighter("Mage")
		var target := _null_entity()
		seed(s)
		_cast(caster, "fire", target)
		if target.current_hp < target.max_hp:
			landed = true
		else:
			missed = true
		if landed and missed:
			break
	assert_true(missed, "fire must sometimes find nothing — live rolls phase_out on spells")
	assert_true(landed, "fire must sometimes land — phase_out is a chance, and physical immunity does not cover magic")


func test_a_phase_out_leaves_magic_block_standing() -> void:
	## Live checks phase_out before it spends Magic Block. A miss that consumes the ward is a
	## different mechanic, and a ward that survives a connecting spell is the other bug.
	var phased := false
	var blocked := false
	for s in range(1, 80):
		var caster := _fighter("Mage")
		var target := _null_entity()
		target.add_status("magic_block", 2)
		seed(s)
		_cast(caster, "fire", target)
		if target.current_hp == target.max_hp and target.has_status("magic_block"):
			phased = true
		elif target.current_hp == target.max_hp and not target.has_status("magic_block"):
			blocked = true
		if phased and blocked:
			break
	assert_true(phased, "a phase-out must miss the spell and leave Magic Block up")
	assert_true(blocked, "a spell that does not phase out must spend Magic Block")
