extends Area2D
class_name BossTrigger

## Simple boss trigger that can be interacted with

signal boss_triggered()

var cave_ref: Node = null
var boss_for_log: String = ""


func _ready() -> void:
	# Ensure collision is set up for interaction detection
	collision_layer = 4  # Interactables layer
	collision_mask = 2   # Player layer
	monitoring = true
	monitorable = true

	# Add to interactables group for easier discovery
	add_to_group("interactables")

	DebugLogOverlay.log("[BOSS] Trigger ready at %s" % global_position)


## The boss this trigger starts, for the log. The cave that builds the trigger says who; unset reads as unnamed.
func boss_label() -> String:
	return boss_for_log if boss_for_log != "" else "unnamed boss"


func interact(_player: Node2D) -> void:
	DebugLogOverlay.log("[BOSS] interact() - defeated: %s" % (cave_ref.boss_defeated if cave_ref else "N/A"))
	if cave_ref and not cave_ref.boss_defeated:
		DebugLogOverlay.log("[BOSS] Starting %s battle!" % boss_label())
		boss_triggered.emit()
		cave_ref._trigger_boss_battle()
	else:
		DebugLogOverlay.log("[BOSS] Already defeated or no cave ref")
