extends GutTest

const TRIPLE := '"""'

## A health number that does not say which audio it read is not a health number.
##
## `audit_wrap_seams.py` resolves every bed through the manifest's `file` key,
## which names the MASTERS in `assets/audio/music`. Every web build ships a
## different artifact: `make_web_audio.sh` transcodes all 161 masters to 48 kbps
## MONO, `make_web_stage.sh` packs that tier, and `deploy_web.sh` pins the
## bitrate to 48 explicitly. So for months the gate printed
##
##     146 looping beds measured, 0 jump more than 12 dB
##
## about audio no web player has ever heard, and the sentence was identical to
## the one it would print about the audio they do hear. The measurement was not
## wrong; it was unlabelled, which is worse, because nothing on screen could
## distinguish the two corpora.
##
## Measured 2026-09-11 across both, with a byte-size control proving they are
## genuinely different files (146 of 146 differ): the transcode moves seams by
## at most +1.16 dB (boss_mordaine, -26.55 -> -25.40) and NOTHING crosses the
## 12 dB threshold. So the gate was lucky rather than right — but "lucky" is a
## fact about today's corpus, and the next bed authored with a hot loop point
## has no such guarantee.

const TOOL := "res://tools/audit_wrap_seams.py"


func _src() -> String:
	var s: String = FileAccess.get_file_as_string(TOOL)
	assert_gt(s.length(), 4000, "SCOPE control: %s read back %d chars" % [TOOL, s.length()])
	return s


## Comment lines dropped before scanning. This file's own header explains the
## `--from` option, and so does the tool's — so a whole-file `contains("--from")`
## stays green after the option is DELETED. Caught by mutating it out.
## Drops `#` lines AND triple-quoted blocks. The `#`-only version was a FALSE
## GREEN, not merely a weak one: this file asserts tokens are PRESENT in a Python
## tool that carries seven docstrings, so prose naming a token satisfied the assert
## with the code gone. Measured 2026-09-12 — mentioning `os.path.basename` in the
## module docstring and renaming every real call passed 4/4; without the mention it
## reds. Unlike the two suffix guards, nothing behavioural backstopped it here.
func _code_only(src: String) -> String:
	var keep: PackedStringArray = PackedStringArray()
	var in_doc: bool = false
	for line in src.split("\n"):
		var ln: String = str(line)
		if in_doc:
			if ln.contains(TRIPLE):
				in_doc = false
			continue
		var q: int = ln.find(TRIPLE)
		if q >= 0:
			if ln.find(TRIPLE, q + 3) < 0:
				in_doc = true
			continue
		if ln.strip_edges().begins_with("#"):
			continue
		keep.append(ln)
	return "\n".join(keep)


func test_the_gate_can_be_pointed_at_a_corpus_other_than_the_masters() -> void:
	## Without an option the gate can ONLY answer about masters, and the web
	## question cannot be asked at all.
	var code: String = _code_only(_src())
	assert_false(code.contains("resolves each manifest entry"),
		"CONTROL FAILED: a comment survived the strip, so every assert below can be satisfied by prose")
	## The same control for the OTHER comment syntax, which the `#` check above cannot
	## speak for — this phrase exists only inside the tool's module docstring.
	assert_false(code.contains("Measure the WRAP of every looping bed"),
		"CONTROL FAILED: a DOCSTRING survived the strip. Every presence assert below can then be satisfied by prose, and this guard has no behavioural arm to catch it")
	assert_true(code.contains("\"--from\""),
		"audit_wrap_seams.py takes no corpus option in CODE — it can only measure the masters, and the web build ships a 48 kbps transcode of them")
	assert_true(code.contains("CORPUS_DIR = argv["),
		"the flag parses but never assigns the corpus root, so --from is accepted and ignored")
	assert_true(code.contains("os.path.basename"),
		"a redirected corpus must resolve each manifest entry by BASENAME — the manifest's paths point into assets/audio/music and would ignore the override")


## ⛔ THE ARTIFACT ARM. The source arm below asserts the tool CONTAINS a print of
## its corpus. That is a register claim about output — it survives the line being
## unreachable, the format string changing, or the value being wrong. This runs
## the tool and reads what it actually said.
##
## Written after two of my claims were retracted this session for exactly that
## distinction: I read export_presets.cfg and called it a player experience, and
## I read a source scan and called seven Jukebox rows "never played". This guard
## defends the tool whose number I quote at the top of every hourly report, and
## it was the last register-only claim I had left.
func test_the_tool_actually_prints_the_corpus_it_read() -> void:
	## An EMPTY directory is enough: the corpus line prints before the too-small
	## refusal, so this costs ~1s instead of the 30s a full walk takes.
	var probe: String = OS.get_user_data_dir() + "/seam_corpus_probe"
	DirAccess.make_dir_recursive_absolute(probe)
	assert_true(DirAccess.dir_exists_absolute(probe), "SCOPE control: the probe directory was not created")

	var redirected: Array = []
	var ec_redirected: int = OS.execute("uv", ["run", "tools/audit_wrap_seams.py", "--from", probe], redirected, true)
	assert_gt(redirected.size(), 0,
		"CONTROL FAILED: running the tool produced no output at all — the probe cannot distinguish anything below")
	var said: String = str(redirected[0])
	assert_true(said.contains("corpus: " + probe),
		"the tool did not name the corpus it was pointed at. Expected 'corpus: %s' in its output; a source scan for the print statement would have passed regardless. Got: %s" % [probe, said.substr(0, 400)])
	assert_eq(ec_redirected, 2,
		"an empty corpus should be REFUSED (exit 2), not reported as healthy — got %d. The refusal is what keeps a redirected run from reading as a clean bill" % ec_redirected)

	## And the default must say MASTERS, or the two runs are indistinguishable and
	## naming the corpus buys nothing.
	var masters: Array = []
	OS.execute("uv", ["run", "tools/audit_wrap_seams.py", "--from", "assets/audio/music"], masters, true)
	assert_gt(masters.size(), 0, "CONTROL FAILED: the masters run produced no output")
	var m: String = str(masters[0])
	assert_true(m.contains("corpus: assets/audio/music"),
		"the tool did not name the masters corpus when pointed at it: %s" % m.substr(0, 400))
	assert_false(m.contains(probe),
		"the masters run named the PROBE directory — the corpus line is not tracking what was read")


