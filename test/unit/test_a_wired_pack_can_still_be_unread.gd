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
## ✅ UPDATED .668: @cowir-overworld's village path landed and 13 scenes left this roster — the expiry
## arm RED and named them, which is the contract working rather than a surprise. 24 of 26 entries are
## placed now; the two left are not villages and need a dungeon-shaped literal filter instead.
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
## Empty since .670: cowir-overworld placed the last two (assembly_core, abstract_overworld). A new unread scene goes here WITH its blocker.
const UNPLACED_SCENES := {}


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


## ⚠️ ALL THREE DERIVATIONS BELOW ARE CACHED, AND THE REASON IS A HANG, NOT TIDINESS.
## `_extends_reaches` needs the class index, `_accessor_scene_ids_under` calls it once per map
## script, and several arms re-derive `_placed_scenes()` — uncached that is 42 x 42 `code_of`
## strips per arm, each a char-by-char quote-aware pass over files up to 1,500 lines. A test that
## slow reads as infrastructure rather than as a red, which is the failure this repo keeps paying
## for. Cached, every file is stripped once.
var _map_scripts_cache: Array[String] = []
var _class_index_cache: Dictionary = {}
var _accessor_cache: Dictionary = {}


func _map_scripts() -> Array[String]:
	if not _map_scripts_cache.is_empty():
		return _map_scripts_cache
	var out: Array[String] = []
	var stack: Array[String] = ["res://src/maps"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append("%s/%s" % [dir, sub])
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append("%s/%s" % [dir, f])
	_map_scripts_cache = out
	return out


func _class_name_of(path: String) -> String:
	var rx := RegEx.create_from_string('(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)')
	var m := rx.search(GdSource.code_of(path))
	return m.get_string(1) if m != null else ""


func _extends_of(path: String) -> String:
	var rx := RegEx.create_from_string('(?m)^extends\\s+([A-Za-z_][A-Za-z0-9_]*)')
	var m := rx.search(GdSource.code_of(path))
	return m.get_string(1) if m != null else ""


## class_name -> defining path, for the chain walk. Scoped to src/maps: a loader whose subclasses
## live elsewhere would be UNDER-credited and red this file, which is the safe direction — a human
## reads it rather than a scene silently reading as placed.
func _class_index() -> Dictionary:
	if not _class_index_cache.is_empty():
		return _class_index_cache
	var by_class: Dictionary = {}
	for path in _map_scripts():
		var cn: String = _class_name_of(path)
		if cn != "":
			by_class[cn] = path
	_class_index_cache = by_class
	return by_class


## Bounded chain walk — a cycle in a hand-written `extends` would otherwise spin, and a hung test
## reads as infrastructure rather than as a red.
func _extends_reaches(path: String, base_class: String) -> bool:
	if _class_name_of(path) == base_class:
		return true
	var by_class: Dictionary = _class_index()
	var seen: Array[String] = []
	var cur: String = _extends_of(path)
	var hops: int = 0
	while cur != "" and hops < 8:
		if cur == base_class:
			return true
		if seen.has(cur):
			break
		seen.append(cur)
		if not by_class.has(cur):
			break
		cur = _extends_of(str(by_class[cur]))
		hops += 1
	return false


## Every scene id an override of `_get_area_id()` returns IN THE LOADER'S OWN SUBCLASS TREE.
##
## ⛔ THIS USED TO SCAN ALL OF src/maps, WHICH CREDITED 28 SCENES NO LOADER CAN REACH. Measured
## 2026-10-13: `BaseVillage` is the only pack loader that selects by accessor (the castle,
## AssemblyCore and AbstractOverworld all name their scene as a literal, 0 `_get_area_id()` calls
## between them), and its legitimate reach is its own 14 subclasses. The old derivation handed it
## every `_get_area_id()` override in the tree — including all 27 interiors — so an examine keyed
## to `harmonia_chapel` would have read as PLACED while nothing loaded the pack for any interior.
## That is precisely the dark-content case this file exists to catch, in the one surface about to
## be authored for. A loader places its OWN subclasses and nobody else's.
func _accessor_scene_ids_under(base_class: String) -> Array[String]:
	var out: Array[String] = []
	if base_class == "":
		return out
	if _accessor_cache.has(base_class):
		return _accessor_cache[base_class]
	var rx := RegEx.create_from_string('func _get_area_id\\(\\)[^"]*return "([a-z0-9_]+)"')
	for path in _map_scripts():
		if not _extends_reaches(path, base_class):
			continue
		for m in rx.search_all(GdSource.code_of(path)):
			var id: String = m.get_string(1)
			if not out.has(id):
				out.append(id)
	_accessor_cache[base_class] = out
	return out


## TWO placement mechanisms, both derived, because a literal scan cannot follow an accessor:
##   the castle names its scene as a LITERAL in the file that loads the pack
##   a village loader filters `scene == _get_area_id()`, and each subclass supplies the id
## Measured 2026-10-12 before the village path folded: a literal-only scan left 13 placed scenes
## reading as UNPLACED and every arm in this file PASSING — a declaration outliving its gap in
## silence. Widening the scan from one file to all of them did NOT fix it; the mechanism did.
func _placed_scenes() -> Array[String]:
	var out: Array[String] = []
	var srcs: Array[String] = _placement_sources()
	assert_gt(srcs.size(), 0, "CONTROL: some src path must load the pack in CODE, not prose")
	for path in srcs:
		var code: String = GdSource.code_of(path)
		var selects_by_accessor: bool = code.contains("_get_area_id()")
		## A loader's accessor reach is ITS OWN subclass tree, keyed on its own class_name.
		var reach: Array[String] = _accessor_scene_ids_under(_class_name_of(path)) if selects_by_accessor else ([] as Array[String])
		for scene in _scenes():
			if out.has(scene):
				continue
			if code.contains('"%s"' % scene):
				out.append(scene)
			elif selects_by_accessor and reach.has(scene):
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


func test_the_prose_that_reaches_a_player_is_still_there() -> void:
	## This arm was built to report what is UNREAD, and as of .670 nothing is: @cowir-overworld placed
	## the last two scenes and @cowir-main emptied the roster on the fold. So it needed a new subject,
	## and the stopgap control it was given cannot fail.
	##
	## ⛔ `assert_eq(n == 0, UNPLACED_SCENES.is_empty())` IS TAUTOLOGICAL GIVEN THE ARM ABOVE IT.
	## `n` counts entries whose scene is rostered, and test_every_declared_scene_is_one_the_pack_uses
	## forbids a rostered scene with no entry — so a non-empty roster forces n > 0 and an empty one
	## forces n = 0. The two sides cannot disagree while that sibling passes. It was the right
	## stopgap for a fold (the old `assert_gt(n, 0)` was FALSE the moment the pack was fully read, and
	## had to change in that commit); it is not a claim worth keeping.
	##
	## ✅ THE SUBJECT THIS FILE ACTUALLY HAS LEFT: the prose reaches a player, so the thing to guard
	## is that there is still prose. Arm 1 derives that every entry is PLACED; nothing asserted the
	## entries still carry their text. An entry placed with an empty string is a ReadableProp that
	## opens on nothing — and BaseVillage only warns about it, which is a line in a log that is
	## already 9% warning. Measured 2026-10-13 BY THIS ARM (GDScript split, not my shell): 29 entries, 1,045 words, shortest 24.
	var words := 0
	var thin: Array[String] = []
	for key in _entries():
		var text: String = str((_entries()[key] as Dictionary).get("text", ""))
		var n: int = text.split(" ", false).size()
		words += n
		if n < 10:
			thin.append("%s (%d words)" % [key, n])
	assert_eq(thin, ([] as Array[String]),
		"an examine placed with almost no text opens a panel on nothing, and the engine only warns: %s" % [thin])
	assert_gt(words, 800,
		"the pack carried 1,045 words of placed prose; only %d survive, so this file's subject is being deleted out from under it" % words)
	gut.p("PLACED PROSE: %d examines, %d words, %d scene(s) still unread" % [_entries().size(), words, UNPLACED_SCENES.size()])


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
		if not names_a_scene and not code.contains("_get_area_id()"):
			opaque.append(path)
	assert_eq(opaque, ([] as Array[String]),
		"these files load the pack by a THIRD mechanism — neither a scene literal nor _get_area_id() — so UNPLACED_SCENES can no longer be derived and must be re-read by hand in this change: %s" % [opaque])
