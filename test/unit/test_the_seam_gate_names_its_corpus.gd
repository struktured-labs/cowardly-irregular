extends GutTest

const TRIPLE := '"""'

## A health number that does not say which audio it read is not a health number.
##
## `audit_wrap_seams.py` resolves every bed through the manifest's `file` key,
## which names the MASTERS in `assets/audio/music`. Every web build ships a
## different artifact: `make_web_audio.sh` transcodes all 161 masters to a
## reduced-bitrate MONO tier, `make_web_stage.sh` packs it, and `deploy_web.sh`
## pins which tier through `WEB_AUDIO_KBPS` (48 until struktured's 2026-09-16
## ruling dropped the web build to 40k for the browser cache line). So for
## months the gate printed
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


## ⛔ SHELL, NOT PYTHON — and `_code_only` above CANNOT do this file's shell subjects.
## `test/unit/helpers/gd_source.gd` cannot either: its own header measures that `"""` parity
## eats live shell lines, because shell has no docstring for the fences to delimit.
##
## The exposure is live and load-bearing, measured 2026-09-16 on `deploy_web.sh`:
##
##     a comment ABOVE line 85 reading `# was WEB_AUDIO_KBPS:-48 until the ruling`
##     -> _shipped_kbps() returns 48 while the build ships 40, and 48 is in MEASURED_TIERS,
##        so the whole file reasons about a corpus nobody hears AND reports green
##     `deploy.contains("make_web_stage.sh \"$WEB_AUDIO_KBPS\"")` -> satisfied by a COMMENT
##        naming it, so a deploy that pins a tier and never hands it over reads as wired
##
## That token already appears in a comment in that file today (`:301`), so this is a live
## syntax, not a hypothetical one. Quote-aware, and `#` only starts a comment at the start of
## a word — `${VAR#pat}` and `music_${KBPS}k` must survive.
static func _shell_code_only(src: String) -> String:
	var keep: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var ln: String = str(line)
		var quote: String = ""
		var out: String = ""
		var i: int = 0
		## Bounded by construction: every branch consumes at least one character, so a correct
		## scan cannot reach length + 1. A dropped advance TRUNCATES instead of spinning — a hang
		## reads as infrastructure and outlives its own sweep.
		var budget: int = ln.length() + 1
		while i < ln.length():
			budget -= 1
			if budget < 0:
				break
			var ch: String = ln[i]
			if quote != "":
				out += ch
				if ch == "\\" and quote == "\"" and i + 1 < ln.length():
					out += ln[i + 1]
					i += 2
					continue
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
				out += ch
			elif ch == "#" and (i == 0 or ln[i - 1] == " " or ln[i - 1] == "\t"):
				break
			else:
				out += ch
			i += 1
		keep.append(out)
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
		"audit_wrap_seams.py takes no corpus option in CODE — it can only measure the masters, and the web build ships a reduced-bitrate transcode of them")
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


## Tiers this file's seam numbers were actually measured at (2026-09-12, both corpora).
## A shipped tier outside this list has no measurement behind it, and the verdict would
## again describe audio nobody hears — the exact defect this file exists to prevent.
const MEASURED_TIERS: Array[int] = [48, 44, 40]


## Derived, never restated: a second copy of the number here would go stale the next
## time the ruling moves, which is how this arm broke when 48 became 40.
## `source_override` exists ONLY so an arm can drive THIS function with a poisoned source.
## Without it the arms could test `_shell_code_only` and never its USE — measured 2026-09-16:
## deleting the strip from this very function left all 8 arms green, because every one of them
## called the helper directly. A helper kept and its answer discarded is the shape three lanes
## hit today (@cowir-sprites mutation 7, @cowir-cutscenes, @cowir-ai).
## Does any `make_web_stage.sh` invocation reference the pinned variable? The PROPERTY behind
## "the pin is handed over", independent of quoting, braces, or the path it is called by.
func _has_handover(src: String) -> bool:
	for line in src.split("\n"):
		var l: String = str(line)
		if l.contains("make_web_stage.sh") and l.contains("WEB_AUDIO_KBPS"):
			return true
	return false


