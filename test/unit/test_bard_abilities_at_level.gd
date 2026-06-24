extends GutTest

## tick 81 regression: Bard must have abilities_at_level entries
## matching the other 4 starter jobs. Pre-fix, all 4 Bard abilities
## were in the L1 `abilities` list, giving no progression payoff for
## leveling up the Bard. fighter/cleric/mage/rogue all unlock 2
## additional abilities at L3-4 and L6-8 — Bard is the only starter
## without this progression.
##
## Gating semantic: an ability listed in job["abilities"] is usable
## from L1 (JobSystem.can_use_ability allows `in_job OR in_learned`).
## So the level-gated abilities MUST be removed from the abilities
## list AND added to abilities_at_level — otherwise the gate is moot.
##
## Backward compat: existing high-level Bard saves work because
## assign_job retroactively calls learn_abilities_for_level
## (JobSystem.gd:335-336, tick 59), which grants any abilities whose
## level threshold is ≤ current job_level. So a saved L10 Bard
## re-learns discord and inspiring_melody on load.

const JOBS_JSON_PATH := "res://data/jobs.json"


func _load_jobs() -> Dictionary:
	var f := FileAccess.open(JOBS_JSON_PATH, FileAccess.READ)
	assert_not_null(f, "data/jobs.json must be readable")
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	var err: int = json.parse(text)
	assert_eq(err, OK, "data/jobs.json must parse as valid JSON")
	var data = json.data
	assert_true(data is Dictionary, "data/jobs.json must be a dict")
	return data


func test_bard_has_abilities_at_level_field() -> void:
	var jobs := _load_jobs()
	var bard: Dictionary = jobs.get("bard", {})
	assert_false(bard.is_empty(), "bard job must exist in data/jobs.json")
	assert_true(bard.has("abilities_at_level"),
		"bard must have abilities_at_level field — was the only starter without progression unlocks")


func test_bard_l1_abilities_pruned_to_two_starters() -> void:
	# Pin the L1 set: battle_hymn (basic party buff) + lullaby (basic CC).
	# discord (defense debuff) and inspiring_melody (party AP + MP regen)
	# must NOT be in the L1 list — otherwise the level-gate is no-op
	# because can_use_ability allows job["abilities"] regardless of
	# learned_abilities state.
	var jobs := _load_jobs()
	var bard: Dictionary = jobs.get("bard", {})
	var l1: Array = bard.get("abilities", [])
	assert_eq(l1.size(), 2,
		"bard L1 abilities must be 2 (battle_hymn + lullaby) — others move to abilities_at_level")
	assert_true("battle_hymn" in l1,
		"battle_hymn must remain at L1 — Bard's signature starting buff")
	assert_true("lullaby" in l1,
		"lullaby must remain at L1 — basic CC for early game")
	assert_false("discord" in l1,
		"discord must NOT be at L1 — moved to abilities_at_level[4]")
	assert_false("inspiring_melody" in l1,
		"inspiring_melody must NOT be at L1 — moved to abilities_at_level[8]")


func test_bard_abilities_at_level_thresholds_match_other_starters() -> void:
	# Pin the threshold convention: ~L3-4 mid-tier, ~L6-8 high-tier.
	# Matches fighter (3, 6), cleric (4, 8), mage (4, 8), rogue (3, 6).
	# Bard uses 4 + 8 like cleric/mage (support jobs scale slower).
	var jobs := _load_jobs()
	var bard: Dictionary = jobs.get("bard", {})
	var unlocks: Dictionary = bard.get("abilities_at_level", {})
	assert_true(unlocks.has("4"),
		"abilities_at_level must have a '4' key — mid-tier unlock matches cleric/mage cadence")
	assert_true(unlocks.has("8"),
		"abilities_at_level must have an '8' key — high-tier unlock matches cleric/mage cadence")
	assert_eq(unlocks["4"], ["discord"],
		"L4 unlock must grant discord — defense debuff, complements party damage")
	assert_eq(unlocks["8"], ["inspiring_melody"],
		"L8 unlock must grant inspiring_melody — the powerful party MP+AP regen")


func test_bard_total_abilities_unchanged_for_high_level_chars() -> void:
	# Sanity: a high-level Bard should still have access to all 4
	# (2 L1 + 2 level-gated). Pin the union via set comparison.
	var jobs := _load_jobs()
	var bard: Dictionary = jobs.get("bard", {})
	var l1: Array = bard.get("abilities", [])
	var unlocks: Dictionary = bard.get("abilities_at_level", {})
	var all: Array[String] = []
	for a in l1:
		all.append(str(a))
	for level_key in unlocks.keys():
		var ids: Variant = unlocks[level_key]
		if ids is Array:
			for a in ids:
				all.append(str(a))
	assert_eq(all.size(), 4,
		"Bard total ability count must be 4 (2 L1 + 2 level-gated)")
	# Pin every ability id present.
	for expected_id in ["battle_hymn", "lullaby", "discord", "inspiring_melody"]:
		assert_true(expected_id in all,
			"%s must be reachable through L1 abilities or abilities_at_level union" % expected_id)


func test_every_unlocked_ability_id_resolves_in_abilities_json() -> void:
	# Defensive: if a typo lands in abilities_at_level, learn_ability
	# silently no-ops (Combatant.learn_ability accepts any string).
	# Pin that the unlock targets exist in abilities.json.
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(f, "data/abilities.json must be readable")
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	assert_eq(json.parse(text), OK, "abilities.json must parse")
	var abilities = json.data
	assert_true(abilities is Dictionary, "abilities.json must be a dict")
	var jobs := _load_jobs()
	var bard: Dictionary = jobs.get("bard", {})
	var unlocks: Dictionary = bard.get("abilities_at_level", {})
	for level_key in unlocks.keys():
		var ids: Variant = unlocks[level_key]
		if not (ids is Array):
			continue
		for raw in ids:
			var ability_id: String = str(raw)
			assert_true(abilities.has(ability_id),
				"Bard abilities_at_level[%s] references '%s' which must exist in abilities.json — otherwise the unlock is dead" % [level_key, ability_id])
