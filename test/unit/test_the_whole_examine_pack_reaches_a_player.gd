extends GutTest

## `data/examine_texts.json` was authored on **2026-04-21** and read by NOBODY for six months. This
## release finished it: the castle took 11, the villages 13, and these last two live in neither —
## `pipeline_gauge` in the Assembly Core (a `DragonCave`, floor 2's inspection checkpoint) and
## `vertex_footprint` on the W6 abstract overworld.
##
## 🔑 THE CLAIM THIS FILE EXISTS FOR IS THE WHOLE-PACK ONE, which no per-scene guard can make:
## **every authored entry reaches some player, in some scene.** The three per-scene guards each
## assert their own slice and would all stay green with a scene missing — a 27th entry keyed to a
## scene nobody wired is invisible to every one of them. This arm is the only place that notices.
##
## ⚠️ DERIVED, NOT COUNTED. An earlier version of my village guard pinned `assert_eq(total, 13)`;
## @cowir-story authored three more entries within hours and it red on correct content — the
## coincidental-value ratchet this repo warns about, in a guard I wrote with the derived form three
## lines away. So nothing here is compared against a literal: the pack's own rows are one side and
## the wired scenes are the other, and new content moves both together.

const PACK := "res://data/examine_texts.json"

## Where each scene key is consumed, and by what. A scene added to the pack with no consumer here
## fails the arm below rather than passing quietly — that is the whole point of the file.
const WIRED := {
	"castle_harmonia": "res://src/maps/dungeons/CastleHarmonia.gd",
	"assembly_core": "res://src/maps/dungeons/AssemblyCore.gd",
	"abstract_overworld": "res://src/exploration/AbstractOverworld.gd",
	"_villages": "res://src/maps/villages/BaseVillage.gd",
	"_interiors": "res://src/maps/interiors/BaseInterior.gd",
}


func _pack() -> Dictionary:
	var raw := FileAccess.get_file_as_string(PACK)
	assert_ne(raw, "", "CONTROL: the authored pack must be readable or every arm here is vacuous")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse")
	var all: Dictionary = (parsed as Dictionary).get("examines", {}) if parsed is Dictionary else {}
	assert_gt(all.size(), 0, "CONTROL: the pack must carry entries")
	return all


func _scene_keys() -> Dictionary:
	var out: Dictionary = {}
	for k in _pack().keys():
		var e = _pack()[k]
		if not (e is Dictionary):
			continue
		var scene: String = str((e as Dictionary).get("scene", ""))
		if not out.has(scene):
			out[scene] = []
		(out[scene] as Array).append(str(k))
	return out


## ⛔ THIS REPLACED `scene.ends_with("_village")`, AND THE SUFFIX WAS WRONG IN BOTH DIRECTIONS.
## It missed every base-placed id that is not spelled `*_village` — `maple_heights_strip_mall` and
## `scriptura_plaza` are both BaseVillage subclasses and neither matches, so a pack row for either
## would have read as an orphan on correct content. And it would have accepted any NEW scene merely
## spelled `*_village` with no placer at all. A suffix is a guess about a name; this asks the code.
##
## 🔑 Derived per BASE PLACER: for each `_`-prefixed WIRED entry, the ids that `_get_area_id()`
## overrides declare in that placer's own directory. Villages live beside BaseVillage, interiors
## beside BaseInterior. A subclass filed somewhere else is NOT counted, so it reds here and a human
## reads it — the safe direction, since the alternative is a scene silently reading as reached.
##
## ⚠️ Deliberately duplicated from `test_a_wired_pack_can_still_be_unread`'s accessor derivation
## rather than shared: that file resolves the `extends` chain, this one scopes by directory, and the
## two guards answer OPPOSITE questions about the same pack — that one asks whether a scene is
## placed and used to OVER-credit; this one asks whether it is reached and used to UNDER-credit.
## A third consumer moves a common form into test/unit/helpers/.
func _base_placed_scenes() -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string('func _get_area_id\\(\\)[^"]*return "([a-z0-9_]+)"')
	for key in WIRED.keys():
		if not str(key).begins_with("_"):
			continue
		var dir: String = str(WIRED[key]).get_base_dir()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var code: String = str(GdSource.split(FileAccess.get_file_as_string("%s/%s" % [dir, f]))["code"])
			for m in rx.search_all(code):
				var id: String = m.get_string(1)
				if not out.has(id):
					out.append(id)
	return out


