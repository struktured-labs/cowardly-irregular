extends GutTest

## struktured cap 2026-07-16: "portraits are wrong in the save menu still,
## its all fighter all the time." Combatant.to_dict stores job as a STRING
## id, but _get_party_summary only read the {id,name} DICT shape — the
## else-arm stamped every member job_id "fighter", and that wrong summary
## was BAKED into the save file's metadata. Fix: shape-tolerant summarizer
## + get_save_info rebuilds the preview from the file's player_party so
## pre-fix saves display correctly without a rewrite.


func test_combatant_shape_job_as_string() -> void:
	var party := [
		{"name": "Aria", "job": "bard", "job_id": "bard", "job_level": 7, "current_hp": 40, "max_hp": 55},
		{"name": "Nyx", "job": "rogue", "job_id": "rogue", "job_level": 6, "current_hp": 39, "max_hp": 50},
	]
	var s: Array = SaveSystem.summarize_party(party)
	assert_eq(s[0]["job_id"], "bard", "string-shaped job must resolve (the all-fighter bug)")
	assert_eq(s[1]["job_id"], "rogue")
	assert_eq(s[0]["job"], "Bard", "display name derives from the id when no dict name exists")
	assert_eq(s[0]["level"], 7)


func test_legacy_dict_shape_still_resolves() -> void:
	var party := [{"name": "Vex", "job": {"id": "mage", "name": "Mage"}, "job_level": 5}]
	var s: Array = SaveSystem.summarize_party(party)
	assert_eq(s[0]["job_id"], "mage")
	assert_eq(s[0]["job"], "Mage")


func test_missing_job_falls_back_to_fighter() -> void:
	var s: Array = SaveSystem.summarize_party([{"name": "???"}])
	assert_eq(s[0]["job_id"], "fighter")


func test_non_dict_entries_skipped() -> void:
	var s: Array = SaveSystem.summarize_party([null, "junk", {"name": "Ok", "job_id": "cleric"}])
	assert_eq(s.size(), 1)
	assert_eq(s[0]["job_id"], "cleric")


func test_get_save_info_rebuilds_summary_from_party() -> void:
	# Source pin: baked metadata can't be trusted (pre-fix saves hold the
	# all-fighter summary) — the read path must rebuild from player_party.
	var src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	var i := src.find("func get_save_info")
	assert_gt(i, -1)
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("summarize_party(party)" in body,
		"get_save_info must rebuild party_summary from the save's player_party — the baked summary is wrong in every pre-fix save")
	assert_true("player_party" in body)
