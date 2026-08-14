extends GutTest

## Phase D item 2 — target reticle breathing pulse.
## The defect worth guarding is STACKING, not absence: _update_target_highlight() runs on
## every selection change, so a bare create_tween() there spawns one looping tween per
## keypress. They all animate the same properties, so the reticle visibly accelerates as you
## scroll targets and never settles — and nothing errors, so only the eye catches it.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const BattleJuiceClass = preload("res://src/battle/BattleJuice.gd")
const MENU_SRC := "res://src/ui/Win98Menu.gd"


func _read_src() -> String:
	var f := FileAccess.open(MENU_SRC, FileAccess.READ)
	assert_not_null(f, "CONTROL: Win98Menu.gd unreadable — source assertions would be vacuous")
	return f.get_as_text() if f else ""


func _menu_with_highlight() -> Control:
	var menu: Control = Win98MenuClass.new()
	add_child_autofree(menu)
	var hl := Control.new()
	hl.size = Vector2(90, 70)
	menu.add_child(hl)
	menu._target_highlight = hl
	return menu


func test_environment_admits_motion_at_all() -> void:
	## Without this the behavioural tests below could pass by never animating. Names the
	## condition rather than counting: at headless default time_scale the tier must be one
	## that admits motion, or _start_target_pulse legitimately does nothing.
	var tier: int = BattleJuiceClass.presentation_tier()
	assert_true(tier == BattleJuiceClass.Tier.FULL or tier == BattleJuiceClass.Tier.REDUCED,
		"test env resolved to tier %d, which does not animate — the pulse tests below would pass vacuously" % tier)


func test_starting_twice_yields_exactly_one_tween() -> void:
	var menu := _menu_with_highlight()
	menu._start_target_pulse()
	var first: Tween = menu._target_pulse
	assert_not_null(first, "the first start produced no tween")
	assert_true(first.is_valid(), "the first tween is already dead")
	for _i in range(5):
		menu._start_target_pulse()
	assert_eq(menu._target_pulse, first,
		"repeated starts must reuse the running tween. A new tween per selection change stacks — every one drives the same scale/alpha, so the reticle accelerates as the player scrolls and nothing errors")


func test_stop_kills_the_tween_and_restores_rest_state() -> void:
	var menu := _menu_with_highlight()
	menu._start_target_pulse()
	var t: Tween = menu._target_pulse
	assert_true(t.is_valid(), "precondition: a live tween before stop")
	menu._stop_target_pulse()
	## is_running(), NOT is_valid(). Measured in-engine: after kill() Godot reports
	## is_valid()==true and is_running()==false — is_valid tracks tree containment and is
	## reaped later, so asserting on it fails against a correctly killed tween.
	assert_false(t.is_running(), "the tween must be KILLED on hide, not merely dropped — an orphaned looping tween keeps writing scale/alpha on a hidden node forever")
	assert_null(menu._target_pulse, "_target_pulse must be cleared so a later start can begin cleanly")
	assert_eq(menu._target_highlight.scale, Vector2.ONE,
		"stopping mid-breath must restore scale, or the reticle reappears at whatever size the tween abandoned")
	assert_eq(menu._target_highlight.modulate.a, 1.0,
		"stopping mid-breath must restore alpha for the same reason")


func test_start_after_stop_produces_a_fresh_tween() -> void:
	var menu := _menu_with_highlight()
	menu._start_target_pulse()
	menu._stop_target_pulse()
	menu._start_target_pulse()
	assert_not_null(menu._target_pulse, "after a stop, a later target selection must be able to pulse again")
	assert_true(menu._target_pulse.is_valid(), "the restarted tween must be live")


func test_cleanup_kills_the_pulse_before_freeing_the_node() -> void:
	## Ordering matters: a tween writing properties on a freed node aborts the writing
	## function, and in GDScript that silently skips everything after it.
	var src := _read_src()
	var start := src.find("func _cleanup_target_highlight() -> void:")
	assert_gt(start, -1, "CONTROL: _cleanup_target_highlight was renamed — this test lost its subject")
	var rest := src.substr(start)
	var end := rest.find("\nfunc ")
	var body := rest.substr(0, end) if end != -1 else rest
	var stop_at := body.find("_stop_target_pulse()")
	var free_at := body.find("queue_free()")
	assert_gt(stop_at, -1, "cleanup must kill the pulse")
	assert_gt(free_at, -1, "CONTROL: cleanup no longer frees the highlight — body extraction is wrong")
	assert_true(stop_at < free_at, "the pulse must be killed BEFORE the highlight is freed")


func test_every_hide_path_stops_the_pulse() -> void:
	## Derived by counting the visibility writes rather than naming the two branches I happen
	## to remember — a third hide path added later must not silently skip the kill.
	var src := _read_src()
	var hides := src.count("_target_highlight.visible = false")
	assert_gt(hides, 0, "CONTROL: no hide sites found — the pattern moved and this test proves nothing")
	var stops := src.count("_stop_target_pulse()")
	## one per hide site, plus the cleanup call, plus the function's own declaration line
	assert_true(stops >= hides + 1,
		"found %d hide sites but only %d _stop_target_pulse references — a hide path that skips the kill leaves a looping tween running on a hidden reticle" % [hides, stops])


func test_the_pulse_loops_and_is_tier_gated() -> void:
	var src := _read_src()
	var start := src.find("func _start_target_pulse() -> void:")
	assert_gt(start, -1, "_start_target_pulse is missing")
	var rest := src.substr(start)
	var end := rest.find("\nfunc ")
	var body := rest.substr(0, end) if end != -1 else rest
	assert_true(body.find("set_loops()") != -1, "the pulse must loop — a one-shot breath reads as a glitch")
	assert_true(body.find("_should_animate_motion()") != -1,
		"the pulse must be tier-gated like every other Phase D motion")
	assert_true(body.find("TRANS_SINE") != -1, "the spec calls for a sine breath, not linear")
