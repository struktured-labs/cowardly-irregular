extends GutTest

## Manifest `duration` must describe the file that actually ships (2026-09-09).
##
## This drift has happened twice and neither time was visible from inside the
## game: tools/trim_loop_seams.py shortened OGGs and left the manifest saying
## the old length (107 entries repaired by hand after the 2026-08-26 run), and
## the same tool did it again on a later batch. Nothing failed, nothing warned
## — a stale value is a quiet lie rather than a crash.
##
## ⚠️ I ORIGINALLY WROTE "read by the Jukebox's M:SS display and by anything
## sizing a loop". Grepped the consumer instead of trusting my own sentence
## (fleet rule, 2026-09-09) and the second half is FALSE — I named a consumer
## that does not exist. The manifest's `duration` has exactly ONE reader in
## src/: JukeboxMenu.gd:96. Every other `duration` in the codebase belongs to a
## different dictionary — status effects, ability durations, cutscene steps,
## procedural generation params. Nothing sizes a loop from it.
##
## The Jukebox half DOES hold, and in code rather than in its own comment:
## _format_duration returns "" for sec <= 0.0, which is the 0.0-means-unrendered
## convention below.
##
## So the honest stake is smaller than I claimed: a stale duration shows the
## player the wrong time in the Jukebox. That is still worth catching — this
## drift has happened twice and cost 107 hand-repairs — but the guard defends a
## display, not the audio engine, and overstating it is the thing this file
## exists to prevent.
##
## 🔑 AND IT DOUBLE-DUTIES AS THE "YOU FORGOT --import" GUARD, which I only
## noticed when cowir-controller pointed out that "⚠️ needs --import at the
## fold" in a commit message is a REMINDER WEARING A RULE'S CLOTHES — it works
## only if the person folding at 3am reads it. This one is structural instead.
## Demonstrated 2026-09-10 by building the real hazard rather than reasoning:
##     new OGG on disk + import cache still holding the OLD audio
##        -> FAILS, naming the track and both durations
##     after --import
##        -> passes
## Because load() returns what Godot IMPORTED, not what is on disk, a fold that
## skips the import reads the stale length against a fresh manifest. My first
## simulation had it backwards (old file, new cache) and passed — which is
## correct behaviour and proves nothing, so the arm that matters is the one
## above.
##
## Godot can settle it without ffprobe: the imported AudioStream knows its own
## length. That makes this a CONTENT check, not a bookkeeping one — it compares
## the manifest against the audio the engine will actually play, so it also
## catches a track reverted to an older, longer render.
##
## Tolerance is deliberately loose (0.6s). Vorbis length via the import
## pipeline and the encoder's own idea of duration disagree in the third
## decimal, and the defect class this defends is measured in SECONDS (2-33s
## cuts), never in frames.

const MANIFEST := "res://data/music_manifest.json"
const TOLERANCE_S := 0.6

## A duration of 0.0 means "not rendered yet" by convention (JukeboxMenu reads
## it that way and prints no time), so it is a declaration, not a measurement.
const UNRENDERED := 0.0


