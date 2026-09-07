extends GutTest

## Queue #3 (cowir-main msg 2147): the execution-stall watchdog covered
## EXECUTION_PHASE / PROCESSING_ACTION only. A wedge in ENEMY_SELECTING —
## most likely the LLM boss intent await hanging on network — left the
## battle frozen. Watchdog now also watches ENEMY_SELECTING; recovery
## queues a basic attack (enemies don't defer, per the AI convention at
## _process_ai_selection) on the first alive player and advances the turn.

const BM_PATH: String = "res://src/battle/BattleManager.gd"


func _bm() -> Node:
	var bm: Node = load(BM_PATH).new()
	add_child_autofree(bm)
	return bm


func _pc(name_str: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name_str
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	c.attack = 10
	c.defense = 5
	c.speed = 10
	c.job = {"id": "fighter"}
	return c


## ── State coverage ──────────────────────────────────────────────────────

func test_watched_states_include_enemy_selecting() -> void:
	# Textual pin — the _process guard used to gate on EXECUTION_PHASE /
	# PROCESSING_ACTION only. Adding ENEMY_SELECTING here is the whole
	# point of the ticket; regressing means silence in the wedge case.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "BattleState.ENEMY_SELECTING",
		"ENEMY_SELECTING must be in the watched-states list")
	assert_string_contains(src, "BattleState.EXECUTION_PHASE",
		"EXECUTION_PHASE stays watched")
	assert_string_contains(src, "BattleState.PROCESSING_ACTION",
		"PROCESSING_ACTION stays watched")


func test_player_selecting_is_deliberately_not_watched() -> void:
	# Player-selecting is legit thinking time; watching it would false-
	# trigger on any thoughtful play. Pin the deliberate omission.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var proc_idx: int = src.find("func _process(_delta:")
	assert_gt(proc_idx, -1)
	var body: String = src.substr(proc_idx, 1500)
	assert_false(body.find("BattleState.PLAYER_SELECTING") > -1,
		"_process must NOT reference PLAYER_SELECTING — a thoughtful player is not a stall")


## ── Recovery contract ───────────────────────────────────────────────────

func test_recover_queues_attack_and_advances_selection() -> void:
	var bm := _bm()
	var enemy := _pc("Rat")
	var pc1 := _pc("Hero")
	var pc2 := _pc("Cleric")
	# Runtime state resembling a wedged ENEMY_SELECTING mid-selection.
	bm.enemy_party = [enemy] as Array[Combatant]
	bm.player_party = [pc1, pc2] as Array[Combatant]
	bm.selection_order = [enemy, pc1, pc2] as Array[Combatant]
	bm.selection_index = 0
	bm.current_combatant = enemy
	bm.current_state = bm.BattleState.ENEMY_SELECTING
	# Call the recovery helper directly (watchdog would fire this same
	# method after the stall threshold).
	bm._recover_enemy_selection_stall()
	assert_eq(bm.pending_actions.size(), 1,
		"recovery must queue exactly one action so the enemy still gets a turn")
	var act: Dictionary = bm.pending_actions[0]
	assert_eq(str(act.get("type", "")), "attack",
		"enemies never defer — recovery must be an attack (see _process_ai_selection convention)")
	assert_eq(act.get("combatant", null), enemy,
		"the queued action must belong to the wedged combatant")
	# selection_index moves forward on _end_selection_turn.
	assert_eq(bm.selection_index, 1,
		"_end_selection_turn was called → selection order advanced")
	enemy.free(); pc1.free(); pc2.free()


func test_recover_targets_first_alive_player() -> void:
	var bm := _bm()
	var enemy := _pc("Bat")
	var dead_pc := _pc("Fallen"); dead_pc.is_alive = false
	var alive_pc := _pc("Alive")
	bm.enemy_party = [enemy] as Array[Combatant]
	bm.player_party = [dead_pc, alive_pc] as Array[Combatant]
	bm.selection_order = [enemy] as Array[Combatant]
	bm.selection_index = 0
	bm.current_combatant = enemy
	bm.current_state = bm.BattleState.ENEMY_SELECTING
	bm._recover_enemy_selection_stall()
	assert_eq(bm.pending_actions.size(), 1)
	assert_eq(bm.pending_actions[0].get("target", null), alive_pc,
		"recovery must skip KO'd players and pick the first alive one")
	enemy.free(); dead_pc.free(); alive_pc.free()


func test_recover_is_a_noop_when_no_alive_players() -> void:
	var bm := _bm()
	var enemy := _pc("Slime")
	var ko := _pc("KO"); ko.is_alive = false
	bm.enemy_party = [enemy] as Array[Combatant]
	bm.player_party = [ko] as Array[Combatant]
	bm.selection_order = [enemy] as Array[Combatant]
	bm.selection_index = 0
	bm.current_combatant = enemy
	bm.current_state = bm.BattleState.ENEMY_SELECTING
	bm._recover_enemy_selection_stall()
	assert_eq(bm.pending_actions.size(), 0,
		"no viable target → no attack queued (battle is presumably about to end anyway)")
	# NB: not asserting on selection_index here — _end_selection_turn's
	# recursive _process_next_selection call may itself hit the victory
	# check and reset the index. What matters is we don't hard-loop.
	enemy.free(); ko.free()


func test_recover_short_circuits_when_current_combatant_is_gone() -> void:
	var bm := _bm()
	var pc := _pc("Hero")
	bm.player_party = [pc] as Array[Combatant]
	bm.enemy_party = [] as Array[Combatant]
	bm.selection_order = [pc] as Array[Combatant]
	bm.selection_index = 0
	bm.current_combatant = null
	bm.current_state = bm.BattleState.ENEMY_SELECTING
	bm._recover_enemy_selection_stall()
	assert_eq(bm.pending_actions.size(), 0,
		"null combatant → no queued action")
	pc.free()


## ── Diagnostic message includes state name ──────────────────────────────

func test_push_error_message_names_the_wedged_state() -> void:
	# Post-fix push_error prefixes state name for triage (execution vs
	# enemy_selecting are different failure modes worth distinguishing).
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "BattleState.keys()[current_state]",
		"diagnostic message must name the wedged state so triage isn't guesswork")
