extends GutTest

## ⛔ A PACK WITH A CONSUMER IS NOT A PACK THAT IS READ. `test_every_data_pack_has_a_consumer` asks
## whether any `src/` path loads a file, and on 2026-10-12 `examine_texts.json` gained one — the
## castle's `_load_examine_pack` — so its UNWIRED declaration expired and left the roster, correctly
## by that guard's own contract. MEASURED the same hour: the castle filters `scene ==
## "castle_harmonia"`, so it places **11 of 26** entries and **15 reach nobody**. The pack now reads
## as wired while 58% of its prose is as unreachable as it was in April.
##
## 🔑 THE UNIT WAS THE DEFECT, which is the shape that cost me five false alarms today in the other
## direction: that guard's unit is the FILE and the gap is per-ENTRY. A file-level census cannot see a
## partially-consumed pack, and nothing else was watching. This is the finer unit, and it is a
## DIFFERENT guard rather than a widening, because the file-level question is still worth asking.
##
## 📌 It shrinks as placement lands: @cowir-overworld is taking the 13 village scenes through ONE
## path (`BaseVillage._get_area_id()`, 11 of 11 matching by place after the re-key). Each entry that
## gains a placement must leave UNPLACED_SCENES or this reds — the same expiry contract the
## file-level roster uses, so an excuse cannot outlive the gap it describes.

const PACK := "res://data/examine_texts.json"
const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const MIN_ENTRIES := 20

## A scene whose entries no placement path reads yet. Value is the BLOCKER, never just the world.
const UNPLACED_SCENES := {
	"harmonia_village": "13 village scenes await ONE BaseVillage path on _get_area_id() — @cowir-overworld",
	"eldertree_village": "as harmonia_village",
	"frosthold_village": "as harmonia_village",
	"grimhollow_village": "as harmonia_village",
	"ironhaven_village": "as harmonia_village",
	"maple_heights_village": "as harmonia_village",
	"node_prime_village": "as harmonia_village",
	"rivet_row_village": "as harmonia_village",
	"sandrift_village": "as harmonia_village",
	"brasston_village": "as harmonia_village",
	"vertex_village": "as harmonia_village",
	"abstract_overworld": "NOT a village: an overworld, so _get_area_id() does not serve it. Also one of cowir-story's four inferred re-keys (was overworld_vertex, a footprint in white sand, world 6)",
	"assembly_core": "NOT a village: the W4 dungeon, inferred from the entry's own world number (was dungeon_pipeline, a pressure gauge). Needs its own accessor check before placement",
}


func _entries() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse" % PACK)
	return (parsed as Dictionary).get("examines", {})


## The scenes some src path actually reads entries FOR — derived from EVERY file that loads the pack,
## never from one.
##
## ⛔ THIS SCANNED ONLY THE CASTLE AND THAT WAS A SILENT HOLE, found by asking what happens when
## @cowir-overworld's village placement folds. Their path lives in `BaseVillage`, which a
## castle-only scan never reads — so the 13 village scenes would have stayed "UNPLACED" in the
## roster while being placed in fact, and `test_no_declaration_outlives_its_placement` would have
## PASSED. A declaration outliving its gap, silently, which is the one thing that arm exists to stop.
## The derivation's corpus was one file; the subject was the whole placement surface.
func _placement_sources() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append("%s/%s" % [dir, sub])
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = "%s/%s" % [dir, f]
			if GdSource.code_of(path).contains("examine_texts.json"):
				out.append(path)
	return out


func _placed_scenes() -> Array[String]:
	var out: Array[String] = []
	var srcs: Array[String] = _placement_sources()
	assert_gt(srcs.size(), 0, "CONTROL: some src path must load the pack in CODE, not prose")
	for path in srcs:
		var code: String = GdSource.code_of(path)
		for scene in _scenes():
			if code.contains('"%s"' % scene) and not out.has(scene):
				out.append(scene)
	return out


func _scenes() -> Array[String]:
	var out: Array[String] = []
	for key in _entries():
		var scene: String = str((_entries()[key] as Dictionary).get("scene", ""))
		if scene != "" and not out.has(scene):
			out.append(scene)
	return out