func test_every_manifest_duration_matches_the_shipped_audio() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest must parse to a Dictionary")
	var tracks: Dictionary = (parsed as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest carries %d tracks" % tracks.size())

	var checked: int = 0
	var drifted: Array[String] = []
	var unloadable: Array[String] = []
	for key in tracks.keys():
		var entry: Variant = tracks[key]
		if not (entry is Dictionary):
			continue
		var f: String = str((entry as Dictionary).get("file", ""))
		if f == "":
			continue
		## An unrendered track has NO FILE, and that skip is above. Reaching here
		## with duration 0.0 means the track HAS audio and claims no length —
		## which is the defect, not an exemption from it. The original wrote the
		## skip on the duration instead of the file, so its stated reason ("not
		## rendered yet") did not match its condition and a real track with a
		## zeroed duration was silently exempt. Inert today (0 such tracks), but
		## an exemption is not harmless for covering nothing — that is exactly
		## the shape that converts "we owe something" into "this is fine".
		var declared: float = float((entry as Dictionary).get("duration", UNRENDERED))
		if declared == UNRENDERED:
			drifted.append("%s: has a file but declares duration 0.0" % key)
			continue
		var res_path: String = f if f.begins_with("res://") else "res://" + f
		if not ResourceLoader.exists(res_path):
			unloadable.append("%s (%s)" % [key, f])
			continue
		var stream: Variant = load(res_path)
		if stream == null or not (stream is AudioStream):
			unloadable.append("%s (loaded as %s)" % [key, type_string(typeof(stream))])
			continue
		var actual: float = (stream as AudioStream).get_length()
		checked += 1
		if absf(actual - declared) > TOLERANCE_S:
			drifted.append("%s: manifest %.1fs vs audio %.1fs (%+.1fs)"
				% [key, declared, actual, actual - declared])

	assert_gt(checked, 100,
		"SCOPE control: only %d tracks were actually measured — the walk is broken, and a zero-drift result would be vacuous" % checked)
	assert_eq(unloadable.size(), 0,
		"manifest names audio that will not load (%d): %s — run --import, or the file is missing/an LFS pointer" % [unloadable.size(), unloadable])
	## ⚠️ TWO CAUSES, AND THE MESSAGE USED TO NAME ONLY ONE. It said "whatever
	## rewrote the OGG did not rewrite the number", which sends the reader after
	## a manifest bug. The other cause is a STALE IMPORT CACHE, and it is the
	## likelier one during normal work: load() returns what Godot IMPORTED, not
	## what is on disk, so checking out a tree whose OGGs differ from the last
	## --import compares this manifest against the PREVIOUS branch's audio.
	##
	## Measured 2026-09-11: checking out v3.33.295-alpha with a cache built on a
	## queued trim branch produced exactly this failure on TWO stingers, on a
	## tagged release that was clean — manifest 9.84 vs disk 9.8400. A false RED
	## on a shipped tag, indistinguishable from a real defect by the old wording.
	## Re-importing made it pass.
	##
	## ⚠️ AND A THIRD CAUSE, added 2026-09-11 after the same false red hit three
	## lanes at once on d4f0900c: cause (1)'s instruction can FAIL. cowir-sfx
	## measured a tree whose OGG BYTES differ from main\'s LFS pointer, so
	## --import re-derived the artifact faithfully from last week\'s blob and the
	## red persisted. A reader following the old message would then land on "A
	## REAL DRIFT" and go hunting a manifest bug that does not exist.
	##
	## The counts are the tell and they are free: cowir-adhoc saw 2 offenders,
	## cowir-autogrind saw 15, cowir-main saw 0 — same SHA, three trees. A defect
	## in the tree gives everyone the same number; a number that varies by
	## checkout is measuring how stale each reader is.
	##
	## The discriminator is one command, so the message now carries it.
	assert_eq(drifted.size(), 0,
		"manifest duration disagrees with the audio Godot LOADED (%d): %s\n  TWO CAUSES, check the cheap one first:\n  (1) STALE IMPORT CACHE — you changed branches and did not re-import. load() returns the IMPORTED audio, not the file on disk. Run: XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit  and re-run. If it passes, there was no defect.\n  (2) A STALE LFS BLOB, one layer UNDER the cache — the bytes on disk are not the bytes main points at, so --import faithfully re-derives the WRONG audio and the red survives cause (1). Check: git show origin/main:<file> | grep -o \'sha256:[a-f0-9]*\'  against  sha256sum <file>. DIFFER means run git lfs pull, THEN --import.\n  (3) A REAL DRIFT — something rewrote the OGG without rewriting the number. Confirm with ffprobe against the file on disk before believing it. This is SILENT at runtime; the Jukebox just prints the wrong time." % [drifted.size(), drifted])
