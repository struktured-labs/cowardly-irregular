extends GutTest

## tick 469: jobs.json speculator.volatility_access now actually
## bumps the starting volatility band by one tier when any party
## member has Speculator as their primary OR secondary job.
##
## Pre-tick speculator authored:
##   volatility_access: true
## but no code read the field. The Speculator's market_sense
## passive scales damage with the volatility band, but with no
## way to access higher bands, the Speculator's "embraces chaos"
## fantasy never landed.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make_with_job(name_str: String, job_id: String, secondary: String = "") -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	if JobSystem != null:
		c.job = JobSystem.get_job(job_id)
	if secondary != "":
		c.secondary_job_id = secondary
	return c


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _party_has_volatility_access"),
		"BattleManager must declare _party_has_volatility_access helper")
	# Pin the data field read.
	assert_true(src.contains("bool(job_data.get(\"volatility_access\", false))"),
		"helper must read volatility_access from the job data")


func test_helper_scans_both_job_slots() -> void:
	# Pin that BOTH primary (member.job["id"]) and secondary
	# (member.secondary_job_id) are scanned.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _party_has_volatility_access")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("member.job is Dictionary") and body.contains("secondary_job_id\" in member"),
		"helper must check both primary job dict AND secondary_job_id field")


func test_start_battle_consults_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# The hook lives right after volatility.reset_battle().
	var idx: int = src.find("volatility.reset_battle()")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("_party_has_volatility_access()"),
		"start_battle must consult _party_has_volatility_access after reset_battle")
	assert_true(window.contains("volatility.shift_band(1)"),
		"a positive check must bump the band by exactly 1 (no compound)")


func test_data_still_authors_volatility_access() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/jobs.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("speculator"))
	assert_true(bool(data["speculator"].get("volatility_access", false)),
		"speculator must still author volatility_access = true")


func test_runtime_no_speculator_helper_false() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c: Combatant = _make_with_job("Fighter", "fighter")
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [c]
	bm.player_party = party
	assert_false(bm._party_has_volatility_access(),
		"no-Speculator party must return false")
	# Restore.
	var restore: Array[Combatant] = []
	for x in prior_party:
		if x is Combatant:
			restore.append(x)
	bm.player_party = restore


func test_runtime_speculator_primary_true() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	if JobSystem == null or not JobSystem.jobs.has("speculator"):
		pending("speculator job required")
		return
	var c: Combatant = _make_with_job("Spec", "speculator")
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [c]
	bm.player_party = party
	assert_true(bm._party_has_volatility_access(),
		"speculator primary must return true")
	# Restore.
	var restore: Array[Combatant] = []
	for x in prior_party:
		if x is Combatant:
			restore.append(x)
	bm.player_party = restore


func test_runtime_speculator_secondary_true() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	if JobSystem == null or not JobSystem.jobs.has("speculator"):
		pending("speculator job required")
		return
	var c: Combatant = _make_with_job("FS", "fighter", "speculator")
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [c]
	bm.player_party = party
	assert_true(bm._party_has_volatility_access(),
		"speculator secondary must also return true (dual-class)")
	# Restore.
	var restore: Array[Combatant] = []
	for x in prior_party:
		if x is Combatant:
			restore.append(x)
	bm.player_party = restore
