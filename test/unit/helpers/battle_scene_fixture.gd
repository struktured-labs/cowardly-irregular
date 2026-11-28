extends RefCounted

## Builds a BattleScene from its packed .tscn, so the @onready $-paths find their nodes.
## A bare BattleScene.gd.new() has no children and logs one "Node not found" engine error per path
## on add_child (4450 in the .849 gate). `script` lets a test's ProbeScene subclass ride the real tree.

const SCENE_PATH := "res://src/battle/BattleScene.tscn"


static func build(script: Script = null) -> Node:
	var scene: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	if script != null:
		scene.set_script(script)
	return scene
