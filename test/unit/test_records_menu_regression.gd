extends GutTest

## Records page (2026-07-09): the automation game grades your playthrough.
## Pins the menu wiring and that every row reads REAL state (not snapshots).

const MenuScript := preload("res://src/ui/RecordsMenu.gd")


func test_overworld_menu_wires_records() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_true("\"records\", \"label\": \"Records\"" in src, "menu entry exists")
	assert_true("func _open_records" in src, "opener exists")


func test_records_read_live_state() -> void:
	var menu = MenuScript.new()
	autofree(menu)
	var prev_battles: int = GameState.battles_won
	var prev_gold: int = GameState.party_gold
	var prev_marks = GameState.game_constants.get("cutscene_flag_fool_card_marks", null)
	GameState.battles_won = 137
	GameState.party_gold = 4242
	GameState.game_constants["cutscene_flag_fool_card_marks"] = 4

	var recs: Array = menu._collect_records()
	var by_name := {}
	for r in recs:
		by_name[r[0]] = r
	assert_eq(str(by_name["Battles Won"][1]), "137", "battles read live")
	assert_eq(str(by_name["Gold"][1]), "4242 G", "gold read live")
	assert_eq(str(by_name["Fool Card Marks"][1]), "4 / 5", "marks read live")
	assert_true("counting" in str(by_name["Fool Card Marks"][2]), "the card knows it's counting")
	assert_gt(recs.size(), 7, "the full record roster renders")
	# Calibration row (2026-07-11): game_complete's first player-facing consumer.
	assert_eq(str(by_name["Calibration"][1]), "IN PROGRESS", "pre-ending state reads IN PROGRESS")
	assert_true("uncalibrated" in str(by_name["Calibration"][2]), "pre-ending quip")
	GameState.game_constants["game_complete"] = true
	var recs2: Array = menu._collect_records()
	var cal2: Array = []
	for r in recs2:
		if str(r[0]) == "Calibration":
			cal2 = r
	assert_eq(str(cal2[1]), "COMPLETE", "post-ending state reads COMPLETE")
	assert_true("came back anyway" in str(cal2[2]), "post-ending quip")
	GameState.game_constants.erase("game_complete")

	GameState.battles_won = prev_battles
	GameState.party_gold = prev_gold
	if prev_marks == null:
		GameState.game_constants.erase("cutscene_flag_fool_card_marks")
	else:
		GameState.game_constants["cutscene_flag_fool_card_marks"] = prev_marks


func test_playtime_formats() -> void:
	var menu = MenuScript.new()
	autofree(menu)
	var prev: float = GameState.playtime_seconds
	GameState.playtime_seconds = 3725.0
	assert_eq(menu._fmt_playtime(), "1h 02m 05s", "h/m/s zero-padded")
	GameState.playtime_seconds = prev
