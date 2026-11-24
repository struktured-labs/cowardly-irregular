extends GutTest
## RecipeMatcher: every starter recipe has a choice that counts toward it and a near miss that does not.

## [recipe id, counting choice, near-miss choice]
const CASES := [
	["heal_ally_under_50",
		{"action_type": "ability", "ability_kind": "heal", "target_side": "ally", "target_hp_pct": 0.49},
		{"action_type": "ability", "ability_kind": "heal", "target_side": "ally", "target_hp_pct": 0.5}],
	["cure_status",
		{"action_type": "ability", "ability_kind": "cure", "target_side": "ally", "target_statuses": ["poison"], "cures": ["poison"]},
		{"action_type": "ability", "ability_kind": "cure", "target_side": "ally", "target_statuses": ["blind"], "cures": ["poison"]}],
	["hit_known_weakness",
		{"action_type": "ability", "ability_kind": "damage", "target_side": "enemy", "target_weak": true},
		{"action_type": "ability", "ability_kind": "damage", "target_side": "enemy", "target_weak": false}],
	["finish_under_25",
		{"action_type": "attack", "target_side": "enemy", "target_hp_pct": 0.2},
		{"action_type": "attack", "target_side": "enemy", "target_hp_pct": 0.25}],
	["defer_at_low_ap",
		{"action_type": "defer", "actor_ap": 0},
		{"action_type": "defer", "actor_ap": 1}],
	["advance_full_bank",
		{"action_type": "attack", "actor_ap": 4, "queued": 5},
		{"action_type": "attack", "actor_ap": 4, "queued": 4}],
	["bard_riff_unblinded",
		{"action_type": "ability", "ability_id": "riff", "target_side": "enemy", "target_statuses": []},
		{"action_type": "ability", "ability_id": "riff", "target_side": "enemy", "target_statuses": ["blind"]}],
	["steal_first",
		{"action_type": "ability", "ability_kind": "steal", "target_side": "enemy", "target_hp_pct": 1.0},
		{"action_type": "ability", "ability_kind": "steal", "target_side": "enemy", "target_hp_pct": 0.9}],
	["revive_ko",
		{"action_type": "ability", "ability_kind": "revive", "target_side": "ally", "target_ko": true},
		{"action_type": "ability", "ability_kind": "revive", "target_side": "ally", "target_ko": false}],
]


func test_every_catalog_id_has_a_case():
	var covered: Array = []
	for c in CASES:
		covered.append(c[0])
	assert_eq(RecipeMatcher.RECIPE_IDS.size(), 9, "the starter catalog is the nine story ids")
	for id in RecipeMatcher.RECIPE_IDS:
		assert_true(id in covered, "%s has a positive and a near-miss case" % id)


func test_a_choice_counts_toward_its_recipe():
	var checked := 0
	for c in CASES:
		assert_true(c[0] in RecipeMatcher.recipes_for(c[1]), "%s counts %s" % [c[0], c[1]])
		checked += 1
	assert_eq(checked, CASES.size(), "every positive ran")


func test_a_near_miss_does_not_count():
	var checked := 0
	for c in CASES:
		assert_false(c[0] in RecipeMatcher.recipes_for(c[2]), "%s must not count %s" % [c[0], c[2]])
		checked += 1
	assert_eq(checked, CASES.size(), "every near miss ran")


func test_an_empty_choice_teaches_nothing():
	assert_eq(RecipeMatcher.recipes_for({}), [] as Array[String], "an empty record counts toward no recipe")


func test_a_ko_ally_is_revived_not_healed_or_cured():
	var heal_ko := {"ability_kind": "heal", "target_side": "ally", "target_ko": true, "target_hp_pct": 0.0}
	assert_false("heal_ally_under_50" in RecipeMatcher.recipes_for(heal_ko), "a heal on a KO ally is not a heal-under-50")
	var cure_ko := {"ability_kind": "cure", "target_side": "ally", "target_ko": true, "target_statuses": ["poison"], "cures": ["poison"]}
	assert_false("cure_status" in RecipeMatcher.recipes_for(cure_ko), "a cure on a KO ally does not count")


func test_one_choice_can_teach_two_recipes_in_catalog_order():
	var c := {"action_type": "attack", "target_side": "enemy", "target_weak": true, "target_hp_pct": 0.1}
	assert_eq(RecipeMatcher.recipes_for(c), ["hit_known_weakness", "finish_under_25"] as Array[String],
		"a weak, nearly dead enemy hit with Attack teaches both, weakness first")


func test_the_full_bank_follows_battle_manager():
	assert_false("advance_full_bank" in RecipeMatcher.recipes_for({"actor_ap": 3, "queued": 5}), "AP 3 is not a full bank")
	assert_true("advance_full_bank" in RecipeMatcher.recipes_for({"actor_ap": 4, "queued": 5}), "AP 4 with five queued is")


func test_an_unknown_id_counts_nothing():
	assert_false(RecipeMatcher.counts_toward("no_such_recipe", {"action_type": "attack"}), "an unknown id is false, never a crash")
