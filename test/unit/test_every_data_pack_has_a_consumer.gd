extends GutTest

## A content pack nothing loads is prose the player cannot reach. Measured 2026-10-12: of 32 files
## in data/, seven are named by no path in src/ — four of them 3,573 words of prose nothing loads:
## examine_texts.json (26 examines, 915 words, 2026-04-21 and extended 2026-07-13),
## world2_coordinator_memos.json (6 memos, 944 words, 2026-07-28, 17 strings unique to that file),
## castle_harmonia_narrative.json (5 NPCs + 1 puzzle, 510 words, 2026-07-13) and lore.json (1,204).
## Each was authored for a redesign whose wiring never landed, and nothing failed, so nobody looked.
##
## 🔑 THE REACH CORPUS IS src/ ONLY, AND THAT IS THE WHOLE POINT. A pack read by a test or a tool is
## still unreachable in a player's game; counting those as consumers would have reported all four of
## the above as wired. data/ is excluded too — every file names itself.
##
## ⛔ AND IT IS STRIPPED OF COMMENTS AND DOCSTRINGS, because a presence assert over raw source is
## satisfied by prose ABOUT the code: src/ mentions "Phoenix Down" in four comments and the item
## does not exist. See GdSource's own header for the measured version of that failure.
##
## ⚠️ "NO CONSUMER" IS NOT "UNREACHED CONTENT", and one roster entry is the proof. Every one of the
## 17 strings in world2_coordinator_memos.json is unique to that file — and 7 of its 8 BEATS ship
## anyway, re-authored in other words inside the world2_chapter8_memos cutscene the player reaches.
## A substring census answers "is this text loaded", never "has this beat shipped". Read the shipped
## scene before wiring a pack, or you duplicate the scene you were trying to reach.
##
## 📌 TOP-LEVEL data/*.json only. data/cutscenes/ is loaded through a constructed path
## (`res://data/cutscenes/%s.json`), so a filename scan cannot answer for it — that corpus has its
## own reachability guard in test_every_theater_exclusion_is_declared_regression.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC_DIR := "res://src"
const CONTROL_FILE := "job_personas.json"
const MIN_SOURCE_FILES := 200

## Each unreached pack: [kind, why, the guard that earns the kind].
##   BASELINE   — a claim ABOUT an artifact, whose job is to have no runtime reader; wiring one would
##                be the defect. ⛔ The excuse is earned by a TEST THAT COMPARES the pack against the
##                artifact it describes, and the third column cites it: delete that guard and this
##                one reds, because an unchecked baseline is indistinguishable from a dark pack.
##                (@cowir-sfx's discriminator, 2026-10-12: a test that merely PARSES a pack is the
##                shape that hides one.)
##   TOOLING    — the runtime has no business reading it and no guard compares it either.
##   UNWIRED    — authored for a consumer that never landed. Expires when the wiring lands.
##   SUPERSEDED — the beat ships elsewhere; wiring it as-is would duplicate a scene.
##
## ⚠️ A KIND THAT CANNOT EXPIRE IS THE DANGEROUS ONE. Nothing is pending for BASELINE or TOOLING, so
## a real runtime gap filed there is hidden permanently — worse than the silence this guard ends.
## @cowir-music caught that here: victory_downbeats.json was first filed with a reason that said only
## "a tool writes it", which is true of a dark pack too.

const DECLARED := {
	"artist_sprite_ledger.json": ["BASELINE",
		"content-pins every tracked artist PNG so a fold or a regen cannot overwrite artist work silently; a runtime reader would be the defect",
		"res://test/unit/test_artist_sprite_ledger_regression.gd"],
	"loudness_baseline.json": ["BASELINE",
		"three summary numbers about the music corpus (median_lufs / n_tracks / outlier_bound_lu); its own guard records that NOTHING invokes tools/audit_loudness.py, which is the larger gap and is out of scope here",
		"res://test/unit/test_the_loudness_baseline_still_describes_the_corpus.gd"],
	"victory_downbeats.json": ["BASELINE",
		"per-bed first-downbeat offsets, compared against the audio to catch a re-trim. Its guard's header also records an intent that never landed — the victory overlay's title slam landing ON the downbeat, and VictoryOverlay._build_slam reads nothing. Recorded so it is not rediscovered as a gap: @cowir-sfx's ruling is that aligning the slam is a feature idea, not an unshipped feature",
		"res://test/unit/test_victory_downbeats_match_the_audio_regression.gd"],
	"examine_texts.json": ["UNWIRED",
		"26 examines / 915 words; 11 key to castle_harmonia, a real map id, and 15 to village_harmonia-style hints that name the MUSIC BEDS, not the maps (harmonia_village). @cowir-overworld's ruling: re-key the pack rather than teach the consumer a second source of truth for map identity",
		""],
	"castle_harmonia_narrative.json": ["UNWIRED",
		"5 castle NPCs (17 lines) + 1 puzzle / 510 words authored 2026-07-13 for the multi-floor W1 climax; nothing dispatches them. @cowir-overworld holds the map",
		""],
	"world2_coordinator_memos.json": ["SUPERSEDED",
		"6 memos / 944 words; 7 of its 8 beats already ship inside the world2_chapter8_memos CUTSCENE in different words, so wiring it as-is duplicates the beat. What is unshipped is its DESIGN: six memos scattered in Maple Heights. A design call, not a wiring task",
		""],
	"lore.json": ["UNWIRED",
		"14 jobs + 6 world phases + 7 villain keys / 1204 words; test_no_retired_spell_name_in_player_data treats its prose as PLAYER data while no src path displays it. Where a player would read job or phase lore is a design question, not a wiring task",
		""],
}


