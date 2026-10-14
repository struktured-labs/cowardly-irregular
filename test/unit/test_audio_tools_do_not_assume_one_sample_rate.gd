extends GutTest

## The music corpus is NOT single-rate, and a tool that assumes it is will
## silently respec whatever disagrees.
##
## tools/crossfade_loop.py carried `SR = 48000` under the comment "Encoding of
## the existing corpus, measured rather than assumed: vorbis 48k mono 96k".
## It is wrong for 19 of 165 tracks, which are 44.1 kHz. Somebody measured a
## majority and wrote it down as a universal, and the word "measured" then made
## it un-recheckable — a stated constant with a provenance claim reads settled.
##
## 🔑 WHY NO VERIFICATION CAUGHT IT. The tool decoded at 48k, encoded at 48k,
## and re-read the result at 48k to verify it. Every check asked ffmpeg for the
## rate it expected instead of the rate on disk, so a resampled file was
## resampled BACK into agreement before any arm looked at it. Measured
## 2026-09-11 on a 44.1 kHz fixture: the shipped tool printed the same duration
## and the same seam figures as the fixed one, and wrote 48000.
##
## ⚠️ AND THE CORPUS GATE ADVERTISED IT. audit_wrap_seams prints
## "-> run: crossfade_loop.py --only <track> --apply" beneath what it flags, and
## four of the thirteen it flagged this session — battle_snake, battle_bat,
## boss_tempo_medieval, danger — are 44.1 kHz beds.
##
## This guard pins the PREMISE (the corpus really is multi-rate, so the
## assumption is really wrong) and the FIX (both rewriting tools read the format
## per file and assert it after encoding). It does not pin any literal rate: if
## the corpus is ever normalised to one rate on purpose, the first arm goes RED
## and the guard should be retired deliberately, not patched.

const MANIFEST := "res://data/music_manifest.json"
const REWRITERS := ["res://tools/crossfade_loop.py", "res://tools/trim_wrap_padding.py",
		"res://tools/true_peak_limit.py"]
## Every tool carrying an ffmpeg ENCODE flag must be either audited above or excluded here WITH A
## REASON. A hand list audited 2 of the 14 encoders in tools/ and its drain test only noticed the
## list EMPTYING, never a tool that was never added — which is how true_peak_limit.py forced
## `-ar 48000` on both its decode and its output for months, unaudited, the identical defect this
## file was written for (measured 2026-10-12: a 44.1 kHz master went in and a 48 kHz file came out).
## @cowir-music flagged the short list; the fix is that the UNION must cover every encoder.
const NOT_A_REWRITER := {
	"audit_loop_seams.py": "reads and reports; its encode is a temp decode for analysis",
	"elevenlabs_sfx.py": "GENERATES from the API — no master is its input",
	"gen_chiptune_sfx.py": "GENERATES; a fixed synthesis rate is the source of truth, not an assumption",
	"gen_freight_lift.sh": "GENERATES freight_lift.ogg from sox synthesis; 44.1 kHz is the rate the samples are MADE at, so no master's rate can disagree with it. Its `sox -R` seed is load-bearing for provenance, not its rate",
	"gen_steam_bed.py": "GENERATES; same",
	"seam_loop_beds.py": "reads and reports seam figures",
	"suno_api.py": "DOWNLOADS a new track",
	"suno_browser.py": "DOWNLOADS a new track",
	"suno_gen.py": "DOWNLOADS a new track",
	"trim_loop_seams.py": "reads and reports; the trim is applied by trim_wrap_padding.py",
	"make_web_audio.sh": "derives a WEB TIER beside the masters and never writes one (cowir-deploy's)",
	"make_web_voice.sh": "derives the web VOICE tier; 24 kHz is the deliberate tier rate, not an assumption",
	"voice_spectrum.py": "DECODES only, for analysis — writes no audio",
}


