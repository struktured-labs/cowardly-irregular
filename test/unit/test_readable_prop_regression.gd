extends GutTest

## Phil's notebook, and the mechanism under it. Built on `interact()` because `interaction_callback` is set in 4 interiors and read by NOTHING.

const PropScript = preload("res://src/exploration/ReadableProp.gd")

var _prop: Node = null


func before_each() -> void:
	_prop = PropScript.new()
	add_child_autofree(_prop)


func _entries() -> Array:
	return ["one", {"heading": "H", "body": "two"}, "three"]


## The seam OverworldController actually dispatches on: group + interact().
func test_prop_registers_on_the_seam_the_controller_really_uses() -> void:
	assert_true(_prop.is_in_group("interactables"),
		"OverworldController's fallback scans the interactables group — outside it the prop is unreachable")
	assert_true(_prop.has_method("interact"),
		"the dispatch requires has_method('interact'); interaction_callback meta is read by nothing in src/")


## Reactive-vs-fixed must stay a DATA question, so the provider is re-invoked per open.
func test_provider_is_reinvoked_on_every_open() -> void:
	var calls := [0]
	var provider := func() -> Array:
		calls[0] += 1
		return ["page"]
	_prop.setup("Notebook", provider)
	_prop.interact(null)
	_prop._close_panel()
	_prop.interact(null)
	assert_eq(calls[0], 2,
		"a fixed provider returns a constant and a reactive one reads state — the mechanism must not " +
		"cache, or a corruption-reactive notebook would freeze at whatever it said the first time")


func test_paging_is_clamped_at_both_ends() -> void:
	_prop.setup("Notebook", _entries)
	_prop.interact(null)
	assert_eq(_prop._page, 0, "opens on the first page")
	_prop._page = _entries().size() - 1
	_prop._render_page()
	assert_eq(_prop._page, _entries().size() - 1, "last page holds")


## Bare strings and headed dicts must both render; authors mix them freely.
func test_both_entry_forms_are_accepted() -> void:
	_prop.setup("Notebook", _entries)
	_prop.interact(null)
	var bare: Dictionary = _prop._entry_at(0)
	var headed: Dictionary = _prop._entry_at(1)
	assert_eq(bare["body"], "one", "a bare String becomes the page body")
	assert_eq(bare["heading"], "", "a bare String has no heading")
	assert_eq(headed["heading"], "H", "a Dictionary entry keeps its heading")
	assert_eq(headed["body"], "two", "and its body")


## An empty provider must not open an empty panel the player cannot explain.
func test_empty_provider_opens_nothing() -> void:
	_prop.setup("Notebook", func() -> Array: return [])
	_prop.interact(null)
	assert_false(_prop.is_open(),
		"no entries means no panel — an empty book that still opens reads as a bug, not as emptiness")


## The panel must be a CanvasLayer, or the camera leaves it behind (InnInterior:1487).
func test_panel_is_a_canvaslayer_not_a_control_under_the_node2d() -> void:
	_prop.setup("Notebook", _entries)
	_prop.interact(null)
	assert_true(_prop.is_open(), "the panel must open for this test to mean anything")
	var found: Node = null
	for c in _prop.get_children():
		if c is CanvasLayer:
			found = c
	assert_not_null(found,
		"the panel must hang off a CanvasLayer. A Control parented to this Node2D reads " +
		"screen-center pixels as WORLD coords and the camera abandons it — the 2026-07-25 " +
		"'menu out of sight to the right of the inn' bug, which a book panel reproduces exactly")


## Phil's notebook must actually be PLACED, or the mechanism is another inert asset.
func test_phil_notebook_is_wired_into_harmonia() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	assert_gt(src.length(), 0, "HarmoniaVillage must load")
	assert_true(src.contains("ReadablePropScript.new()"),
		"the prop must be instantiated somewhere — a mechanism with no consumer is the inert class")
	assert_true(src.contains("_phil_notebook_entries"),
		"and pointed at a provider")
	assert_true(src.contains("func _phil_notebook_entries"),
		"which must exist, or the Callable resolves to nothing and the book silently never opens")
