class_name InteractGeometry
extends RefCounted
## THE interaction-geometry contract (struktured ultracode 2026-07-18: "object
## detection is still terrible... evaluate it as a whole"). Every radius, box,
## and offset the interaction system uses lives HERE — call sites reference
## these names, tests pin the values, and a feel change is one edit.
## (pin) = locked by an existing test; change value and test together.

const TILE := 32.0

# -- Player anchor --
const PLAYER_FEET_OFFSET := Vector2.ZERO  # feet == body origin (tile-standing point) — THE definition
const PLAYER_TOUCH_RADIUS := 12.0  # standing-on-top waives the facing cone

# -- Press probe (OverworldController) --
const PROBE_REACH_FLAT := 40.0  # (pin) INTERACT_REACH mirror in test_village_reachability_framework
const PROBE_REACH_MODE7 := 80.0  # settled ruling 2026-07-11
const GROUP_FALLBACK_RADIUS := 40.0  # was 48 — fallback may never out-reach the facing-biased probe

# -- Class A: NPC talk --
const NPC_TALK_RADIUS := 44.0  # cardinal-adjacent (32px) in, diagonal (45.25px) out — geometry excludes diagonal talk
const NPC_TALK_RADIUS_MODE7 := 128.0  # (pin) test_overworld_npc_collision_layer_regression
const FACING_COS_MIN := 0.5  # ±60° cone, class A only

# -- Class B: grab zones --
const CHEST_GRAB_RADIUS_FLAT := 40.0  # (pin) ruling 2026-07-11 — do not re-litigate
const CHEST_GRAB_RADIUS_MODE7 := 128.0  # (pin)
const SAVE_RADIUS := 48.0  # ruling 2026-07-11; Y-stretch is Mode-7-conditional
const SIGNPOST_RADIUS_FLAT := 48.0  # was 128 unconditional — a 4-tile label zone in flat villages
const SIGNPOST_RADIUS_MODE7 := 128.0

# -- Class C: press-doors / transitions --
const DOOR_BOX := Vector2(64, 48)  # (pin) interior door
const DOOR_OFFSET := Vector2(0, 24)  # (pin)
const BUILDING_ENTRY_BOX := Vector2(64, 96)  # shop/inn 2026-07-13 fix; VillageBar adopts
const BUILDING_ENTRY_OFFSET := Vector2(0, 48)
const ENTRANCE_BOX_FLAT := Vector2(64, 64)  # replaces the 32x32 stand-on-the-exact-tile portals
const ENTRANCE_BOX_MODE7 := Vector2(64, 192)  # the proven W1 recipe (2x6 tiles)
const MODE7_TRIGGER_Y_OFFSET := -96.0  # -3 tiles north — compensates the log-warp visual skew

# -- Class D: auto-sensors --
const AUTO_SENSOR_SLOP := 8.0
const STAIRS_BOX := Vector2(48, 48)  # unifies UP 32x32 / DOWN 64x64
const MONSTER_TOUCH_RADIUS := 48.0

# -- Mode 7 shared --
const MODE7_Y_STRETCH := 1.67  # (pin)

# -- Physics vocabulary --
const LAYER_INTERACTABLE := 4  # (pin)
const MASK_PLAYER := 2  # (pin)


## The ONLY Mode 7 context signal — dead ancestor-name/property detectors are retired.
static func is_mode7() -> bool:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var overlay = (ml as SceneTree).root.get_node_or_null("Mode7Overlay")
		if overlay != null and "is_active" in overlay:
			return bool(overlay.is_active)
	return false


## Unifies the three coexisting player-identity predicates.
static func is_player(body: Node) -> bool:
	if body == null:
		return false
	return body.is_in_group("player") or body.has_method("set_can_move")


static func feet(player: Node2D) -> Vector2:
	return player.global_position + PLAYER_FEET_OFFSET


## Interactable anchor = node origin + its CollisionShape2D offset (offset shapes
## stop losing arbitration ties they visually win).
static func anchor(node: Node2D) -> Vector2:
	for child in node.get_children():
		if child is CollisionShape2D:
			return node.global_position + (child as CollisionShape2D).position
	return node.global_position


## Class-A facing cone: player must roughly face the target; waived on top of it.
static func facing_allows(player: Node2D, target: Node2D) -> bool:
	var to_target: Vector2 = anchor(target) - feet(player)
	if to_target.length() <= PLAYER_TOUCH_RADIUS:
		return true
	var facing: Vector2 = Vector2.DOWN
	if "current_direction" in player:
		# OverworldPlayer.Direction enum {DOWN, UP, LEFT, RIGHT} = 0..3; string form tolerated for stubs/tests.
		match player.current_direction:
			0, "down": facing = Vector2.DOWN
			1, "up": facing = Vector2.UP
			2, "left": facing = Vector2.LEFT
			3, "right": facing = Vector2.RIGHT
	elif "facing_direction" in player and player.facing_direction is Vector2:
		facing = player.facing_direction
	return facing.dot(to_target.normalized()) >= FACING_COS_MIN


## Shared trigger-collision builder (replaces 9 copy-pasted helpers + inline blocks).
static func setup_trigger_collision(area: Area2D, size: Vector2, offset: Vector2 = Vector2.ZERO) -> void:
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	collision.position = offset
	area.add_child(collision)
	area.collision_layer = LAYER_INTERACTABLE
	area.collision_mask = MASK_PLAYER
	area.monitoring = true
	area.monitorable = true
