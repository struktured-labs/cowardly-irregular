extends GutTest

## Regression: BestiaryMenu detail panel surfaces drop table + EXP/Gold
## rewards so players designing autobattle / autogrind scripts have the
## input data they need (drop rates and currency yield) to plan farming
## loops. Pre-fix the menu showed name/level/stats/weak/resist/flavor
## but DROPS were hidden — the game's "automation as core gameplay"
## design principle (CLAUDE.md #1) requires this data to be surfaced
## so autobattle setups can be intelligent.

const BESTIARY_SYSTEM_PATH := "res://src/bestiary/BestiarySystem.gd"
const BESTIARY_MENU_PATH := "res://src/ui/BestiaryMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_bestiary_entries_include_drop_and_reward_fields() -> void:
	# Source pin: get_seen_entries_sorted must include the new fields so
	# the menu has data to render. Catches anyone removing them later.
	var text = _read(BESTIARY_SYSTEM_PATH)
	for field in ["exp_reward", "gold_reward", "drops", "one_shot_reward"]:
		assert_true(text.find("\"%s\":" % field) > -1,
			"BestiarySystem.get_seen_entries_sorted must populate '%s' field on entries" % field)


func test_menu_renders_rewards_and_drops_labels() -> void:
	var text = _read(BESTIARY_MENU_PATH)
	# Labels must exist
	assert_true(text.find("_detail_rewards") > -1,
		"BestiaryMenu must declare _detail_rewards label field")
	assert_true(text.find("_detail_drops") > -1,
		"BestiaryMenu must declare _detail_drops label field")
	# Refresh path must populate both
	var refresh_idx = text.find("func _refresh_detail")
	assert_true(refresh_idx > -1, "_refresh_detail must exist")
	var refresh_end = text.find("\n\nfunc ", refresh_idx)
	var body = text.substr(refresh_idx, refresh_end - refresh_idx) if refresh_end > -1 else text.substr(refresh_idx, 3000)
	assert_true(body.find("_detail_rewards.text") > -1,
		"_refresh_detail must populate _detail_rewards label")
	assert_true(body.find("_detail_drops.text") > -1,
		"_refresh_detail must populate _detail_drops label")


func test_format_drops_handles_real_drop_data() -> void:
	# Behavioral: BestiaryMenu._format_drops produces expected output
	# given a real monsters.json shape ({item, chance}).
	var script = load(BESTIARY_MENU_PATH)
	var menu = script.new()
	add_child_autofree(menu)

	var drops := [
		{"item": "bone", "chance": 0.5},
		{"item": "ether", "chance": 0.15},
	]
	var result: String = menu._format_drops(drops, null)
	assert_true(result.begins_with("Drops:"),
		"Result must start with 'Drops:' prefix")
	assert_true(result.find("Bone 50%") > -1,
		"Drop entry must format as 'Title Case <pct>%' — got: %s" % result)
	assert_true(result.find("Ether 15%") > -1,
		"Second drop must also format correctly — got: %s" % result)


func test_format_drops_handles_empty_drop_table() -> void:
	var script = load(BESTIARY_MENU_PATH)
	var menu = script.new()
	add_child_autofree(menu)
	var result: String = menu._format_drops([], null)
	assert_eq(result, "Drops: —",
		"Empty drop table must render as 'Drops: —' (em-dash)")


func test_format_drops_appends_one_shot_reward() -> void:
	# Monsters with one_shot_reward (rare bonus drops, e.g. boss tokens)
	# show it appended in parens to distinguish from regular drops.
	var script = load(BESTIARY_MENU_PATH)
	var menu = script.new()
	add_child_autofree(menu)
	var drops := [{"item": "scale", "chance": 0.25}]
	var result: String = menu._format_drops(drops, "calibrant_token")
	assert_true(result.find("Scale 25%") > -1,
		"Regular drop must still render")
	assert_true(result.find("(One-shot: Calibrant Token)") > -1,
		"one_shot_reward must append as (One-shot: <Title Case name>) — got: %s" % result)


func test_format_drops_handles_null_one_shot() -> void:
	# Most monsters have one_shot_reward = null. Must NOT render any
	# (One-shot:) suffix for those — would be visual noise.
	var script = load(BESTIARY_MENU_PATH)
	var menu = script.new()
	add_child_autofree(menu)
	var result: String = menu._format_drops([{"item": "bone", "chance": 0.5}], null)
	assert_false(result.find("One-shot") > -1,
		"null one_shot_reward must NOT render a (One-shot:) suffix")
