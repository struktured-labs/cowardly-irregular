extends GutTest

## Regression: cadence #4 scout 2026-07-16 — 8 cutscenes referenced 7
## backdrop ids that didn't exist on disk (castle_harmonia_throne, fire/ice/
## lightning/shadow_cave, suburban_community_center, suburban_strip_mall).
## _try_load_backdrop_image returned false and the scenes fell through to
## _apply_world_gradient — a flat two-color gradient with no atmospheric
## content. The 4 dragon-cave intros + Mordaine throne approach are W1
## boss content in tonight's playtest window.
##
## Ratchet: every `background` id referenced by an overlay cutscene must
## resolve to either an OGV video backdrop (assets/cutscene_videos/) or a
## PNG image backdrop (assets/cutscene_backdrops/). Staged scenes
## (presentation:"staged") don't render a backdrop and are skipped.

const OGV_DIR := "res://assets/cutscene_videos"
const PNG_DIR := "res://assets/cutscene_backdrops"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _cutscene_files() -> Array:
	var out: Array = []
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append("res://data/cutscenes/%s" % f)
	assert_gt(out.size(), 100, "sanity: many cutscene JSON files expected")
	return out


func _backdrop_resolves(bg: String) -> bool:
	return ResourceLoader.exists("%s/%s.ogv" % [OGV_DIR, bg]) or ResourceLoader.exists("%s/%s.png" % [PNG_DIR, bg])


func test_castle_harmonia_throne_repointed_to_existing_asset() -> void:
	# Direct pin for the highest-priority fix: Mordaine's throne room
	# approach was silently rendering a world-gradient instead of the
	# throne room asset.
	var path := "res://data/cutscenes/world1_throne_room_approach.json"
	assert_true(FileAccess.file_exists(path), "world1_throne_room_approach.json must exist")
	var parsed = JSON.parse_string(_read(path))
	assert_true(parsed is Dictionary, "throne_room_approach must parse")
	assert_eq(str(parsed.get("background", "")), "throne_room",
		"world1_throne_room_approach must use the throne_room backdrop, not a made-up variant that falls back to the world gradient (was 'castle_harmonia_throne', pre-fix)")


func test_every_overlay_cutscene_backdrop_resolves() -> void:
	# Overlay cutscenes without a resolvable backdrop fall through to
	# _apply_world_gradient — a flat two-color gradient. That's a valid
	# design fallback but should NEVER be silently reached because of a
	# typo'd or drifted backdrop id. Staged scenes don't load a backdrop.
	var offenders: Dictionary = {}
	for path in _cutscene_files():
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		if str(parsed.get("presentation", "")) == "staged":
			continue
		var bg := str(parsed.get("background", "")).strip_edges()
		if bg == "":
			continue
		if _backdrop_resolves(bg):
			continue
		if not offenders.has(bg):
			offenders[bg] = []
		if offenders[bg].size() < 3:
			offenders[bg].append(path.get_file())
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for bg in offenders:
		reports.append("'%s' (e.g. in %s)" % [bg, ", ".join(offenders[bg])])
	assert_true(false,
		"cutscene JSON references backdrops with no OGV or PNG on disk (silent world-gradient fallback):\n  %s" % "\n  ".join(reports))


## ── THE OTHER DIRECTION, added 2026-09-12 ──────────────────────────────────
##
## THE ARM ABOVE QUANTIFIES OVER BACKGROUNDS. IT CANNOT SEE A SHIPPED VIDEO NOBODY NAMES.
##
## `_try_load_backdrop_image` composes `res://assets/cutscene_videos/<background>.ogv` — a
## COMPOSED path, so no video's filename appears in any source file and a literal scan reports
## every one of them as unreferenced. The forward ratchet asks "does this background resolve?"
## and is structurally blind to the reverse, which is the expensive half: **an .ogv that no
## cutscene names still ships in the web pck.**
##
## Measured on b621a0e0 (.330): 20 videos, 20 PNGs, 18 distinct backgrounds. Two videos are
## named by nothing — `brasston_square` (1,186,757 B) and `maple_heights_street` (923,681 B),
## **2,110,438 B = 2.01 MiB of a 6.89 MiB web-cache overage**, shipped for scenes that do not
## exist. Both keep their PNG twin, so authoring a cutscene on either background later still
## renders; it renders still instead of moving.
##
## 🔑 WHY IT SURVIVED: the pair is invisible from both ends. From source, the composed path
## hides it. From the forward guard, the quantifier hides it. Deleting them is @struktured's
## call — they were generated deliberately (`tools/gen_cutscene_video.py` carries a prompt for
## each) and 2.01 MiB does not on its own clear the cache line. This file's job is that the
## number stops being invisible, not that anyone acts on it.
##
## ⚠️ WHAT THIS DOES NOT CLAIM. "Named by a cutscene" is not "a player sees it" — the scene
## carrying it may itself be undispatched. That is a different corpus and a different guard.

