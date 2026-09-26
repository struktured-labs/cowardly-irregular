extends GutTest

## The tavern piano is a side activity. Its zone stored interaction_callback, and nothing in src/
## reads that meta — OverworldController only calls interact(). Confirm at the piano did nothing.

const TAVERN_PATH := "res://src/maps/interiors/TavernInterior.gd"
const CONTROLLER_PATH := "res://src/exploration/OverworldController.gd"

var _tavern: Node2D = null
var _mode7_was: bool = false


func before_each() -> void:
	_mode7_was = Mode7Overlay.is_active
	_tavern = load(TAVERN_PATH).new()
	add_child_autofree(_tavern)


func after_each() -> void:
	Mode7Overlay.is_active = _mode7_was
	_tavern = null


## The controller's own nearest-pick. A zone that only carries the callback meta comes back null.
func test_confirm_at_the_piano_plays_or_says_why_not() -> void:
	var piano := _tavern.find_child("PianoInteractable", true, false)
	assert_not_null(piano, "CONTROL: the tavern builds a piano zone")
	if piano == null:
		return
	assert_true(piano.is_in_group("interactables"),
		"the piano must sit in the interactables group the controller scans")
	var controller = load(CONTROLLER_PATH).new()
	add_child_autofree(controller)
	var picked = controller._pick_nearest_interactable(
		[{"collider": piano}], piano.global_position)
	assert_eq(picked, piano,
		"confirm at the piano must select the piano — the interact button skips a zone with no interact()")
	if picked == null:
		return
	picked.interact(null)
	var text := _all_label_text(_tavern)
	assert_true(text.contains("sounds terrible") or text.contains("beautiful melody"),
		"confirm at the piano must show what happened, got: %s" % text.substr(0, 240))


func _all_label_text(root: Node) -> String:
	if root == null or not is_instance_valid(root):
		return ""
	var out := ""
	if root is Label:
		out = (root as Label).text
	for c in root.get_children():
		out += _all_label_text(c)
	return out
