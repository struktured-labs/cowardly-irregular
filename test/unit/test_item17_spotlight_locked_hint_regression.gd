extends GutTest

## User playtest item 17: "does the game default to autobattle for all?
## couldnt tell if that or spotlight but it should default to off of course."
##
## Audit finding:
## - System-level autobattle_enabled dict defaults to {} → is_autobattle_
##   enabled(id) returns false for any PC (already correct).
## - Non-Fighter PCs default to autobattle_locked=true — spotlight-lock
##   design (user's own msg 1950 approval). Locked PCs' command menu
##   returns silently, so their turns route through autobattle.
## - The two mechanisms LOOK identical from playtest: player sees
##   4/5 PCs auto-resolve and can't tell the mechanism.
##
## Fix: first-battle tutorial hint explaining WHY the non-Fighter PCs
## are on autopilot right now. Fires the first time a spotlight-locked
## PC's turn opens the command menu.

const TUTORIAL_HINTS_PATH := "res://src/ui/TutorialHints.gd"
const BATTLE_COMMAND_MENU_PATH := "res://src/battle/BattleCommandMenu.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_spotlight_locked_intro_hint_authored() -> void:
	var src := _read(TUTORIAL_HINTS_PATH)
	assert_true(src.contains("\"spotlight_locked_intro\":"),
		"TutorialHints must declare 'spotlight_locked_intro' hint")
	# Body must actually explain the mechanism.
	assert_true(src.contains("Spotlight Duel"),
		"hint body must reference Spotlight Duel — otherwise the explainer doesn't guide the player to the unlock path")


func test_command_menu_fires_hint_on_locked_pc() -> void:
	var src := _read(BATTLE_COMMAND_MENU_PATH)
	# BattleCommandMenu extends RefCounted (no get_tree), so it fires
	# the hint through _scene reference (the BattleScene host).
	assert_true(src.contains("TutorialHints.show(_scene, \"spotlight_locked_intro\")"),
		"BattleCommandMenu must fire the spotlight_locked_intro hint on the first locked-PC turn via _scene (RefCounted has no get_tree)")


func test_hint_only_fires_when_gate_actually_blocks() -> void:
	# Pin ordering: hint fires INSIDE the spotlight-locked branch,
	# AFTER the debug_override check has failed (i.e. we're actually
	# going to silent-return). Debug-unlocked run must NOT show it.
	var src := _read(BATTLE_COMMAND_MENU_PATH)
	var idx: int = src.find("spotlight_locked_intro")
	assert_gt(idx, -1)
	# The nearest preceding gate must include the debug_override check
	# so the hint only fires on the real locked path. Msg 2379 added a
	# solo_duel_override sibling on the same line — both must be present.
	var window_before: String = src.substr(max(0, idx - 1500), 1500)
	assert_true(window_before.contains("not debug_override"),
		"hint must fire behind the debug_override gate (real locked path only)")
	assert_true(window_before.contains("not solo_duel_override"),
		"solo-duel override must ALSO gate the hint — otherwise the duelist sees a spotlight-lock explainer they aren't subject to")


func test_hint_shows_dedupes_via_tutorial_hints_static() -> void:
	# Sanity: TutorialHints.show already dedupes per hint id per session
	# (existing guard). No need to add extra dedupe at the call site.
	var src := _read(TUTORIAL_HINTS_PATH)
	var fn_idx: int = src.find("static func show")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_shown_hints"),
		"TutorialHints.show must dedupe via _shown_hints (session-scoped) — the fire site relies on this")
