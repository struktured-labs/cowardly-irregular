extends GutTest

## A wandering villager talks through its own _input, and that handler runs
## before doors: NPCs are added after transitions and buildings, and _input
## walks the tree last-child-first. set_input_as_handled() then eats the
## confirm, so the door's handler and the player's unhandled interact never
## run.
##
## Harmonia's merchant patrol ends on the suburban portal's exact cell
## (both Vector2(23 * TILE, 13 * TILE)) and pauses there. Sven's route is
## the row the shop entry boxes are centered on. Standing in the doorway
## while they pass opened their one-liner instead of the door.
##
## The fixture puts the wanderer and a press-to-enter transition on the
## same point, with the door added FIRST so the wanderer receives _input
## first — the same order as the village. Before the yield, the viewport
## is marked handled and the door's signal never fires.

func _player() -> OverworldPlayer:
	var body := OverworldPlayer.new()
	body.name = "Player"
	body.current_direction = OverworldPlayer.Direction.DOWN
	return body


func _door() -> AreaTransition:
	var door := AreaTransition.new()
	door.name = "Door"
	door.target_map = "overworld"
	door.target_spawn = "default"
	door.require_interaction = true
	door.show_indicator = false
	door.show_gate_visual = false
	return door


func _box(area: Area2D) -> void:
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 64)
	col.shape = shape
	area.add_child(col)
	area.collision_layer = 4
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = true


func _accept() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	return ev


func _stage(with_door: bool) -> Dictionary:
	Mode7Overlay.is_active = false
	var vp := SubViewport.new()
	vp.name = "WandererDoorVP"
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var root := Node2D.new()
	vp.add_child(root)
	var door: AreaTransition = null
	if with_door:
		door = _door()
		root.add_child(door)
		_box(door)
	var npc := WanderingNPC.new()
	npc.npc_name = "Patroller"
	npc.dialogue = "Eyes peeled."
	root.add_child(npc)
	var player := _player()
	root.add_child(player)
	var at := Vector2(200, 200)
	if door != null:
		door.global_position = at
	npc.global_position = at
	# A body that spawns already inside an area often gets no body_entered until it moves.
	player.global_position = at + Vector2(30, 0)
	await get_tree().physics_frame
	player.global_position = at
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"vp": vp, "npc": npc, "player": player, "door": door}


func test_a_wanderer_standing_in_a_door_lets_the_door_have_the_press() -> void:
	var stage: Dictionary = await _stage(true)
	var npc: WanderingNPC = stage["npc"]
	var door: AreaTransition = stage["door"]
	assert_true(npc._player_nearby, "the wanderer is in talk range — otherwise the press is dropped before the door check and this passes for free")
	assert_true(door._player_in_zone, "the player is inside the door — otherwise the door could not have taken the press")
	var entered := [false]
	door.transition_triggered.connect(func(_map, _spawn): entered[0] = true)
	var vp := npc.get_viewport()
	assert_false(vp.is_input_handled(), "viewport starts with the press unclaimed")
	npc._input(_accept())
	var stole: bool = vp.is_input_handled()
	if not stole:
		door._input(_accept())
	npc.free()
	assert_false(stole, "confirm while standing in the doorway must not be consumed by the wanderer")
	assert_true(entered[0], "the door must still receive that press and transition")


func test_a_wanderer_on_open_ground_still_takes_the_press() -> void:
	var stage: Dictionary = await _stage(false)
	var npc: WanderingNPC = stage["npc"]
	assert_true(npc._player_nearby, "control: the wanderer is in talk range with no door present")
	assert_false(npc._door_owns_confirm(stage["player"]), "open ground is not an entry")
	var vp := npc.get_viewport()
	npc._input(_accept())
	var took: bool = vp.is_input_handled()
	npc.free()
	assert_true(took, "with no door underfoot the wanderer still opens conversation")
