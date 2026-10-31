extends GutTest

## `tools/pre_ready_guards.sh` is what every lane runs before READY, so a silently broken derivation
## would let the whole fleet report a clean sweep having checked nothing — the exact failure the tool
## exists to prevent. Nothing tested it until now (0 guards named it), and a `--selftest` flag would
## run nowhere: the walker that discovers those filters to `.py`.
##
## Each arm drives the real script through `--list`, which prints the derivation and runs no tests, so
## this file costs milliseconds rather than the 15 minutes a full sweep can take.
##
## The three legs exist because each is blind to what the others catch, measured on c1054f593:
##   TREE       a guard that WALKS a directory names none of your symbols (src 245 · data 115 · tools 11)
##   PER-FILE   a guard that reads a file as TEXT and pins lines in it (BattleManager.gd: 347)
##   CLASSNAME  a file reached by its declared class_name, not its path (VoiceLines.gd: 0 by path, 10 by name)

const TOOL := "tools/pre_ready_guards.sh"


func _list(paths: String) -> String:
	var out: Array = []
	var args: Array = ["-c", "cd %s && PRE_READY_PATHS=%s bash %s --list 2>&1" % [
			ProjectSettings.globalize_path("res://").trim_suffix("/"), _q(paths), TOOL]]
	OS.execute("bash", args, out, true)
	return "\n".join(out)


