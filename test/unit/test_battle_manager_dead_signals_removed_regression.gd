extends GutTest

## tick 416: two dead BattleManager signals removed:
##
##   - autobattle_toggled: declared on BattleManager but NEVER
##     emitted there. Removing it was right.
##     ⛔ THE STATED REASON WAS NOT: "the live signal of the same name lives on
##     AutobattleToggleUI where the toggle UI actually emits it." AutobattleToggleUI
##     is NEVER INSTANTIATED — 0 `.new()`, 0 `.tscn`, 0 `add_child`, and the only
##     trace is an unassigned `var _autobattle_toggle_ui` at BattleScene:227. It emits
##     to nobody. The live per-character path is
##     AutobattleSystem.toggle_autobattle(character_id) — MenuScene:1261,
##     AutobattleGridEditor:2006.
##
##   - battle_actions_logged: emitted by end_battle but had ZERO
##     listeners. The autogrind path at GameLoop:4185 already calls
##     _summarize_battle_actions() synchronously and feeds the
##     result into AutogrindSystem.update_learned_patterns. The
##     signal emit just computed the summary a second time per
##     battle for no reader.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_autobattle_toggled_signal_removed() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# The declaration line must be gone.
	assert_false(src.contains("signal autobattle_toggled(character_id"),
		"BattleManager must NOT declare autobattle_toggled — the live signal lives on AutobattleToggleUI")


func test_battle_actions_logged_signal_removed() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_false(src.contains("signal battle_actions_logged"),
		"BattleManager must NOT declare battle_actions_logged — dead signal with no listeners")
	# The emit must also be gone.
	assert_false(src.contains("battle_actions_logged.emit"),
		"BattleManager must NOT emit battle_actions_logged — the autogrind path uses _summarize_battle_actions directly")


func test_the_toggle_signal_and_any_handler_agree_on_arity() -> void:
	## WAS `test_autobattle_toggle_ui_still_has_signal`, and the NAME carried the false premise:
	## "still has" reads as confirming a live path. The signal exists and reaches nothing.
	## What is worth pinning is the CONTRACT, which held only by luck: the signal carries
	## (character_id, enabled) and BattleScene's identically-named handler takes ONE arg, so a
	## future wiring attempt binds a 2-arg signal to a 1-arg method. This arm reds on that.
	var ui: String = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleToggleUI.gd")
	assert_true(ui.contains("signal autobattle_toggled(character_id: String, enabled: bool)"),
		"CONTROL: the signal's two-parameter shape is what any handler must match")
	var scene: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at: int = scene.find("func _on_autobattle_toggled(")
	if at < 0:
		pass_test("no handler by that name — nothing to keep in agreement")
		return
	var sig: String = scene.substr(at, scene.find(")", at) - at)
	## ⛔ NOT ASSERTED UNCONDITIONALLY — it would red on day one, which is the ratchet shape that
	## reds on a correct change and passes on a wrong one. Today NOTHING connects the signal, so the
	## mismatch is inert. This arm arms itself the moment somebody wires it.
	var wired: bool = false
	for path in ["res://src/battle/BattleScene.gd", "res://src/battle/BattleManager.gd",
			"res://src/ui/autobattle/AutobattleToggleUI.gd"]:
		if FileAccess.get_file_as_string(path).contains("autobattle_toggled.connect"):
			wired = true
	gut.p("    signal wired: %s · handler takes: %s" % [wired, sig.replace("func _on_autobattle_toggled(", "")])
	if not wired:
		assert_false(sig.contains("character_id"),
			("PREMISE CHECK: while nothing connects the signal, the handler is still the OLD " +
			"one-arg global-flag shape. If someone gave it (character_id, enabled), they were " +
			"wiring it — connect it and delete this branch."))
		return
	assert_true(sig.contains("character_id"),
		("autobattle_toggled is now CONNECTED, and it carries (character_id, enabled) while this " +
		"handler takes %s — the bind fails. And note the semantics: the handler sets the LEGACY " +
		"GLOBAL via BattleManager.toggle_autobattle, so a per-character toggle would flip every " +
		"character. Give it both parameters and route to AutobattleSystem, not the global.") % sig)


func test_the_code_and_the_prose_about_it_agree() -> void:
	## NOT a ratchet against wiring the panel up — wiring it is a correct change and a guard that
	## reds on one of those is the shape I deleted one of today. This pins the AGREEMENT: two
	## comments now assert the panel is never instantiated, and the day that stops being true they
	## become the same misdirection they replaced. Either state passes; disagreement reds.
	var scene: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var bm: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var made: bool = scene.contains("AutobattleToggleUIClass.new()") or scene.contains("AutobattleToggleUI.new()")
	var claims_dead: bool = bm.contains("AutobattleToggleUI IS NEVER INSTANTIATED")
	gut.p("    instantiated: %s · prose claims never-instantiated: %s" % [made, claims_dead])
	if made:
		assert_false(claims_dead,
			("AutobattleToggleUI is instantiated now, and BattleManager still says it NEVER is. " +
			"That comment was corrected precisely because a false liveness claim sends the next " +
			"reader down a path that does not exist — update it with the wiring."))
	else:
		assert_true(claims_dead,
			("The panel is still unreachable and nothing says so any more. Restoring the old " +
			"'the live signal lives on AutobattleToggleUI' reading is what cost a reader the trace."))


func test_autogrind_summary_path_intact() -> void:
	# Sanity: GameLoop's autogrind path must still call the summary
	# function synchronously (so removing the signal doesn't lose
	# pattern-learning data).
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("BattleManager._summarize_battle_actions()"),
		"GameLoop must still call BattleManager._summarize_battle_actions() in the autogrind path")
	assert_true(src.contains("AutogrindSystem.update_learned_patterns(region_id, battle_summary)"),
		"GameLoop must still feed the summary into AutogrindSystem")