func test_the_corpora_are_real() -> void:
	assert_gt(_entries().size(), MIN_ENTRIES, "CONTROL: only %d examines read" % _entries().size())
	assert_gt(_scenes().size(), 5, "CONTROL: only %d distinct scenes read" % _scenes().size())
	## ⛔ A CONTENT FLOOR, NOT A COUNT. @cowir-sfx's ranking, measured the same hour: a non-empty floor
	## is faked by 1 of 8 rows and a magnitude floor by a coincidentally-sized wrong range (their first
	## version derived 14 Color() components and sailed through `size() > 5`). Naming the scene the
	## castle demonstrably places cannot be faked by a wrong range — only by the right one.
	assert_true(_placed_scenes().has("castle_harmonia"),
		"CONTROL: the castle places its own 11 entries, so this scene must read as placed; without it every verdict below is vacuous, got %s" % [_placed_scenes()])


func test_every_examine_is_placed_or_declared() -> void:
	var orphaned: Array[String] = []
	var placed: Array[String] = _placed_scenes()
	for key in _entries():
		var scene: String = str((_entries()[key] as Dictionary).get("scene", ""))
		if not placed.has(scene) and not UNPLACED_SCENES.has(scene):
			orphaned.append("%s (scene %s)" % [key, scene])
	assert_eq(orphaned, ([] as Array[String]),
		"these examines are in a pack that HAS a consumer and are still read by nothing — the file-level census cannot see them: %s" % [orphaned])


func test_no_declaration_outlives_its_placement() -> void:
	## The expiry. When a village path lands, its scene leaves this roster or the guard reds — so the
	## list shrinks with the work instead of becoming the record of a gap nobody closed.
	var stale: Array[String] = []
	for scene in UNPLACED_SCENES:
		if _placed_scenes().has(str(scene)):
			stale.append(str(scene))
	assert_eq(stale, ([] as Array[String]),
		"these scenes are placed now, so their entries here are excuses for a gap that is closed: %s" % [stale])


func test_every_declared_scene_is_one_the_pack_uses() -> void:
	var ghosts: Array[String] = []
	for scene in UNPLACED_SCENES:
		if not _scenes().has(str(scene)):
			ghosts.append(str(scene))
	assert_eq(ghosts, ([] as Array[String]), "no examine names these scenes any more: %s" % [ghosts])


func test_the_unread_prose_stays_counted() -> void:
	## Not a pin on a number: the roster names the scenes, and this reports what is still unread so
	## the cost is visible in the output rather than inferred from a list's length.
	var words := 0
	var n := 0
	for key in _entries():
		var e: Dictionary = _entries()[key]
		if UNPLACED_SCENES.has(str(e.get("scene", ""))):
			n += 1
			words += str(e.get("text", "")).split(" ", false).size()
	assert_gt(n, 0, "CONTROL: this arm reports the unread entries; an empty roster means they are all placed")
	gut.p("UNREAD: %d of %d examines, %d words, across %d scenes" % [n, _entries().size(), words, UNPLACED_SCENES.size()])


## ⛔ AND WHEN THE DERIVATION CANNOT SEE A PLACEMENT MECHANISM, IT MUST SAY SO LOUDLY RATHER THAN
## REPORT A ROSTER IT CAN NO LONGER TRUST. Measured by simulating @cowir-overworld's village
## placement before it folds: their path lives in `BaseVillage`, which loads the pack but names NO
## scene — each subclass supplies its id through `_get_area_id()`. So a derivation that asks "does a
## pack-loading file contain this scene's literal" sees nothing, the 13 village scenes stay
## "UNPLACED" in the roster while being placed in fact, and every arm above PASSES. I widened the
## scan from one file to all of them and the simulation still passed, because the hole is not the
## file count — it is that a literal scan cannot follow an ACCESSOR.
##
## 🔑 So this arm watches for the mechanism rather than for the scenes: a pack-loading file that
## resolves its scene through an accessor means the roster is no longer derivable here and needs a
## human. It reds in the SAME fold that lands the placement, which is the only moment the roster can
## be corrected honestly.
func test_no_placement_path_resolves_its_scene_by_an_accessor() -> void:
	var opaque: Array[String] = []
	for path in _placement_sources():
		var code: String = GdSource.code_of(path)
		var names_a_scene := false
		for scene in _scenes():
			if code.contains('"%s"' % scene):
				names_a_scene = true
				break
		if not names_a_scene and (code.contains("_get_area_id()") or code.contains("get_area_id(")):
			opaque.append(path)
	assert_eq(opaque, ([] as Array[String]),
		"these files load the pack but resolve the scene through an accessor, so UNPLACED_SCENES above can no longer be derived and must be re-read by hand in this change: %s" % [opaque])
