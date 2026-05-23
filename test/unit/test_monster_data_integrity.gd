extends GutTest

## Global integrity guard for monsters.json (2026-05-23).
##
## Catches the silent-failure class fixed in d186a58: monster drop
## tables / one_shot rewards / abilities that reference IDs not
## defined in items.json / abilities.json. These don't crash at
## runtime — the drop just no-ops, the ability gets silently skipped
## by the AI — so they slip past manual review.
##
## The audit that found this: 180 broken drop refs across the entire
## monster database. After the d186a58 cleanup, the count is 0.
## This test pins the 0 so a future contributor doesn't accidentally
## reintroduce the class of bug.


var _job_system: Node
var _item_system: Node


func before_all() -> void:
	_job_system = get_tree().root.get_node_or_null("JobSystem")
	_item_system = get_tree().root.get_node_or_null("ItemSystem")


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	assert_not_null(data, "%s must parse" % path)
	return data


func test_every_monster_drop_resolves_to_a_real_item() -> void:
	"""Each monster's drop_table[].item must exist in items.json,
	otherwise the drop silently no-ops on victory (player sees a
	humanized ID string in inventory that does nothing)."""
	var monsters = _read_json("res://data/monsters.json")
	var items = _read_json("res://data/items.json")
	var bad: Array = []
	for mid in monsters:
		var m = monsters[mid]
		for entry in m.get("drop_table", []):
			var item_id = entry.get("item", "")
			if item_id != "" and not items.has(item_id):
				bad.append("%s -> %s" % [mid, item_id])
	assert_eq(bad.size(), 0,
		"All monster drop_table items must resolve. Broken refs: %s" % str(bad.slice(0, 10)))


func test_every_one_shot_reward_resolves_to_a_real_item() -> void:
	"""one_shot.reward_item is the strategic-prep reward — if it
	doesn't exist, the player gets nothing for completing the puzzle."""
	var monsters = _read_json("res://data/monsters.json")
	var items = _read_json("res://data/items.json")
	var bad: Array = []
	for mid in monsters:
		var m = monsters[mid]
		var os = m.get("one_shot", {})
		var reward = os.get("reward_item", "")
		if reward != "" and not items.has(reward):
			bad.append("%s -> %s" % [mid, reward])
	assert_eq(bad.size(), 0,
		"All one_shot rewards must resolve. Broken: %s" % str(bad.slice(0, 10)))


func test_every_monster_ability_resolves_in_job_system() -> void:
	"""Abilities silently no-op in battle if the ID doesn't exist
	in abilities.json — the AI just skips the cast and the player
	wonders why the boss isn't using its kit."""
	if _job_system == null:
		pending("JobSystem autoload not available")
		return
	var monsters = _read_json("res://data/monsters.json")
	var bad: Array = []
	for mid in monsters:
		var m = monsters[mid]
		for ab in m.get("abilities", []):
			if ab == "":
				continue
			var ability = _job_system.get_ability(ab)
			if ability.is_empty():
				bad.append("%s -> %s" % [mid, ab])
	assert_eq(bad.size(), 0,
		"All monster abilities must resolve in JobSystem. Broken: %s" % str(bad.slice(0, 10)))


func test_every_monster_weakness_and_resistance_is_a_known_element() -> void:
	"""Elemental tags drive damage modifiers — typo'd elements silently
	don't apply the 1.5x / 0.5x / 0x multiplier."""
	var monsters = _read_json("res://data/monsters.json")
	# Canonical element strings (must match between abilities.json element
	# field and monster weaknesses/resistances/immunities arrays —
	# Combatant.calculate_elemental_modifier compares them as raw strings).
	# Derived from abilities.json by inspection (2026-05-23).
	var known_elements = ["fire", "ice", "lightning", "earth", "water",
						   "wind", "holy", "dark", "poison", "neutral",
						   "physical"]
	var bad: Array = []
	for mid in monsters:
		var m = monsters[mid]
		for tag in m.get("weaknesses", []):
			if not (tag in known_elements):
				bad.append("%s weakness: %s" % [mid, tag])
		for tag in m.get("resistances", []):
			if not (tag in known_elements):
				bad.append("%s resistance: %s" % [mid, tag])
		for tag in m.get("immunities", []):
			if not (tag in known_elements):
				bad.append("%s immunity: %s" % [mid, tag])
	assert_eq(bad.size(), 0,
		"All elemental tags must be known elements. Bad: %s" % str(bad.slice(0, 10)))
