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


## ⛔ ResourceLoader.exists() AND load() BOTH ANSWER FROM THE IMPORT CACHE, so
## every duration arm in this lane was blind to a DELETED source. `--import`
## rebuilds artifacts from the bytes on disk but does not REAP an orphan, so a
## tree that has ever imported keeps serving a .oggstr whose .ogg is gone.
##
## Measured 2026-09-11 by deleting assets/audio/music/victory_medieval.ogg:
##     test_manifest_duration_matches_audio          GREEN
##     test_music_manifest_duration_matches_stream   GREEN
##     test_every_authored_bed_has_a_consumer        GREEN
## Three guards over the same corpus, none of which could see the disk.
##
## 🔑 THE PREMISE WAS ALREADY RIGHT — this file walks every manifest entry by
## name, which is the named-membership shape the fleet converged on today. A
## correct premise is fully defeated by a reader that is not looking at the
## thing, and it is the QUIETER failure of the two, because the premise being
## right is what makes the green persuasive. cowir-sprites hit the identical
## split in a test literally named "exists_on_disk".
##
## FileAccess.file_exists reads the filesystem. That is the whole fix.
## ⛔ THE OTHER DIRECTION, which the arm below does not cover. It quantifies over
## MANIFEST ENTRIES and asks whether each file exists. Nothing quantified over
## FILES ON DISK asking whether the manifest names them — cowir-deploy's
## directionality point, which they flagged on their pck gate ("1517 owed of
## 3326 stored; an orphan lives in that 1809 and is invisible by construction").
##
## Not hypothetical here: measured by hand 2026-09-11, the music directory held
## 163 .ogg against 161 named, and the two extras were real dead files —
## sfx_ability_fire.ogg and sfx_ability_ice.ogg, 619 KB of 30-second Suno output
## that shipped in the desktop builds for five months because only the WEB
## preset excluded them. They were found by a manual count, not by any guard.
## This is that count, kept.
func test_every_music_file_on_disk_is_named_by_the_manifest() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var named: Dictionary = {}
	for key in tracks.keys():
		var e: Variant = tracks[key]
		if e is Dictionary:
			var f: String = str((e as Dictionary).get("file", ""))
			if f != "":
				named[f.trim_prefix("res://")] = true
	assert_gt(named.size(), 100, "SCOPE control: the manifest names %d files" % named.size())

	var d := DirAccess.open("res://assets/audio/music")
	assert_true(d != null, "SCOPE control: the music directory will not open")
	if d == null:
		return
	var on_disk: int = 0
	var orphans: Array[String] = []
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if n.ends_with(".ogg"):
			on_disk += 1
			if not named.has("assets/audio/music/" + n):
				orphans.append(n)
		n = d.get_next()
	d.list_dir_end()

	assert_gt(on_disk, 100,
		"SCOPE control: only %d .ogg found on disk — DirAccess is not reaching the directory and an empty orphan list would be vacuous" % on_disk)
	assert_eq(orphans.size(), 0,
		"audio shipping in the build that NO manifest entry names (%d of %d): %s — nothing can play it and nothing reports it missing. It rides in every desktop export; only the Web preset's exclude_filter would drop it, and only if the name happens to match a pattern." % [orphans.size(), on_disk, orphans])


func test_every_manifest_file_is_actually_on_disk() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: walked %d manifest tracks" % tracks.size())

	var missing: Array[String] = []
	var checked: int = 0
	for key in tracks.keys():
		var e: Variant = tracks[key]
		if not (e is Dictionary):
			continue
		var f: String = str((e as Dictionary).get("file", ""))
		if f == "":
			continue
		var res_path: String = f if f.begins_with("res://") else "res://" + f
		checked += 1
		if not FileAccess.file_exists(res_path):
			## Name what the cache says too, so the reader can tell a deleted
			## source from a path typo at a glance.
			var cached: String = "and load() STILL SERVES IT" if ResourceLoader.exists(res_path) else "and the cache agrees it is gone"
			missing.append("%s -> %s (%s)" % [key, f, cached])
	assert_gt(checked, 100,
		"SCOPE control: only %d entries carried a file path — a clean result below would be vacuous" % checked)
	assert_eq(missing.size(), 0,
		"the manifest names audio that is NOT ON DISK (%d of %d): %s — every other duration arm in this lane reads through load(), which keeps serving the imported artifact after the source is deleted, so they stay green. A fresh clone would fail where this tree succeeds, and an export from here can ship an asset whose source no longer exists." % [missing.size(), checked, missing])


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
