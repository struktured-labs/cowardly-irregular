extends Area2D
class_name BossTrigger

## Simple boss trigger that can be interacted with

signal boss_triggered()

var cave_ref: Node = null


func _ready() -> void:
	# Ensure collision is set up for interaction detection
	collision_layer = 4  # Interactables layer
	collision_mask = 2   # Player layer
	monitoring = true
	monitorable = true
	print("[BOSS TRIGGER] Ready - collision_layer=%d, collision_mask=%d" % [collision_layer, collision_mask])


func interact(_player: Node2D) -> void:
	print("[BOSS TRIGGER] interact() called! cave_ref=%s, boss_defeated=%s" % [cave_ref != null, cave_ref.boss_defeated if cave_ref else "N/A"])
	if cave_ref and not cave_ref.boss_defeated:
		print("[BOSS TRIGGER] Triggering boss battle!")
		boss_triggered.emit()
		cave_ref._trigger_boss_battle()
	else:
		print("[BOSS TRIGGER] Cannot trigger - cave_ref=%s, boss_defeated=%s" % [cave_ref != null, cave_ref.boss_defeated if cave_ref else "N/A"])