func _data_packs() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open("res://data")
	assert_not_null(d, "CONTROL: res://data must be readable")
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


## Every .gd and .tscn under src/, comment- and docstring-stripped for the .gd half.
func _reach() -> Dictionary:
	var code: PackedStringArray = []
	var raw: PackedStringArray = []
	var files := 0
	var stack: Array[String] = [SRC_DIR]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append("%s/%s" % [dir, sub])
		for f in d.get_files():
			var path: String = "%s/%s" % [dir, f]
			if f.ends_with(".gd"):
				files += 1
				raw.append(FileAccess.get_file_as_string(path))
				code.append(GdSource.code_of(path))
			elif f.ends_with(".tscn"):
				files += 1
				var body: String = FileAccess.get_file_as_string(path)
				raw.append(body)
				code.append(body)
	return {"code": "\n".join(code), "raw": "\n".join(raw), "files": files}


func test_the_reach_corpus_is_real_and_survives_stripping() -> void:
	## Over-stripping and a correct strip are the same green, so a known consumer must survive.
	var r: Dictionary = _reach()
	assert_gt(int(r["files"]), MIN_SOURCE_FILES, "CONTROL: the src walk found only %s files" % r["files"])
	assert_true(str(r["code"]).contains(CONTROL_FILE),
		"CONTROL: %s is loaded by src/ and must survive the strip, or every verdict here is over-stripping" % CONTROL_FILE)
	assert_false(str(r["code"]).contains("Environmental examine texts for props"),
		"CONTROL: the corpus must not include data/ itself, or every pack names itself")


func test_every_data_pack_is_reached_from_src_or_declared() -> void:
	var code: String = str(_reach()["code"])
	var silent: Array[String] = []
	for f in _data_packs():
		if not code.contains(f) and not DECLARED.has(f):
			silent.append(f)
	assert_eq(silent, ([] as Array[String]),
		"a content pack no src path loads is prose the player cannot reach — wire it, or declare it here with its reason: %s" % [silent])


func test_no_declaration_outlives_the_gap_it_describes() -> void:
	## A declaration must expire with the gap. Wire examine_texts.json and this reds until its line
	## goes — which is the only thing that keeps the roster from becoming a list of excuses.
	var code: String = str(_reach()["code"])
	var stale: Array[String] = []
	for f in DECLARED:
		if code.contains(str(f)):
			stale.append(str(f))
	assert_eq(stale, ([] as Array[String]),
		"these packs are loaded by src/ now, so their declarations are excuses for a gap that is closed: %s" % [stale])


func test_every_declaration_names_a_pack_that_exists() -> void:
	var packs: Array[String] = _data_packs()
	var ghosts: Array[String] = []
	for f in DECLARED:
		if not (str(f) in packs):
			ghosts.append(str(f))
	assert_eq(ghosts, ([] as Array[String]), "a declaration for a file that is gone hides nothing: %s" % [ghosts])


func test_no_pack_is_reached_by_prose_alone() -> void:
	## The failure this file would otherwise ship: a pack named only in a comment reads as wired.
	var r: Dictionary = _reach()
	var prose_only: Array[String] = []
	for f in _data_packs():
		if str(r["raw"]).contains(f) and not str(r["code"]).contains(f):
			prose_only.append(f)
	assert_eq(prose_only, ([] as Array[String]),
		"src/ names these packs only in comments or docstrings, so nothing loads them: %s" % [prose_only])


func test_every_baseline_cites_a_guard_that_compares_it() -> void:
	## The excuse expires with the guard that earns it. A baseline nothing checks is not a baseline —
	## it is a dark pack with a better name, and this file would be excusing it.
	var broken: Array[String] = []
	for f in DECLARED:
		if str(DECLARED[f][0]) != "BASELINE":
			continue
		var cite: String = str(DECLARED[f][2])
		if cite == "" or not FileAccess.file_exists(cite):
			broken.append("%s cites %s, which does not exist" % [f, cite if cite != "" else "<nothing>"])
			continue
		if not FileAccess.get_file_as_string(cite).contains(str(f)):
			broken.append("%s cites %s, which never names it" % [f, cite])
	assert_eq(broken, ([] as Array[String]),
		"a BASELINE declaration is earned by a guard that compares the pack against its artifact: %s" % [broken])


func test_only_a_baseline_cites_a_guard() -> void:
	## A citation on an UNWIRED entry would read as "checked", which is the opposite of pending.
	var wrong: Array[String] = []
	for f in DECLARED:
		if str(DECLARED[f][0]) != "BASELINE" and str(DECLARED[f][2]) != "":
			wrong.append(str(f))
	assert_eq(wrong, ([] as Array[String]), "only a BASELINE is earned by a citation: %s" % [wrong])


func test_the_pending_packs_stay_named() -> void:
	## Not a count: the roster names each one with its size. An authored pack that reaches no player
	## is a defect with a measurement, and this message is where it lives so it is not rediscovered.
	var pending_packs: Array[String] = []
	var kinds: Array[String] = []
	for f in DECLARED:
		var kind: String = str(DECLARED[f][0])
		if not (kind in kinds):
			kinds.append(kind)
		if kind in ["UNWIRED", "SUPERSEDED"]:
			pending_packs.append("%s [%s] — %s" % [f, kind, DECLARED[f][1]])
	for kind in kinds:
		assert_true(kind in ["BASELINE", "TOOLING", "UNWIRED", "SUPERSEDED"],
			"undeclared kind %s: this arm would not report it, so it would go quiet" % kind)
	assert_gt(pending_packs.size(), 0, "CONTROL: this arm reports the pending packs; an empty roster means they are all wired")
	for entry in pending_packs:
		gut.p("PENDING: %s" % entry)
