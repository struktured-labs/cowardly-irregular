extends GutTest

## struktured's play logs are where real bugs get found, and log retention is a HARD FIFO: every
## launch that opens the project rotates `user://logs/godot.log` to a timestamped name and deletes
## the oldest. At the engine default of 5 that window is tiny, and a launch does not have to PLAY
## anything to spend a slot — measured on his own profile 2026-10-12, two 71-byte banner-only
## headless runs (08:51 and 08:53, no Vulkan line, no autoload prints) took 2 of his 5 slots, and
## the oldest real traces were already gone. The 821 KB log those stubs rotated was from 10-05,
## which is why its filename says nothing about its age.
##
## Measured in a sandbox before this setting landed, `godot --headless --quit` repeatedly:
##   default      run 1..5 -> 1,2,3,4,5 retained, then 5, 5, 5          (capped at 5)
##   with 25      8 launches -> 8 retained · 27 launches -> 25          (capped at 25)
## So the number is a real cap in both directions; rotation was not disabled.
##
## Read through ProjectSettings rather than from the file text, because a mistyped key
## (`max_log_file`) sits in project.godot looking correct while the engine serves its own default —
## spelling is not behaviour. The file read beside it is the other half: it proves the value is
## COMMITTED rather than assigned at runtime by some autoload, which would not help him on a build
## he already has.

const KEY := "debug/file_logging/max_log_files"
const ENGINE_DEFAULT := 5


func test_the_retention_window_is_wider_than_the_engine_default() -> void:
	var n: int = int(ProjectSettings.get_setting(KEY, ENGINE_DEFAULT))
	## The RELATIONSHIP, not the number: what matters is headroom over the default, because the
	## defect is a stub launch evicting a real trace. Pinning 25 would red on a deliberate raise.
	assert_gt(n, ENGINE_DEFAULT,
		("%s reads %d, the engine default — so the engine is serving its own value and ours is "
		+ "absent or misspelled. At 5, two ad-hoc headless runs cost him 40%% of his crash traces.") % [KEY, n])
	## A cap that never evicts is the other failure: these are ~800 KB each in a real session.
	assert_lt(n, 200,
		"%d retained logs is no longer a rotation policy — a real session log is ~800 KB, so this fills his profile instead of protecting it" % n)


func test_the_setting_is_committed_and_not_assigned_at_runtime() -> void:
	## ProjectSettings would read the same if an autoload called set_setting() at boot, which does
	## nothing for a build already on disk. So require it in the file the export packs.
	var cfg := FileAccess.get_file_as_string("res://project.godot")
	assert_gt(cfg.length(), 0, "VOID: project.godot read empty, so this arm checks nothing")
	assert_true(cfg.contains("file_logging/max_log_files="),
		"max_log_files is live in ProjectSettings but not in project.godot — something is setting it at runtime, which cannot help a build he already has")
	var at: int = cfg.find("file_logging/max_log_files=")
	## Guarded on `at`, because find() returns -1 and substr(0, -1) is the WHOLE file, whose last
	## section is [rendering] — so with the key absent this arm named a section nothing is in. The
	## arm above already says the true thing; a second message pointing at the wrong subject is
	## worse than silence, which is the misfiling shape the suppressed-cue classifier had.
	if at > -1:
		var section: String = cfg.substr(0, at)
		var last_section: int = section.rfind("[")
		var head: String = section.substr(last_section, 10) if last_section > -1 else ""
		assert_true(head.begins_with("[debug]"),
			"the key sits under %s, not [debug] — the engine reads debug/file_logging/max_log_files, so a key in the wrong section is inert" % head.strip_edges())
