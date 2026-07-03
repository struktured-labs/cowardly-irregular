extends GutTest

## Dead-field find (render-smoke follow-up 2026-07-02): all 93
## monsters author exp_reward (slime 15 → Mordaine 900), the bestiary
## DISPLAYS those numbers, autogrind PAYS them — but live battles
## paid a flat base 50 regardless of enemy. Victory EXP now sums the
## defeated roster's authored exp_reward.


func test_victory_exp_sums_authored_rewards() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("get(\"exp_reward\", 25)"),
		"victory EXP must read per-monster exp_reward (default 25 for meta-less test enemies)")
	assert_false(src.contains("var base_exp = 50"),
		"the flat base-50 is the regression — it paid Mordaine like a slime pair")
	assert_true(src.contains("if base_exp <= 0:"),
		"empty/unknown rosters need the safety floor")


func test_data_spread_justifies_the_wiring() -> void:
	# The authored spread is meaningful (tutorial trash vs W1 finale) —
	# if this collapses, the wiring stops mattering and someone should ask why.
	var mm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var body: Dictionary = mm.get("monsters", mm)
	var slime: int = int(body.get("slime", {}).get("exp_reward", 0))
	var mordaine: int = int(body.get("chancellor_mordaine", {}).get("exp_reward", 0))
	assert_gt(slime, 0)
	assert_gt(mordaine, slime * 10,
		"boss EXP must dwarf trash EXP or the data-driven wiring is pointless")
