extends GutTest

## tick 206: Toast stack has a hard MAX_STACK cap so a burst of
## events (corruption cascade, status proc storm) can't push the
## stack off-screen.
##
## With tick 205's STACK_ROW_HEIGHT=48 and BASE_Y=80, a stack of
## 14 would occupy y=80..704 — most of a 720px viewport, overlapping
## with the battle HUD hint bar. Worse: the user can't actually
## read 14 toasts in the 2s hold time. Newer events are usually
## more relevant ("you just took a crit" > "5s ago a buff applied"),
## so when at cap we evict the OLDEST and let the newest in.
##
## MAX_STACK = 5: comfortable readable count, leaves room for
## battle UI and the hint bar.

const TOAST := "res://src/ui/Toast.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Constant present ──────────────────────────────────────────────────

func test_max_stack_constant_defined() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("const MAX_STACK := 5"),
		"MAX_STACK must be 5 — comfortably readable + room for HUD")


# ── Eviction loop is in show() ─────────────────────────────────────────

func test_eviction_loop_present() -> void:
	# Pin: the while-loop evicts via pop_front + queue_free.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("while _active_layers.size() >= MAX_STACK:"),
		"eviction must use a while-loop (handles N events catching up after a cap-violation)")
	assert_true(body.contains("var oldest: Node = _active_layers.pop_front()"),
		"eviction must pop_front (oldest first) — FIFO eviction")
	assert_true(body.contains("oldest.queue_free()"),
		"evicted layer must be queue_freed")


func test_eviction_runs_after_prune_before_offset() -> void:
	# Pin: ordering must be:
	#   1. Prune dead layers (drops finished toasts that already faded)
	#   2. Evict oldest while >= cap (drops still-live oldest if at cap)
	#   3. Compute stack_offset
	# Reversing prune-then-evict means a cap of 5 with 3 dead + 2 live
	# would evict the still-live ones unnecessarily.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var prune_idx: int = body.find("_active_layers = _active_layers.filter")
	var evict_idx: int = body.find("while _active_layers.size() >= MAX_STACK:")
	var offset_idx: int = body.find("var stack_offset: float = _active_layers.size()")
	assert_gt(prune_idx, -1)
	assert_gt(evict_idx, -1)
	assert_gt(offset_idx, -1)
	assert_lt(prune_idx, evict_idx, "prune must run BEFORE evict")
	assert_lt(evict_idx, offset_idx, "evict must run BEFORE stack_offset compute")


# ── Eviction safety ───────────────────────────────────────────────────

func test_eviction_handles_invalid_layer() -> void:
	# Pin: the queue_free call is guarded by is_instance_valid — a layer
	# manually freed elsewhere shouldn't crash the eviction loop.
	var src := _read(TOAST)
	var fn_idx: int = src.find("static func show(")
	var next_fn: int = src.find("\nstatic func show_save", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if is_instance_valid(oldest):"),
		"queue_free must be guarded by is_instance_valid")


# ── Runtime: 6th toast evicts the 1st ─────────────────────────────────

func test_runtime_sixth_toast_evicts_first() -> void:
	# End-to-end: spawn 6 toasts. Only 5 should remain in _active_layers.
	# The first one (text="t1") must be gone.
	var parent := Node.new()
	add_child_autofree(parent)
	var ToastCls = load(TOAST)
	ToastCls._active_layers = []

	for i in range(6):
		ToastCls.show(parent, "t%d" % i)

	assert_eq(ToastCls._active_layers.size(), 5,
		"after 6 shows, MAX_STACK (5) toasts remain — oldest evicted")

	# The remaining toasts must be t1..t5 (t0 evicted). Find label texts.
	var texts_seen: Array = []
	for layer in ToastCls._active_layers:
		for child in layer.get_children():
			if child is Label and child.position.x == 0:
				texts_seen.append(child.text)
	assert_false("t0" in texts_seen,
		"t0 (first/oldest) must be evicted")
	assert_true("t5" in texts_seen,
		"t5 (newest) must be present")


# ── Runtime: exactly 5 toasts uses no eviction ────────────────────────

func test_runtime_five_toasts_no_eviction() -> void:
	# Pin the boundary: at exactly MAX_STACK there's no eviction yet.
	# Eviction only kicks in when SIZE >= MAX_STACK before adding new.
	# So showing the 5th should leave 5 in the stack with all original
	# texts intact.
	var parent := Node.new()
	add_child_autofree(parent)
	var ToastCls = load(TOAST)
	ToastCls._active_layers = []

	for i in range(5):
		ToastCls.show(parent, "k%d" % i)

	assert_eq(ToastCls._active_layers.size(), 5,
		"5 shows yields 5 layers (no eviction at the boundary)")

	var texts_seen: Array = []
	for layer in ToastCls._active_layers:
		for child in layer.get_children():
			if child is Label and child.position.x == 0:
				texts_seen.append(child.text)
	# All 5 originals must be present.
	for i in range(5):
		assert_true("k%d" % i in texts_seen,
			"k%d must be present (no premature eviction)" % i)


# ── Runtime: eviction frees the layer immediately (no fade) ────────────

func test_runtime_evicted_layer_queue_freed() -> void:
	# The evicted layer goes through queue_free, so after one frame it's
	# no longer a valid instance.
	var parent := Node.new()
	add_child_autofree(parent)
	var ToastCls = load(TOAST)
	ToastCls._active_layers = []

	for i in range(5):
		ToastCls.show(parent, "f%d" % i)
	# Capture the first layer reference.
	var first_layer = ToastCls._active_layers[0]
	assert_true(is_instance_valid(first_layer))

	ToastCls.show(parent, "boom")
	# After eviction the first_layer reference is queue_freed (becomes
	# invalid after one process frame). _active_layers no longer contains it.
	assert_false(first_layer in ToastCls._active_layers,
		"evicted layer must be removed from _active_layers")


# ── Cross-pin: tick 205 stacking preserved ────────────────────────────

func test_tick_205_stacking_preserved() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("const STACK_ROW_HEIGHT := 48.0"),
		"tick 205 STACK_ROW_HEIGHT preserved")
	assert_true(src.contains("var stack_offset: float = _active_layers.size() * STACK_ROW_HEIGHT"),
		"tick 205 stack_offset formula preserved")
	assert_true(src.contains("var y: float = BASE_Y + stack_offset"),
		"tick 205 y computation preserved")


func test_tick_205_lifecycle_preserved() -> void:
	var src := _read(TOAST)
	assert_true(src.contains("_active_layers.append(layer)"),
		"tick 205 layer registration preserved")
	assert_true(src.contains("tween.tween_callback(func(): _active_layers.erase(layer))"),
		"tick 205 erase-on-fade preserved")
