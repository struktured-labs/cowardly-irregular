extends GutTest

## tick 205: Toast.show stacks simultaneous toasts vertically
## so they don't overlap at y=80 as unreadable mush.
##
## Pre-fix: every Toast.show() call positioned the label at fixed
## Vector2(0, 80). If two events fired in the same frame (e.g.,
## corruption_effect_added + game_constant_modified during a single
## battle round — see ticks 178/179), both labels rendered at the
## same y, overlapping each other and producing unreadable garbage.
##
## Fix: a static _active_layers tracker records live toast layers.
## Each new toast offsets its y by `count * STACK_ROW_HEIGHT`.
## Layers prune themselves from the list as they fade, so a fully-
## consumed queue doesn't leave stale slots.

const TOAST := "res://src/ui/Toast.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Stack tracker var present ──────────────────────────────────────────

func test_active_layers_static_var_declared() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("static var _active_layers: Array = []"),
		"_active_layers must be a static Array (shared across all Toast.show calls)")


func test_row_height_constant_defined() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("const STACK_ROW_HEIGHT := 48.0"),
		"STACK_ROW_HEIGHT must be a named const for stacking math")
	assert_true(src.contains("const BASE_Y := 80.0"),
		"BASE_Y must be a named const (the first-toast position)")


# ── Stack offset computation ───────────────────────────────────────────

func test_show_prunes_invalid_before_offset_compute() -> void:
	# Pin: the filter MUST run before stack_offset is computed,
	# otherwise dead layers inflate the offset and the new toast
	# spawns below an empty slot.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	assert_gt(fn_idx, -1)
	# The next static func is `show_save`.
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var filter_idx: int = body.find("_active_layers = _active_layers.filter")
	var offset_idx: int = body.find("var stack_offset: float = _active_layers.size()")
	assert_gt(filter_idx, -1, "filter call missing")
	assert_gt(offset_idx, -1, "stack_offset compute missing")
	assert_lt(filter_idx, offset_idx,
		"filter must run BEFORE stack_offset is computed")


func test_y_position_uses_base_plus_offset() -> void:
	# Pin: the label y = BASE_Y + stack_offset, not the bare 80.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("var y: float = BASE_Y + stack_offset"),
		"label y must be BASE_Y + stack_offset (stack from top)")
	assert_true(body.contains("label.position = Vector2(0, y)"),
		"label uses computed y")


func test_shadow_position_uses_y_plus_offset() -> void:
	# Pin: shadow follows the label's y (offset by 2px each axis as
	# before). Old hardcoded `82` would leave the shadow at top
	# while the label moves down.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("shadow.position = Vector2(2, y + 2)"),
		"shadow follows label y (y + 2 vertical offset for shadow effect)")


# ── Layer lifecycle ────────────────────────────────────────────────────

func test_new_toast_appends_to_active() -> void:
	# Pin: each show() appends its layer to _active_layers BEFORE
	# the tween runs.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("_active_layers.append(layer)"),
		"new layer must be tracked in _active_layers")


func test_layer_erased_when_done() -> void:
	# Pin: the tween chain includes a callback that erases the
	# layer from _active_layers as it finishes. Otherwise the
	# tracker leaks forever and every new toast renders further
	# down the screen.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("tween.tween_callback(func(): _active_layers.erase(layer))"),
		"tween must erase layer from _active_layers as it finishes")
	# AND queue_free still runs (don't leak CanvasLayer).
	assert_true(body.contains("tween.tween_callback(layer.queue_free)"),
		"tween must still queue_free the layer")


# ── Negative pins: pre-fix shape gone ──────────────────────────────────

func test_hardcoded_y80_position_gone() -> void:
	# Negative pin: the old `label.position = Vector2(0, 80)` and
	# `shadow.position = Vector2(2, 82)` literals must be gone.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("label.position = Vector2(0, 80)"),
		"hardcoded label.position must be gone")
	assert_false(body.contains("shadow.position = Vector2(2, 82)"),
		"hardcoded shadow.position must be gone")


# ── Real stacking behavior at runtime ──────────────────────────────────

func test_runtime_two_simultaneous_toasts_have_different_y() -> void:
	# End-to-end: spawn two toasts back-to-back in the same frame
	# and verify their label y positions differ by STACK_ROW_HEIGHT.
	# Catches a regression where the stack_offset isn't actually
	# applied to the label position.
	var parent := Node.new()
	add_child_autofree(parent)
	# Get current active count (should be 0 in test isolation).
	var ToastCls = load(TOAST)
	# Reset the static tracker so the test isn't polluted by prior tests.
	ToastCls._active_layers = []

	ToastCls.show(parent, "first")
	ToastCls.show(parent, "second")

	# Both layers should be in _active_layers and have distinct y for their labels.
	assert_eq(ToastCls._active_layers.size(), 2,
		"two simultaneous toasts must both be tracked")
	# Label is at x=0, shadow at x=2 — filter to the non-shadow label.
	var y_values: Array = []
	for layer in ToastCls._active_layers:
		for child in layer.get_children():
			if child is Label and child.text in ["first", "second"] and child.position.x == 0:
				y_values.append(child.position.y)
	# Should have 2 distinct y values.
	var unique: Dictionary = {}
	for y in y_values:
		unique[y] = true
	assert_eq(unique.size(), 2,
		"two stacked toasts must have distinct y positions (got %s)" % str(y_values))
	# The difference between them should be STACK_ROW_HEIGHT (48).
	y_values.sort()
	if y_values.size() == 2:
		assert_eq(y_values[1] - y_values[0], ToastCls.STACK_ROW_HEIGHT,
			"second toast must be STACK_ROW_HEIGHT below the first")

	# Cleanup is handled by autofree on parent.


func test_runtime_isolated_toast_uses_base_y() -> void:
	# After clearing _active_layers, a single new toast spawns at BASE_Y.
	var parent := Node.new()
	add_child_autofree(parent)
	var ToastCls = load(TOAST)
	ToastCls._active_layers = []

	ToastCls.show(parent, "lone")
	assert_eq(ToastCls._active_layers.size(), 1,
		"single toast tracked")
	var layer = ToastCls._active_layers[0]
	# Filter to the non-shadow label (label at x=0, shadow at x=2).
	for child in layer.get_children():
		if child is Label and child.text == "lone" and child.position.x == 0:
			assert_eq(child.position.y, ToastCls.BASE_Y,
				"first toast spawns at BASE_Y, not BASE_Y + offset")


# ── Color and variant helpers preserved ────────────────────────────────

func test_show_warning_helper_preserved() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("static func show_warning(parent: Node, text: String) -> void:"),
		"show_warning helper preserved")


func test_show_save_helper_preserved() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("static func show_save(parent: Node, location: String = \"\") -> void:"),
		"show_save helper preserved")
