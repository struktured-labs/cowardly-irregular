extends GutTest

## Regression, cowir-main 21522: ambient_cave (manifest key suno_dripping_stone) crossed the 12 dB seam gate
## on the shipped 40k tier at .760 (+12.1 dB @ 100ms, publish.log "NOT blocking"), and the fix the audit
## prints, crossfade_loop.py --only <track> --apply, answered "+7.0 dB at a 0.3s seam - it already loops".
## The audit judges the worst of SEAM_WINDOWS_S (50/100/300 ms); the fixer judged 0.3s alone, so a short
## loud head hit over a steady tail was flagged by one tool and skipped by the other.

const TOOL := "tools/crossfade_loop.py"
const KEY := "suno_dripping_stone"


func _probe(name: String, head_amp: float) -> String:
	## 12 s of a 220 Hz tone at 0.05, the first 50 ms at head_amp: +15.6 dB at 50 ms but +8.4 at 300 ms for 0.3.
	var dir: String = OS.get_user_data_dir() + "/loop_fixer_probe"
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir + "/" + name + ".ogg"
	var expr: String = "if(lt(t\\,0.05)\\,%s\\,0.05)*sin(2*PI*220*t)" % str(head_amp)
	var out: Array = []
	var ec: int = OS.execute("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "aevalsrc=%s:s=44100:d=12" % expr,
		"-ac", "1", "-c:a", "libvorbis", "-b:a", "96k", path], out, true)
	assert_eq(ec, 0, "CONTROL: ffmpeg could not write the probe %s: %s" % [path, str(out)])
	return path


func _dry_run(source: String) -> Array:
	## A dry run: no --apply, so nothing is written, and --source keeps the manifest's own file out of it.
	## Exit 0 = skipped or folded; 1 = "a named target needed work and was not fixed" (a refusal); anything else broke.
	var out: Array = []
	var ec: int = OS.execute("uv", ["run", TOOL, "--only", KEY, "--source", source], out, true)
	var said: String = str(out[0]) if out.size() > 0 else ""
	assert_true(ec == 0 or ec == 1, "CONTROL: %s exited %d on %s, which is neither a verdict nor a refusal: %s" % [TOOL, ec, source, said.substr(0, 400)])
	assert_true(said.contains(KEY), "CONTROL: the tool's report never named %s, so it judged nothing: %s" % [KEY, said.substr(0, 400)])
	return [ec, said]


func test_a_flat_bed_is_still_skipped() -> void:
	## The control that makes the next arm mean something: a skip is still reachable.
	var r: Array = _dry_run(_probe("flat", 0.05))
	var said: String = r[1]
	assert_eq(r[0], 0, "a flat bed must exit 0 (nothing needed work): %s" % said.substr(0, 400))
	assert_true(said.contains("skipped:"), "a bed with a flat wrap was not skipped, so 'not skipped' below proves nothing: %s" % said.substr(0, 400))


func test_a_short_head_hit_is_not_called_already_looping() -> void:
	var said: String = _dry_run(_probe("hit", 0.3))[1]
	assert_false(said.contains("skipped:"),
		"the fixer called a +15.6 dB step at 50 ms 'already loops' because it measured only a 0.3s window, which the audit flags and this tool must fix or refuse: %s" % said.substr(0, 400))
