extends GutTest

## Ring selector for autobattle/autogrind ability + item pickers
## (struktured 2026-07-28: "consider a ring like selector for the different abilities in
##  autobattle/autogrind menus").
##
## Why a ring here: this project is controller-first, and on a d-pad a list costs O(n) presses
## to reach item n while a ring is a DIRECTION. That advantage only holds while every option is
## visible at once, which is why it pages at RING_CAPACITY instead of cramming — a 30-spoke ring
## would be slower than the list it replaced.

const PickerScript := preload("res://src/ui/RadialPicker.gd")
const EDITOR_PATH := "res://src/ui/autobattle/AutobattleGridEditor.gd"

var _viewport: SubViewport


func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	add_child(_viewport)


func after_each() -> void:
	_viewport.queue_free()


func _picker(n: int) -> Control:
	var opts: Array = []
	for i in range(n):
		opts.append({"id": "opt_%d" % i, "label": "Option %d" % i})
	var p: Control = PickerScript.new()
	p.setup({"title": "Ability", "kind": "ability_id", "options": opts, "selected": 0})
	p.size = Vector2(1280, 720)
	_viewport.add_child(p)
	return p


func test_picker_builds_for_a_typical_ability_list() -> void:
	var p := _picker(8)
	assert_not_null(p, "the ring must build for a normal-sized ability list")
	p.free()


func test_ring_pages_rather_than_cramming() -> void:
	# The design constraint: past RING_CAPACITY the direction->item mapping stops being
	# readable, so it must page. A ring that keeps adding spokes is worse than a list.
	var cap: int = PickerScript.RING_CAPACITY
	var p := _picker(cap * 3)
	assert_eq(p._page_count(), 3, "%d options at capacity %d must be 3 pages" % [cap * 3, cap])
	assert_eq(p._page_slice().size(), cap, "a full page shows exactly RING_CAPACITY spokes")
	p.free()


func test_a_short_list_is_a_single_page() -> void:
	var p := _picker(4)
	assert_eq(p._page_count(), 1, "a short list must not paginate")
	assert_eq(p._page_slice().size(), 4)
	p.free()


func test_paging_wraps_and_moves_the_selection_with_it() -> void:
	var cap: int = PickerScript.RING_CAPACITY
	var p := _picker(cap * 2)
	p._turn_page(1)
	assert_eq(p._page, 1, "L1/R1 must page")
	assert_gt(p._selected, cap - 1, "selection must follow onto the new page, not strand off-ring")
	p._turn_page(1)
	assert_eq(p._page, 0, "paging wraps")
	p.free()


func test_direction_selects_the_nearest_spoke() -> void:
	# The whole premise: pushing a direction lands on the option in that direction.
	var p := _picker(4)   # slots at 12, 3, 6, 9 o'clock
	p._draw()             # establishes _center
	p._select_toward(Vector2.UP)
	assert_eq(p._selected, 0, "up must select the 12 o'clock spoke")
	p._select_toward(Vector2.DOWN)
	assert_eq(p._selected, 2, "down must select the 6 o'clock spoke")
	p._select_toward(Vector2.RIGHT)
	assert_eq(p._selected, 1, "right must select the 3 o'clock spoke")
	p._select_toward(Vector2.LEFT)
	assert_eq(p._selected, 3, "left must select the 9 o'clock spoke")
	p.free()


func test_first_slot_is_always_twelve_oclock() -> void:
	# A stable anchor matters more than balanced spacing once paging exists: the player
	# should always know where entry 1 of the current page is.
	for n in [3, 5, 8, 10]:
		var p := _picker(n)
		var a: float = p._slot_angle(0, n)
		assert_almost_eq(a, -PI / 2.0, 0.001, "slot 0 of %d must sit at 12 o'clock" % n)
		p.free()


func test_selection_opens_on_the_page_containing_the_current_value() -> void:
	# Re-opening a picker on an ability that lives on page 3 must not dump the player on page 1.
	var cap: int = PickerScript.RING_CAPACITY
	var opts: Array = []
	for i in range(cap * 3):
		opts.append({"id": "opt_%d" % i, "label": "Option %d" % i})
	var p: Control = PickerScript.new()
	p.setup({"title": "Ability", "kind": "ability_id", "options": opts, "selected": cap * 2 + 1})
	assert_eq(p._page, 2, "the ring must open on the page holding the current selection")
	p.free()


func test_empty_options_do_not_crash() -> void:
	var p: Control = PickerScript.new()
	p.setup({"title": "Ability", "kind": "ability_id", "options": [], "selected": 0})
	p.size = Vector2(640, 480)
	_viewport.add_child(p)
	p._draw()
	p._select_toward(Vector2.UP)
	assert_true(true, "an empty option set must be survivable, not a crash")
	p.free()


# ── integration with the grid editor ────────────────────────────────

func test_ring_is_used_for_content_kinds_only() -> void:
	# Ring for browsing (abilities, items); list for short semantic choices. The ring is not
	# strictly better — it is better for BROWSING, and claiming otherwise would make
	# condition_type worse.
	var src := FileAccess.get_file_as_string(EDITOR_PATH)
	assert_string_contains(src, "RADIAL_KINDS", "the editor must declare which kinds get the ring")
	var idx := src.find("RADIAL_KINDS :=")
	var decl := src.substr(idx, 120)
	assert_string_contains(decl, "ability_id", "abilities are the kind struktured named")
	assert_string_contains(decl, "item_id", "items browse the same way")
	assert_false(decl.contains("condition_type"),
		"structural kinds must keep the list — a ring would make them slower to read")


func test_both_pickers_commit_through_one_seam() -> void:
	# Two presentations of the same choice. A second dispatch copy is how one picker silently
	# stops handling a kind the other gained.
	var src := FileAccess.get_file_as_string(EDITOR_PATH)
	assert_string_contains(src, "func _commit_option_choice",
		"the commit dispatch must be extracted, not duplicated per picker")
	assert_eq(src.count("_apply_ability_id("), 2,
		"exactly one definition and one call site — a second call means the dispatch was copied")