func _tools_dir_source(path: String) -> String:
	var s: String = FileAccess.get_file_as_string(path)
	assert_gt(s.length(), 2000, "SCOPE control: %s read back %d chars" % [path, s.length()])
	return s


func test_the_corpus_really_does_carry_more_than_one_sample_rate() -> void:
	## The premise. If every OGG were 48k, a hardcoded 48k would be correct and
	## this whole file would be defending nothing.
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: walked %d tracks" % tracks.size())

	var rates: Dictionary = {}
	var checked: int = 0
	for key in tracks.keys():
		var e: Variant = tracks[key]
		if not (e is Dictionary):
			continue
		var f: String = str((e as Dictionary).get("file", ""))
		if f == "" or not ResourceLoader.exists(f):
			continue
		var stream: Variant = load(f)
		if not (stream is AudioStream):
			continue
		checked += 1
		## AudioStreamOggVorbis exposes the rate the file was encoded at.
		var sr: int = 0
		if stream.has_method("get_packet_sequence"):
			var seq: Variant = stream.call("get_packet_sequence")
			if seq != null and seq.has_method("get_sampling_rate"):
				sr = int(seq.call("get_sampling_rate"))
		if sr > 0:
			rates[sr] = int(rates.get(sr, 0)) + 1

	assert_gt(checked, 100,
		"SCOPE control: only %d streams loaded — a green below would mean 'nothing measured', not 'one rate'" % checked)
	assert_gt(rates.size(), 1,
		"every measured OGG is one sample rate (%s) — the corpus is uniform now, so the assumption these tools were fixed for no longer holds; retire this guard deliberately rather than leaving a check that defends nothing" % [rates])


func test_neither_rewriting_tool_hardcodes_a_rate_in_its_encode() -> void:
	## A literal rate anywhere in an ffmpeg argument list is the defect shape,
	## regardless of which variable it sits next to.
	var offenders: Array[String] = []
	for path in REWRITERS:
		var src: String = _tools_dir_source(path)
		for line in src.split("\n"):
			var l: String = str(line)
			if l.strip_edges().begins_with("#") or l.strip_edges().begins_with("##"):
				continue
			if l.contains("\"-ar\"") and (l.contains("\"48000\"") or l.contains("\"44100\"")):
				offenders.append("%s: %s" % [path.get_file(), l.strip_edges()])
	assert_eq(offenders.size(), 0,
		"an ffmpeg encode/decode names a literal sample rate (%d): %s — the corpus is multi-rate, so this converts whatever disagrees and the tool's own verification cannot see it" % [offenders.size(), offenders])


func test_both_rewriting_tools_assert_the_format_after_encoding() -> void:
	## The fix is the assertion, not the intent. A tool that reads the format
	## correctly can still be broken by one edit to its encode call; only a
	## post-encode probe catches that.
	var missing: Array[String] = []
	for path in REWRITERS:
		var src: String = _tools_dir_source(path)
		if not src.contains("encoder changed the format"):
			missing.append(path.get_file())
	assert_eq(missing.size(), 0,
		"rewriting tools with no post-encode format assertion (%s) — the guarantee is documented and unenforced, which is the state that shipped 19 beds' worth of silent respec risk" % [missing])


