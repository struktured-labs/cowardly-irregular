extends RefCounted

## BattleScene from its .tscn so @onready paths resolve; a bare .new() logged 4450 "Node not found" in the .849 gate.

const SCENE_PATH := "res://src/battle/BattleScene.tscn"


## Real nodes, no auto battle: _start_test_battle writes the BattleManager autoload, and the bare script never reached it.
class Quiet extends "res://src/battle/BattleScene.gd":
	func _start_test_battle() -> void:
		pass


## script: a probe subclass to run instead (extend Quiet to stay quiet). live: run the real _start_test_battle.
static func build(script: Script = null, live: bool = false) -> Node:
	var scene: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	if script != null:
		scene.set_script(script)
	elif not live:
		scene.set_script(Quiet)
	return scene
