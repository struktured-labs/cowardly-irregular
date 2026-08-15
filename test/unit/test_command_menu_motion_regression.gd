extends GutTest

## Phase D item 1 — command menu open/close motion.
## The defect this guards is msg 2503/2529: force_close() emits menu_closed, whose handler
## nulls active_win98_menu behind an identity guard. If Phase D had deferred that emit to
## sit alongside the fade, the next PC's menu would already be active when it landed and the
## guard would be comparing the wrong pair. ONLY the visual free defers.
##
## Tier-dependent BEHAVIOUR is asserted at source level here, deliberately: exercising it
## live would mean writing Engine.time_scale, which this project has a documented watchdog
## and double-scaling history around. The tier FUNCTION is pinned separately and behaviourally
## in test_presentation_tier_ladder_regression.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const BattleJuiceClass = preload("res://src/battle/BattleJuice.gd")
const MENU_SRC := "res://src/ui/Win98Menu.gd"
const CMD_SRC := "res://src/battle/BattleCommandMenu.gd"


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "CONTROL: could not open %s — every source assertion below is vacuous" % path)
	return f.get_as_text() if f else ""


func _body_of(src: String, header: String) -> String:
	var start := src.find(header)
	if start == -1:
		return ""
	var rest := src.substr(start + header.length())
	## Bound by the next top-level func, never by a line count — a fixed window silently
	## truncates and returns well-formed text from an incomplete region.
	var end := rest.find("\nfunc ")
	return rest.substr(0, end) if end != -1 else rest


func test_source_reads_and_anchors_resolve() -> void:
	var menu_src := _read(MENU_SRC)
	assert_gt(menu_src.length(), 0, "CONTROL: Win98Menu.gd read empty")
	var body := _body_of(menu_src, "func force_close() -> void:")
	assert_gt(body.length(), 0,
		"CONTROL: force_close was renamed or moved — this test can no longer find its subject and would pass on nothing")
	assert_true(body.find("\t_is_closing = true") != -1,
		"CONTROL naming a known member: the double-close guard should be inside the extracted body")


func test_menu_closed_emits_synchronously_during_force_close() -> void:
	## The load-bearing property. If this ever needs an await, the identity guard is racing.
	var menu: Control = Win98MenuClass.new()
	menu.is_root_menu = true
	add_child_autofree(menu)
	var fired := [false]
	menu.menu_closed.connect(func(): fired[0] = true)
	menu.force_close()
	assert_true(fired[0],
		"menu_closed must fire SYNCHRONOUSLY inside force_close() — it drives the identity-guarded null-write of active_win98_menu (msg 2529). Deferring it lets the next PC's menu become active first")


## ⚠️ WEAKER THAN IT LOOKS, and measured to be: this checks TEXT ORDER, not reachability.
## Verified by mutation — guarding the emit with `and false` and moving it into the fade
## callback leaves the source string at the same offset, so this test PASSED on a tree where
## the emit genuinely no longer fired synchronously. Only the behavioural test above caught it.
## Kept because it does catch someone physically relocating the line, which is the likelier
## refactor. It is NOT the guard; do not let a green here stand in for the behavioural one.
func test_the_emit_line_is_not_textually_relocated_below_the_fade() -> void:
	var body := _body_of(_read(MENU_SRC), "func force_close() -> void:")
	var emit_at := body.find("menu_closed.emit()")
	var tween_at := body.find("create_tween()")
	assert_gt(emit_at, -1, "force_close no longer emits menu_closed")
	assert_gt(tween_at, -1, "force_close no longer has the deferred fade — Phase D item 1 was reverted?")
	assert_true(emit_at < tween_at,
		"the menu_closed.emit() line must stay textually above the fade. A text check cannot prove it is REACHED — test_menu_closed_emits_synchronously_during_force_close is what proves that")


func test_the_fade_targets_the_instance_not_the_shared_field() -> void:
	## The captured-ref requirement. force_close runs ON the menu, so `self` IS the capture —
	## what must never appear is a re-read of the scene-level field, which is precisely the
	## value that has already moved on to the next menu by the time a tween callback runs.
	var body := _body_of(_read(MENU_SRC), "func force_close() -> void:")
	assert_true(body.find("tween_property(self,") != -1,
		"the close fade must tween `self` — a captured instance, not a looked-up one")
	assert_eq(body.count("active_win98_menu"), 0,
		"force_close must NEVER reference active_win98_menu. Re-reading that field inside a deferred callback is the msg 2503 two-menus bug verbatim")