func test_the_assertion_runs_BEFORE_the_decode_that_would_mask_it() -> void:
	## ⛔ ORDERING IS THE FIX. Both tools re-read their temp file through a
	## decode that REQUESTS the expected rate, so ffmpeg resamples a respecced
	## file back into agreement. An assertion placed after that decode is
	## inert — it compares a converted file against what it was converted to.
	var wrong: Array[String] = []
	for path in REWRITERS:
		var src: String = _tools_dir_source(path)
		var probe_at: int = src.find("encoder changed the format")
		## ⛔ THE MASKING DECODE, IN ANY OF ITS SHAPES — and NOT FOUND is a refusal, not a skip.
		## `continue` here meant a tool whose re-read is spelled differently passed this arm without
		## being looked at: true_peak_limit.py re-reads with `_read(args.dst`, so adding it to the
		## list above would have bought a vacuous green on the one claim that is the actual fix.
		var decode_at: int = -1
		for shape in ["decode(tmp", "_read(args.dst", "_read(tmp"]:
			var at: int = src.find(shape)
			if at > -1 and (decode_at < 0 or at < decode_at):
				decode_at = at
		if probe_at < 0:
			wrong.append("%s (NO post-encode assertion at all)" % path.get_file())
			continue
		if decode_at < 0:
			wrong.append("%s (its re-read of the output is spelled in a shape this arm does not know, so the ORDERING is unchecked — add the shape rather than letting it pass)" % path.get_file())
			continue
		if probe_at > decode_at:
			wrong.append("%s (assert at %d, masking decode at %d)" % [path.get_file(), probe_at, decode_at])
	assert_eq(wrong.size(), 0,
		"the format assertion sits AFTER the decode that normalises the file (%s) — it can never fail, which is worse than absent because it reads as covered" % [wrong])


func test_the_rewriter_list_has_not_drained() -> void:
	## Drain-tested 2026-09-11: REWRITERS emptied -> 13 asserts to 7, every test still PASSING
	## (grade B — no red, no [Risky], only a number nobody reads on a green run). It is the
	## subject of every loop in this file, so emptying it makes the file scan nothing and agree.
	assert_gte(REWRITERS.size(), 2,
		"REWRITERS lists %d tools, was 2 — every check here iterates this list; a tool leaving it stops being audited rather than passing" % REWRITERS.size())
	for path in REWRITERS:
		assert_true(FileAccess.file_exists(path),
			"REWRITERS names %s and it is not on disk — audit a tool that exists, or drop the entry" % path)


## THE UNION, which is what makes the list above a derivation rather than a snapshot: every tool in
## tools/ that carries an ffmpeg encode flag is audited or excluded with a reason. A new audio tool
## reds this until someone classifies it — which is the thing the drain test could never notice.
func test_every_encoding_tool_is_audited_or_excluded_with_a_reason() -> void:
	var d := DirAccess.open("res://tools")
	assert_not_null(d, "VOID: cannot open res://tools")
	if d == null:
		return
	var encoders: Array[String] = []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".py") or f.ends_with(".sh"):
			var src: String = FileAccess.get_file_as_string("res://tools/" + f)
			## Comment lines stripped: this file's own prose names "-c:a" and would classify itself.
			var code := ""
			for line in src.split("\n"):
				var t := str(line).strip_edges()
				if not (t.begins_with("#") or t.begins_with("##")):
					code += str(line) + "\n"
			if code.contains("-c:a") or code.contains("libvorbis") or code.contains("-acodec"):
				encoders.append(f)
		f = d.get_next()
	d.list_dir_end()
	assert_gt(encoders.size(), 5,
		"VOID: only %d encoding tool(s) derived from res://tools — the scan is broken, and a short list here would read as full coverage" % encoders.size())
	var audited := {}
	for path in REWRITERS:
		audited[str(path).get_file()] = true
	var unclassified: Array[String] = []
	for name in encoders:
		if not audited.has(name) and not NOT_A_REWRITER.has(name):
			unclassified.append(name)
	assert_eq(unclassified, [],
		"these tools encode audio and are neither audited by this file nor excluded with a reason (%d of %d encoders): %s — classify each one; an unclassified encoder is how true_peak_limit.py carried `-ar 48000` unnoticed" % [unclassified.size(), encoders.size(), unclassified])
	## And the exclusions must name REAL files, or the map is a place for stale names to hide.
	var ghosts: Array[String] = []
	for name in NOT_A_REWRITER:
		if not FileAccess.file_exists("res://tools/" + str(name)):
			ghosts.append(str(name))
	assert_eq(ghosts, [],
		"NOT_A_REWRITER names tools that no longer exist, so its reasons defend nothing: %s" % [ghosts])
