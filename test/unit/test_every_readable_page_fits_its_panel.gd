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
##   heading WRAPS at `heading_box()` since 2026-10-14, within a two-line band. It did not before,
##   and excess width drew PAST the panel over whatever was behind it, which rewrote his text once.
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

## ⛔ THIS FILE HELD `HEADING_FONT = 13` AND `HEADING_H = 22.0` AS ITS OWN CONSTANTS — a second
## copy of the subject, which is what the note above them admitted to. `ReadableProp` now names both
## (`HEADING_FONT`, `heading_box()`), so they are read from the class. Had they stayed, this guard
## would have gone on measuring a 22 px one-line band after the panel grew to two, and rejected an
## authored heading that now fits.

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


## ⛔ THE HOST IS RE-MADE ON DEMAND, BECAUSE `before_all`'s IS TEST-SCOPED. It is added with
## `add_child_autofree`, which GUT frees when the FIRST test ends -- so a second arm calling this
## measured against a dead host and every size came back **0.0**, which reads as "nothing is too
## wide" and is a false clean on the whole corpus. Caught by this file's own width control, not by
## the arm: 105 headings all measured 0 px and the arm would have reported them all fitting.
func _measure(txt: String, font: int, wrap_at: float) -> Vector2:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		_host = Control.new()
		_host.size = Vector2(900, 700)
		add_child_autofree(_host)
		await get_tree().process_frame
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
				## Headings WRAP since 2026-10-14, so the question is the wrapped HEIGHT against the
				## band, not the one-line width: a 460 px heading is now correct and used to red here.
				var hbox := ReadableProp.heading_box()
				var hh: float = (await _measure(head, ReadableProp.HEADING_FONT, hbox.x)).y
				stats["head_tall"] = max(float(stats.get("head_tall", 0.0)), hh)
				stats["head_wide"] = max(float(stats.get("head_wide", 0.0)), (await _measure(head, ReadableProp.HEADING_FONT, 0.0)).x)
				if hh > hbox.y:
					bad.append("%s: '%s' page %d heading needs %.0f px of %.0f when wrapped at %.0f — it would draw past the panel; shorten it or raise HEADING_H" % [
						where, str(n.display_name), i + 1, hh, hbox.y, hbox.x])


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
	## The heading corpus must still reach PAST one line, or this file would pass with the band back
	## at 22 px and nothing would record that wrapping is load-bearing.
	assert_gt(float(stats.get("head_wide", 0.0)), ReadableProp.heading_box().x,
		"CONTROL: widest heading is %.0f px against a %.0f px band — nothing needs a second line, so a green says nothing about wrapping" % [
			float(stats.get("head_wide", 0.0)), ReadableProp.heading_box().x])
	gut.p("  %d scenes, %d props, %d pages; tallest body %.0f/%.0f px; tallest heading %.0f/%.0f px (widest unwrapped %.0f px over a %.0f px band)" % [
		scenes, int(stats.get("props", 0)), int(stats.get("pages", 0)),
		float(stats.get("tall", 0.0)), ReadableProp.body_box().y,
		float(stats.get("head_tall", 0.0)), ReadableProp.heading_box().y,
		float(stats.get("head_wide", 0.0)), ReadableProp.heading_box().x])


func after_all() -> void:
	SoundState.restore()


