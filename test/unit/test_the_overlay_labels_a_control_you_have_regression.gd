extends GutTest

## The drawn pad overlay is ON BY DEFAULT during a grind and labelled FOUR controls that do
## nothing, plus one it described wrongly. Every label is a promise that pressing that button does
## that thing; four of nine were false.
##
##   plus  "Speed+"    ⛔ bound to nothing. The same +/- speed pair CLAUDE.md records as a dead
##   minus "Speed-"    ⛔ instruction removed from the battle hint bar on 2026-07-28 — removed
##                        there, left here, on a surface that is on by default.
##   dpad  "Navigate"  ⛔ no d-pad handler is reachable during a grind.
##   start "Rules"     ⛔ in the TIER-0 context … and ✅ in the ludicrous one. See below.
##   l, r  "Tier"      ⚠️ both shoulders must be HELD TOGETHER; the label promised either.
##
## 🔑 WHY "Rules" SURVIVED, and it is the reason this needed measuring rather than reading: the
## two contexts carry the SAME label and only one has a listener.
##   tier 0      GameLoop:5596  overlay only          -> the AUTOGRIND branch binds no START
##   ludicrous   GameLoop:5592  overlay + DASHBOARD   -> AutogrindInputHelper.classify_event
##                                                       maps JOY_BUTTON_START -> "adjust_rules"
## ⚠️ The dashboard is ALSO shown at tier 1 (GameLoop:6236) — the overlay simply has no tier-1
## context, which is why ludicrous is the only context that can carry the label. And on main the
## dashboard's adjust_rules_requested has NO listener (GameLoop connects its pause/exit/tier_cycle
## and not that one), so START emits into nothing until @cowir-autogrind's cf0e0135 lands. This
## guard pins WHERE the label goes, which is right in both states; it does not claim the control
## works today.
## So the label is correct in exactly one of the two places it appears. Deleting it from both, or
## keeping it in both, are each wrong in one context.
##
## WHAT IS ACTUALLY REACHABLE while grinding, read off GameLoop's AUTOGRIND branch (:907+):
##   ui_cancel -> stop · JOY_BUTTON_Y / KEY_Y -> turbo · battle_toggle_auto / KEY_P -> pause
##   KEY_T -> tier · L+R held together -> tier
## and, in ludicrous only, the dashboard's classify_event: BACK -> pause, START -> adjust_rules,
## L+R -> tier, KEY_P/R/T.

const OVERLAY := "res://src/ui/ControllerOverlay.gd"
const GAMELOOP := "res://src/GameLoop.gd"
const HELPER := "res://src/ui/autogrind/AutogrindInputHelper.gd"


func _overlay():
	return load(OVERLAY)


## The AUTOGRIND input branch, bounded at its own end rather than a fixed window.
func _autogrind_branch() -> String:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var at := src.find("if current_state == LoopState.AUTOGRIND:")
	assert_gt(at, -1, "the AUTOGRIND input branch must exist")
	var stop := src.find("\n\tif event is InputEventKey and event.pressed and event.keycode == KEY_F5", at)
	assert_gt(stop, at, "the F5 handler follows the branch — that is its end")
	return src.substr(at, stop - at)


## ⛔ THE DEFECT. Every label in the TIER-0 context must name something that branch actually binds.
func test_every_tier0_label_names_a_reachable_control() -> void:
	var ctx: Dictionary = _overlay().autogrind_context()
	var branch := _autogrind_branch()
	assert_gt(branch.length(), 200, "CONTROL: the branch must be substantial, got %d" % branch.length())

	# button_id -> the token that proves it is bound in that branch
	var proof := {
		"y": "JOY_BUTTON_Y",
		"b": "ui_cancel",
		"select": "battle_toggle_auto",
		"l": "JOY_BUTTON_LEFT_SHOULDER",
		"r": "JOY_BUTTON_RIGHT_SHOULDER",
	}
	for key in ctx:
		assert_true(proof.has(key),
			"the tier-0 overlay labels '%s' as \"%s\", and nothing in GameLoop's AUTOGRIND branch " % [key, ctx[key]] +
			"binds it. Remove the label, or bind the control. Dead as of this guard: plus/minus " +
			"(Speed+/-, unbound since 2026-07-28), dpad (Navigate), start (Rules — belongs in the " +
			"LUDICROUS context, whose screen also carries the dashboard that classifies START; tier 0 " +
			"shows the overlay alone)")
		if proof.has(key):
			assert_true(branch.find(proof[key]) > -1,
				"'%s' is labelled \"%s\" but %s does not appear in the branch" % [key, ctx[key], proof[key]])


## The tier label must say the combo, because pressing ONE shoulder does nothing.
func test_the_tier_label_says_both_shoulders() -> void:
	var branch := _autogrind_branch()
	assert_true(branch.find("Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)") > -1,
		"precondition: tier cycling requires BOTH shoulders held — that is what the label must say")
	for ctx in [_overlay().autogrind_context(), _overlay().autogrind_ludicrous_context()]:
		for key in ["l", "r"]:
			assert_true(str(ctx.get(key, "")).find("L+R") > -1,
				"the '%s' label must name the combo, got \"%s\" — one shoulder alone does nothing"
					% [key, ctx.get(key, "<absent>")])


## ⛔ THE ASYMMETRY, pinned so nobody "tidies" the two contexts into agreement. Rules belongs in
## the ludicrous context ONLY — that is the only context here whose screen also carries the
## DASHBOARD, whose classify_event turns START into adjust_rules. Tier 0 shows the overlay alone.
## (The dashboard is up at tier 1 too; the overlay simply has no tier-1 context.)
func test_rules_is_labelled_where_the_dashboard_listens_and_nowhere_else() -> void:
	var helper := FileAccess.get_file_as_string(HELPER)
	assert_true(helper.find("JOY_BUTTON_START") > -1 and helper.find("adjust_rules") > -1,
		"precondition: the dashboard's classify_event must map START to adjust_rules")
	var gl := FileAccess.get_file_as_string(GAMELOOP)
	assert_true(gl.find("_show_autogrind_dashboard()") > -1,
		"precondition: the dashboard must be shown somewhere, or ludicrous has no listener either")

	assert_false(_overlay().autogrind_context().has("start"),
		"tier 0 shows the overlay ALONE (GameLoop:5596) — no dashboard, so START reaches nothing")
	assert_true(_overlay().autogrind_ludicrous_context().has("start"),
		"ludicrous shows the dashboard (GameLoop:5592), the only screen that classifies START as " +
		"adjust_rules — do not delete this one for symmetry with tier 0. NOTE: on main that signal " +
		"has no listener yet, so the press is inert until cf0e0135 connects it; this arm pins WHERE " +
		"the label belongs, not that the control works today")


## THE CONTROL. Without it the arms pass on an empty context and an unreadable branch.
func test_the_contexts_and_the_branch_are_really_being_read() -> void:
	var tier0: Dictionary = _overlay().autogrind_context()
	var lud: Dictionary = _overlay().autogrind_ludicrous_context()
	assert_gt(tier0.size(), 3, "the tier-0 context must still label several controls, not none")
	assert_gt(lud.size(), 3, "and so must ludicrous")
	assert_true(tier0.has("b") and tier0.has("y"),
		"Exit and Turbo are the two this guard must never let anyone remove — both are bound")
	assert_ne(tier0, lud, "the two contexts must DIFFER, or the asymmetry arm proves nothing")
	assert_true(_autogrind_branch().find("_stop_autogrind") > -1,
		"the branch reader must reach real code — a stale anchor would return an empty window")