## ⛔ THE ARM THE OTHER THREE GUARDS CANNOT MAKE: every scene the pack names must have a consumer.
## A village scene counts through BaseVillage, which serves all eleven from one placer.
func test_every_scene_the_pack_names_has_a_consumer() -> void:
	var by_scene := _scene_keys()
	var orphans: Array = []
	for scene in by_scene.keys():
		if WIRED.has(scene):
			continue
		## A key served by a BASE-CLASS placer rather than a per-scene file.
		if _base_placed_scenes().has(scene):
			continue
		orphans.append("%s (%d entr%s)" % [scene, (by_scene[scene] as Array).size(),
			"y" if (by_scene[scene] as Array).size() == 1 else "ies"])
	orphans.sort()
	assert_eq(orphans, [],
		"these pack scenes reach NO player — authored text with no consumer, which is the state this pack was in for six months: %s" % ", ".join(orphans))


## And each named consumer must actually read the pack, not merely exist. A file that stopped
## loading it would leave its scene's entries dark while this guard's table still looked complete.
func test_every_named_consumer_reads_the_pack() -> void:
	var silent: Array = []
	for scene in WIRED.keys():
		var path: String = WIRED[scene]
		var raw := FileAccess.get_file_as_string(path)
		if raw == "":
			silent.append("%s (unreadable)" % path)
			continue
		var code: String = str(GdSource.split(raw)["code"])
		## The strip's own two directions, because over-stripping and a correct strip are the same
		## green: a known code site must survive, and no comment may reach the code half.
		assert_true(code.contains("func "), "CONTROL: the strip kept no code from %s" % path)
		assert_false(code.contains("##"), "CONTROL: a comment survived into %s's code half" % path)
		if not code.contains("examine_texts.json"):
			silent.append("%s does not name the pack" % path)
	silent.sort()
	assert_eq(silent, [], "these consumers no longer read the pack: %s" % ", ".join(silent))


## The two new scenes build their readable with the authored text. The per-scene guards cover the
## castle and the villages; nothing covered these.
func test_the_assembly_core_builds_its_gauge() -> void:
	var gs := get_node_or_null("/root/GameState")
	var saved_floor = null
	var had := false
	if gs != null:
		had = gs.game_constants.has("assembly_core_floor")
		saved_floor = gs.game_constants.get("assembly_core_floor", null)
		gs.game_constants["assembly_core_floor"] = 2

	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var core = load("res://src/maps/dungeons/AssemblyCore.gd").new()
	vp.add_child(core)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(int(core.current_floor), 2,
		"CONTROL: floor 2 was asked for and the core built %d, so this arm would measure the wrong floor" % int(core.current_floor))
	var found: ReadableProp = null
	var stack: Array = [core]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is ReadableProp and str(n.name) == "Examine_pipeline_gauge":
			found = n
			break
	assert_not_null(found, "the Assembly Core must place its authored gauge on floor 2")
	if found != null:
		var want: String = str((_pack()["pipeline_gauge"] as Dictionary).get("text", ""))
		found.interact(null)
		assert_true(found.is_open(), "pressing the gauge opened nothing")
		assert_eq(found._entry_at(0)["body"], want, "the gauge must show its AUTHORED text")
		found._close_panel()

	if gs != null:
		if had:
			gs.game_constants["assembly_core_floor"] = saved_floor
		else:
			gs.game_constants.erase("assembly_core_floor")


func test_the_abstract_overworld_builds_its_footprint() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var world = load("res://src/exploration/AbstractOverworld.gd").new()
	vp.add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var found: ReadableProp = null
	for n in world.npcs.get_children():
		if n is ReadableProp and str(n.name) == "Examine_vertex_footprint":
			found = n
			break
	assert_not_null(found, "W6 must place its authored footprint")
	if found == null:
		return
	## Cell-CENTRED: W6 is flat, so a readable is pressable only by standing on it, and a 28px prop
	## on a cell corner sits 24px off every axis-aligned probe.
	var step: float = float(world.MAP_SCALE * world.TILE_SIZE)
	var cell := Vector2i(found.position / step)
	var centre := Vector2(cell.x * step + step / 2.0, cell.y * step + step / 2.0)
	assert_almost_eq(found.position, centre, Vector2.ONE,
		"the footprint is not cell-centred, so it draws and cannot be pressed")
	var want: String = str((_pack()["vertex_footprint"] as Dictionary).get("text", ""))
	found.interact(null)
	assert_true(found.is_open(), "pressing the footprint opened nothing")
	assert_eq(found._entry_at(0)["body"], want, "the footprint must show its AUTHORED text")
	found._close_panel()
