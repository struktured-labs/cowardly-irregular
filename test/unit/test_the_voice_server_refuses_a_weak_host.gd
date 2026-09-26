extends GutTest

## The voice-server launcher installed on a CPU-only laptop, filled swap, and a 2.6 s line never finished
## (moonshot, 2026-09-25). install now refuses such a host with exit 8 unless --allow-weak-host is passed.
## tools/tts_server/ sits below the depth test_every_tool_selftest_still_passes walks, so this runs its selftest.

const LAUNCHER := "tools/tts_server/cowir_tts.py"


func _run(args: Array) -> Array:
	var out: Array = []
	var code := OS.execute("python3", args, out, true)
	return [code, "\n".join(out)]


func test_the_launcher_selftest_passes() -> void:
	var probe := _run(["-c", "print('alive')"])
	if probe[0] != 0:
		pending("python3 unavailable — the launcher cannot be exercised here")
		return
	var res := _run([ProjectSettings.globalize_path("res://" + LAUNCHER), "--selftest"])
	assert_eq(res[0], 0, "cowir_tts.py --selftest failed:\n%s" % res[1])
	assert_true(str(res[1]).contains("the moonshot shape"), "CONTROL: the selftest printed none of its cases:\n%s" % res[1])


func test_the_refusal_code_is_documented_for_the_wizard() -> void:
	var src := FileAccess.get_file_as_string("res://" + LAUNCHER)
	assert_true(src.contains("EXIT_WEAK_HOST = 8"), "the weak-host exit code moved; the setup wizard branches on 8")
	assert_true(src.contains("    8  this machine cannot host"), "exit 8 is missing from the documented code table")
	assert_true(src.contains("--allow-weak-host"), "the knowing opt-in flag is gone")
