extends GutTest

## Regression: AutogrindController.stop_grind() must reset the three
## "next battle" deferred-modifier fields so a stop-mid-grind doesn't
## leak fatigue / flee state into the next grind session.
##
## The bug shape: _request_next_battle sets these mid-grind…
##   • _skip_next_battle           — when a flee_battle rule fires
##   • _next_battle_enemy_boost    — when system fatigue rolls "enemy_boost"
##   • _next_battle_exp_bonus      — when system fatigue rolls "exp_surge"
## …and they're consumed only when the NEXT battle actually launches. If
## the player stops the grind in between (between fatigue trigger and
## battle launch — a real window during BETWEEN_BATTLES sleep), the
## flags would persist to the next start_grind. First battle of the
## new session would then be skipped (flee), have arbitrarily-buffed
## enemies (+20% stats), or pay arbitrarily-bumped EXP (+50%), without
## any rule justifying it.
##
## Fix: stop_grind clears all three to their default values, matching
## the other in-progress state fields (_current_battle_is_meta_boss,
## _current_meta_boss_data, _pending_tier_switch) it already resets.
##
## Tests:
##   • Source pin that stop_grind resets the three fields
##   • Behavioural: set the fields true / nonzero, call stop_grind,
##     assert they're back to defaults
##   • Survives the no-op early-return path (if state is already IDLE,
##     no field is touched — preserves the existing semantics for that
##     case so an unintentional stop_grind doesn't clear legitimate
##     state set by some other system path)

const AUTOGRIND_CONTROLLER_PATH := "res://src/autogrind/AutogrindController.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pin ────────────────────────────────────────────────────────────────

func test_stop_grind_resets_next_battle_state_fields() -> void:
	var text := _read(AUTOGRIND_CONTROLLER_PATH)
	var idx := text.find("func stop_grind")
	assert_gt(idx, -1, "stop_grind must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Each of the three fields must be reset to its default value inside
	# stop_grind. Pin both the field name and the right-hand-side default.
	assert_true(body.contains("_skip_next_battle = false"),
		"stop_grind must reset _skip_next_battle to false")
	assert_true(body.contains("_next_battle_enemy_boost = 0.0"),
		"stop_grind must reset _next_battle_enemy_boost to 0.0")
	assert_true(body.contains("_next_battle_exp_bonus = 0.0"),
		"stop_grind must reset _next_battle_exp_bonus to 0.0")


# ── Behavioural ──────────────────────────────────────────────────────────────

func _make_controller() -> Node:
	var AGCScript: GDScript = load(AUTOGRIND_CONTROLLER_PATH)
	var ctrl: Node = AGCScript.new()
	add_child_autofree(ctrl)
	return ctrl


func test_stop_grind_clears_pending_skip_flag() -> void:
	var ctrl := _make_controller()
	# Force a non-IDLE state so stop_grind doesn't early-return.
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	ctrl._skip_next_battle = true
	ctrl.stop_grind("test")
	assert_false(ctrl._skip_next_battle,
		"stop_grind must clear _skip_next_battle so it doesn't leak into the next session")


func test_stop_grind_clears_pending_enemy_boost() -> void:
	var ctrl := _make_controller()
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	ctrl._next_battle_enemy_boost = 0.2
	ctrl.stop_grind("test")
	assert_almost_eq(float(ctrl._next_battle_enemy_boost), 0.0, 0.0001,
		"stop_grind must clear _next_battle_enemy_boost so first battle of next session isn't silently buffed")


func test_stop_grind_clears_pending_exp_bonus() -> void:
	var ctrl := _make_controller()
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	ctrl._next_battle_exp_bonus = 0.5
	ctrl.stop_grind("test")
	assert_almost_eq(float(ctrl._next_battle_exp_bonus), 0.0, 0.0001,
		"stop_grind must clear _next_battle_exp_bonus so first battle of next session doesn't silently pay bonus EXP")


func test_stop_grind_idle_early_return_does_not_clobber_state() -> void:
	# Regression guard: if _state is already IDLE, stop_grind returns
	# immediately without touching these fields. Documents that the
	# pre-fix early-return invariant is preserved — clearing is gated by
	# the same "actually grinding" check that the rest of the body uses.
	var ctrl := _make_controller()
	ctrl._state = ctrl.State.IDLE
	ctrl._skip_next_battle = true
	ctrl._next_battle_enemy_boost = 0.2
	ctrl._next_battle_exp_bonus = 0.5
	ctrl.stop_grind("test")
	assert_true(ctrl._skip_next_battle,
		"idle early-return must NOT clobber _skip_next_battle (preserves caller-set state)")
	assert_almost_eq(float(ctrl._next_battle_enemy_boost), 0.2, 0.0001,
		"idle early-return must NOT clobber _next_battle_enemy_boost")
	assert_almost_eq(float(ctrl._next_battle_exp_bonus), 0.5, 0.0001,
		"idle early-return must NOT clobber _next_battle_exp_bonus")
