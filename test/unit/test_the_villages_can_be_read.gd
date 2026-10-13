extends GutTest

## `data/examine_texts.json` — authored since **2026-04-21**, read by nobody until this release.
## CastleHarmonia took its 11 entries an hour ago; these are the VILLAGE half: **13 entries across
## 11 villages**, every one of which has had a well, a statue, a notice board or a monument authored
## for it and walked past by every player for six months.
##
## 🔑 ONE CONSUMER, NOT ELEVEN. Every village extends `BaseVillage`, and the pack's `scene` keys are
## exactly `_get_area_id()` values — @cowir-story re-keyed them in `934463708` (before: `village_brasston`,
## `overworld_grimhollow`, `dungeon_pipeline`). So the placer lives in the base class and each village
## gets its own entries for free. ⚠️ I measured today's agreement and briefly published it as proof
## the re-key had been unnecessary; the parent commit says 13 of 15 did not match. A current
## agreement cannot tell *always matched* from *was fixed*.
##
## 🔑 OFFSETS FROM THE ARRIVAL SPAWN, NOT ABSOLUTE CELLS — and the guard pins the relationship
## rather than the number. A village resize shifts every `.gd` Vector2 and touches no data file,
## which is the documented trap for staged-cutscene coords; the spawn moves WITH its map, so an
## offset keeps its meaning where a coordinate would not.

const BASE := "res://src/maps/villages/BaseVillage.gd"
const PACK := "res://data/examine_texts.json"

const VILLAGES := {
	"harmonia_village": "res://src/maps/villages/HarmoniaVillage.gd",
	"eldertree_village": "res://src/maps/villages/EldertreeVillage.gd",
	"frosthold_village": "res://src/maps/villages/FrostholdVillage.gd",
	"grimhollow_village": "res://src/maps/villages/GrimhollowVillage.gd",
	"sandrift_village": "res://src/maps/villages/SandriftVillage.gd",
	"brasston_village": "res://src/maps/villages/BrasstonVillage.gd",
	"ironhaven_village": "res://src/maps/villages/IronhavenVillage.gd",
	"maple_heights_village": "res://src/maps/villages/MapleHeightsVillage.gd",
	"rivet_row_village": "res://src/maps/villages/RivetRowVillage.gd",
	"node_prime_village": "res://src/maps/villages/NodePrimeVillage.gd",
	"vertex_village": "res://src/maps/villages/VertexVillage.gd",
}


func _pack_by_scene() -> Dictionary:
	var raw := FileAccess.get_file_as_string(PACK)
	assert_ne(raw, "", "CONTROL: the authored pack must be readable or every arm here is vacuous")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse")
	var all: Dictionary = (parsed as Dictionary).get("examines", {}) if parsed is Dictionary else {}
	var out: Dictionary = {}
	for k in all.keys():
		var e = all[k]
		if not (e is Dictionary):
			continue
		var scene: String = str((e as Dictionary).get("scene", ""))
		if not VILLAGES.has(scene):
			continue
		if not out.has(scene):
			out[scene] = {}
		(out[scene] as Dictionary)[str(k)] = e
	return out


## ⛔ THE CODE HALF, measured on the castle's sibling guard rather than assumed: every arm below that
## reads source is satisfied by the PRESENCE of a token, which is an ACCEPTANCE set — a phantom
## WIDENS what passes instead of reding. On the castle file, naming a deleted mark in a quoted
## comment took `Failing 1` to `Failing 3` once the strip went in.
##
## 🔑 Three controls, each catching a direction the others pass (the fleet's four-mutant table,
## 2026-10-12). The usual `doc`-half floor is NOT one of them here and would red on a correct strip:
## `GdSource.split` puts only `"""` regions in `doc`, and GDScript comments are `##`.
func _source() -> String:
	var raw := FileAccess.get_file_as_string(BASE)
	assert_ne(raw, "", "CONTROL: BaseVillage.gd must be readable")
	var code: String = str(GdSource.split(raw)["code"])
	assert_true(code.contains("func _place_authored_examines"),
		"CONTROL: the strip must keep real code; every arm here is vacuous if it ate the placer")
	assert_false(code.contains("##"),
		"CONTROL: no comment may survive into the code half, or a presence assert is still prose-satisfiable")
	## DERIVED, not a magnitude: a ratio threshold's safe margin is a per-file property (this file
	## against CastleHarmonia's 0.572 and BattleScene's 0.673), so a shared constant would be the
	## coincidental value. A mutant that preserves the one line the assert above names still has to
	## preserve every declaration to pass this.
	assert_eq(code.count("\nfunc "), raw.count("\nfunc "),
		"CONTROL: the strip kept %d of %d declarations — it ate code, and a named-line assert cannot see that" % [
			code.count("\nfunc "), raw.count("\nfunc ")])
	return code


