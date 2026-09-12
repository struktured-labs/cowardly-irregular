extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

## A system collapse and a meta-boss spawn are the two loudest beats the grind has, and both were
## announced to a panel the player cannot see.
##
## `AutogrindUI` was the ONLY listener for either signal, and `_toggle_grinding` sets that node
## `visible = false` for the whole grind — its `_battle_log` is `add_child`'d to a panel under it.
## `_launch_collapse_boss_battle` otherwise only `print`s to stdout. So a collapse fired, a boss
## appeared, and the console the player is actually watching (BattleScene's) said nothing.
##
## 🔑 The build-up already reached them: `corruption_threshold_crossed` toasts "collapse imminent"
## from GameLoop. The warning shipped on a live surface and the payoff did not.
##
## Same defect as `fatigue_event` before .3xx — six authored descriptions emitted to zero listeners.

const GL := "res://src/GameLoop.gd"
const UI := "res://src/ui/autogrind/AutogrindUI.gd"


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


## The body of a named function, EXCLUDING its signature line, so an arm cannot pass by matching a
## neighbour — or by matching the parameter name in the signature itself.
## ⛔ This returned the signature too, and `contains("boss_name")` was satisfied by
## `func _on_autogrind_meta_boss_spawned(boss_name: String)` while the body ignored the parameter.
## A mutation that hardcoded the name scored GREEN. Same trap as a contains() matching a signature
## rather than a body, which this lane already had written down.
func _fn_body(src: String, name_: String) -> String:
	var at := src.find("func %s(" % name_)
	if at < 0:
		return ""
	var after_sig := src.find("\n", at)
	if after_sig < 0:
		return ""
	var end := src.find("\nfunc ", after_sig)
	return src.substr(after_sig, (end - after_sig) if end > after_sig else 400)


## Both signals must have a GameLoop listener. The defect was zero.
func test_both_beats_are_connected_to_a_live_surface() -> void:
	var src := _code_only(GL, "func _on_grind_complete(")
	assert_gt(src.length(), 1000, "CONTROL: GameLoop source must have been read")
	## The two that already work, as a positive control: if the pattern moved, this arm's shape is
	## wrong rather than the connections being missing, and the message should say so.
	assert_true(src.contains("AutogrindSystem.fatigue_event.connect("),
		"CONTROL: the proven pattern (fatigue_event) must still be here; if not, re-derive this file")
	for sig in ["system_collapse", "meta_boss_spawned"]:
		assert_true(src.contains("AutogrindSystem.%s.connect(" % sig),
			("GameLoop does not listen for %s. Its only other listener is AutogrindUI, which is " +
			"visible = false for the whole grind — connect it here beside fatigue_event and route " +
			"it to _show_autogrind_toast, as _on_autogrind_corruption_band does") % sig)


## ⛔ THESE TWO ARMS WERE BEHAVIOURAL AND VACUOUS. They fetched GameLoop from the scene tree and
## pass_test()'d when it was absent — and it is ALWAYS absent: GameLoop is the MAIN SCENE, not an
## autoload (root's children are the 31 autoloads plus GutRunner). Both passed a mutation that
## gutted the handler. My own "did the escape fire?" check grepped for text GUT does not emit, so
## it agreed with them. An escape hatch IS the vacuity; source arms with no escape instead.
func test_a_collapse_reaches_the_surface_the_player_watches() -> void:
	var body := _fn_body(_code_only(GL, "func _on_grind_complete("), "_on_autogrind_system_collapse")
	assert_gt(body.length(), 40, "GameLoop must own a collapse handler — found %d chars" % body.length())
	assert_true(body.contains("_show_autogrind_toast("),
		"the collapse handler must toast: AutogrindUI's log is hidden for the whole grind")
	assert_true(body.contains("_autogrind_battle_summaries.append("),
		"and must write the battle summary the player reads back, as the corruption-band handler does")
	assert_true(body.to_upper().contains("COLLAPSE"),
		"the line must name the event rather than appending something unnamed")


## The boss NAME must survive — a handler that drops its argument still toasts.
func test_a_meta_boss_spawn_names_the_boss() -> void:
	var body := _fn_body(_code_only(GL, "func _on_grind_complete("), "_on_autogrind_meta_boss_spawned")
	assert_gt(body.length(), 40, "GameLoop must own a spawn handler — found %d chars" % body.length())
	assert_true(body.contains("boss_name"),
		("the spawn handler ignores its boss_name parameter. meta_boss_spawned emits " +
		"boss_data.get(\"name\"), and a handler that drops it still appends a line, so the player " +
		"is told a meta-boss arrived and never which one"))
	assert_true(body.contains("_show_autogrind_toast(") and body.contains("_autogrind_battle_summaries.append("),
		"and it must reach both live surfaces, like the collapse handler")


## The PREMISE. If the console ever stops hiding itself mid-grind, this fix is redundant rather than
## wrong — but the next reader should re-derive it instead of assuming.
func test_the_console_really_is_hidden_during_a_grind() -> void:
	var ui := _code_only(UI, "func _toggle_grinding(")
	var at := ui.find("func _toggle_grinding")
	assert_gt(at, -1, "PRECONDITION: the console must still own the grind toggle")
	var body := ui.substr(at, 1400)
	assert_true(body.contains("visible = false"),
		("_toggle_grinding no longer hides the console. If AutogrindUI is visible during a grind its " +
		"own _battle_log IS a live surface, and these GameLoop handlers may be duplicating it — " +
		"re-measure which surface the player watches before removing either"))


## BOTH halves, because they need different mechanisms (@cowir-overworld): `#` comments are
## line-addressable and `"""` regions are not — a docstring carries no `#`, so a line pass cannot
## see it. That is the .325 defect, and @cowir-controller demonstrated it as a live false green in
## their lane and I reproduced one in mine: delete a real connect, plant a docstring claiming it,
## and a raw reader passes 5/5. Region half is a parity split — stateless, nothing to desync.
## `must_survive` is REQUIRED so no call site can omit the positive control.
func _code_only(path: String, must_survive: String) -> String:
	## PATH-taking by construction: a literal source string cannot reach this wrapper, which is what
	## makes the blank-control floor below safe (cowir-sprites' rule, 2026-09-12). A source-taking
	## wrapper must NOT floor — it would red on correct literal-input self-test rows.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped
