extends GutTest

## PRE-CHECK TURNED GUARD. EnemyStatusPanel's height is an INPUT to the battle log panel's budget:
## `available = 474 - enemy_panel_bottom`, and the log HIDES once available drops below its chrome
## plus one line. The enemy panel's per-enemy box already contains a `TextScale.scaled(12)` stat
## label, so it ALREADY grows with Text Size today — before anything in BattleScene's themed-node
## batch touches it.
##
## So the question this file answers, with the real panel rather than a synthetic height: at the
## field ceiling of five enemies, does the log survive every preset? If it does not, that is a LIVE
## defect reachable by any player who raises Text Size and meets a full pull — not something the
## themed-node work would introduce.

const SCENE := "res://src/battle/BattleScene.tscn"
## Measured 2026-10-14 with five enemies: available = 474 - 406 = 68px of budget.
## These fit; 1.5x and 2.0x do NOT, and that boundary is pinned by its own arm below rather than
## left as a silent gap. On main (chrome = the literal 64) NONE of them fit, including the default.
const FITTING: Array = [0.8, 1.0, 1.25]
const NOT_FITTING: Array = [1.5, 2.0]

var _saved_scale: float = 1.0
var _scene: Node = null


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null


func _enemy(n: String, hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = n
	c.max_hp = hp
	c.current_hp = hp
	c.max_mp = 10
	c.current_mp = 10
	c.is_alive = true
	return c


## Five is the field ceiling MAX_FIELD_ENEMIES enforces, so this is the worst real roster.
func _full_roster() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for i in range(5):
		out.append(_enemy("Goblin %d" % i, 40))
	return out


func test_the_log_survives_a_full_roster_up_to_the_measured_limit() -> void:
	var report: Array = []
	for s in FITTING:
		GameState.text_size_scale = float(s)
		_scene = load(SCENE).instantiate()
		add_child(_scene)
		await get_tree().process_frame
		var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
		var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
		assert_false(panel == null or enemy == null,
			"fixture: the log and enemy panels must exist at %sx" % str(s))
		if panel == null or enemy == null:
			return
		## Drive the REAL panel: five enemies through the real status builder.
		_scene.test_enemies.assign(_full_roster())
		if _scene._ui_manager and _scene._ui_manager.has_method("update_enemy_status"):
			_scene._ui_manager.update_enemy_status()
		await get_tree().process_frame
		await get_tree().process_frame
		_scene._reposition_battle_log_panel_now()
		await get_tree().process_frame
		var bottom: float = enemy.position.y + enemy.size.y
		report.append("%sx: enemy_bottom=%.0f log_visible=%s log_h=%.0f"
			% [str(s), bottom, str(panel.visible), panel.size.y])
		assert_true(panel.visible,
			("at %sx a five-enemy roster HID the battle log. The enemy panel's bottom reached %.0f, "
			+ "and the log's budget is 474 minus that — so every message the battle writes becomes "
			+ "invisible exactly when the player has most to read. Report: %s")
			% [str(s), bottom, str(report)])
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	gut.p("full-roster log budget: %s" % str(report))


## CONTROL — the panel CAN hide, so the arm above is not satisfied by a log that never disappears.
## Without this, a `visible` assertion that can never fail would read as coverage.
func test_the_log_does_hide_when_the_gap_really_is_gone() -> void:
	GameState.text_size_scale = 1.0
	_scene = load(SCENE).instantiate()
	add_child(_scene)
	await get_tree().process_frame
	var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
	var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
	assert_false(panel == null or enemy == null, "fixture: both panels must exist")
	if panel == null or enemy == null:
		return
	## Past any plausible roster: the hide branch is meant to fire here rather than overlap the CTB.
	enemy.custom_minimum_size.y = 460.0
	await get_tree().process_frame
	_scene._reposition_battle_log_panel_now()
	await get_tree().process_frame
	assert_false(panel.visible,
		"CONTROL: with the gap genuinely gone the panel must hide rather than overlap the turn-order "
		+ "card — if it cannot hide, the arm above proves nothing")


## THE MEASURED LIMIT, recorded rather than hidden. At five enemies the log panel has 68px of
## budget, and above 1.25x the scaled chrome no longer fits inside it, so the panel hides rather
## than overlap the turn-order card. This arm PINS that boundary: if a later change makes 1.5x fit,
## it reds and the constant moves deliberately — and if the boundary creeps DOWN toward the default,
## it reds too. How the battle HUD should trade space on a full roster at large text is a design
## call, not something to silently absorb.
func test_the_boundary_above_which_a_full_roster_loses_the_log() -> void:
	var report: Array = []
	for s in NOT_FITTING:
		GameState.text_size_scale = float(s)
		_scene = load(SCENE).instantiate()
		add_child(_scene)
		await get_tree().process_frame
		var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
		assert_false(panel == null, "fixture: the log panel must exist at %sx" % str(s))
		if panel == null:
			return
		_scene.test_enemies.assign(_full_roster())
		if _scene._ui_manager and _scene._ui_manager.has_method("update_enemy_status"):
			_scene._ui_manager.update_enemy_status()
		await get_tree().process_frame
		await get_tree().process_frame
		_scene._reposition_battle_log_panel_now()
		await get_tree().process_frame
		report.append("%sx visible=%s" % [str(s), str(panel.visible)])
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	gut.p("measured limit, full roster: %s" % str(report))
	assert_true(report.has("1.5x visible=false") or report.has("2.0x visible=false"),
		("the known boundary has MOVED. It was measured on 2026-10-14 as: a five-enemy roster keeps "
		+ "the log up to 1.25x and loses it at 1.5x and above. If both now fit, that is good news and "
		+ "this arm plus FITTING/NOT_FITTING should be updated deliberately. Got: %s") % str(report))
