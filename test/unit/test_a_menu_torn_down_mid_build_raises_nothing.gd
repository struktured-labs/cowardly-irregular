extends GutTest

## cutscenes 24328, from battle's tint arm: a BattleScene taken out of the tree while its command menu was still in the
## two short waits at the end of Win98Menu._build_menu raised "Cannot call method 'create_timer' on a null value" (:1042).
## The menu was still a valid instance, so the is_instance_valid check passed, and get_tree() is null off the tree. A
## battle torn down in play (a grind restart, an escape mid-open) does the same. The waits now ask is_inside_tree too.

const W98 := "res://src/ui/Win98Menu.gd"


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
	assert_true(m.has_method("setup") and m.has_method("_build_menu"), "Win98Menu.setup / _build_menu must exist")
	assert_true("_can_accept_input" in m and "_can_close_on_click" in m, "Win98Menu's two input latches must exist")


## CONTROL: in the tree the menu opens deaf and starts listening after its two waits.
func test_a_menu_in_the_tree_listens_after_its_waits() -> void:
	var m = _new_menu()
	add_child_autofree(m)
	m.setup("Command", _rows(), Vector2(10, 10), "fighter")
	assert_false(m._can_accept_input, "CONTROL: a fresh menu ignores the press that opened it")
	await wait_until(func(): return m._can_close_on_click, 2.0)
	assert_true(m._can_accept_input and m._can_close_on_click, "and listens once both waits have passed")


## Built OFF the tree there is no timer: it used to raise at the first wait and stay deaf for good.
func test_a_menu_built_off_the_tree_listens_at_once() -> void:
	var m = _new_menu()
	autofree(m)
	m.setup("Command", _rows(), Vector2(10, 10), "fighter")
	assert_true(m._can_accept_input, "a menu built with no tree accepts input")
	assert_true(m._can_close_on_click, "and can be closed")


## Torn down BETWEEN the waits: the first wait has passed, the second must not be reached through a null tree.
func test_a_menu_removed_mid_wait_never_finishes_opening() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var m = _new_menu()
	host.add_child(m)
	m.setup("Command", _rows(), Vector2(10, 10), "fighter")
	host.remove_child(m)
	await wait_seconds(0.3)
	assert_false(m._can_accept_input, "a menu with no tree never starts listening")
	assert_false(m._can_close_on_click, "and its second wait never ran")
	m.free()


## The source half, because the defect was a script error the arms above cannot count: every wait in the build is
## followed by a tree check before the next thing that needs one.
func test_every_wait_in_the_build_checks_the_tree() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	var at := src.find("func _build_menu(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	var waits := body.count("await get_tree().create_timer(")
	assert_gt(waits, 0, "CONTROL: the build still waits")
	assert_eq(body.count("if not is_instance_valid(self) or not is_inside_tree():"), waits, "each of the %d waits is followed by a tree check" % waits)
	assert_lt(body.find("if not is_inside_tree():"), body.find("await get_tree().create_timer("), "and the first wait is not reached off the tree")
