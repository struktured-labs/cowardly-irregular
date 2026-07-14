extends GutTest

## tick 349: OverworldNPC._adjust_collision_for_mode7 now sets
## collision_layer = 4 / collision_mask = 2 / monitoring for ALL
## NPCs, not just non-Mode-7 ones.
##
## Pre-fix the layer/mask setup lived in the ELSE branch of the
## Mode 7 ancestor check:
##
##   while parent:
##       if parent is Mode 7:
##           shape.radius = 128.0
##           # Y-stretch
##           return  # <-- early return skips layer setup
##       parent = parent.get_parent()
##
##   # Only reaches here if NOT Mode 7
##   collision_layer = 4
##   collision_mask = 2
##   monitoring = true
##
## So Mode 7 overworld NPCs never got collision_layer = 4.
## OverworldController._on_interaction_requested's PRIMARY physics
## intersect_point query (collision_mask=4 at line ~181) couldn't
## find them. The fallback group/distance loop (line ~201) still
## worked, but every Mode 7 NPC interaction routed through the
## slower path.
##
## Symptom: "interactions feel slightly laggy in overworlds compared
## to villages" — invisible to most players, real for the engine
## profile.
##
## Fix: set collision layer/mask BEFORE the Mode 7 check so the
## early return in the Mode 7 branch doesn't skip it.

const OVERWORLD_NPC_PATH := "res://src/exploration/OverworldNPC.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: collision_layer set BEFORE Mode 7 check ─────────────

func test_layer_set_before_mode7_check() -> void:
	var src := _read(OVERWORLD_NPC_PATH)
	var fn_idx: int = src.find("func _adjust_collision_for_mode7")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	var layer_idx: int = body.find("collision_layer = 4")
	var while_idx: int = body.find("while parent:")
	assert_gt(layer_idx, -1, "collision_layer = 4 must still exist")
	assert_gt(while_idx, -1, "Mode 7 ancestor while-loop must still exist")
	assert_lt(layer_idx, while_idx,
		"collision_layer = 4 must come BEFORE the Mode 7 ancestor loop — pre-fix it was after the early return, so Mode 7 NPCs never got the layer set")


# ── Source pin: collision_mask + monitoring also before the check ───

func test_mask_and_monitoring_set_before_mode7_check() -> void:
	var src := _read(OVERWORLD_NPC_PATH)
	var fn_idx: int = src.find("func _adjust_collision_for_mode7")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	var while_idx: int = body.find("while parent:")
	var mask_idx: int = body.find("collision_mask = 2")
	var monitor_idx: int = body.find("monitoring = true")
	var monitorable_idx: int = body.find("monitorable = true")
	assert_gt(mask_idx, -1)
	assert_gt(monitor_idx, -1)
	assert_gt(monitorable_idx, -1)
	assert_lt(mask_idx, while_idx, "collision_mask must come BEFORE the Mode 7 loop")
	assert_lt(monitor_idx, while_idx, "monitoring must come BEFORE the Mode 7 loop")
	assert_lt(monitorable_idx, while_idx, "monitorable must come BEFORE the Mode 7 loop")


# ── Source pin: Mode 7 branch still has the shape adjustment ────────

func test_mode7_branch_still_adjusts_shape() -> void:
	# Regression guard — don't accidentally drop the Mode 7 shape boost
	# while refactoring.
	var src := _read(OVERWORLD_NPC_PATH)
	var fn_idx: int = src.find("func _adjust_collision_for_mode7")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("shape.radius = 128.0"),
		"Mode 7 branch must still enlarge the collision shape to radius 128")
	assert_true(body.contains("Vector2(1.0, 1.67)"),
		"Mode 7 branch must still apply the Y-stretch")