func _shipped_kbps(source_override: String = "") -> int:
	var deploy_raw: String = source_override if source_override != "" else FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	assert_gt(deploy_raw.length(), 500, "SCOPE control: deploy_web.sh read back %d chars" % deploy_raw.length())
	var deploy: String = _shell_code_only(deploy_raw)
	assert_true(deploy.contains("WEB_AUDIO_KBPS"),
		"CONTROL: the strip ate the assignment — every assert below would be satisfied by nothing")
	var re: RegEx = RegEx.create_from_string("WEB_AUDIO_KBPS:-([0-9]+)")
	var m: RegExMatch = re.search(deploy)
	assert_not_null(m, "deploy_web.sh no longer pins a bitrate through WEB_AUDIO_KBPS — the shipped tier cannot be derived, so nothing below knows which corpus ships")
	if m == null:
		return 0
	return int(m.get_string(1))


## Same `source_override` seam as `_shipped_kbps`, for the same reason: without it an arm can only
## reach `_shell_code_only`, and the strip could be dropped from this read with every arm green.
func _transcode_code(source_override: String = "") -> String:
	var audio_raw: String = source_override if source_override != "" else FileAccess.get_file_as_string("res://tools/make_web_audio.sh")
	assert_gt(audio_raw.length(), 500, "SCOPE control: make_web_audio.sh read back %d chars" % audio_raw.length())
	var audio: String = _shell_code_only(audio_raw)
	assert_true(audio.contains("ffmpeg"),
		"CONTROL: the strip ate the transcode call — the asserts that consume this would measure an empty string")
	return audio


## ⛔ ITS OWN ARM, not a side-assert inside a value-returning helper — so a real change to
## deploy_web.sh reds by NAME instead of firing inside `_shipped_kbps` under a message about
## deriving a tier.
##
## ⚠ AND ITS LIMIT, because I measured it rather than assuming: this is a LIVE-STATE
## assertion, so no mutation of THIS file can red it while deploy_web.sh is correct — neutering
## it is invisible. The logic behind it is covered by the two arms that drive `_has_handover`
## with constructed sources; dropping its variable condition reds both by name. A named failure
## is worth having and is not the same as being mutation-proven.
##
## ⛔ THE PROPERTY, NOT THE SPELLING. It used to assert the literal
## `make_web_stage.sh "$WEB_AUDIO_KBPS"` — where a token SITS rather than what the script DOES.
## Two legal respellings red that on correct code: `"${WEB_AUDIO_KBPS}"` and a bare
## `$WEB_AUDIO_KBPS`. (@cowir-battle's smell, same day: the literal I asserted about was a NAME.)
func test_the_pinned_tier_is_handed_to_the_stage_script() -> void:
	var deploy: String = _shell_code_only(FileAccess.get_file_as_string("res://tools/deploy_web.sh"))
	assert_true(deploy.contains("WEB_AUDIO_KBPS"),
		"CONTROL: the strip ate the assignment — the assert below would be satisfied by nothing")
	assert_true(_has_handover(deploy),
		"deploy_web.sh pins a bitrate it does not hand to the stage script — no make_web_stage.sh invocation references WEB_AUDIO_KBPS, so the stage default would ship instead and the pin would be decorative")


func test_the_shipped_tier_is_a_measured_mono_reencode_so_the_question_is_real() -> void:
	## SCOPE control for the whole file. If the web build ever stops transcoding,
	## every arm above still passes while defending nothing.
	var audio: String = _transcode_code()
	assert_true(audio.contains("libvorbis"),
		"the web tier is no longer a re-encode — if it became a copy, seams could not move and this file is moot")
	assert_true(audio.contains("-ac 1"),
		"the web tier is no longer folded to mono — the stereo fold is half of why a seam can move")
	var kbps: int = _shipped_kbps()
	assert_true(kbps in MEASURED_TIERS,
		"the web build ships a %dk tier and this file's numbers were measured at %s — re-run audit_wrap_seams.py --from tmp/web_audio/music_%dk and add the tier to MEASURED_TIERS, or the gate speaks about audio nobody ships" % [kbps, str(MEASURED_TIERS), kbps])


## A clean report must state its MARGIN, not only its violations.
##
## "146 looping beds measured, 0 jump more than 12 dB" is true of a corpus whose worst bed
## sits at 3 dB and of one sitting at 11.8 — and ambient_cave is the second. Measured
## 2026-09-12: +11.8 dB on the MASTERS, +11.7 at the then-shipped 48k tier, a 0.2 dB margin the
## gate printed nothing about for months. It is why that bed crosses at 44k (+12.2) and 40k
## (+12.1): the bitrate is the TRIGGER, not the cause. ⛔ The web build MOVED to 40k on
## 2026-09-16, so ambient_cave now crosses on the tier players actually hear — cowir-music's
## loop point, not a gate defect. A gate that cannot distinguish
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


