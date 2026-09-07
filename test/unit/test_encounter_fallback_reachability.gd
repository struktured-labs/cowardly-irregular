extends GutTest

## Is OverworldController's out-of-tree randf() fallback (:139) REACHABLE in play?
## It runs only when `es == null`, which needs is_inside_tree()==false. Its sole
## caller is _on_player_moved, a signal handler subscribed in _ready() and
## unsubscribed in _exit_tree() — so the subscription, not the call, is the gate.

var _ctrl = null
var _player = null

func before_each() -> void:
	_player = preload("res://src/exploration/OverworldPlayer.gd").new()
	_ctrl = preload("res://src/exploration/OverworldController.gd").new()
	_ctrl.player = _player
	add_child_autofree(_player)
	add_child_autofree(_ctrl)

func test_handler_is_connected_while_in_tree() -> void:
	assert_true(_ctrl.is_inside_tree(), "CONTROL: controller is in the tree")
	assert_true(_player.moved.is_connected(_ctrl._on_player_moved),
		"CONTROL: _ready() connected the step handler — so a later false is a real reading")

func test_leaving_the_tree_disconnects_the_step_handler() -> void:
	var parent = _ctrl.get_parent()
	parent.remove_child(_ctrl)
	assert_false(_ctrl.is_inside_tree(), "controller is out of the tree")
	assert_false(_player.moved.is_connected(_ctrl._on_player_moved),
		"_exit_tree must disconnect: a still-subscribed out-of-tree controller would reach the randf() fallback, which reads NO EncounterSystem gate")
	parent.add_child(_ctrl)

func test_steps_emitted_out_of_tree_never_reach_the_controller() -> void:
	var parent = _ctrl.get_parent()
	_ctrl._encounter_rate = 1.0
	_ctrl.encounter_enabled = true
	parent.remove_child(_ctrl)
	var emitted = 0
	for i in range(200):
		_player.moved.emit(1)
		emitted += 1
	assert_eq(emitted, 200, "CONTROL: the emit loop actually ran")
	assert_false(_player.moved.is_connected(_ctrl._on_player_moved),
		"still unsubscribed after 200 steps at rate 1.0 with encounters enabled")
	parent.add_child(_ctrl)

func test_encounter_system_is_an_autoload_so_es_is_never_null_in_tree() -> void:
	var es = get_tree().root.get_node_or_null("EncounterSystem")
	assert_not_null(es, "EncounterSystem is an autoload (project.godot) — so in-tree, es is never null and the guarded path always wins")
