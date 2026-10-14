extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## ⛔ SUPERSEDES `test_an_examine_fits_the_panel_that_shows_it`, WHICH I SHIPPED IN `.682` AND WHICH
## COVERS LESS THAN ITS NAME. That file reads `data/examine_texts.json`. `ReadableProp` is built at
## 12 sites in 10 files, and the pack is only two of them (`BaseVillage`, `BaseInterior`) — the six
## overworlds, `AssemblyCore` and `CastleHarmonia` build their pages IN CODE, and those carry the
## multi-paragraph bodies. A lore page could overflow and that guard would stay green: the
## `test_<your_defect>` shape, in my own file, written hours after I quoted the rule at another lane.
##
## 🔑 SO THIS DRIVES THE REAL PROVIDERS INSTEAD OF ANY DATA FILE. Every scene that can hold a
## ReadableProp is built, every prop found, and its OWN `_provider` Callable invoked through the
## accessors the renderer uses — `_fetch_entries()` then `_entry_at(i)`. That covers the JSON pack
## and every in-code page automatically and forever, with nothing to keep in step. My first probe
## scraped the in-code pages with a RegEx; that is the wrong instrument and it is not in here.
##
## ⛔ WHAT OVERFLOW COSTS, PER AXIS, BECAUSE THEY FAIL DIFFERENTLY:
##   body    autowraps at `body_box()`, so excess height is DRAWN NOWHERE. A one-entry provider
##           shows no page arrows (`_render_page`), so the tail is unreachable, not merely scrolled.
##   heading does NOT autowrap, so excess width draws PAST the panel over whatever is behind it.
##
## ⚠️ NO TOLERANCE ON EITHER AXIS: both compare a rendered extent against a box boundary, so the
## neighbourhood is empty (@cowir-controller's form of @cowir-sfx's question). Geometry is read from
## the class — `body_box()`, `BODY_FONT` — never copied.

const VILLAGE_DIR := "res://src/maps/villages/"
const INTERIOR_DIR := "res://src/maps/interiors/"
const OVERWORLDS := [
	"res://src/exploration/OverworldScene.gd", "res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd", "res://src/exploration/IndustrialOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd", "res://src/exploration/AbstractOverworld.gd",
]
## The two dungeons that build pages in code, with the floors that carry them.
const DUNGEONS := [
	{"path": "res://src/maps/dungeons/CastleHarmonia.gd", "floors": [1, 2, 3, 4]},
	{"path": "res://src/maps/dungeons/AssemblyCore.gd", "floors": [1, 2, 3]},
]
const NOT_A_ROOM := ["BaseInterior.gd", "InteriorPlacementSweep.gd"]

## Heading font is a literal in `_build_panel` beside the body's named one; read the box from the
## class and keep this one figure here, named, so a drift is visible rather than silent.
const HEADING_FONT: int = 13
const HEADING_H: float = 22.0

var _vp: SubViewport = null
var _host: Control = null


func before_all() -> void:
	_host = Control.new()
	_host.size = Vector2(900, 700)
	add_child_autofree(_host)


func _build(path: String, floor_n: int = 0) -> Node2D:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.set_story_flag("world1_mordaine_defeated", true)
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var n = scr.new()
	if floor_n > 0 and "current_floor" in n:
		n.current_floor = floor_n
	_vp.add_child(n)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return n


func _teardown(n: Node2D) -> void:
	n.queue_free()
	await get_tree().process_frame
	_vp.queue_free()
	await get_tree().process_frame


func _measure(txt: String, font: int, wrap_at: float) -> Vector2:
	var lab := Label.new()
	lab.text = txt
	lab.add_theme_font_size_override("font_size", font)
	if wrap_at > 0.0:
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size = Vector2(wrap_at, 0.0)
	_host.add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	var sz: Vector2 = lab.get_minimum_size()
	lab.queue_free()
	await get_tree().process_frame
	return sz


