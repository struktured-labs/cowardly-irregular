extends GutTest

## Regression (2026-07-08, found by the deploy render smoke): BattleScene's
## _on_round_started_corruption_glitch() took 0 args but round_started emits 1.
## Godot 4 accepts the connect and then REFUSES the call at every emit — the
## corruption stutter silently never played (error spam only at runtime).
## This scans every direct `BattleManager.<signal>.connect(handler)` in
## BattleScene.gd and asserts the handler's parameter count can actually
## receive the signal's declared args, so the whole class is pinned.

const BM_PATH := "res://src/battle/BattleManager.gd"
const BS_PATH := "res://src/battle/BattleScene.gd"


func _signal_arg_counts(src: String) -> Dictionary:
	var out := {}
	var rx := RegEx.new()
	rx.compile("(?m)^signal\\s+(\\w+)(\\(([^)]*)\\))?")
	for m in rx.search_all(src):
		var args := m.get_string(3).strip_edges()
		out[m.get_string(1)] = 0 if args == "" else args.split(",").size()
	return out


func _handler_param_range(src: String, fname: String) -> Array:
	# Returns [required, total] param counts, or [] if not found.
	var rx := RegEx.new()
	rx.compile("(?m)^func\\s+%s\\(([^)]*)\\)" % fname)
	var m := rx.search(src)
	if m == null:
		return []
	var params := m.get_string(1).strip_edges()
	if params == "":
		return [0, 0]
	var required := 0
	var total := 0
	for p in params.split(","):
		total += 1
		if not ("=" in p):
			required += 1
	return [required, total]


func test_every_direct_battlemanager_signal_handler_has_compatible_arity() -> void:
	var bm := FileAccess.get_file_as_string(BM_PATH)
	var bs := FileAccess.get_file_as_string(BS_PATH)
	var signals := _signal_arg_counts(bm)
	assert_gt(signals.size(), 10, "sanity: BattleManager declares its signal roster")

	var rx := RegEx.new()
	rx.compile("BattleManager\\.(\\w+)\\.connect\\((\\w+)\\)")
	var checked := 0
	for m in rx.search_all(bs):
		var sig := m.get_string(1)
		var handler := m.get_string(2)
		if handler == "func" or not signals.has(sig):
			continue
		var argc: int = signals[sig]
		var range_: Array = _handler_param_range(bs, handler)
		if range_.is_empty():
			continue  # handler defined elsewhere (inherited/autoload) — out of scope
		checked += 1
		assert_true(range_[0] <= argc and argc <= range_[1],
			"BattleScene.%s takes %d..%d params but signal %s emits %d — Godot silently refuses the call at every emit (the corruption-glitch bug class)"
			% [handler, range_[0], range_[1], sig, argc])
	assert_gt(checked, 5, "sanity: the connect scan should find BattleScene's handler roster")


func test_corruption_glitch_handler_accepts_round_number() -> void:
	var bs := FileAccess.get_file_as_string(BS_PATH)
	var range_ := _handler_param_range(bs, "_on_round_started_corruption_glitch")
	assert_eq(range_.size(), 2, "handler must exist")
	assert_true(range_[0] <= 1 and 1 <= range_[1],
		"the original bug: corruption-glitch handler must accept round_started's 1 arg")
