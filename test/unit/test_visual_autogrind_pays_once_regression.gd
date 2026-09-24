extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## A visual autogrind fight paid twice. BattleManager.end_battle grants EXP and gold on every
## victory, then GameLoop hands the same totals to AutogrindSystem.on_battle_victory, which
## grants them again. Ludicrous speed never enters end_battle, so it paid once. Watching the
## fight paid double — and the console still announced the single figure.
##
## The battle engine records the award and, while a grind settler is attached, leaves the
## wallet and the job EXP alone. on_battle_victory remains the one payer for that fight.
## A normal battle, a stopped grind, and a headless fight keep the payer they already had.

var _ag: Dictionary
var _gold: int
var _exp_mult: Variant
var _gold_mult: Variant
var _bestiary: Dictionary
var _bm: Dictionary
var _host: Node

const _BESTIARY_KEYS: Array[String] = [
	"seen_monsters", "seen_monsters_last_location", "defeated_monsters", "defeated_counts",
]


func before_each() -> void:
	_ag = AutogrindState.snapshot_and_isolate()
	_gold = GameState.party_gold
	_exp_mult = GameState.game_constants.get("exp_multiplier", null)
	_gold_mult = GameState.game_constants.get("gold_multiplier", null)
	GameState.game_constants["exp_multiplier"] = 1.0
	GameState.game_constants["gold_multiplier"] = 1.0
	_bestiary = {}
	for k in _BESTIARY_KEYS:
		var v: Variant = GameState.game_constants.get(k, null)
		_bestiary[k] = (v as Dictionary).duplicate(true) if v is Dictionary else null
	_bm = {
		"defer": BattleManager.defer_victory_payout,
		"phase": BattleManager._first_damage_phase,
		"one_shot": BattleManager._one_shot_achieved,
		"full_auto": BattleManager._full_autobattle,
		"auto_turns": BattleManager._autobattle_player_turns,
		"state": BattleManager.current_state,
		"players": BattleManager.player_party.duplicate(),
		"enemies": BattleManager.enemy_party.duplicate(),
		"all": BattleManager.all_combatants.duplicate(),
	}
	AutogrindSystem.current_region_id = ""
	AutogrindSystem.is_grinding = false
	AutogrindSystem._grind_stats["elapsed_seconds"] = 0.0
	AutogrindSystem._grind_stats["start_time"] = 0.0
	_host = null


func after_each() -> void:
	if _host != null and is_instance_valid(_host):
		if _host.has_method("_on_autogrind_battle_ended") and BattleManager.battle_ended.is_connected(_host._on_autogrind_battle_ended):
			BattleManager.battle_ended.disconnect(_host._on_autogrind_battle_ended)
		_host.free()
		_host = null
	BattleManager.defer_victory_payout = bool(_bm["defer"])
	BattleManager._first_damage_phase = int(_bm["phase"])
	BattleManager._one_shot_achieved = bool(_bm["one_shot"])
	BattleManager._full_autobattle = bool(_bm["full_auto"])
	BattleManager._autobattle_player_turns = int(_bm["auto_turns"])
	BattleManager.current_state = int(_bm["state"])
	var players: Array[Combatant] = []
	var enemies: Array[Combatant] = []
	var everyone: Array[Combatant] = []
	for p in _bm["players"]:
		players.append(p)
	for e in _bm["enemies"]:
		enemies.append(e)
	for c in _bm["all"]:
		everyone.append(c)
	BattleManager.player_party = players
	BattleManager.enemy_party = enemies
	BattleManager.all_combatants = everyone
	BattleManager._ko_this_battle.clear()
	GameState.party_gold = _gold
	if _exp_mult == null:
		GameState.game_constants.erase("exp_multiplier")
	else:
		GameState.game_constants["exp_multiplier"] = _exp_mult
	if _gold_mult == null:
		GameState.game_constants.erase("gold_multiplier")
	else:
		GameState.game_constants["gold_multiplier"] = _gold_mult
	for k in _BESTIARY_KEYS:
		if _bestiary[k] == null:
			GameState.game_constants.erase(k)
		else:
			GameState.game_constants[k] = _bestiary[k]
	AutogrindState.restore(_ag)