func test_off_and_minimal_keep_the_pre_phase_d_path() -> void:
	var body := _body_of(_read(MENU_SRC), "func force_close() -> void:")
	assert_true(body.find("if not animate:") != -1,
		"the non-animated branch must exist — OFF/MINIMAL is the byte-for-byte baseline")
	var hide_at := body.find("hide()")
	assert_gt(hide_at, -1, "the immediate hide() must survive for the non-animated path")
	## hide() must still run BEFORE the cleanup/emit sequence on that path, as it did pre-Phase-D.
	assert_true(hide_at < body.find("_cleanup_target_highlight()"),
		"on the non-animated path hide() must still precede highlight cleanup — that was the original order and OFF must reproduce it")


func test_open_motion_is_gated_and_restores_the_resting_alpha() -> void:
	var menu_src := _read(MENU_SRC)
	var body := _body_of(menu_src, "func play_open_motion(target_alpha: float) -> void:")
	assert_gt(body.length(), 0, "play_open_motion is missing — Phase D item 1 open half")
	assert_true(body.find("if not _should_animate_motion():") != -1,
		"the entrance must be tier-gated")
	assert_true(body.find("modulate.a = target_alpha") != -1,
		"the ungated path must land on the caller's resting alpha, not 1.0 — the menu is deliberately translucent over the actor")


func test_the_caller_animates_after_setup_not_before() -> void:
	## setup() assigns final placement; sliding relative to a pre-setup y would slide from
	## whatever the previous layout left behind.
	var src := _read(CMD_SRC)
	var setup_at := src.find(".setup(combatant.combatant_name")
	var motion_at := src.find(".play_open_motion(")
	assert_gt(setup_at, -1, "the setup() call site moved")
	assert_gt(motion_at, -1, "play_open_motion is never called — the entrance is dead code")
	assert_true(setup_at < motion_at,
		"play_open_motion must be called AFTER setup(), which owns the menu's resting position")


## Stand-in for BattleScene: only _tier() matters to the gate, and duck-typing it keeps the
## test free of the real scene's autoload graph.
class _FakeScene extends Node:
	var tier_value: int = 0
	func _tier() -> int:
		return tier_value


## BEHAVIOURAL, not structural — names the OUTCOME (no motion during autogrind) rather than
## the mechanism. The bug this pins was live and reachable: the command menu opens on every
## player selection turn (BattleManager emits selection_turn_started unconditionally,
## _on_selection_turn_started has no autogrind gate, use_win98_menus is never false), so a
## no-arg presentation_tier() animated the menu through an entire visible grind.
func test_the_gate_reads_live_scene_state_not_the_false_defaults() -> void:
	var menu: Control = Win98MenuClass.new()
	add_child_autofree(menu)
	var fake := _FakeScene.new()
	add_child_autofree(fake)

	assert_true(menu._should_animate_motion(),
		"PRECONDITION: with no scene handle the menu animates at the headless default tier — if this is false the assertions below cannot discriminate")

	menu._battle_scene = fake
	fake.tier_value = BattleJuiceClass.Tier.OFF
	assert_false(menu._should_animate_motion(),
		"OFF from the live scene must suppress motion. presentation_tier()'s autogrind bool DEFAULTS to false, so a no-arg call reports FULL through a visible autogrind")

	fake.tier_value = BattleJuiceClass.Tier.MINIMAL
	assert_false(menu._should_animate_motion(), "MINIMAL must not animate")

	fake.tier_value = BattleJuiceClass.Tier.REDUCED
	assert_true(menu._should_animate_motion(), "REDUCED must animate")

	fake.tier_value = BattleJuiceClass.Tier.FULL
	assert_true(menu._should_animate_motion(), "FULL must animate")


func test_the_caller_hands_the_menu_a_scene_handle() -> void:
	## Without this wiring the gate silently falls back to the false defaults — the handle
	## being set is what makes the behavioural test above true in production.
	var src := _read(CMD_SRC)
	var assign_at := src.find("_battle_scene = _scene")
	var setup_at := src.find(".setup(combatant.combatant_name")
	assert_gt(assign_at, -1,
		"BattleCommandMenu must hand the menu a scene handle, or _should_animate_motion falls back to presentation_tier()'s false defaults")
	assert_true(assign_at < setup_at,
		"the handle must be assigned BEFORE setup() so the menu's first tier read already sees live turbo/autogrind state")


func test_tier_helper_admits_exactly_full_and_reduced() -> void:
	var body := _body_of(_read(MENU_SRC), "func _should_animate_motion() -> bool:")
	assert_gt(body.length(), 0, "_should_animate_motion is missing")
	assert_true(body.find("Tier.FULL") != -1 and body.find("Tier.REDUCED") != -1,
		"motion must be admitted for FULL and REDUCED")
	assert_eq(body.count("Tier.OFF"), 0,
		"OFF must never be admitted to the animated path")
	assert_eq(body.count("Tier.MINIMAL"), 0,
		"MINIMAL must never be admitted to the animated path")