## \u26d4 A SOURCE PIN NEEDS BOTH BOUNDARIES. `src.find("\\nfunc ", at)` returns -1 for the LAST
## function in a file, and `substr(at, -1 - at)` yields nothing — so the arm went green-by-vacuity
## in the first version of this guard and red once it had asserts. Falling back to EOF is the fix;
## a bare `find` is a pin whose end boundary is only usually there.
func _func_body(src: String, decl: String) -> String:
	var at := src.find(decl)
	if at < 0:
		return ""
	var end := src.find("\nfunc ", at + decl.length())
	if end < 0:
		end = src.length()
	var body := src.substr(at, end - at)
	## \u26d4 DERIVED, because `length() > 0` is the control that cannot see an OVER-RUN
	## (@cowir-battle, 2026-10-12: an anchor can be CORRECT while the assertion defending it is
	## inert). The placer is currently the LAST function, so the EOF fallback is the live path — add
	## a function below it with a broken close anchor and the slice would swallow it silently, and
	## every assert about "the placer's body" would then be about someone else's.
	assert_eq(body.count("\nfunc "), 0,
		"the slice for '%s' holds %d further function header(s) — it over-ran, so every assert about this body is about the wrong code" % [
			decl, body.count("\nfunc ")])
	return body


func test_the_pack_has_a_consumer() -> void:
	var src := _source()
	assert_true(src.contains("examine_texts.json"),
		"BaseVillage must NAME the pack; @cowir-story's census guard kept this red from 2026-04-21")
	assert_true(src.contains("ReadableProp.new()"),
		"and it must build readables — naming the pack without placing anything reaches no player")
	assert_true(src.contains("_place_authored_examines()"),
		"and the placer must be CALLED, not merely defined")


## No arm may read the subject file raw: the controls in `_source()` are the only strip evidence,
## and a later arm fetching the file itself would route around all three of them.
func test_no_arm_reads_the_base_outside_the_accessor() -> void:
	var own := FileAccess.get_file_as_string("res://test/unit/test_the_villages_can_be_read.gd")
	assert_ne(own, "", "CONTROL: this guard must be able to read itself")
	## \u26d4 THE NEEDLE IS ASSEMBLED, because a literal one MATCHES ITSELF: written whole, this line
	## is an occurrence in the file it is counting, so the arm read 2 and blamed the subject. The
	## same self-confirming shape as `grep $'\\x00'` matching every line.
	var needle := "get_file_as_string(" + "BASE)"
	var reads := own.count(needle)
	assert_eq(reads, 1,
		"BaseVillage must be read in exactly ONE place (`_source`), found %d — a second read bypasses the strip controls" % reads)


## Every authored village entry must have an offset, or it has no cell and reaches nobody. A subset
## is the silent-partial-wiring shape: the pack reads as consumed while some prose stays dark.
func test_every_authored_village_examine_has_an_offset() -> void:
	var by_scene := _pack_by_scene()
	var src := _source()
	var total := 0
	var missing: Array = []
	for scene in by_scene.keys():
		for examine_id in (by_scene[scene] as Dictionary).keys():
			total += 1
			if not src.contains(str(examine_id)):
				missing.append(str(examine_id))
	assert_eq(total, 13, "CONTROL: the pack must still carry 13 village entries, found %d" % total)
	missing.sort()
	assert_eq(missing, [], "these authored examines have no offset, so their text reaches no player: %s" % ", ".join(missing))