## ⛔ THE DERIVATION READS SHELL SOURCE, AND SHELL HAS COMMENTS. These three arms exist because
## `_shipped_kbps()` decides which corpus this whole file reasons about: get it wrong and every
## other arm is a correct measurement of audio nobody hears — the exact defect the file was
## written to prevent, arriving through its own instrument.
const _KBPS_RE := "WEB_AUDIO_KBPS:-([0-9]+)"


func _derive_kbps(src: String) -> int:
	var re: RegEx = RegEx.create_from_string(_KBPS_RE)
	var m: RegExMatch = re.search(src)
	return int(m.get_string(1)) if m != null else 0


func test_a_comment_cannot_name_the_shipped_tier() -> void:
	var raw: String = FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	var real: int = _derive_kbps(_shell_code_only(raw))
	assert_true(real in MEASURED_TIERS,
		"CONTROL: the live file derives %d kbps, which must be a tier this file has numbers for" % real)

	## Planted ABOVE the assignment, because RegEx.search takes the FIRST match — a comment below
	## it changes nothing and would make this arm pass without defending anything.
	var lines: PackedStringArray = raw.split("\n")
	var planted: PackedStringArray = PackedStringArray()
	planted.append("# historical: WEB_AUDIO_KBPS:-48 until the 2026-09-16 ruling")
	for l in lines:
		planted.append(str(l))
	var poisoned: String = "\n".join(planted)

	assert_eq(_derive_kbps(poisoned), 48,
		"CONTROL FAILED: the planted comment did not poison the RAW source, so the strip below has nothing to prove")
	assert_eq(_derive_kbps(_shell_code_only(poisoned)), real,
		"a shell COMMENT named the shipped tier: derived %d against the code's %d. Every arm in this file would then measure the wrong corpus and report green" % [_derive_kbps(_shell_code_only(poisoned)), real])


func test_a_comment_cannot_stand_in_for_the_pass_through() -> void:
	## The pass-through assert is what stops a pinned bitrate being decorative. A comment naming
	## the call satisfies `contains()` exactly as well as the call does.
	var raw: String = FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	## Gut the real invocation BY REFERENCE rather than by spelling, then leave a comment naming it.
	var gutted_lines: PackedStringArray = PackedStringArray()
	var gutted_one: bool = false
	for line in raw.split("\n"):
		var l: String = str(line)
		if not gutted_one and l.contains("make_web_stage.sh") and l.contains("WEB_AUDIO_KBPS"):
			gutted_lines.append(l.replace("WEB_AUDIO_KBPS", "48"))
			gutted_one = true
		else:
			gutted_lines.append(l)
	assert_true(gutted_one, "CONTROL: the live file really does hand the tier over on some line")
	var gutted: String = "\n".join(gutted_lines) + "\n# we hand it over with make_web_stage.sh \"$WEB_AUDIO_KBPS\" further up\n"

	assert_true(_has_handover(gutted), "CONTROL FAILED: the gutted source lost the planted comment, so this arm proves nothing")
	assert_false(_has_handover(_shell_code_only(gutted)),
		"a comment stood in for the pass-through: a deploy that pins a tier and never hands it over would read as wired")


func test_the_strip_leaves_shell_that_is_not_a_comment() -> void:
	## ⛔ THE DANGEROUS DIRECTION, and shell has two ways to lose here that Python does not:
	## `${VAR#pattern}` is parameter expansion, and a `#` inside quotes is data. Over-stripping
	## and a correct strip are the same green — the controls above only fire if code SURVIVES.
	var probe: String = "\n".join([
		"KBPS=\"${WEB_AUDIO_KBPS:-40}\"",
		"DIR=\"tmp/web_audio/music_${KBPS}k\"",
		"TRIMMED=${DIR#tmp/}",
		"echo \"a # inside quotes is data\"",
		"echo 'single # too'",
		"real_code=1  # but this trailing one is a comment",
		"# and this whole line is",
	])
	var code: String = _shell_code_only(probe)
	assert_true(code.contains("${WEB_AUDIO_KBPS:-40}"), "the assignment must survive")
	assert_true(code.contains("music_${KBPS}k"), "a ${} expansion must survive")
	## ⛔ UNQUOTED ON PURPOSE. Quoted, the quote branch swallows the `#` before the word-start rule
	## is ever consulted — so a quoted probe passes with that rule DELETED. Measured: mutating
	## `# only at a word start` to `# always` left this arm green until the quotes came off.
	assert_true(code.contains("${DIR#tmp/}"), "parameter expansion with # must survive — this is not a comment")
	assert_true(code.contains("a # inside quotes is data"), "a # inside double quotes is data")
	assert_true(code.contains("single # too"), "a # inside single quotes is data")
	assert_true(code.contains("real_code=1"), "code before a trailing comment must survive")
	assert_false(code.contains("but this trailing one is a comment"), "a trailing comment must go")
	assert_false(code.contains("and this whole line is"), "a whole-line comment must go")


