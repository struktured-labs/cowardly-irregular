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
const REWRITERS := ["res://tools/crossfade_loop.py", "res://tools/trim_wrap_padding.py"]


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
		var decode_at: int = src.find("decode(tmp")
		if probe_at < 0 or decode_at < 0:
			continue
		if probe_at > decode_at:
			wrong.append("%s (assert at %d, masking decode at %d)" % [path.get_file(), probe_at, decode_at])
	assert_eq(wrong.size(), 0,
		"the format assertion sits AFTER the decode that normalises the file (%s) — it can never fail, which is worse than absent because it reads as covered" % [wrong])