## The inverse: an offset naming nothing would place a warning instead of prose, and nothing else
## would say so.
##
## 🔑 READ THROUGH THE CLASS, NOT AS TEXT (@cowir-autogrind's prior step, 2026-10-12). A regex over
## the declaration would be exposed to the bracket-in-the-TYPE bug three lanes hit tonight —
## `const X: Array[String] = [` closes a `find(']')` inside `Array[String]`, extracting ZERO names
## cleanly. `get_script_constant_map()` hands over the array the ENGINE parsed, so no delimiter is
## ever searched for and the class is unreachable rather than avoided. Text extraction is right when
## the subject IS the text; this arm wants the MEMBERS.
func test_every_offset_names_a_real_authored_entry() -> void:
	var consts: Dictionary = load(BASE).get_script_constant_map()
	assert_true(consts.has("_EXAMINE_OFFSETS"), "the offset table must exist as a const on BaseVillage")
	var offsets: Dictionary = consts["_EXAMINE_OFFSETS"]
	assert_gt(offsets.size(), 0, "CONTROL: the parsed table must be non-empty, or every comparison below is vacuous")

	var authored: Array = []
	var by_scene := _pack_by_scene()
	for scene in by_scene.keys():
		for examine_id in (by_scene[scene] as Dictionary).keys():
			authored.append(str(examine_id))
	authored.sort()
	var named: Array = []
	for k in offsets.keys():
		named.append(str(k))
	named.sort()
	assert_eq(named, authored,
		"the offset table and the authored village entries must correspond EXACTLY — an extra offset places nothing, a missing one leaves prose dark")
	for k in offsets.keys():
		assert_true(offsets[k] is Vector2i, "offset '%s' must be a Vector2i, not %s" % [str(k), type_string(typeof(offsets[k]))])


## The prose stays in the pack. A copy in the script is a second source for one surface, which is
## how a village's `fallbacks[]` drifted from its constructor dialogue.
func test_the_text_is_not_copied_into_the_script() -> void:
	var src := _source()
	var by_scene := _pack_by_scene()
	var copied: Array = []
	var skipped: Array = []
	for scene in by_scene.keys():
		for examine_id in (by_scene[scene] as Dictionary).keys():
			var text: String = str(((by_scene[scene] as Dictionary)[examine_id] as Dictionary).get("text", ""))
			## \u26d4 THE 30-CHAR FLOOR IS A REAL EXEMPTION AND IT MUST BE REPORTED, NOT HIDDEN. A short
			## text is skipped deliberately: matching on too few characters is how a supersession check
			## of mine scored 51 phantom hits off one `'...'` line earlier today. But a silent skip means
			## a future short examine could be copied into the script with nothing to say so, so the arm
			## PRINTS what it exempted. Vacuous today \u2014 measured, the shortest authored text is 131 chars.
			if text.length() < 30:
				skipped.append(str(examine_id))
				continue
			if src.contains(text.substr(0, 30)):
				copied.append(str(examine_id))
	assert_eq(copied, [], "authored prose is duplicated in the script: %s" % ", ".join(copied))
	gut.p("  copy check: %d entries, %d exempt as under 30 chars%s" % [
		_village_entry_count(by_scene), skipped.size(),
		("" if skipped.is_empty() else " \u2014 UNCHECKED: " + ", ".join(skipped))])


## Named rather than inlined so the count in the report above cannot drift from the set checked.
func _village_entry_count(by_scene: Dictionary) -> int:
	var n := 0
	for scene in by_scene.keys():
		n += (by_scene[scene] as Dictionary).size()
	return n


## The offsets are a RELATIONSHIP to the arrival spawn, not coordinates. An absolute cell here would
## be the coincidental-value ratchet: correct today, wrong the day a map is regenerated, and silent.
func test_the_placement_is_relative_to_the_spawn() -> void:
	var src := _source()
	var body := _func_body(src, "func _place_authored_examines")
	assert_gt(body.length(), 0, "CONTROL: the placer's body must be sliceable, or every assert below is vacuous")
	assert_true(body.contains('spawn_points.get("default"'),
		"placement must be derived from the village's own arrival spawn, not from absolute cells")
	assert_true(body.contains("_resolve_examine_cell("),
		"and it must resolve through the walkability search, or a regenerated map puts prose inside a building")
	assert_true(body.contains("_examine_px("),
		"and through the cell-centring helper — a 28px prop on a cell corner draws and cannot be pressed")


## ⛔ THE DRIFT BOUND IN THE BUILD ARM IS DERIVED FROM `_EXAMINE_SEARCH_RADIUS`, SO IT CANNOT
## CATCH A CHANGE TO THAT CONST — raise it to 40 and the bound rises with it. Measured: that mutation
## was GREEN across all eight arms. The claim "a nudge, not a relocation" is therefore a SECOND claim
## about the const itself, and it needs its own assert.
##
## 🔑 Read through the class, not as text, and bounded by DESIGN INTENT rather than by the
## implementation's current number: 4 may become 5 without this reding, 40 may not. A self-derived
## bound is the fixture testing its own claim.
func test_the_search_nudges_rather_than_relocates() -> void:
	var consts: Dictionary = load(BASE).get_script_constant_map()
	assert_true(consts.has("_EXAMINE_SEARCH_RADIUS"), "the search radius must be a named const")
	var r: int = int(consts["_EXAMINE_SEARCH_RADIUS"])
	assert_gt(r, 0, "a radius of 0 cannot route around a building, so a resize would place nothing")
	assert_lte(r, 6,
		"radius %d turns the resolver from a NUDGE into a relocation: an examine would land cells away from the spot it was authored for, still walkable and still wrong, with nothing to say so" % r)


