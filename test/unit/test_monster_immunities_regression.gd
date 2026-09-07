extends GutTest

## tick 463: monsters.json top-level immunities list now actually
## gates physical attacks.
##
## Pre-tick monsters.json authored:
##   null_entity: immunities = ["physical"]
## ("The W6 abstract boss ignores physical entirely") but no code
## path read the field. Every physical attack and physical ability
## still hit null_entity for the standard damage formula.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _monster_immune_to_category"),
		"BattleManager must declare _monster_immune_to_category helper")
	# Pin the monsters.json field read.
	assert_true(src.contains("mdata.get(\"immunities\", [])"),
		"helper must read the top-level immunities list from monster data")
	# Pin generic membership check.
	assert_true(src.contains("category in immunities"),
		"helper must check membership generically (category-string based)")


func test_attack_consults_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_attack")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_monster_immune_to_category(actual_target, \"physical\")"),
		"_execute_attack must consult _monster_immune_to_category for physical")


func test_physical_ability_consults_helper() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_physical_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_monster_immune_to_category(target, \"physical\")"),
		"_execute_physical_ability must consult _monster_immune_to_category for physical")


func test_immunity_check_after_dodge() -> void:
	# Ordering: immunity check must come AFTER dodge so an
	# immune AND invisible target doesn't double-report.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_attack")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var dodge_idx: int = body.find("_target_dodges_physical(attacker, actual_target)")
	var immune_idx: int = body.find("_monster_immune_to_category(actual_target, \"physical\")")
	assert_gt(dodge_idx, -1)
	assert_gt(immune_idx, -1)
	assert_lt(dodge_idx, immune_idx,
		"immunity check must come AFTER the dodge check")


func test_data_still_authors_null_entity_immunity() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	if not data.has("null_entity"):
		pending("null_entity monster not in data — skipping data pin")
		return
	var immunities: Variant = data["null_entity"].get("immunities", [])
	assert_true(immunities is Array)
	assert_true("physical" in (immunities as Array),
		"null_entity must still author physical immunity")


func test_runtime_helper_false_for_player_combatant() -> void:
	# Players never have monster_type — must return false cleanly.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var c: Combatant = _make("PlayerLike")
	assert_false(bm._monster_immune_to_category(c, "physical"),
		"combatant without monster_type meta must return false")


func test_runtime_helper_true_for_authored_monster() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	if EncounterSystem == null or not (EncounterSystem.monster_database is Dictionary):
		pending("EncounterSystem monster_database not loaded")
		return
	# Find any monster with a physical immunity authored.
	var test_id: String = ""
	for mid in EncounterSystem.monster_database.keys():
		var mdata: Dictionary = EncounterSystem.monster_database[mid]
		var imm: Variant = mdata.get("immunities", [])
		if imm is Array and "physical" in (imm as Array):
			test_id = str(mid)
			break
	if test_id == "":
		pending("no monster authors physical immunity in monster_database")
		return
	var m: Combatant = _make("ImmuneMonster")
	m.set_meta("monster_type", test_id)
	assert_true(bm._monster_immune_to_category(m, "physical"),
		"monster with authored physical immunity must report true")


func test_runtime_helper_non_immune_category() -> void:
	# A monster immune to physical must NOT be reported immune to magic.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	if EncounterSystem == null or not (EncounterSystem.monster_database is Dictionary):
		pending("EncounterSystem monster_database not loaded")
		return
	var test_id: String = ""
	for mid in EncounterSystem.monster_database.keys():
		var mdata: Dictionary = EncounterSystem.monster_database[mid]
		var imm: Variant = mdata.get("immunities", [])
		if imm is Array and "physical" in (imm as Array) and not ("magic" in (imm as Array)):
			test_id = str(mid)
			break
	if test_id == "":
		pending("no monster authors only-physical immunity")
		return
	var m: Combatant = _make("PartialImmune")
	m.set_meta("monster_type", test_id)
	assert_false(bm._monster_immune_to_category(m, "magic"),
		"physical-immune monster must NOT be reported magic-immune — helper must respect category")
