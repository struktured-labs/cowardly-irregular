extends GutTest

## user:// is keyed by project name, so every checkout on a box writes the same logs directory, and a play log carried
## no record of which build produced it. Three lanes each spent time on a defect mined from a log whose build predated
## the fix. The game now prints its version (and, in a source run, its commit) once at startup.

const GAME_LOOP := "res://src/GameLoop.gd"


func test_the_build_line_names_the_version() -> void:
	var shown: String = Version.display()
	assert_true(shown.begins_with("v" + Version.SEMVER), "CONTROL: display() leads with the semver: %s" % shown)
	assert_gt(Version.SEMVER.length(), 4, "CONTROL: there is a real semver to print")


func test_startup_prints_the_build_right_after_started() -> void:
	var src := FileAccess.get_file_as_string(GAME_LOOP)
	var started := src.find("DebugLogOverlay.log(\"[GAME] Started\")")
	assert_gt(started, -1, "CONTROL: the Started marker the deploy boot gate asserts is still there, unchanged")
	var build := src.find("print(\"[GAME] Build %s\" % Version.display())")
	assert_gt(build, started, "the build line is printed at startup, after the Started marker")
	assert_lt(build - started, 400, "and right beside it, not in some later branch")
	assert_eq(src.count("[GAME] Build"), 1, "printed from exactly one place")
