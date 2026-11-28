extends RefCounted

## BattleScene from its .tscn so @onready paths resolve; a bare .new() logged 4450 "Node not found" in the .849 gate.

const SCENE_PATH := "res://src/battle/BattleScene.tscn"


static func build(script: Script = null) -> Node:
	var scene: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	if script != null:
		scene.set_script(script)
	return scene