## Every page of every ReadableProp in `root`, measured through the prop's own accessors.
func _pages_of(root: Node, where: String, bad: Array, stats: Dictionary) -> void:
	var box: Vector2 = ReadableProp.body_box()
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is ReadableProp):
			continue
		stats["props"] = int(stats.get("props", 0)) + 1
		var entries: Array = n._fetch_entries()
		n._entries = entries
		if entries.is_empty():
			bad.append("%s: '%s' has a provider that returns NOTHING — it answers a press with an empty panel" % [
				where, str(n.display_name)])
			continue
		for i in range(entries.size()):
			var e: Dictionary = n._entry_at(i)
			stats["pages"] = int(stats.get("pages", 0)) + 1
			var body: String = str(e.get("body", ""))
			var head: String = str(e.get("heading", ""))
			if body != "":
				var bh: float = (await _measure(body, ReadableProp.BODY_FONT, box.x)).y
				stats["tall"] = max(float(stats.get("tall", 0.0)), bh)
				if bh > box.y:
					bad.append("%s: '%s' page %d body needs %.0f px of %.0f — %.0f px drawn nowhere, and a %d-page provider gives no arrow to reach it; trim about %.0f px" % [
						where, str(n.display_name), i + 1, bh, box.y, bh - box.y, entries.size(), bh - box.y])
			if head != "":
				var hw: float = (await _measure(head, HEADING_FONT, 0.0)).x
				stats["wide"] = max(float(stats.get("wide", 0.0)), hw)
				if hw > box.x:
					bad.append("%s: '%s' page %d heading needs %.0f px of %.0f — headings do not wrap, so %.0f px draws past the panel; shorten it" % [
						where, str(n.display_name), i + 1, hw, box.x, hw - box.x])


func test_every_readable_page_fits_the_panel_that_shows_it() -> void:
	var bad: Array = []
	var stats: Dictionary = {}
	var scenes := 0
	for p in OVERWORLDS:
		var n = await _build(p)
		if n == null:
			continue
		scenes += 1
		await _pages_of(n, str(p).get_file().get_basename(), bad, stats)
		await _teardown(n)
	var d := DirAccess.open(VILLAGE_DIR)
	if d != null:
		var vs: Array = []
		for f in d.get_files():
			if f.ends_with(".gd") and f != "BaseVillage.gd":
				vs.append(f)
		vs.sort()
		for f in vs:
			var n = await _build(VILLAGE_DIR + f)
			if n == null:
				continue
			scenes += 1
			await _pages_of(n, f.get_basename(), bad, stats)
			await _teardown(n)
	var d2 := DirAccess.open(INTERIOR_DIR)
	if d2 != null:
		var ins: Array = []
		for f in d2.get_files():
			if f.ends_with(".gd") and not (f in NOT_A_ROOM):
				ins.append(f)
		ins.sort()
		for f in ins:
			var n = await _build(INTERIOR_DIR + f)
			if n == null:
				continue
			scenes += 1
			await _pages_of(n, f.get_basename(), bad, stats)
			await _teardown(n)
	for spec in DUNGEONS:
		for fl in (spec["floors"] as Array):
			var n = await _build(str(spec["path"]), int(fl))
			if n == null:
				continue
			scenes += 1
			await _pages_of(n, "%s f%d" % [str(spec["path"]).get_file().get_basename(), int(fl)], bad, stats)
			await _teardown(n)

	assert_gt(scenes, 45,
		"CONTROL: only %d scenes built — the corpus is the whole point of this file, and a short one is the defect it replaces" % scenes)
	assert_gt(int(stats.get("props", 0)), 25,
		"CONTROL: only %d ReadableProps found across %d scenes" % [int(stats.get("props", 0)), scenes])
	assert_gt(int(stats.get("pages", 0)), int(stats.get("props", 0)) - 1,
		"CONTROL: %d pages from %d props — every prop must yield at least one page or the providers were not driven" % [
			int(stats.get("pages", 0)), int(stats.get("props", 0))])
	## The corpus must still reach toward both limits, or a green is about short content.
	assert_gt(float(stats.get("tall", 0.0)), ReadableProp.body_box().y * 0.6,
		"CONTROL: tallest body is %.0f px of %.0f — nothing approaches the height limit, so a green says little" % [
			float(stats.get("tall", 0.0)), ReadableProp.body_box().y])
	bad.sort()
	for b in bad:
		gut.p("DOESNOTFIT %s" % str(b))
	assert_eq(bad, [], "a readable page does not fit its panel: %s" % "; ".join(bad))
	gut.p("  %d scenes, %d props, %d pages; tallest body %.0f/%.0f px, widest heading %.0f/%.0f px" % [
		scenes, int(stats.get("props", 0)), int(stats.get("pages", 0)),
		float(stats.get("tall", 0.0)), ReadableProp.body_box().y,
		float(stats.get("wide", 0.0)), ReadableProp.body_box().x])


func after_all() -> void:
	SoundState.restore()
