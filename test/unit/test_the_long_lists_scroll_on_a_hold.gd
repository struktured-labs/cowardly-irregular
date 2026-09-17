extends GutTest

## struktured 2026-08-22 asked for hold-to-repeat in menus. It reached EquipmentMenu, Win98Menu and
## (2026-09-17) the autobattle grid. The four longest lists in the game were not among them:
##
##     ItemsMenu       172 items      page jump, one row per press otherwise
##     AbilitiesMenu   289 abilities  page jump, one row per press otherwise
##     JobMenu         14 jobs + slots
##     QuestLog        scrolls by LINES, 3 per press
##
## Paging is a DIFFERENT affordance, not a substitute: a trigger pull moves exactly ten rows,
## clamped, which is a jump rather than a scroll. Holding a direction is the baseline JRPG gesture
## and these four did not have it.
##
## ⛔ THE LOAD-BEARING HALF IS THE REFUSAL, NOT THE WALK. MenuRepeat polls Input directly and
## inherits NONE of _input's early returns — Win98Menu measured a 2s hold stepping the parent 22
## times behind an open submenu. Every arm below that walks has a sibling proving the hidden menu
## stays put.

const PAST_DELAY := 0.5   ## past MenuRepeat.INITIAL_DELAY, so one tick arms the hold and the next fires

const ITEMS := "res://src/ui/ItemsMenu.gd"
const ABILITIES := "res://src/ui/AbilitiesMenu.gd"
const JOBS := "res://src/ui/JobMenu.gd"
const QUESTLOG := "res://src/ui/QuestLog.gd"


func after_each() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")


func _menu(path: String) -> Node:
	var n: Node = load(path).new()
	add_child_autofree(n)
	n.visible = true
	return n


## Returns the change in `field` over `ticks` polled frames with `action` held.
func _hold(m: Node, field: String, action: String, ticks: int = 3) -> int:
	var before: int = int(m.get(field))
	Input.action_press(action, 1.0)
	for i in range(ticks):
		m._process(PAST_DELAY)
	Input.action_release(action)
	return int(m.get(field)) - before


## ⛔ EXISTENCE FIRST, and DERIVED: a hand-listed set of four would not notice a fifth menu wiring
## _nav_repeat without a _process to tick it. Every holder of the latch must drive it.
func test_every_menu_that_holds_the_latch_also_ticks_it() -> void:
	var holders: Array = []
	var half_wired: Array = []
	for path in _ui_scripts("res://src/ui"):
		var code := FileAccess.get_file_as_string(path)
		if not code.contains("MenuRepeat.new("):
			continue
		holders.append(path)
		if not code.contains("_nav_repeat.tick("):
			half_wired.append(path)
	assert_gt(holders.size(), 4, "the scan must find the holders, or this arm passes over nothing")
	assert_eq(half_wired, [],
		"these construct a MenuRepeat and never tick it — the latch exists and no hold ever fires: %s"
			% [half_wired])


## A holder that does not reset on refusal keeps its ramp across a close/reopen.
func test_every_holder_refuses_before_it_ticks() -> void:
	var unguarded: Array = []
	for path in _ui_scripts("res://src/ui"):
		var code := FileAccess.get_file_as_string(path)
		if not code.contains("MenuRepeat.new("):
			continue
		if not code.contains("_nav_repeat.reset()"):
			unguarded.append(path)
	assert_eq(unguarded, [],
		"these tick a hold with no reset path — MenuRepeat polls Input and inherits none of "
		+ "_input's early returns, so a hidden menu keeps stepping: %s" % [unguarded])