## video id -> why it ships unnamed. Each line is a claim about the CORPUS, so it must be false
## before the line can be deleted.
##   grows   -> a video shipped for a scene nobody wrote
##   shrinks -> someone authored the scene, or deleted the file. Delete the line either way.
const UNNAMED_BACKDROP_VIDEOS := {
	"brasston_square": "1,186,757 B — W3 town square; PNG twin ships too",
	"maple_heights_street": "923,681 B — W2 autumn street; PNG twin ships too",
}


func _video_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open(OGV_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".ogv"):
			out.append(f.trim_suffix(".ogv"))
	out.sort()
	return out


## Every background any cutscene names, staged included: a staged scene renders no backdrop,
## but a video it names is authored-for, not orphaned, and deleting it would be a content loss.
func _named_backgrounds() -> Dictionary:
	var out: Dictionary = {}
	for path in _cutscene_files():
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		var bg := str(parsed.get("background", "")).strip_edges()
		if bg != "":
			out[bg] = int(out.get(bg, 0)) + 1
	return out


## PREMISE. Both corpora real, and the reader answers BOTH ways — a walk that finds no videos
## reports zero orphans, and a walk that finds no backgrounds reports every video as one.
func test_premise_the_reverse_reader_answers_both_ways() -> void:
	var vids := _video_ids()
	var named := _named_backgrounds()
	assert_gt(vids.size(), 15,
		"only %d .ogv found — the video walk is short, and a short walk reports zero orphans no matter what ships" % vids.size())
	assert_gt(named.size(), 12,
		"only %d distinct backgrounds parsed — a short read makes EVERY video look orphaned and inverts this arm" % named.size())
	# NAMED members, not counts: a sweep that resolved nothing also reports zero missing.
	assert_true(named.has("prologue_forest"),
		"CONTROL: prologue_forest is named by ~25 cutscenes; if it reads unnamed the background walk is broken and every verdict below is noise")
	assert_true(vids.has("prologue_forest"),
		"CONTROL: prologue_forest.ogv must be found by the video walk, or the walk is not reading the asset dir")
	assert_false(named.has("zzz_no_such_backdrop"),
		"CONTROL: a fabricated background must read as unnamed, or the check cannot return a positive")


## THE RATCHET. A video nobody names is web-pck weight for a scene that does not exist.
func test_every_shipped_backdrop_video_is_named_by_a_cutscene() -> void:
	var named := _named_backgrounds()
	var orphans: Array[String] = []
	for vid in _video_ids():
		if not named.has(vid) and not UNNAMED_BACKDROP_VIDEOS.has(vid):
			orphans.append(vid)
	orphans.sort()
	assert_eq(orphans.size(), 0,
		"a backdrop video ships that no cutscene names — it costs web-pck bytes for a scene nobody wrote: %s. Author the scene, or add it to UNNAMED_BACKDROP_VIDEOS with its byte cost so the weight stays visible." % ", ".join(orphans))


## THE STALE-LIST DUAL. The ratchet only compares videos that still SHIP, so an entry whose file
## was deleted leaves an inert suppression behind — a debt line created by deletion rather than
## by being written wrong. Reds in the good direction too: someone authored the scene.
func test_the_unnamed_list_still_describes_the_corpus() -> void:
	var named := _named_backgrounds()
	var vids := _video_ids()
	var now_named: Array[String] = []
	var gone: Array[String] = []
	for k in UNNAMED_BACKDROP_VIDEOS.keys():
		var vid := str(k)
		if not vids.has(vid):
			gone.append(vid)
		elif named.has(vid):
			now_named.append(vid)
	now_named.sort()
	gone.sort()
	assert_eq(now_named.size(), 0,
		"GOOD NEWS, STALE LIST: %s is now named by a cutscene, so it is content rather than weight. Delete the line(s) from UNNAMED_BACKDROP_VIDEOS." % ", ".join(now_named))
	assert_eq(gone.size(), 0,
		"UNNAMED_BACKDROP_VIDEOS names a video that no longer ships: %s — the entry is describing a corpus that has moved on. Delete the line." % ", ".join(gone))