class _GrindHost extends Node:
	var _is_autogrinding: bool = false
	var _autogrind_controller: Node = null
	func _on_autogrind_battle_ended(_victory: bool) -> void:
		pass


class _Ctrl extends Node:
	var _current_battle_is_meta_boss: bool = false


func _hero() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Grinder"
	c.job_level = 40
	c.job_exp = 0
	c.is_alive = true
	c.current_hp = c.max_hp
	add_child_autofree(c)
	return c


func _slime() -> Combatant:
	var e := Combatant.new()
	e.combatant_name = "Slime"
	e.is_alive = false
	e.set_meta("monster_type", "slime")
	add_child_autofree(e)
	return e


## Run end_battle the way a finished fight does, and return the award it recorded.
func _finish(hero: Combatant, defer: bool) -> Dictionary:
	var slime := _slime()
	BattleManager._first_damage_phase = -1
	BattleManager._one_shot_achieved = false
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	BattleManager._ko_this_battle.clear()
	BattleManager.player_party = [hero] as Array[Combatant]
	BattleManager.enemy_party = [slime] as Array[Combatant]
	BattleManager.all_combatants = [hero, slime] as Array[Combatant]
	BattleManager.defer_victory_payout = defer
	var exp0: int = hero.job_exp
	var gold0: int = GameState.party_gold
	BattleManager.end_battle(true)
	var results: Dictionary = BattleManager.get_battle_results()
	var recorded: int = int((results["char_results"] as Array)[0]["exp_gained"])
	var gold: int = int(results["total_gold"])
	return {"exp0": exp0, "gold0": gold0, "recorded": recorded, "gold": gold}


func test_a_visual_grind_pays_exp_and_gold_once() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"control: this arm honors the flag only when no GameLoop is in the tree")
	var hero := _hero()
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var paid: Dictionary = _finish(hero, true)
	assert_gt(int(paid["recorded"]), 0, "control: the slime must be worth EXP, or this arm measured nothing")
	assert_gt(int(paid["gold"]), 0, "control: the slime must be worth gold, or the wallet arm is vacuous")
	assert_eq(hero.job_exp, int(paid["exp0"]),
		"end_battle already paid the EXP a visual grind's settler is about to pay")
	assert_eq(GameState.party_gold, int(paid["gold0"]),
		"end_battle already paid the gold a visual grind's settler is about to pay")
	AutogrindSystem.on_battle_victory(int(paid["recorded"]), {"gold": int(paid["gold"])})
	assert_eq(hero.job_exp - int(paid["exp0"]), int(paid["recorded"]),
		"visual autogrind granted job EXP twice — once in end_battle and again in on_battle_victory. Got %d, the battle was worth %d" % [hero.job_exp - int(paid["exp0"]), int(paid["recorded"])])
	assert_eq(GameState.party_gold - int(paid["gold0"]), int(paid["gold"]),
		"visual autogrind granted gold twice — once in end_battle and again in on_battle_victory. Got %d, the battle was worth %d" % [GameState.party_gold - int(paid["gold0"]), int(paid["gold"])])


func test_a_normal_battle_still_pays() -> void:
	var hero := _hero()
	var paid: Dictionary = _finish(hero, false)
	assert_eq(hero.job_exp - int(paid["exp0"]), int(paid["recorded"]),
		"a battle with no grind settler must still grant its EXP")
	assert_eq(GameState.party_gold - int(paid["gold0"]), int(paid["gold"]),
		"a battle with no grind settler must still grant its gold")


func test_the_headless_settler_still_pays_on_its_own() -> void:
	## Ludicrous speed never calls end_battle. Removing the grant from on_battle_victory
	## would zero that mode while fixing the visual double.
	var hero := _hero()
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var exp0: int = hero.job_exp
	var gold0: int = GameState.party_gold
	AutogrindSystem.on_battle_victory(15, {"gold": 10})
	assert_eq(hero.job_exp - exp0, 15, "a headless victory must still grant its EXP through on_battle_victory")
	assert_eq(GameState.party_gold - gold0, 10, "a headless victory must still grant its gold through on_battle_victory")


