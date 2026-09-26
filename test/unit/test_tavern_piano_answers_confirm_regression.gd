extends GutTest

## The Dancing Tonberry piano and the locked private-quarters stairs overlap.
## The stairs used to take confirm in _input and mark it handled, so the field
## controller never ran and the piano's interact() was never called. This loads
## the real tavern, stands on the piano, and delivers confirm through the viewport.

const TAVERN_PATH := "res://src/maps/interiors/TavernInterior.gd"
const _DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]

var _viewport: SubViewport
var _tavern: Node2D
var _mode7_was: bool = false
var _gl = null
var _gl_state = null
var _saved_locks: Array = []


func before_each() -> void:
	for action in _DIRECTIONS:
		Input.action_release(action)
	_mode7_was = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	_hold_exploration_open()
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.handle_input_locally = true
	add_child(_viewport)
	_tavern = load(TAVERN_PATH).new()
	_viewport.add_child(_tavern)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_each() -> void:
	Mode7Overlay.is_active = _mode7_was
	for action in _DIRECTIONS:
		Input.action_release(action)
	_release_exploration_hold()
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_tavern = null


## Standing on the piano is inside both zones. Confirm must reach the piano.
func test_confirm_on_the_piano_plays_it() -> void:
	var player := await _stand_on_piano()
	if player == null:
		return
	_face(player, _away_from_stairs(player))
	var feet: Array = _zones_at(player, player.global_position)
	assert_true(feet.has("PianoInteractable") and feet.has("LockedStairs"),
		"the player is standing in the piano/stairs overlap — otherwise the press never meets the swallow, got %s" % feet)
	if not (feet.has("PianoInteractable") and feet.has("LockedStairs")):
		return
	_press_confirm()
	var text := _all_label_text(_tavern)
	assert_true(_piano_answered(text),
		"confirm on the piano must play it or say why not, got: %s" % _excerpt(text))
	assert_false(text.contains("private quarters"),
		"that press must not be taken by the locked stairs, got: %s" % _excerpt(text))


## The same spot, faced at the stairs, still shows the locked-quarters line.
func test_facing_the_stairs_still_shows_the_locked_message() -> void:
	var player := await _stand_on_piano()
	if player == null:
		return
	_face(player, _toward_stairs(player))
	var aimed: Array = _zones_at(player, _probe_point(player))
	assert_true(aimed.has("LockedStairs"),
		"facing the stairs must put the probe in the locked zone, got %s" % aimed)
	assert_false(aimed.has("PianoInteractable"),
		"that probe must clear the piano box, or nearest-of-both still picks the piano underfoot, got %s" % aimed)
	if not aimed.has("LockedStairs") or aimed.has("PianoInteractable"):
		return
	_press_confirm()
	var text := _all_label_text(_tavern)
	assert_true(text.contains("private quarters"),
		"facing the stairs must show the locked message, got: %s" % _excerpt(text))
	assert_false(_piano_answered(text),
		"facing the stairs must not also play the piano, got: %s" % _excerpt(text))


func _stand_on_piano() -> OverworldPlayer:
	var player := _tavern.player as OverworldPlayer
	var piano := _tavern.find_child("PianoInteractable", true, false)
	var stairs := _tavern.find_child("LockedStairs", true, false)
	assert_not_null(player, "the tavern builds a player")
	assert_not_null(piano, "the tavern builds a piano zone")
	assert_not_null(stairs, "the tavern builds the locked stairs")
	if player == null or piano == null or stairs == null:
		return null
	assert_true(piano.has_method("interact"), "the piano must answer interact()")
	assert_true(stairs.has_method("interact"), "the stairs must answer interact() so the field pick can choose them")
	if not piano.has_method("interact") or not stairs.has_method("interact"):
		return null
	# Spawn-inside often skips body_entered; step off the spot and back so the space registers the overlap.
	player.global_position = piano.global_position + Vector2(8, 0)
	await get_tree().physics_frame
	player.global_position = piano.global_position
	player.velocity = Vector2.ZERO
	for _step in range(4):
		await get_tree().physics_frame
		player.global_position = piano.global_position
		player.velocity = Vector2.ZERO
	return player


