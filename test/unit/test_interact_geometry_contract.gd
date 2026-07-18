extends GutTest

## The interaction-geometry contract (struktured ultracode 2026-07-18).
## Pins every load-bearing constant so later migration steps can't drift them,
## and behavioral-tests the static helpers the whole system routes through.


func test_pinned_values() -> void:
	assert_eq(InteractGeometry.PROBE_REACH_FLAT, 40.0, "probe reach mirrors reachability framework INTERACT_REACH")
	assert_eq(InteractGeometry.PROBE_REACH_MODE7, 80.0, "ruling 2026-07-11")
	assert_eq(InteractGeometry.GROUP_FALLBACK_RADIUS, 40.0, "fallback may never out-reach the facing-biased probe")
	assert_eq(InteractGeometry.NPC_TALK_RADIUS, 44.0, "cardinal-adjacent in, diagonal out — the Chrono Trigger rule")
	assert_eq(InteractGeometry.NPC_TALK_RADIUS_MODE7, 128.0)
	assert_eq(InteractGeometry.CHEST_GRAB_RADIUS_FLAT, 40.0, "SETTLED ruling 2026-07-11 — do not re-litigate")
	assert_eq(InteractGeometry.SAVE_RADIUS, 48.0)
	assert_eq(InteractGeometry.SIGNPOST_RADIUS_FLAT, 48.0, "was 128 unconditional — 4-tile label zones in flat villages")
	assert_eq(InteractGeometry.DOOR_BOX, Vector2(64, 48))
	assert_eq(InteractGeometry.DOOR_OFFSET, Vector2(0, 24))
	assert_eq(InteractGeometry.BUILDING_ENTRY_BOX, Vector2(64, 96), "the 2026-07-13 shop/inn fix, now canonical")
	assert_eq(InteractGeometry.ENTRANCE_BOX_MODE7, Vector2(64, 192), "the proven W1 recipe")
	assert_eq(InteractGeometry.MODE7_TRIGGER_Y_OFFSET, -96.0, "3 tiles north — the log-warp compensation")
	assert_eq(InteractGeometry.MODE7_Y_STRETCH, 1.67)
	assert_eq(InteractGeometry.LAYER_INTERACTABLE, 4)
	assert_eq(InteractGeometry.MASK_PLAYER, 2)
	assert_lte(InteractGeometry.GROUP_FALLBACK_RADIUS, InteractGeometry.PROBE_REACH_FLAT,
		"INVARIANT: omnidirectional fallback <= directional probe, else facing becomes advisory")


func test_talk_radius_geometry() -> void:
	# 44 admits cardinal-adjacent tile centers (32px) and excludes diagonal (45.25px).
	assert_lt(32.0, InteractGeometry.NPC_TALK_RADIUS)
	assert_gt(sqrt(2.0) * 32.0, InteractGeometry.NPC_TALK_RADIUS,
		"diagonal adjacency must stay OUTSIDE the talk radius — no special-case needed")


func test_anchor_includes_shape_offset() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	node.global_position = Vector2(100, 100)
	var cs := CollisionShape2D.new()
	cs.position = Vector2(0, 24)
	node.add_child(cs)
	assert_eq(InteractGeometry.anchor(node), Vector2(100, 124),
		"anchor = origin + shape offset — offset doors stop losing ties they visually win")


func test_facing_cone_and_touch_waiver() -> void:
	# Node2D lacks current_direction — stub a scripted player so the property probe works.
	var stub := GDScript.new()
	stub.source_code = "extends Node2D\nvar current_direction: String = \"down\""
	stub.reload()
	var player: Node2D = stub.new()
	add_child_autofree(player)
	player.global_position = Vector2(0, 0)
	var npc := Node2D.new()
	add_child_autofree(npc)
	npc.global_position = Vector2(32, 0)
	player.current_direction = "right"
	assert_true(InteractGeometry.facing_allows(player, npc), "facing the NPC → allowed")
	player.current_direction = "left"
	assert_false(InteractGeometry.facing_allows(player, npc), "facing away → refused (NPCs stop talking to your back)")
	npc.global_position = Vector2(8, 0)
	assert_true(InteractGeometry.facing_allows(player, npc), "standing on top waives the cone")


func test_is_player_unified_predicate() -> void:
	var grouped := Node2D.new()
	add_child_autofree(grouped)
	grouped.add_to_group("player")
	assert_true(InteractGeometry.is_player(grouped))
	assert_false(InteractGeometry.is_player(Node2D.new()) or InteractGeometry.is_player(null))


func test_setup_trigger_collision_shape() -> void:
	var area := Area2D.new()
	add_child_autofree(area)
	InteractGeometry.setup_trigger_collision(area, Vector2(64, 96), Vector2(0, 48))
	var cs: CollisionShape2D = null
	for c in area.get_children():
		if c is CollisionShape2D:
			cs = c
	assert_not_null(cs)
	assert_eq((cs.shape as RectangleShape2D).size, Vector2(64, 96))
	assert_eq(cs.position, Vector2(0, 48))
	assert_eq(area.collision_layer, 4)
	assert_eq(area.collision_mask, 2)
	assert_true(area.monitoring and area.monitorable)
