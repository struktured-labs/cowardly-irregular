extends GutTest

## A command menu whose battle is torn down while it is still building (cutscenes 24328: the second input wait called
## get_tree() on a menu with no tree; battle's guard b607db2c6 stops that). ONE frame earlier the same menu, already out
## of the tree, still ran the rest of the build: it clamped itself against a viewport it no longer has (which moves it
## to the corner), re-selected, and started its submenu timer off the tree. The build now stops at its first resume.
## setup() only builds a menu that is IN the tree, so "built off the tree" is not a case; "removed mid-build" is.

const W98 := "res://src/ui/Win98Menu.gd"
const AT := Vector2(300, 200)


func _rows() -> Array:
	return [{"id": "attack", "label": "Attack"}, {"id": "defer", "label": "Defer", "data": null}]


func _new_menu() -> Node:
	var m = load(W98).new()
	m.is_root_menu = true
	m.battle_mode = true
	return m


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m = _new_menu()
	add_child_autofree(m)
	assert_true(m.has_method("setup") and m.has_method("_build_menu") and m.has_method("_clamp_to_screen"), "Win98Menu.setup / _build_menu / _clamp_to_screen must exist")
	assert_true("_can_accept_input" in m and "_can_close_on_click" in m, "Win98Menu's two input latches must exist")


## CONTROL: in the tree the menu stays where it was put, opens deaf, and listens after its waits.
func test_a_menu_in_the_tree_finishes_opening() -> void:
	var m = _new_menu()
	add_child_autofree(m)
	m.setup("Command", _rows(), AT, "fighter")
	assert_false(m._can_accept_input, "CONTROL: a fresh menu ignores the press that opened it")
	await wait_until(func(): return m._can_close_on_click, 2.0)
	assert_true(m._can_accept_input and m._can_close_on_click, "it listens once both waits have passed")
	assert_eq(m.position, AT, "CONTROL: and a menu that fits the screen is not moved by the clamp")


## Removed in its FIRST frame: the build must not go on without a tree. Off the tree the clamp sees a zero viewport and
## throws the menu into the corner, so its position is what shows whether the rest of the build ran.
func test_a_menu_removed_in_its_first_frame_stops_building() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var m = _new_menu()
	host.add_child(m)
	m.setup("Command", _rows(), AT, "fighter")
	host.remove_child(m)
	await wait_seconds(0.3)
	assert_eq(m.position, AT, "the menu was not clamped against a viewport it no longer has")
	assert_false(m._can_accept_input, "and it never starts listening")
	assert_false(m._can_close_on_click, "nor reaches its second wait")
	m.free()


## Removed BETWEEN the two input waits (battle's case): the first has passed, the second is never reached.
func test_a_menu_removed_between_its_waits_never_finishes_opening() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var m = _new_menu()
	host.add_child(m)
	m.setup("Command", _rows(), AT, "fighter")
	await wait_until(func(): return m._can_accept_input, 2.0)
	assert_true(m._can_accept_input and not m._can_close_on_click, "CONTROL: caught between the two waits")
	host.remove_child(m)
	await wait_seconds(0.3)
	assert_false(m._can_close_on_click, "the second latch is never opened on a menu with no tree")
	m.free()


## The source half, because the defect is a script error the arms above cannot count: every await in the build is
## followed by a tree check before anything that needs one.
func test_every_resume_in_the_build_checks_the_tree_first() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var at := src.find("func _build_menu(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	var awaits := body.count("await get_tree().")
	assert_eq(awaits, 3, "CONTROL: the build resumes three times (a frame, then two input waits)")
	var frame := body.find("await get_tree().process_frame")
	var first_wait := body.find("await get_tree().create_timer(")
	var last_wait := body.rfind("await get_tree().create_timer(")
	assert_true(body.substr(frame, body.find("_clamp_to_screen()", frame) - frame).contains("not is_inside_tree()"), "after the frame, before the clamp")
	assert_true(body.substr(first_wait, last_wait - first_wait).contains("not is_inside_tree()"), "after the first wait, before the second")
	assert_false(body.substr(body.find("\n", last_wait)).contains("get_tree()"), "and nothing after the last wait asks for the tree")
