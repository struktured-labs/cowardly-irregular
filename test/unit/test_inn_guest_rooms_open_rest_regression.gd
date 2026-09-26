extends GutTest

## The Guest Rooms stairs and the desk bell were built as the inn's rest gates.
## Both store interaction_callback and nothing in src/ reads that meta — OverworldController
## only calls interact(). Pressing the button on the sign did nothing. Talking the
## innkeeper all the way through her greeting was the only way a night's rest opened.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"
const CONTROLLER_PATH := "res://src/exploration/OverworldController.gd"

var _inn: Node2D = null
var _mode7_was: bool = false


func before_each() -> void:
	_mode7_was = Mode7Overlay.is_active
	_inn = load(INN_PATH).new()
	add_child_autofree(_inn)


func after_each() -> void:
	Mode7Overlay.is_active = _mode7_was
	_inn = null


func test_guest_rooms_are_a_rest_the_interact_button_can_reach() -> void:
	_assert_zone_opens_rest("StairsRestService", "Guest Rooms")


func test_the_desk_bell_is_a_rest_the_interact_button_can_reach() -> void:
	_assert_zone_opens_rest("RestService", "desk bell")


## The controller's own nearest-pick. A zone that only carries the callback meta comes back null.
func _assert_zone_opens_rest(node_name: String, what: String) -> void:
	var zone := _inn.find_child(node_name, true, false)
	assert_not_null(zone, "CONTROL: the inn builds a %s zone" % what)
	if zone == null:
		return
	assert_true(zone.is_in_group("interactables"),
		"%s must sit in the interactables group the controller scans" % what)
	var controller = load(CONTROLLER_PATH).new()
	add_child_autofree(controller)
	var picked = controller._pick_nearest_interactable(
		[{"collider": zone}], zone.global_position)
	assert_eq(picked, zone,
		"standing on the %s must be offered a room — the interact button skips a zone with no interact()" % what)
	if picked == null:
		return
	var walker := Node2D.new()
	add_child_autofree(walker)
	picked.interact(walker)
	assert_true(_inn._rest_pending,
		"pressing interact at the %s must open the rest offer" % what)
	var label := _find_label(_inn._rest_dialog)
	assert_not_null(label, "the rest offer must be on screen, not only a flag")
	if label != null:
		assert_true(label.text.contains(str(_inn.REST_COST)),
			"the offer must name the price the rest will charge, got: %s" % label.text)


func _find_label(root: Node) -> Label:
	if root == null or not is_instance_valid(root):
		return null
	if root is Label:
		return root as Label
	for c in root.get_children():
		var found := _find_label(c)
		if found != null:
			return found
	return null
