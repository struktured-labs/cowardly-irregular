extends GutTest

## tick 465: monsters.json top-level adaptation_speed field now
## actually overrides the global elemental-adaptation threshold.
##
## Pre-tick monsters.json authored:
##   adaptive_slime: adaptation_speed = 2
## paired with learns_from=["abilities","targets","ap_patterns"],
## but no code path read the field. The hardcoded
## _LEARNS_FROM_THRESHOLD = 3 applied to every learns_from monster
## — the slime's "I adapt quickly" gimmick was no quicker than any
## boss. After this tick, the slime gains its elemental resistance
## on the 2nd matching hit instead of the 3rd.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 1000, "max_mp": 50,
		"attack": 10, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_adaptation_helper_reads_field() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _maybe_apply_elemental_adaptation")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("data.has(\"adaptation_speed\")"),
		"_maybe_apply_elemental_adaptation must check the monster's adaptation_speed field")
	# Override gate: only used when authored, otherwise fall back.
	assert_true(body.contains("int(data.get(\"adaptation_speed\", _LEARNS_FROM_THRESHOLD))"),
		"adaptation_speed must override the threshold when authored, default to the const otherwise")


func test_threshold_min_clamped_at_1() -> void:
	# Pin the max(1, ...) clamp so a 0/negative authored value doesn't
	# divide-by-zero or auto-adapt on the first non-element hit.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _maybe_apply_elemental_adaptation")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("threshold = max(1, int("),
		"threshold must clamp at min 1 (zero/negative authoring would break the >= check)")


func test_data_still_authors_adaptation_speed() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	var found: bool = false
	for mid in data.keys():
		var entry: Dictionary = data[mid]
		if entry.has("adaptation_speed") and int(entry["adaptation_speed"]) > 0:
			found = true
			break
	assert_true(found,
		"monsters.json must still author adaptation_speed > 0 on at least one entry")


func test_runtime_adaptive_slime_adapts_in_2_hits() -> void:
	# End-to-end: a target with monster_type=adaptive_slime should
	# gain a fire resistance after 2 fire hits, not 3.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	if EncounterSystem == null or not (EncounterSystem.monster_database is Dictionary):
		pending("EncounterSystem monster_database not loaded")
		return
	# Find any monster that authors adaptation_speed.
	var slug: String = ""
	var slug_speed: int = 0
	for mid in EncounterSystem.monster_database.keys():
		var mdata: Dictionary = EncounterSystem.monster_database[mid]
		if mdata.has("adaptation_speed"):
			slug = str(mid)
			slug_speed = int(mdata["adaptation_speed"])
			break
	if slug == "":
		pending("no adaptation_speed monster in database")
		return
	var m: Combatant = _make("Slime")
	m.set_meta("monster_type", slug)
	# Each hit should NOT add resistance until count reaches the
	# authored adaptation_speed.
	for i in range(slug_speed - 1):
		bm._maybe_apply_elemental_adaptation(m, "fire")
		assert_false(m.get_meta("_learned_adaptation", false),
			"adaptation must NOT trigger before %d hits (got triggered at %d)" % [slug_speed, i + 1])
	# The N-th hit should trigger the adaptation.
	bm._maybe_apply_elemental_adaptation(m, "fire")
	assert_true(m.get_meta("_learned_adaptation", false),
		"adaptation must trigger on the %d-th hit when adaptation_speed=%d" % [slug_speed, slug_speed])
	assert_true("fire" in m.elemental_resistances,
		"adapting to fire must add 'fire' to elemental_resistances")


func test_runtime_non_authored_monster_keeps_default_3() -> void:
	# A learns_from monster WITHOUT adaptation_speed must still adapt
	# at the default threshold (3). Take 2 hits — no adapt yet.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	if EncounterSystem == null or not (EncounterSystem.monster_database is Dictionary):
		pending("EncounterSystem monster_database not loaded")
		return
	# Find a learns_from monster that DOES NOT author adaptation_speed.
	var slug: String = ""
	for mid in EncounterSystem.monster_database.keys():
		var mdata: Dictionary = EncounterSystem.monster_database[mid]
		var lf: Variant = mdata.get("learns_from", [])
		if not (lf is Array):
			continue
		var qualifies: bool = false
		for tag in lf:
			if str(tag) == "all" or str(tag) == "abilities":
				qualifies = true
				break
		if qualifies and not mdata.has("adaptation_speed"):
			slug = str(mid)
			break
	if slug == "":
		pending("no learns_from-without-adaptation_speed monster found")
		return
	var m: Combatant = _make("Default")
	m.set_meta("monster_type", slug)
	# 2 hits — no adapt.
	bm._maybe_apply_elemental_adaptation(m, "ice")
	bm._maybe_apply_elemental_adaptation(m, "ice")
	assert_false(m.get_meta("_learned_adaptation", false),
		"unauthored monster must still take 3 hits to adapt (default _LEARNS_FROM_THRESHOLD)")
	# 3rd hit — adapt.
	bm._maybe_apply_elemental_adaptation(m, "ice")
	assert_true(m.get_meta("_learned_adaptation", false),
		"3rd hit on unauthored monster must trigger default-threshold adaptation")
