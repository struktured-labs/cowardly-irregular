extends SceneTree

## Simple test runner for CI/command line
## Usage: XDG_DATA_HOME=$PWD/tmp/xdg godot --headless -s test/run_tests.gd
##
## ⛔ THE SANDBOX PREFIX IS NOT OPTIONAL AND IS NOT COSMETIC. A bare run writes the PLAYER'S
## real `user://` — on 2026-09-18 a bare tool invocation rotated away struktured's crash logs.
## ⚠️ And an EMPTY XDG_DATA_HOME is WORSE than a wrong one: the XDG spec treats empty as unset,
## so godot writes the real profile at EC=0 with no warning, while a nonexistent path fails
## CLOSED (EC=134, nothing written). If you script this, guard the substitution:
##     SB=$(mktemp -d …) || exit 1; [ -n "$SB" ] || exit 1

func _init():
	var gut = load("res://addons/gut/gut.gd").new()
	root.add_child(gut)

	# Configure GUT
	gut.add_directory("res://test/unit")
	# Log level is set via property in GUT 9.x, not method
	if "LOG_LEVEL_ALL_ASSERTS" in gut:
		gut.log_level = gut.LOG_LEVEL_ALL_ASSERTS
	else:
		gut.log_level = 2

	# Connect to completion signal
	gut.end_run.connect(_on_tests_finished)

	# Run tests
	gut.test_scripts()


func _on_tests_finished():
	var gut = root.get_node("Gut")
	var failed = gut.get_fail_count()
	var passed = gut.get_pass_count()

	print("\n=== TEST RESULTS ===")
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)

	if failed > 0:
		quit(1)
	else:
		quit(0)
