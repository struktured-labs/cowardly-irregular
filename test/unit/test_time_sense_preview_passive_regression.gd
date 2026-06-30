extends GutTest

## tick 451: time_sense passive's meta_effects.preview_enemy_actions
## now actually emits a battle-log preview of the enemies' queued
## actions before execution.
##
## Pre-fix passives.json authored:
##   time_sense: {meta_effects: {preview_enemy_actions: true,
##                                preview_turns: 1}}
##   description: "Preview enemy actions 1 turn ahead"
## but no code path read either field. Players equipped Time Sense
## and got no intel — the "preview 1 turn ahead" promise was
## decoration.

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


func test_gate_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _party_wants_action_preview"),
		"BattleManager must declare _party_wants_action_preview helper")
	assert_true(src.contains("me.get(\"preview_enemy_actions\", false)"),
		"helper must read preview_enemy_actions from passive meta_effects")


func test_emit_helper_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("func _emit_enemy_action_preview"),
		"BattleManager must declare _emit_enemy_action_preview helper")
	assert_true(src.contains("[Time Sense]"),
		"emit must label the line with a [Time Sense] badge")


func test_execution_phase_consults_gate() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _start_execution_phase")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_wants_action_preview()"),
		"_start_execution_phase must consult the gate")
	assert_true(body.contains("_emit_enemy_action_preview()"),
		"_start_execution_phase must call the emit helper when the gate is true")


func test_emit_filters_to_enemies() -> void:
	# Pin that the emit skips player_party entries — preview is
	# about enemies, not the player's own queue.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _emit_enemy_action_preview")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("c in player_party"),
		"emit must skip combatants in player_party (preview is for enemies)")


func test_data_still_authors_preview() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("time_sense"))
	var me: Variant = data["time_sense"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_true(bool(me.get("preview_enemy_actions", false)),
		"time_sense must still author preview_enemy_actions = true")


func test_runtime_no_passive_gate_false() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var hero: Combatant = _make("Hero")
	hero.equipped_passives = []
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [hero]
	bm.player_party = party
	assert_false(bm._party_wants_action_preview(),
		"vanilla party must NOT request preview — fix must be passive-gated")
	# Restore.
	var restore: Array[Combatant] = []
	for c in prior_party:
		if c is Combatant:
			restore.append(c)
	bm.player_party = restore


func test_runtime_with_passive_gate_true() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("time_sense"):
		pending("time_sense passive required")
		return
	var hero: Combatant = _make("Seer")
	hero.equipped_passives = ["time_sense"]
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [hero]
	bm.player_party = party
	assert_true(bm._party_wants_action_preview(),
		"time_sense-equipped party must request the preview")
	var restore: Array[Combatant] = []
	for c in prior_party:
		if c is Combatant:
			restore.append(c)
	bm.player_party = restore


func test_runtime_dead_member_no_preview() -> void:
	# Edge case: a dead party member doesn't contribute. (Reading
	# passives off a dead member is benign but the gate's
	# `member.is_alive` check makes the intent explicit.)
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "BattleManager autoload must be present")
	if bm == null:
		return
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null or not ps.passives.has("time_sense"):
		pending("time_sense passive required")
		return
	var dead: Combatant = _make("Ghost")
	dead.equipped_passives = ["time_sense"]
	dead.current_hp = 0
	dead.is_alive = false
	var prior_party: Array = bm.player_party.duplicate()
	var party: Array[Combatant] = [dead]
	bm.player_party = party
	assert_false(bm._party_wants_action_preview(),
		"dead member's passive must not grant preview")
	var restore: Array[Combatant] = []
	for c in prior_party:
		if c is Combatant:
			restore.append(c)
	bm.player_party = restore
