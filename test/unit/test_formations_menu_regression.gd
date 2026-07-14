extends GutTest

## Formations reference page (2026-07-09): group attacks are a headline
## system whose requirements were only discoverable by accident. Pins the
## menu wiring, the live party-qualification read, and extends the
## shadow_strike defense-truth pin to the FORMATIONS tooltip (the third
## place the "ignores defense" lie lived).

const MenuScript := preload("res://src/ui/FormationsMenu.gd")


func test_overworld_menu_wires_formations() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_true("\"formations\", \"label\": \"Formations\"" in src, "menu entry exists")
	assert_true("func _open_formations" in src, "opener exists")
	assert_true("formations.party = party" in src, "party handed to the page (live ✓ marks)")


func test_party_qualification_reads_live_jobs() -> void:
	var menu = MenuScript.new()
	autofree(menu)
	var fighter := Combatant.new()
	add_child_autofree(fighter)
	fighter.initialize({"name": "F", "max_hp": 10, "max_mp": 5, "attack": 5, "defense": 5, "magic": 5, "speed": 5})
	JobSystem.assign_job(fighter, "fighter")
	var rogue := Combatant.new()
	add_child_autofree(rogue)
	rogue.initialize({"name": "R", "max_hp": 10, "max_mp": 5, "attack": 5, "defense": 5, "magic": 5, "speed": 5})
	JobSystem.assign_job(rogue, "rogue")
	menu.party = [fighter, rogue]
	var jobs: Array = menu._party_job_ids()
	assert_true("fighter" in jobs and "rogue" in jobs, "live party jobs read")
	assert_eq(jobs.size(), 2, "no duplicates or ghosts")
	menu.party = []
	assert_eq(menu._party_job_ids().size(), 0, "empty party -> no jobs, no crash")


func test_formations_data_shape_holds() -> void:
	var formations: Array = MenuScript.FORMATIONS
	assert_eq(formations.size(), 6, "six formation specials")
	for f in formations:
		assert_true(f.has("name") and f.has("tooltip") and f.has("required_jobs") and f.has("ap_cost"),
			"formation %s carries the fields the page renders" % f.get("id", "?"))


func test_no_formation_tooltip_claims_defense_ignored() -> void:
	# Third home of the lie (after the BM log + HBR log, fixed v3.33.47):
	# shadow_strike's FORMATIONS tooltip said "ignores defense" while
	# take_damage applies it in full.
	for f in MenuScript.FORMATIONS:
		var tip := str(f.get("tooltip", "")).to_lower()
		assert_false("ignores defense" in tip or "defense ignored" in tip,
			"formation '%s' tooltip must not claim defense bypass (take_damage applies it)" % f.get("id", "?"))