func test_the_derivation_itself_strips_before_it_reads() -> void:
	## ⛔ THE ARM THE OTHER THREE COULD NOT BE. They drive `_shell_code_only` directly, so the
	## strip could be deleted from `_shipped_kbps()` and every one of them stays green — the
	## helper is still correct, it is simply no longer consulted. This drives the REAL function.
	var raw: String = FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	var real: int = _shipped_kbps()
	assert_true(real in MEASURED_TIERS, "CONTROL: the live derivation gives %d" % real)

	var planted: PackedStringArray = PackedStringArray()
	planted.append("# historical: WEB_AUDIO_KBPS:-48 until the 2026-09-16 ruling")
	for l in raw.split("\n"):
		planted.append(str(l))
	assert_eq(_shipped_kbps("\n".join(planted)), real,
		"_shipped_kbps() read a COMMENT as the shipped tier — it returned %d against the code's %d, and this file would then measure a corpus nobody hears" % [_shipped_kbps("\n".join(planted)), real])


func test_a_comment_cannot_stand_in_for_the_transcode() -> void:
	## The other half of the same exposure. "the web tier is still a re-encode" is asserted by
	## `contains("libvorbis")` over shell source, and a comment saying the word satisfies it just
	## as well — at which point a tier that became a straight COPY reads as a re-encode, and every
	## seam number in this file describes a transform that no longer happens.
	var raw: String = FileAccess.get_file_as_string("res://tools/make_web_audio.sh")
	assert_true(_transcode_code().contains("libvorbis"), "CONTROL: the live script really does transcode")

	var gutted: String = raw.replace("libvorbis", "copy")
	gutted += "\n# we used to pass -c:a libvorbis here before the copy-through\n"
	assert_true(gutted.contains("libvorbis"),
		"CONTROL FAILED: the gutted source lost the planted comment, so this arm proves nothing")
	assert_false(_transcode_code(gutted).contains("libvorbis"),
		"a comment stood in for the transcode: a tier that became a straight copy would read as a re-encode")


func test_the_handover_check_reads_the_reference_not_the_spelling() -> void:
	## ⛔ THE ARM THAT MAKES THE REWRITE MEAN SOMETHING. The old form asserted the literal
	## `make_web_stage.sh "$WEB_AUDIO_KBPS"`, so two legal shell respellings redded it on correct
	## code. Without this arm the tolerance is unpinned and the next edit can quietly restore the
	## brittleness — the property is "the invocation references the pinned variable", and shell has
	## several right ways to write that.
	var forms: Array[String] = [
		'  ./tools/make_web_stage.sh "$WEB_AUDIO_KBPS" || die',
		'  ./tools/make_web_stage.sh "${WEB_AUDIO_KBPS}" || die',
		'  bash tools/make_web_stage.sh $WEB_AUDIO_KBPS',
		'  WEB_AUDIO_KBPS=40 exec ./tools/make_web_stage.sh "$WEB_AUDIO_KBPS"',
	]
	for f in forms:
		assert_true(_has_handover(f), "a legal shell spelling must still read as handed over: %s" % f.strip_edges())

	## ⛔ AND THE NEGATIVE, or the check above is satisfied by anything: a hardcoded tier is
	## exactly the defect — the pin exists and the stage never sees it.
	assert_false(_has_handover('  ./tools/make_web_stage.sh 48 || die'),
		"a hardcoded bitrate must NOT read as handed over — that is the decorative pin this arm exists for")
	assert_false(_has_handover('  echo "$WEB_AUDIO_KBPS kbps tier"'),
		"a line naming the variable without calling the stage script is not a handover")