func _ui_scripts(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_ui_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func test_holding_down_walks_the_item_list() -> void:
	var m := _menu(ITEMS)
	var items: Array = []
	for i in range(30):
		items.append({"data": {}, "count": 1})
	m.set("_item_list", items)
	m.set("selected_item_index", 0)
	m.set("mode", 0)
	assert_gt(_hold(m, "selected_item_index", "ui_down"), 0,
		"172 items at one row per press is the walk this exists to shorten")


func test_a_hidden_item_list_does_not_walk() -> void:
	var m := _menu(ITEMS)
	var items: Array = []
	for i in range(30):
		items.append({"data": {}, "count": 1})
	m.set("_item_list", items)
	m.set("selected_item_index", 5)
	m.set("mode", 0)
	m.visible = false
	assert_eq(_hold(m, "selected_item_index", "ui_down"), 0,
		"a hold must not navigate a closed menu — the poll never sees _input's `if not visible`")


## The press path reaches target mode only through a non-empty check; a poll has no such history.
func test_target_mode_does_not_index_an_empty_list() -> void:
	var m := _menu(ITEMS)
	m.set("_item_list", [])
	m.set("selected_item_index", 0)
	m.set("mode", 1)
	assert_true(m._nav_blocked(),
		"target mode with an empty list must refuse, or the tick indexes _item_list[0] out of range")


func test_holding_down_walks_the_ability_list() -> void:
	var m := _menu(ABILITIES)
	var abilities: Array = []
	for i in range(30):
		abilities.append({"id": "a%d" % i, "name": "A%d" % i})
	m.set("_abilities_list", abilities)
	m.set("selected_index", 0)
	assert_gt(_hold(m, "selected_index", "ui_down"), 0,
		"289 abilities at one row per press is the walk this exists to shorten")


func test_a_hidden_ability_list_does_not_walk() -> void:
	var m := _menu(ABILITIES)
	var abilities: Array = []
	for i in range(30):
		abilities.append({"id": "a%d" % i, "name": "A%d" % i})
	m.set("_abilities_list", abilities)
	m.set("selected_index", 5)
	m.visible = false
	assert_eq(_hold(m, "selected_index", "ui_down"), 0, "a hold must not navigate a closed menu")


func test_holding_down_scrolls_the_quest_log() -> void:
	var m := _menu(QUESTLOG)
	m.set("_total_lines", 200)
	m.set("_max_visible_lines", 20)
	m.set("_scroll_offset", 0)
	assert_gt(_hold(m, "_scroll_offset", "ui_down"), 0,
		"the log scrolls three lines per press; a long log is a long hold")


func test_a_hidden_quest_log_does_not_scroll() -> void:
	var m := _menu(QUESTLOG)
	m.set("_total_lines", 200)
	m.set("_max_visible_lines", 20)
	m.set("_scroll_offset", 30)
	m.visible = false
	assert_eq(_hold(m, "_scroll_offset", "ui_down"), 0, "a hold must not scroll a closed log")


## ⚠ NO CLAMP ARM HERE, DELIBERATELY. I wrote two and mutation killed both: _build_ui()
## re-clamps _scroll_offset on every rebuild, so replacing _scroll_step's clampi with an unbounded
## mini() left the suite GREEN. The arms measured _build_ui's clamp and called it mine.
##
## That also retires the defect claim they were written for: the old `_scroll_offset -= 3` behind
## `> 0` did go to -1 from offset 2, but _build_ui() corrected it before anything read it, so no player
## ever saw it. The clamp in _scroll_step stays because a single owner should be correct read on
## its own — it is not a bugfix and this file will not imply it is.


## JobMenu's SLOT_SELECT mode steps over the SLOTS const, so it needs no party state. The
## JOB_SELECT half calls _get_available_jobs(), which reads `character` — covered by the derived
## arms above rather than by a fixture that would have to build a Combatant to say one true thing.
func test_holding_down_walks_the_job_slots() -> void:
	var m := _menu(JOBS)
	m.set("mode", 0)
	m.set("selected_slot", 0)
	# SLOTS has TWO entries, so an EVEN step count wraps back to the start and reads as no movement.
	var moved := _hold(m, "selected_slot", "ui_down", 4)
	assert_ne(moved, 0,
		"a held direction must step the slot cursor on its own — and this arm needs an ODD number "
		+ "of steps to say so: over a 2-row wrap an even ramp lands where it started")


func test_a_hidden_job_menu_does_not_walk() -> void:
	var m := _menu(JOBS)
	m.set("mode", 0)
	m.set("selected_slot", 0)
	m.visible = false
	assert_eq(_hold(m, "selected_slot", "ui_down", 4), 0, "a hold must not navigate a closed menu")