func test_a_stopped_grind_is_paid_by_the_battle() -> void:
	## Stopping mid-fight disconnects the settler. Deferring anyway would drop the fight's rewards.
	_host = _GrindHost.new()
	_host.name = "GameLoop"
	_host._is_autogrinding = false
	get_tree().root.add_child(_host)
	assert_eq(get_tree().root.get_node_or_null("GameLoop"), _host, "control: the stub must be the GameLoop the predicate reads")
	BattleManager.battle_ended.connect(_host._on_autogrind_battle_ended)
	var hero := _hero()
	var paid: Dictionary = _finish(hero, true)
	assert_eq(hero.job_exp - int(paid["exp0"]), int(paid["recorded"]),
		"a grind that has already stopped must still receive the battle's EXP from end_battle")
	assert_eq(GameState.party_gold - int(paid["gold0"]), int(paid["gold"]),
		"a grind that has already stopped must still receive the battle's gold from end_battle")


func test_an_attached_settler_defers_and_then_pays_once() -> void:
	_host = _GrindHost.new()
	_host.name = "GameLoop"
	_host._is_autogrinding = true
	var ctrl := _Ctrl.new()
	ctrl._current_battle_is_meta_boss = false
	_host._autogrind_controller = ctrl
	_host.add_child(ctrl)
	get_tree().root.add_child(_host)
	BattleManager.battle_ended.connect(_host._on_autogrind_battle_ended)
	var hero := _hero()
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var paid: Dictionary = _finish(hero, true)
	assert_eq(hero.job_exp, int(paid["exp0"]),
		"an attached grind settler must not have end_battle pay EXP it will pay itself")
	AutogrindSystem.on_battle_victory(int(paid["recorded"]), {"gold": int(paid["gold"])})
	assert_eq(hero.job_exp - int(paid["exp0"]), int(paid["recorded"]),
		"the settler must pay the deferred award exactly once")
	assert_eq(GameState.party_gold - int(paid["gold0"]), int(paid["gold"]),
		"the settler must pay the deferred gold exactly once")


func test_the_visual_path_defers_unless_the_fight_is_a_meta_boss() -> void:
	var gl: String = GdSource.code_of("res://src/GameLoop.gd")
	assert_true(gl.contains("func _start_autogrind_battle"), "control: GameLoop source must survive the strip")
	var at: int = gl.find("func _start_autogrind_battle")
	var stop: int = gl.find("\nfunc ", at + 20)
	var body: String = gl.substr(at, (stop - at) if stop > 0 else -1)
	var add_at: int = body.find("add_child(battle_scene)")
	var flag_at: int = body.find("defer_victory_payout = not meta_boss_battle")
	var conn_at: int = body.find("battle_ended.connect(_on_autogrind_battle_ended")
	var await_at: int = body.find("await get_tree().process_frame")
	assert_gt(add_at, -1, "control: the battle scene must still be added in this function")
	assert_gt(flag_at, add_at,
		"defer_victory_payout must be set after the scene is in the tree — start_battle clears a leftover flag, and setting it earlier is wiped")
	assert_gt(conn_at, add_at, "the settler must be connected after the scene exists")
	assert_lt(conn_at, await_at,
		"the settler must be connected before the first resumed frame, or a one-action fight ends with nobody to pay the deferred award")
	var stopped: int = gl.find("func _stop_autogrind")
	var stopped_end: int = gl.find("\nfunc ", stopped + 20)
	var stop_body: String = gl.substr(stopped, (stopped_end - stopped) if stopped_end > 0 else -1)
	assert_true(stop_body.contains("defer_victory_payout = false"),
		"stopping mid-fight must clear the defer flag, or end_battle skips a payout the disconnected settler will never make")
	var done: int = gl.find("func _on_grind_complete")
	var done_end: int = gl.find("\nfunc ", done + 20)
	var done_body: String = gl.substr(done, (done_end - done) if done_end > 0 else -1)
	assert_true(done_body.contains("defer_victory_payout = false"),
		"a grind that ends itself must clear the defer flag too — this path does not go through _stop_autogrind")