## ⛔ EVERY ARM ABOVE MEASURES WITH A LABEL *THIS FILE* MAKES, so none of them can see the REAL
## one lose its wrapping. `_measure` sets AUTOWRAP_WORD_SMART on its own label, which answers "would
## this fit IF it wrapped" — delete `_heading_label.autowrap_mode` from `_build_panel` and every arm
## above still passes while the panel clips again, silently reverting the fix they exist to defend.
## This arm drives the real panel and asks the real label how many lines it took.
func test_the_real_heading_label_wraps_in_the_built_panel() -> void:
	var long_head := "Layer four, printed, laminated, drilled and bolted through the other three"
	var prop := ReadableProp.new()
	prop.setup("WrapProbe", func(): return [{"heading": long_head, "body": "body"}])
	add_child_autofree(prop)
	await get_tree().process_frame
	prop.interact(null)
	await get_tree().process_frame
	await get_tree().process_frame
	var lab: Label = prop._heading_label
	assert_not_null(lab, "CONTROL: the built panel must carry a heading label")
	if lab == null:
		return
	assert_eq(lab.text, long_head, "CONTROL: the probe heading must have reached the real label")
	var box := ReadableProp.heading_box()
	assert_eq(lab.size.x, box.x, "CONTROL: the label must be the band width, else wrapping is measured against the wrong box")
	assert_gt(lab.get_line_count(), 1,
		"the REAL heading label did not wrap: this heading is wider than the %.0f px band, so without autowrap it draws past the panel onto the map" % box.x)
	assert_true(lab.get_line_count() <= 2,
		"the real heading took %d lines against a band sized for 2 (%.0f px); grow HEADING_H or shorten the heading" % [lab.get_line_count(), box.y])
	assert_true(lab.get_minimum_size().y <= box.y,
		"the wrapped heading needs %.0f px of the %.0f px band" % [lab.get_minimum_size().y, box.y])
	## Leave no lock behind: _open_panel pushed one and other files share the manager.
	prop._close_panel()
	await get_tree().process_frame
	assert_false(prop.is_open(), "CONTROL: the probe panel must close so its input lock cannot leak")


## ⛔ THE RUNTIME WALK ABOVE READS EVERY PROVIDER IN **ONE** STATE, AND PROVIDERS BRANCH ON GAME
## STATE. `_fetch_entries` is called fresh on every open by design, and `OverworldScene.
## _survey_stone_entries` appends pages on `corruption >= 0.35`, on a `secret_` flag and on a chest
## flag -- so those headings exist, are reachable in play, and are invisible to a default-state
## build. A behavioural guard inherits the blind spots of the state it puts the scene in.
##
## This arm takes the other axis: every `"heading"` AUTHORED IN SOURCE, branch or no branch,
## measured with a real Label at the band width. Measured 2026-10-14: 133 headings, exactly ONE
## needs a second line (74 chars, ~460 px) and the next widest is ~323 px, so the corpus has a
## clear gap rather than a crowd at the limit.
func test_every_authored_heading_fits_the_band_whatever_state_reveals_it() -> void:
	var rx := RegEx.create_from_string('"heading"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"')
	var dirs: Array = ["res://src/exploration/", "res://src/maps/villages/", "res://src/maps/interiors/", "res://src/maps/dungeons/"]
	var box := ReadableProp.heading_box()
	var seen: Dictionary = {}
	var over: Array = []
	var widest := 0.0
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for fn in da.get_files():
			if not str(fn).ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(d + str(fn))
			for m in rx.search_all(src):
				var head: String = m.get_string(1)
				if head == "" or seen.has(head):
					continue
				seen[head] = true
				var hh: float = (await _measure(head, ReadableProp.HEADING_FONT, box.x)).y
				widest = max(widest, (await _measure(head, ReadableProp.HEADING_FONT, 0.0)).x)
				if hh > box.y:
					over.append("%s: '%s' needs %.0f px of %.0f wrapped at %.0f" % [str(fn), head, hh, box.y, box.x])
	assert_gt(seen.size(), 100,
		"CONTROL: only %d authored headings found — the scan missed the corpus and a green says nothing" % seen.size())
	assert_gt(widest, box.x,
		"CONTROL: widest authored heading is %.0f px against a %.0f px band — nothing needs a second line, so this arm proves nothing about wrapping" % [widest, box.x])
	over.sort()
	for o in over:
		gut.p("  OVERFLOWS %s" % o)
	assert_eq(over, [],
		"%d authored heading(s) do not fit the band even wrapped: %s" % [over.size(), "; ".join(over)])
	gut.p("  %d distinct authored headings, widest %.0f px over a %.0f px band, all within %.0f px" % [
		seen.size(), widest, box.x, box.y])
