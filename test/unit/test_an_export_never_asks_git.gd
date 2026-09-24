extends GutTest

## Version.display() appends the git short-hash in dev runs. The export path was meant to fall
## back to the clean semver, but an export globalizes res:// to "" and still ran
## `git -C "" rev-parse` in the player's working directory. The shipped .481 Windows build logged
## `Could not create child process: git -C  rev-parse "--short=8" HEAD`. On Linux, a launch from
## inside any repo would print that unrelated repo's hash on the title screen.


func test_an_export_template_never_asks_git() -> void:
	assert_false(Version._should_ask_git(false, "/home/player/game/"),
		"an exported build shelled out to git in the player's working directory")


func test_an_empty_project_path_never_asks_git() -> void:
	assert_false(Version._should_ask_git(true, ""),
		"git -C \"\" runs in the cwd, not the project — the exact call the Windows build logged")


func test_control_a_source_run_still_gets_its_hash() -> void:
	assert_true(Version._should_ask_git(true, ProjectSettings.globalize_path("res://")),
		"CONTROL: a source run must still ask, or F12 screenshots lose their build hash")
	assert_true(OS.has_feature("editor"), "CONTROL: this suite runs on the editor build, which is what a dev run is")


func test_the_hash_path_consults_the_predicate_before_shelling_out() -> void:
	var src := FileAccess.get_file_as_string("res://src/meta/Version.gd")
	var fn := src.find("static func _git_short_hash")
	assert_gt(fn, -1, "Version._git_short_hash must exist")
	var body := src.substr(fn, src.find("\nstatic func ", fn + 1) - fn)
	var gate := body.find("_should_ask_git(")
	var shell := body.find("OS.execute(")
	assert_gt(gate, -1, "_git_short_hash must consult _should_ask_git")
	assert_gt(shell, -1, "CONTROL: _git_short_hash still shells out to git")
	assert_lt(gate, shell, "the predicate must run BEFORE OS.execute, or an export still spawns git")
