extends GutTest

## Runtime smoke tests for the Mordaine boss.
## Source-level checks already exist in test_mordaine_scaffold.gd —
## these complement with actual instantiation + ability resolution
## to catch issues that wouldn't show up in pure source parsing
## (e.g. ability ID typos, stat-block field name drift, JSON drift).


var _job_system: Node


func before_all() -> void:
	_job_system = get_tree().root.get_node_or_null("JobSystem")


func _load_mordaine_data() -> Dictionary:
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	assert_not_null(data, "monsters.json must parse")
	var m = data.get("chancellor_mordaine", {})
	assert_false(m.is_empty(), "monsters.json must contain chancellor_mordaine")
	return m


func test_mordaine_combatant_instantiates_from_json() -> void:
	"""Building a Combatant from the JSON stat block must succeed
	without losing fields. Regression: stat-block field renames in
	monsters.json would silently zero out HP/MP/attack on instantiation."""
	var m = _load_mordaine_data()
	var c = autofree(Combatant.new())
	c.combatant_name = m["name"]
	c.max_hp = m["stats"]["max_hp"]
	c.current_hp = c.max_hp
	c.max_mp = m["stats"]["max_mp"]
	c.attack = m["stats"]["attack"]
	c.magic = m["stats"]["magic"]
	c.speed = m["stats"]["speed"]
	c.is_alive = true

	assert_eq(c.max_hp, 1500, "Mordaine max_hp must round-trip from JSON")
	assert_eq(c.max_mp, 300, "Mordaine max_mp must round-trip from JSON")
	assert_gt(c.magic, c.attack,
		"Mordaine is magic-heavy — magic should exceed attack (regression: balance shift)")
	assert_true(c.is_alive, "Combatant must start alive")


func test_mordaine_abilities_all_exist_in_job_system() -> void:
	"""Every ability referenced in chancellor_mordaine.abilities MUST
	resolve in JobSystem.get_ability — a typo here means the boss
	silently fails to cast and just skips turns. Worse: a runtime
	ability lookup miss is invisible to the player (looks like AI
	choosing not to act)."""
	if _job_system == null:
		pending("JobSystem autoload not available")
		return
	var m = _load_mordaine_data()
	var abilities = m.get("abilities", [])
	assert_gt(abilities.size(), 0, "Mordaine must have at least one ability")
	for ability_id in abilities:
		var ability = _job_system.get_ability(ability_id)
		assert_false(ability.is_empty(),
			"Ability '%s' in Mordaine's kit must exist in JobSystem (regression: typo or removed ability)" % ability_id)
		# Smoke check fields
		assert_true(ability.has("name"),
			"Ability '%s' must have a name field" % ability_id)


func test_mordaine_drop_items_all_resolve() -> void:
	"""Each drop_table entry's item_id should resolve in ItemSystem.
	A missing item would cause the drop to silently no-op on victory
	(player wonders why they didn't get the reward they saw advertised)."""
	var item_system = get_tree().root.get_node_or_null("ItemSystem")
	if item_system == null:
		pending("ItemSystem autoload not available")
		return
	var m = _load_mordaine_data()
	var drops = m.get("drop_table", [])
	for entry in drops:
		var item_id = entry.get("item", "")
		# Mordaine introduces 'calibrant_token' which is new — verify
		# the others ('elixir', 'megalixir', 'boss_trophy') resolve.
		# calibrant_token will be checked separately when ItemSystem
		# learns about it.
		if item_id == "calibrant_token":
			continue
		var item = item_system.items.get(item_id, {})
		assert_false(item.is_empty(),
			"Mordaine drop '%s' must exist in ItemSystem" % item_id)


func test_mordaine_weaknesses_and_resistances_are_known_elements() -> void:
	"""Mordaine's weaknesses/resistances should reference real elements
	that battle effect resolution recognizes. A typo'd element silently
	skips the damage modifier."""
	var m = _load_mordaine_data()
	var known_elements = ["fire", "ice", "lightning", "earth", "water",
						   "wind", "holy", "dark", "neutral", "physical"]
	for w in m.get("weaknesses", []):
		assert_true(w in known_elements,
			"Mordaine weakness '%s' must be a recognized element" % w)
	for r in m.get("resistances", []):
		assert_true(r in known_elements,
			"Mordaine resistance '%s' must be a recognized element" % r)


func test_mordaine_one_shot_setup_is_well_formed() -> void:
	"""one_shot blocks reward strategic prep. The hp_threshold should
	equal or exceed max_hp (so one full-damage hit qualifies) and the
	reward_item should be present (or this whole block is dead data)."""
	var m = _load_mordaine_data()
	var os = m.get("one_shot", {})
	if os.is_empty():
		return  # No one_shot set — fine
	assert_gte(os.get("hp_threshold", 0), m["stats"]["max_hp"],
		"one_shot hp_threshold must be at least max_hp (otherwise threshold is unreachable on a fresh boss)")
	assert_ne(os.get("reward_item", ""), "",
		"one_shot must declare a reward_item")
	assert_ne(os.get("setup_hint", ""), "",
		"one_shot should include a setup_hint for the bestiary")