func _toward_stairs(player: OverworldPlayer) -> Vector2:
	var stairs := _tavern.find_child("LockedStairs", true, false)
	return (stairs as Node2D).global_position - player.global_position


func _away_from_stairs(player: OverworldPlayer) -> Vector2:
	return -_toward_stairs(player)


func _face(player: OverworldPlayer, direction: Vector2) -> void:
	if abs(direction.x) >= abs(direction.y):
		player.current_direction = OverworldPlayer.Direction.RIGHT if direction.x >= 0.0 else OverworldPlayer.Direction.LEFT
	else:
		player.current_direction = OverworldPlayer.Direction.DOWN if direction.y >= 0.0 else OverworldPlayer.Direction.UP


func _probe_point(player: OverworldPlayer) -> Vector2:
	var reach := InteractGeometry.PROBE_REACH_MODE7 if Mode7Overlay.is_active else InteractGeometry.PROBE_REACH_FLAT
	var offset := Vector2.RIGHT
	match player.current_direction:
		OverworldPlayer.Direction.DOWN:
			offset = Vector2.DOWN
		OverworldPlayer.Direction.UP:
			offset = Vector2.UP
		OverworldPlayer.Direction.LEFT:
			offset = Vector2.LEFT
		OverworldPlayer.Direction.RIGHT:
			offset = Vector2.RIGHT
	return player.global_position + offset * reach


func _zones_at(player: Node2D, at: Vector2) -> Array:
	var space := player.get_world_2d().direct_space_state
	if space == null:
		return []
	var query := PhysicsPointQueryParameters2D.new()
	query.position = at
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = InteractGeometry.LAYER_INTERACTABLE
	var names: Array = []
	for hit in space.intersect_point(query):
		var collider = hit.get("collider", null)
		if collider != null:
			names.append(str(collider.name))
	return names


func _press_confirm() -> void:
	var down := InputEventAction.new()
	down.action = "ui_accept"
	down.pressed = true
	_viewport.push_input(down)
	var up := InputEventAction.new()
	up.action = "ui_accept"
	up.pressed = false
	_viewport.push_input(up)


func _piano_answered(text: String) -> bool:
	return text.contains("sounds terrible") or text.contains("beautiful melody") \
		or text.contains("immediately regret") or text.contains("It's chaos")


func _all_label_text(root: Node) -> String:
	if root == null or not is_instance_valid(root):
		return ""
	var out := ""
	if root is Label:
		out = (root as Label).text
	for child in root.get_children():
		out += _all_label_text(child)
	return out


func _excerpt(text: String) -> String:
	for key in ["terrible", "melody", "regret", "chaos", "private quarters"]:
		var at := text.find(key)
		if at >= 0:
			return text.substr(maxi(0, at - 40), 180)
	if text.length() <= 180:
		return text
	return text.substr(text.length() - 180)


func _hold_exploration_open() -> void:
	_gl = get_tree().root.get_node_or_null("GameLoop")
	if _gl != null and "current_state" in _gl and "LoopState" in _gl:
		_gl_state = _gl.current_state
		_gl.current_state = _gl.LoopState.EXPLORATION
	var ilm = get_tree().root.get_node_or_null("InputLockManager")
	if ilm != null and ilm.is_locked():
		_saved_locks = ilm.get_active_locks().duplicate()
		ilm.pop_all()


func _release_exploration_hold() -> void:
	if _gl != null and is_instance_valid(_gl) and _gl_state != null and "current_state" in _gl:
		_gl.current_state = _gl_state
	_gl = null
	_gl_state = null
	var ilm = get_tree().root.get_node_or_null("InputLockManager")
	if ilm != null:
		for lock_id in _saved_locks:
			ilm.push_lock(str(lock_id))
	_saved_locks = []
