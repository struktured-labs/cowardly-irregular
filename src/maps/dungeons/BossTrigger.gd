extends Area2D
class_name BossTrigger

## Simple boss trigger that can be interacted with

signal boss_triggered()

var cave_ref: Node = null

func interact(_player: Node2D) -> void:
	if cave_ref and not cave_ref.boss_defeated:
		boss_triggered.emit()
		cave_ref._trigger_boss_battle()