func _q(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


## The derived count for a leg line like "245 guards walk res://src".
## The number immediately before a phrase like "by path" / "by class_name" on a per-file line.
func _leg_number(line: String, phrase: String) -> int:
	var at: int = line.find(phrase)
	if at < 0:
		return -1
	var head: String = line.substr(0, at).strip_edges()
	var words: PackedStringArray = head.split(" ")
	var last: String = words[words.size() - 1] if words.size() > 0 else ""
	return int(last) if last.is_valid_int() else -1


func _count(text: String, needle: String) -> int:
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if not line.contains(needle):
			continue
		var words: PackedStringArray = line.replace("pre_ready_guards:", "").strip_edges().split(" ")
		if words.size() > 0 and words[0].is_valid_int():
			return int(words[0])
	return -1


## A -1 from _count/_leg_number means THE PHRASE WAS NOT FOUND, which is this parser's defect, not the sweep's.
func _input_not_found(phrase: String, text: String) -> void:
	assert_true(false, "INPUT NOT FOUND: no line of %s's output contains '%s', so this arm measured nothing and any number it would have printed describes this parser rather than the sweep. That substring is an INTERFACE this guard reads: if you reworded the tool, restore it verbatim and append your change after it. Got:\n%s" % [TOOL, phrase, text.substr(0, 500)])


func test_the_tool_is_there_and_answers() -> void:
	var text := _list("src/battle/BattleManager.gd")
	assert_true(text.contains("pre_ready_guards:"),
		"VOID: %s produced no derivation line, so every arm below is checking nothing. Got:\n%s" % [TOOL, text])


func test_the_tree_leg_finds_the_directory_walkers() -> void:
	## These guards name no symbol of yours; a symbol-derived corpus can never contain them, which is
	## what the first .654 gate red was.
	var text := _list("src/battle/BattleManager.gd")
	var src := _count(text, "guards walk res://src")
	if src < 0:
		_input_not_found("guards walk res://src", text)
		return
	assert_gt(src, 100, "the src tree leg derived %d walkers — it was 245 when written, so the walk scan has broken" % src)


func test_the_data_leg_sees_a_manifest_only_change() -> void:
	## Every manifest lives in data/, which is the most common edit shape in the sprite, sfx and
	## autogrind lanes, and was invisible to this tool until the trees came from the diff.
	var dtext := _list("data/monsters.json")
	var data := _count(dtext, "guards walk res://data")
	if data < 0:
		_input_not_found("guards walk res://data", dtext)
		return
	assert_gt(data, 50, "the data tree leg derived %d walkers — a manifest-only change would go unchecked" % data)


func test_the_class_name_leg_finds_what_no_path_reaches() -> void:
	## src/llm/VoiceLines.gd has NO path dependents: everything reaches it as `VoiceLines.<fn>`. So this
	## is not a refinement of the path leg — for that file it is the only leg that finds anything.
	var text := _list("src/llm/VoiceLines.gd")
	assert_true(text.contains("by class_name"),
		"the per-file line names no class_name leg, so a file reached only by its class name derives nothing:\n%s" % text)
	var idx: int = text.find("VoiceLines.gd ->")
	assert_gt(idx, -1, "the per-file leg did not report on VoiceLines.gd at all:\n%s" % text)
	var line: String = text.substr(idx, 90)
	## RELATIONSHIP, not an absolute: when written, VoiceLines.gd had 0 path dependents and 10 by name.
	## Pinning the 0 broke the moment THIS file mentioned the path — my own guard became a dependent and
	## made it 1. What must hold is that the class_name leg finds substantially more than the path leg,
	## which is the gap the leg exists for; a coincidental count is not.
	var by_path: int = _leg_number(line, "by path")
	var by_name: int = _leg_number(line, "by class_name")
	## A sentinel on EITHER side makes the comparison below unfalsifiable: any real count beats -1.
	if by_path < 0 or by_name < 0:
		_input_not_found("by path / by class_name", line)
		return
	assert_gt(by_name, by_path,
		"the class_name leg must out-find the path leg for VoiceLines.gd — that gap is why it exists. Got: %s" % line)
	assert_gt(by_name, 5, "only %d class_name dependents for VoiceLines.gd; it was 10 when written" % by_name)


func test_a_shared_test_helper_is_in_scope() -> void:
	## An earlier filter was `^(src|data|assets)/`, which dropped test/unit/helpers entirely — so editing
	## gd_source.gd (218 dependents by path, 201 by name) derived zero per-file guards.
	var text := _list("test/unit/helpers/gd_source.gd")
	assert_true(text.contains("helpers/gd_source.gd ->"),
		"a shared helper derived no dependents, so editing one is unchecked:\n%s" % text)


func test_no_stated_paths_still_derives_from_the_diff() -> void:
	## With no PRE_READY_PATHS the tool infers the change list itself, and must still produce a set.
	## The stronger claim — that an UNREADABLE diff widens to every tree rather than reporting nothing —
	## cannot be driven from here without a test-only hook to break git, so it is verified by hand
	## (measured: git merge-base forced to fail -> "every tree", 277 guards) and left out of this file
	## rather than asserted weakly.
	var text := _list("")
	assert_true(text.contains("distinct guards for:"),
		"with no stated paths the tool derived no set at all:\n%s" % text)


func test_list_runs_no_tests() -> void:
	## --list exists on cost grounds: a 15-minute sweep that cannot be previewed gets skipped and
	## reported as swept. If it started running the suite it would stop being used.
	var text := _list("data/monsters.json")
	assert_false(text.contains("Totals"), "--list ran the suite; it must only print the derivation:\n%s" % text)


## PRE_READY_PATHS is documented space-separated, and every derivation reads LINES. A multi-path value
## arrived as one line, so `awk -F/ '{print $1}'` returned only the FIRST path's tree and the per-file
## legs got the whole string as a filename and were skipped by the -f test. Measured by @cowir-ai on a
## src+test set: "src" alone, none of the ten test-dir guards, EC=0 — and the add-a-test-file case is
## exactly when a lane also touches src, so the normal shape was the under-derived one.
func test_a_multi_path_set_derives_every_tree_in_it() -> void:
	var text := _list("src/cutscene/CutsceneDialogue.gd test/unit/test_a_thinking_box_cannot_trap_the_player.gd")
	assert_true(text.contains("walk res://src"), "the src tree is missing from a mixed set:\n%s" % text)
	assert_true(text.contains("walk res://test"),
		"the TEST tree is missing from a mixed set — only the first path's tree derived, so an added test file runs none of the guards that judge it:\n%s" % text)


func test_every_stated_path_gets_its_own_per_file_leg() -> void:
	## The same defect's other half: the per-file legs read the whole string as one filename, so a
	## multi-path set produced no dependents at all.
	var text := _list("src/cutscene/CutsceneDialogue.gd src/llm/DynamicConversation.gd")
	var legs := 0
	for raw in text.split("\n"):
		if raw.contains(" -> ") and raw.contains("by path"):
			legs += 1
	assert_eq(legs, 2, "expected one per-file leg per stated path, got %d:\n%s" % [legs, text])


func test_the_walk_scan_carries_its_own_positive_control() -> void:
	## A per-tree floor cannot work (addons/ legitimately derives 0), so the control is on the REGEX:
	## if the walk pattern matches implausibly little, the derivation is broken rather than the branch.
	var src := FileAccess.get_file_as_string("res://" + TOOL)
	assert_gt(src.length(), 0, "VOID: could not read %s" % TOOL)
	## Both the ASSIGNMENT and the USE: checking only the name passed a mutant that renamed it to
	## MIN_WALKERS_REMOVED, because the old name is a substring of the new one. A token is spelling;
	## the comparison is the control.
	assert_true(src.contains("MIN_WALKERS=") and src.contains("-lt \"$MIN_WALKERS\""),
		"the positive control on the walk regex is not both declared and APPLIED — a pattern that matches nothing would read as a clean sweep")
	assert_true(src.contains("exit 2"), "the broken-derivation refusal is gone")


## project.godot is read by 39 test guards and derived ZERO of them: the per-file leg takes an
## extension allowlist (gd|json|tscn|cfg|tres) and `.godot` was not in it, so a project-settings
## change — input map, autoloads, logging — swept nothing and the tool said "nothing applies", exit 0.
func test_a_project_settings_change_derives_its_readers() -> void:
	var text := _list("project.godot")
	assert_true(text.contains("project.godot ->"),
		"project.godot derived no dependents, so an input-map or autoload change sweeps nothing:\n%s" % text)
	var idx: int = text.find("project.godot ->")
	var by_path: int = _leg_number(text.substr(idx, 90), "by path")
	if by_path < 0:
		_input_not_found("by path", text.substr(idx, 90))
		return
	## RELATIONSHIP, not the 39 measured today: this grows whenever a guard starts reading the file.
	assert_gt(by_path, 10,
		"only %d guards derived for project.godot; it was 39 when written, so the allowlist or the path grep has drifted" % by_path)


## The allowlist is a branch set with no else, and before 2026-10-12 the kind it did not list was
## DROPPED rather than reported — the same shape @cowir-overworld found in a `match` with no default
## and @cowir-deploy in a positive-match counter, all three in one afternoon. A reader can act on a
## named gap and cannot act on an absence.
func test_a_changed_path_no_leg_can_see_is_named() -> void:
	var text := _list("README.md")
	assert_true(text.contains("NO LEG CAN SEE"),
		"a root-level unrecognised kind derived nothing and said nothing — a green sweep then covers a file it never considered:\n%s" % text)
	assert_true(text.contains("README.md"), "the warning does not NAME the path, so it cannot be acted on:\n%s" % text)


## CONTROL: a warning that fires on every run is a warning nobody reads. A fully covered path must
## not trip it — and this is the arm that separates "the report works" from "the report always fires".
func test_a_fully_covered_change_is_not_warned_about() -> void:
	var text := _list("src/audio/SoundManager.gd")
	assert_false(text.contains("NO LEG CAN SEE"),
		"a path both legs cover was reported as underivable, so the warning fires on every sweep and gets ignored:\n%s" % text)
	assert_false(text.contains("guards for: docs"),
		"the summary names a tree that yielded no guards — a plausible label contradicting the warning above it")


## A flag the tool does not read must be refused before any guard runs: `--help` once fell through to a
## full 300-script sweep during a fold gate (cowir-overworld, 2026-10-14). Bounded so a regression costs 20s.
func test_an_unknown_flag_is_refused_before_anything_runs() -> void:
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	for flag in ["--help", "-h", "--list extra"]:
		var out: Array = []
		var cmd := "cd %s && PRE_READY_PATHS=tools/pre_ready_guards.sh timeout 20 bash %s %s 2>&1" % [root, TOOL, flag]
		var ec: int = OS.execute("bash", ["-c", cmd], out, true)
		var text := "\n".join(out)
		assert_eq(ec, 2, "%s must exit 2 (refused), got %d:\n%s" % [flag, ec, text])
		assert_true(text.contains("unknown argument"), "%s was not named as unknown:\n%s" % [flag, text])
		assert_false(text.contains("Totals") or text.contains("Scripts "), "%s RAN guards instead of refusing:\n%s" % [flag, text])
	var control := _list("tools/pre_ready_guards.sh")
	assert_true(control.contains("distinct guards"), "CONTROL: --list must still answer, or the refusal arm proves nothing:\n%s" % control)