## ⛔ THE ARM THAT MATTERS: every arm above reads SOURCE. This builds all eleven villages and counts
## what a player would actually find.
func test_every_village_actually_builds_its_examines() -> void:
	var by_scene := _pack_by_scene()
	assert_eq(by_scene.size(), 11, "CONTROL: 11 villages must carry entries, found %d" % by_scene.size())
	var built_total := 0
	var report: Array = []
	for scene in VILLAGES.keys():
		if not by_scene.has(scene):
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var v = load(VILLAGES[scene]).new()
		vp.add_child(v)
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_eq(str(v._get_area_id()), scene,
			"CONTROL: %s must report its own area id, or this arm measures the wrong pack rows" % scene)

		var ts: float = float(v.TILE_SIZE)
		var want: Array = (by_scene[scene] as Dictionary).keys()
		want.sort()
		var found: Dictionary = {}
		var cells: Dictionary = {}
		for n in v.npcs.get_children():
			if n is Node2D:
				var c: String = str(Vector2i((n as Node2D).position / ts))
				if cells.has(c):
					fail_test("%s: two interactables on cell %s: '%s' and '%s' — nearest-wins hides one" % [
						scene, c, str(cells[c]), str(n.name)])
				cells[c] = str(n.name)
			if n is ReadableProp and str(n.name).begins_with("Examine_"):
				found[str(n.name).trim_prefix("Examine_")] = n
		var built: Array = found.keys()
		built.sort()
		assert_eq(built, want, "%s should hold a ReadableProp for exactly its authored examines" % scene)

		var spawn_cell := Vector2i(v.spawn_points.get("default", Vector2.ZERO) / ts)
		for examine_id in found.keys():
			var prop = found[examine_id]
			var cell := Vector2i(prop.position / ts)
			assert_true(v._is_cell_walkable(cell),
				"%s: '%s' sits on cell %s, which the player cannot stand on — and a flat readable is pressable ONLY by standing on it" % [
					scene, examine_id, str(cell)])
			var centre := Vector2(cell.x * ts + ts / 2.0, cell.y * ts + ts / 2.0)
			assert_almost_eq(prop.position, centre, Vector2.ONE,
				"%s: '%s' is not cell-centred; a 28px prop on a corner is 24px off every axis-aligned probe" % [
					scene, examine_id])
			var want_cell: Vector2i = spawn_cell + v._examine_offset_for(str(examine_id))
			var drift: int = max(abs(cell.x - want_cell.x), abs(cell.y - want_cell.y))
			assert_lte(drift, v._EXAMINE_SEARCH_RADIUS,
				"%s: '%s' resolved %d cells from its intended %s — the search is meant to nudge, not relocate" % [
					scene, examine_id, drift, str(want_cell)])
			assert_true(prop.is_in_group("interactables"),
				"%s: '%s' must be interactable or the player cannot read it" % [scene, examine_id])
		built_total += built.size()
		report.append("%s:%d" % [scene.trim_suffix("_village"), built.size()])

	assert_eq(built_total, 13,
		"all 13 authored village examines must reach a player, built %d" % built_total)
	gut.p("  " + ", ".join(report))


## And one must actually open with its authored text, not an empty panel.
func test_an_examine_opens_with_its_authored_text() -> void:
	var by_scene := _pack_by_scene()
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v = load(VILLAGES["harmonia_village"]).new()
	vp.add_child(v)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var found: ReadableProp = null
	for n in v.npcs.get_children():
		if n is ReadableProp and str(n.name).begins_with("Examine_"):
			found = n
			break
	assert_not_null(found, "SCOPE: Harmonia must hold at least one examine to press")
	if found == null:
		return
	var examine_id: String = str(found.name).trim_prefix("Examine_")
	found.interact(null)
	assert_true(found.is_open(), "pressing %s opened nothing" % examine_id)
	var want: String = str(((by_scene["harmonia_village"] as Dictionary)[examine_id] as Dictionary).get("text", ""))
	assert_eq(found._entry_at(0)["body"], want,
		"the panel must show the AUTHORED text for %s, not a placeholder" % examine_id)
	found._close_panel()
	assert_false(found.is_open(), "the panel must close, releasing the input lock")