func test_the_report_names_the_audio_it_measured() -> void:
	## The anti-recurrence property. The tool may default to masters forever;
	## what it may not do is print a health verdict that does not say so.
	var s: String = _src()
	assert_true(s.contains("corpus: %s"),
		"the gate prints a bed count and a dB verdict without naming the corpus — the masters and the shipped tier produce the identical sentence")
	var idx: int = s.find("corpus: %s")
	assert_gt(idx, -1)
	var window: String = s.substr(idx, 400)
	assert_true(window.contains("MASTERS"),
		"the default branch must say it is reading the MASTERS — an unlabelled default is the state this file exists to prevent")


func test_the_shipped_tier_is_48k_mono_so_the_question_is_real() -> void:
	## SCOPE control for the whole file. If the web build ever stops transcoding,
	## every arm above still passes while defending nothing.
	var audio: String = FileAccess.get_file_as_string("res://tools/make_web_audio.sh")
	assert_gt(audio.length(), 500, "SCOPE control: make_web_audio.sh read back %d chars" % audio.length())
	assert_true(audio.contains("libvorbis"),
		"the web tier is no longer a re-encode — if it became a copy, seams could not move and this file is moot")
	assert_true(audio.contains("-ac 1"),
		"the web tier is no longer folded to mono — the stereo fold is half of why a seam can move")
	var deploy: String = FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	assert_true(deploy.contains("make_web_stage.sh 48"),
		"deploy_web.sh no longer pins the bitrate to 48 — the tier the gate should be pointed at has changed, and the numbers in this file's header were measured at 48k")

## A clean report must state its MARGIN, not only its violations.
##
## "146 looping beds measured, 0 jump more than 12 dB" is true of a corpus whose worst bed
## sits at 3 dB and of one sitting at 11.8 — and ambient_cave is the second. Measured
## 2026-09-12: +11.8 dB on the MASTERS, +11.7 at the shipped 48k tier, a 0.2 dB margin the
## gate printed nothing about for months. It is why that bed crosses at 44k (+12.2) and 40k
## (+12.1): the bitrate is the TRIGGER, not the cause. A gate that cannot distinguish
## comfortable from one-encode-away cannot be consulted before an encoder change, which is
## the one time anybody needs it.
func test_a_clean_report_states_how_close_the_worst_bed_came() -> void:
	var src: String = _code_only(_src())
	## The wording moved from a single closest bed to the whole sub-1 dB band (below), so this
	## asserts the SURVIVING fallback — the line that still runs when no bed is inside 1 dB.
	assert_gt(src.find("closest: %s at %+.1f dB"), 0,
		"the seam audit reports no margin at all when every bed is comfortably clear. FIX: keep the `closest:` fallback in tools/audit_wrap_seams.py — rows already carries the worst step for every bed, so this costs no measurement. Without it '0 jumps' cannot tell a 3 dB corpus from a 0.2 dB one, and an encoder change is decided blind")
	assert_gt(src.find("JUMP_DB - worst_ok[0]"), 0,
		"the margin is no longer DERIVED from the threshold — a hardcoded figure here would go stale the moment JUMP_DB moves, which is the coincidental-magnitude shape CLAUDE.md warns about")
	assert_gt(src.find("a re-encode at any bitrate can tip these"), 0,
		"the low-headroom warning is gone. FIX: keep the sub-1 dB branch; a thin margin printed as a bare number reads as a pass, and the warning is what makes it a finding")

	## ⛔ AND IT MUST REPORT THE BAND, NOT THE CLOSEST BED. I shipped closest-only and told
	## struktured the tier change cost "one Jukebox-only bed". Measured the next hour: FOUR
	## beds under 1 dB — ambient_cave 0.2, danger_suburban 0.5, dungeon_dragon_ice 0.6,
	## battle_steampunk 0.9 — and three of those are live gameplay beds, not Jukebox rows.
	## One name reads as an outlier; the count is what says whether the corpus is tight.
	assert_gt(src.find("headroom: %d bed(s) under 1 dB"), 0,
		"the seam audit reports only the closest bed again. FIX: restore the band print in tools/audit_wrap_seams.py — a single name reads as one outlier, and the measured corpus has four beds inside 1 dB with three of them on live gameplay routes")
	assert_gt(src.find("for step, key, ws in tight:"), 0,
		"the sub-1 dB beds are counted but no longer NAMED. FIX: keep the loop that prints each one with its margin; a count tells you the corpus is tight and not which encoder change to re-measure")
