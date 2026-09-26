extends GutTest

## The counter in front of the shopkeeper is a BrowseService zone. It stored
## interaction_callback, and nothing in src/ reads that meta — OverworldController
## only calls interact(). Confirm on the counter therefore did nothing: the zone
## was skipped, and the keeper behind it refuses a press she is not being faced.
## Talking her through the greeting was the only way the wares opened.
##
## Every ShopType rides this one zone. GameLoop._create_shop_interior is the
## scene the player walks into (there is no separate counter per type). Scriptura's
## bookshop and the forge interior are different rooms and do not build it.

const GameLoopScript := preload("res://src/GameLoop.gd")
const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const PlayerScript := preload("res://src/exploration/OverworldPlayer.gd")

var _mode7_was: bool = false
var _gl: Node = null


func before_each() -> void:
	_mode7_was = Mode7Overlay.is_active
	# GameLoop is the main scene, not an autoload, so it is absent under test.
	# Kept out of the tree: _ready would boot the game, and a /root/GameLoop
	# that is not exploring makes the player's confirm press a no-op.
	_gl = GameLoopScript.new()
	autofree(_gl)


func after_each() -> void:
	Mode7Overlay.is_active = _mode7_was
	_gl = null


func test_confirm_at_the_counter_opens_the_shop() -> void:
	assert_true(_gl.has_method("_create_shop_interior"),
		"CONTROL: GameLoop._create_shop_interior is the scene the player walks into")
	if not _gl.has_method("_create_shop_interior"):
		return
	var types: Array = ShopInteriorScript.ShopType.values()
	assert_gt(types.size(), 0, "CONTROL: ShopType must name the rooms that share the counter")
	for shop_type in types:
		await _assert_counter_opens(int(shop_type))


## Stand on the counter zone, facing away from the keeper, and press confirm.
func _assert_counter_opens(shop_type: int) -> void:
	var what := _type_name(shop_type)
	var shop = _gl._create_shop_interior(shop_type)
	add_child(shop)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone: Node = shop.find_child("BrowseService", true, false)
	if zone == null:
		_drop(shop)
		assert_not_null(zone, "%s builds a BrowseService counter zone" % what)
		return
	var player = shop.player
	if player == null:
		_drop(shop)
		assert_not_null(player, "%s stands a player in the room" % what)
		return
	# Down is away from the keeper (she stands one tile north). Facing her still
	# talks; the counter itself is what a press from the approach tile must open.
	player.current_direction = PlayerScript.Direction.DOWN
	player.global_position = (zone as Node2D).global_position
	await get_tree().physics_frame
	var standing: Array = _colliders_at(player, player.global_position)
	if not standing.has(zone):
		_drop(shop)
		assert_true(standing.has(zone),
			"CONTROL: %s player is standing in the counter zone, physics saw %s" % [what, standing])
		return
	assert_true(player._can_move(),
		"CONTROL: %s confirm only emits while the player can move (locks: %s)" % [what, _lock_ids()])
	if not player._can_move():
		_drop(shop)
		return
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	player._unhandled_input(ev)
	var layer: Node = shop._wares_layer
	var menu := _shop_menu(layer)
	var opened: bool = menu != null and menu.is_inside_tree() and menu.visible
	_drop(shop)
	assert_true(opened,
		"pressing confirm at the %s counter must open the shop menu" % what)


func _type_name(shop_type: int) -> String:
	var keys: Array = ShopInteriorScript.ShopType.keys()
	if shop_type >= 0 and shop_type < keys.size():
		return str(keys[shop_type])
	return str(shop_type)


func _colliders_at(player: Node2D, at: Vector2) -> Array:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = at
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 4
	var hits: Array = []
	var space := player.get_world_2d().direct_space_state
	for result in space.intersect_point(q):
		var c = result.get("collider", null)
		if c != null:
			hits.append(c)
	return hits


func _shop_menu(layer: Node) -> Node:
	if layer == null or not is_instance_valid(layer):
		return null
	for c in layer.get_children():
		if c.get_script() == ShopSceneScript:
			return c
	return null


func _lock_ids() -> Array:
	var ilm := get_tree().root.get_node_or_null("InputLockManager")
	if ilm == null or not ilm.has_method("get_active_locks"):
		return []
	return ilm.get_active_locks()


func _drop(shop) -> void:
	if shop == null or not is_instance_valid(shop):
		return
	var layer: Node = shop.get("_wares_layer")
	if layer != null and is_instance_valid(layer):
		layer.free()
	shop.free()
