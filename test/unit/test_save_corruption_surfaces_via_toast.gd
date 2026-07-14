extends GutTest

## tick 178 regression: save corruption events now surface to the
## player via Toast notifications. Pre-fix:
##
##   - `save_corrupted` signal fired on every add_corruption
##     increase but had ZERO listeners. Player corrupted their
##     save (via Scriptweaver constants edit, Necromancer
##     spell, etc.) and got NO visible feedback.
##
##   - `_apply_random_corruption_effect` print()'d the new
##     effect to debug console but had no signal. The player
##     had no surface for WHICH effect (visual_glitch /
##     stat_drain / etc.) just landed.
##
## Fix:
##   - New `corruption_effect_added(effect: String)` signal
##     fires when a NEW effect lands in corruption_effects.
##   - GameLoop._ready wires both signals to Toast handlers.
##   - save_corrupted Toast fires at level thresholds
##     (10/25/50/75/100%) only — avoids spamming on every
##     small corruption nudge.
##   - corruption_effect_added Toast fires on every new
##     effect (distinct events, worth surfacing each time).

const GAME_STATE := "res://src/meta/GameState.gd"
const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Signal declaration ──────────────────────────────────────────────────

func test_corruption_effect_added_signal_declared() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("signal corruption_effect_added(effect: String)"),
		"GameState must declare corruption_effect_added(effect: String) signal")


# ── Signal emit site ───────────────────────────────────────────────────

func test_apply_random_corruption_effect_emits_signal() -> void:
	var src := _read(GAME_STATE)
	var idx: int = src.find("func _apply_random_corruption_effect")
	assert_gt(idx, -1, "_apply_random_corruption_effect must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("corruption_effect_added.emit(effect)"),
		"_apply_random_corruption_effect must emit the new-effect signal")


func test_emit_inside_only_new_effect_branch() -> void:
	# Pin: the emit must be inside the `if not effect in
	# corruption_effects:` branch — else duplicate effect picks
	# would re-fire the toast.
	var src := _read(GAME_STATE)
	var idx: int = src.find("func _apply_random_corruption_effect")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	var guard_idx: int = body.find("if not effect in corruption_effects:")
	var emit_idx: int = body.find("corruption_effect_added.emit(effect)")
	assert_gt(guard_idx, -1)
	assert_gt(emit_idx, -1)
	assert_lt(guard_idx, emit_idx,
		"signal emit must be INSIDE the 'not in corruption_effects' guard — else re-picked effects spam the toast")


# ── GameLoop wires the listeners ───────────────────────────────────────

func test_gameloop_connects_save_corrupted() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GameState.save_corrupted.connect(_on_save_corruption_increased)"),
		"GameLoop._ready must connect save_corrupted to the threshold-toast handler")


func test_gameloop_connects_corruption_effect_added() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GameState.corruption_effect_added.connect(_on_corruption_effect_added)"),
		"GameLoop._ready must connect corruption_effect_added to the danger-toast handler")


func test_gameloop_uses_is_connected_guard() -> void:
	# Defensive: GameLoop may be re-_ready'd in test contexts.
	# is_connected() guards prevent double-connection errors.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("not GameState.save_corrupted.is_connected(_on_save_corruption_increased)"),
		"save_corrupted connect must be guarded by is_connected check")
	assert_true(src.contains("not GameState.corruption_effect_added.is_connected(_on_corruption_effect_added)"),
		"corruption_effect_added connect must be guarded by is_connected check")


# ── Handler implementations ────────────────────────────────────────────

func test_save_corruption_handler_uses_thresholds() -> void:
	# Pin: handler only fires Toast at 10/25/50/75/100% thresholds.
	# Otherwise every 0.01 nudge during Edit Formula would spam.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_save_corruption_increased")
	assert_gt(idx, -1, "save corruption handler must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("var thresholds: Array[int] = [10, 25, 50, 75, 100]"),
		"handler must use threshold list to gate toast firing")
	assert_true(body.contains("Toast.show(self,"),
		"handler must call Toast.show on threshold cross")


func test_save_corruption_handler_uses_warning_color() -> void:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_save_corruption_increased")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("Toast.WARNING_COLOR"),
		"save corruption toast uses WARNING_COLOR (orange) — distinct from default")


func test_save_corruption_handler_tracks_shown_thresholds() -> void:
	# Pin: handler tracks which thresholds have been shown to
	# avoid re-toasting between thresholds (e.g., level goes
	# 0.26 → 0.27 → 0.30 — all in [25, 50) band, only one toast).
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_save_corruption_increased")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("corruption_thresholds_shown"),
		"handler must persist shown-threshold tracker as meta")
	assert_true(body.contains("if shown.has(prev_threshold):"),
		"handler must check tracker before re-firing toast at the same threshold")


func test_corruption_effect_handler_uses_danger_color() -> void:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_corruption_effect_added")
	assert_gt(idx, -1, "corruption effect handler must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("Toast.DANGER_COLOR"),
		"corruption-effect toast uses DANGER_COLOR (red) — more severe than threshold")


func test_corruption_effect_handler_prettifies_effect_name() -> void:
	# Pin: effect display uses replace+to_upper for dramatic
	# all-caps presentation ("VISUAL GLITCH" not "visual_glitch").
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_corruption_effect_added")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("effect.replace(\"_\", \" \").to_upper()"),
		"corruption-effect toast must uppercase the effect name for dramatic effect")
