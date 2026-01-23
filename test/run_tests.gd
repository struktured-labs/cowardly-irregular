extends SceneTree

## Simple test runner for CI/command line
## Usage: godot --headless -s test/run_tests.gd

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
