extends SceneTree

## Run a single test file for quick iteration
## Usage: godot --headless -s test/run_single_test.gd -- test/unit/test_sprite_generation.gd

func _init():
	var gut = load("res://addons/gut/gut.gd").new()
	root.add_child(gut)

	# Get the test file from command line args
	var args = OS.get_cmdline_user_args()
	if args.size() == 0:
		print("Usage: godot --headless -s test/run_single_test.gd -- <test_file.gd>")
		quit(1)
		return

	var test_path = args[0]
	if not test_path.begins_with("res://"):
		test_path = "res://" + test_path

	gut.add_script(test_path)
	gut.log_level = 2
	gut.end_run.connect(_on_tests_finished)
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
