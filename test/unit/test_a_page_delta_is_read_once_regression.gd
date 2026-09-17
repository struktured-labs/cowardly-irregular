extends GutTest

## ⛔ I BROKE THIS MYSELF THIS MORNING. Adding the analog latch to MenuPaging.page_delta made it a
## CONSUMING read, and ten menus called it TWICE in one handler — once as the branch condition,
## once inside the branch for the direction:
##
##     elif MenuPaging.page_delta(event) != 0:
##         ... + MenuPaging.page_delta(event) * PAGE_ROWS ...
##
## PROBED, not reasoned:
##     trigger (L2)  first = -1   second = 0     <- branch taken, input consumed, cursor moves ZERO
##     shoulder btn  first = -1   second = -1    <- buttons are not latched, so they page correctly
##
## So paging was DEAD on the analog triggers in ten menus and alive on the two routes anyone tests
## with. @cowir-cutscenes found it; the same shape as my world-map arm passing on a two-column grid.
##
## THIS IS A CALL-GRAPH CHECK AND IT OWNS THE PROPERTY: that the second read is CONSUMED. No arm
## can observe that directly — a consumed read returns 0, and so does "not a paging input at all".
##
## ⚠️ I first wrote that the defect was therefore invisible to behavioural arms. OVERSTATED, and it
## would have discouraged the right test: the CONSEQUENCE is plainly visible — the cursor moves 0
## rows where it should move PAGE_ROWS — as long as the arm drives the MENU'S OWN _input and not
## the helper. cowir-music wrote exactly that for JukeboxMenu; it reds on main's call site while
## its shoulder-button control passes. That arm owns the outcome for one menu; this owns the
## property for all ten. Neither substitutes for the other.

const PAGING_CALL := "MenuPaging.page_delta(event)"


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func test_no_file_reads_page_delta_twice() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var offenders: Array = []
	var scanned := 0
	var callers := 0
	for path in _gd_files("res://src"):
		var code: String = GdSource.code_of(path)
		if code == "":
			continue
		scanned += 1
		var n := code.count(PAGING_CALL)
		if n > 0:
			callers += 1
		if n > 1:
			offenders.append("%s (%d calls)" % [path.get_file(), n])
	assert_gt(scanned, 200, "the scan must read the src tree; a short corpus passes vacuously")
	assert_gt(callers, 5, "…and must actually find paging menus, or it is scanning the wrong thing")
	assert_eq(offenders, [],
		"page_delta CONSUMES the trigger axis — a second read in one handler returns 0 and the "
		+ "branch pages nothing on L2/R2. Read it once into a var and reuse it: %s" % [offenders])


## The property the call-graph check stands on. If this stops being true the check is pointless,
## and someone should delete it rather than keep a rule with no reason.
func test_a_second_read_of_one_trigger_event_returns_zero() -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_TRIGGER_LEFT
	ev.axis_value = 0.9
	Input.action_press("battle_defer")
	assert_eq(MenuPaging.page_delta(ev), -1, "the first read pages")
	assert_eq(MenuPaging.page_delta(ev), 0, "the second read of the SAME event returns nothing")
	Input.action_release("battle_defer")
	var rel := InputEventJoypadButton.new()
	rel.button_index = JOY_BUTTON_LEFT_SHOULDER
	rel.pressed = false
	MenuPaging.page_delta(rel)
