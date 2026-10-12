extends GutTest

## `data/examine_texts.json` — 26 entries, 915 words — has been authored since **2026-04-21** and
## read by nobody. Eleven of them are this castle's, and they are the "reading environmental
## storytelling" half of success criterion 4 in `docs/design/w1-progression-expansion.md`; the floors,
## pools, signposts and boss trigger landed, the NPCs landed an hour ago, and these did not.
##
## 🔑 THE PLACEMENT RULE IS @cowir-story's AND THE FLAT GEOMETRY AGREES WITH IT, which is why this
## is not a compromise. Every text is written in second person doing the looking — *"When you touch
## it, text appears"*, *"The needle is exactly centered. You have never seen a real gauge exactly
## centered."* — so the subject is the player's vantage, not an object across a room. And
## `DragonCave` sets `Mode7Overlay.is_active = false`, so `READABLE_BOX_FLAT` is 28px and a readable
## is pressable ONLY BY STANDING ON IT (measured in W6: three crystals, exactly 4 presses each, one
## per facing from their own cell). Keying each examine to the tile the player occupies while looking
## makes the flat behaviour correct.
##
## ⚠️ TWO KINDS, AND THE PACK DECIDES WHICH: a `room_beat` is the ROOM speaking, so it reads from
## anywhere sensible in it — a Signpost, which is proximity-read and is what the castle already uses
## for `_LORE`. Everything else is a thing you stop at, so it is a ReadableProp you stand on. The
## guard pins that split to the pack's own `prop` field rather than to a list here.
##
## 📌 THE FLOOR ASSIGNMENTS ARE MINE, NOT THE AUTHOR'S. The pack carries `world / scene / prop /
## name / text` and no floor. @cowir-story flagged four of their fifteen re-keys as inferences;
## these eleven floors are eleven more, anchored to the castle's own `_LORE` rooms. An arm below
## pins that every mark names a real authored entry, so an inference cannot silently point at
## nothing — but no test can tell you a floor is the one the author imagined.

const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"
const PACK := "res://data/examine_texts.json"
var _snap: Dictionary = {}


## The floor is cross-test state; `CastleFloor` names it and puts it back. That helper's header
## carries the two measurements, including a 7/7 GREEN with a floor-3 placement deleted outright.
func before_each() -> void:
	_snap = CastleFloor.snapshot()


func after_each() -> void:
	CastleFloor.restore(_snap)


func _castle_entries() -> Dictionary:
	var raw := FileAccess.get_file_as_string(PACK)
	assert_ne(raw, "", "CONTROL: the authored pack must be readable or every arm here is vacuous")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse")
	var all: Dictionary = (parsed as Dictionary).get("examines", {}) if parsed is Dictionary else {}
	var mine: Dictionary = {}
	for k in all.keys():
		var e = all[k]
		if e is Dictionary and str((e as Dictionary).get("scene", "")) == "castle_harmonia":
			mine[str(k)] = e
	return mine


## ⛔ THE CODE HALF, NOT THE FILE — measured on THIS guard rather than inherited from the thread.
## Every source arm below is satisfied by the mere PRESENCE of an id, which @cowir-story's split
## names an ACCEPTANCE set: a phantom does not red, it WIDENS what passes. The attack, run here:
## delete `castle_harmonia_glyphs`' mark and name it in a QUOTED comment inside the mark table.
##
##     test_every_authored_castle_examine_is_placed      GREEN   fooled (src.contains(id))
##     test_every_mark_names_a_real_authored_entry       GREEN   fooled (the regex needs only quotes)
##     test_the_castle_builds_each_floors_examines...    RED     "account for all 11 ... not 10"
##
## ⚠️ ONE arm spoke, and it was the RUNTIME one. So the behavioural arm is not redundant with these
## source arms — it is the only thing covering their blind spot, and pruning it as duplication would
## turn this from caught into silent. @cowir-ai measured the same inversion on their own guard.
##
## 🔑 The two controls below are what this file's shape supports, and the usual `doc`-half floor is
## NOT: `GdSource.split` puts only `"""` regions in `doc`, GDScript comments are `##`, and this file
## has zero triple-quotes — measured `doc len=0`, so flooring it would red on a correct strip.
## Over-stripping and a correct strip are the same green, so one control proves code survived and
## the other proves prose did not.
func _source() -> String:
	var raw := FileAccess.get_file_as_string(CASTLE)
	assert_ne(raw, "", "CONTROL: CastleHarmonia.gd must be readable")
	var code: String = str(GdSource.split(raw)["code"])
	assert_true(code.contains("func _place_castle_examines"),
		"CONTROL: the strip must keep real code; every arm here is vacuous if it ate the placer")
	assert_false(code.contains("##"),
		"CONTROL: no comment may survive into the code half, or a presence assert is still prose-satisfiable")
	return code


func test_the_pack_has_a_consumer() -> void:
	var src := _source()
	assert_true(src.contains("examine_texts.json"),
		"the castle must NAME the pack; @cowir-story's census guard kept this red from 2026-04-21")
	assert_true(src.contains("_place_castle_examines"),
		"and it must place them — naming the pack without placing anything reaches no player")


## Every authored castle entry must have a cell. A subset is the silent-partial-wiring shape: the
## pack reads as consumed and some of the prose still reaches nobody.
func test_every_authored_castle_examine_is_placed() -> void:
	var authored := _castle_entries()
	assert_eq(authored.size(), 11, "CONTROL: the pack must still carry 11 castle entries, found %d" % authored.size())
	var src := _source()
	var missing: Array = []
	for examine_id in authored.keys():
		if not src.contains(str(examine_id)):
			missing.append(str(examine_id))
	missing.sort()
	assert_eq(missing, [], "these authored examines have no cell, so their text still reaches no player: %s" % ", ".join(missing))


## The inverse direction: a mark naming nothing. An inference that points at a key the author never
## wrote would place a warning instead of prose, and nothing else would say so.
func test_every_mark_names_a_real_authored_entry() -> void:
	var authored := _castle_entries()
	var src := _source()
	var at := src.find("const _EXAMINE_MARKS")
	assert_gt(at, -1, "the mark table must exist")
	var end := src.find("\n}", at)
	assert_gt(end, at, "CONTROL: the table ends")
	var table := src.substr(at, end - at)
	var re := RegEx.create_from_string('"(castle_harmonia_[a-z_]+)"')
	var phantom: Array = []
	var marked := 0
	for m in re.search_all(table):
		marked += 1
		if not authored.has(m.get_string(1)):
			phantom.append(m.get_string(1))
	assert_eq(marked, authored.size(),
		"CONTROL: %d marks for %d authored entries — the two must correspond exactly" % [marked, authored.size()])
	phantom.sort()
	assert_eq(phantom, [], "these marks name no authored entry, so they would place a warning: %s" % ", ".join(phantom))


## The text stays in the pack. A copy in the script is a second source for the same prose, which is
## how a village's `fallbacks[]` drifted from its constructor dialogue.
func test_the_text_is_not_copied_into_the_script() -> void:
	var src := _source()
	var copied: Array = []
	for examine_id in _castle_entries().keys():
		var text: String = str((_castle_entries()[examine_id] as Dictionary).get("text", ""))
		if text.length() >= 30 and src.contains(text.substr(0, 30)):
			copied.append(str(examine_id))
	assert_eq(copied, [], "authored prose is duplicated in the script: %s" % ", ".join(copied))


## The two-kinds split must come from the PACK's `prop`, not from a list in the script.
func test_the_kind_split_is_driven_by_the_pack() -> void:
	var src := _source()
	var at := src.find("func _place_castle_examines")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_true(body.contains('entry.get("prop", "")') and body.contains("_ROOM_BEAT"),
		"the Signpost-vs-ReadableProp choice must read the pack's own `prop` field")
	assert_true(body.contains("Signpost.new()") and body.contains("ReadableProp.new()"),
		"both kinds must be buildable, or one half of the pack is unreachable")
	assert_true(body.contains("_sign_position("),
		"placement must share the signposts' allocator, or an examine can land on a sign or an NPC")


## ⛔ THE ARM THAT MATTERS: every arm above reads SOURCE. This builds the castle on EVERY floor
## and counts what a player would actually find — including floor 4, which is authored BARE, so
## placing every examine on every floor is caught rather than merely unlikely. A room beat is
## checked by its authored TEXT on a Signpost, because `DragonCave` adds signposts of its own
## (floor label, stairs) and a count of them would not be the castle's.
func test_the_castle_builds_each_floors_examines_and_no_others() -> void:
	var authored := _castle_entries()
	var covered: Array = []
	var placed_total := 0
	for floor_num in [1, 2, 3, 4]:
		var castle = await CastleFloor.build(self, floor_num)
		assert_not_null(castle, "CONTROL: the castle must build on floor %d" % floor_num)
		if castle == null:
			continue
		assert_eq(int(castle.total_floors), 4,
			"CONTROL: this arm walks floors 1-4; the castle now has %d" % int(castle.total_floors))
		assert_eq(int(castle.current_floor), floor_num,
			"CONTROL: floor %d was asked for and the castle built %d, so the rest of this arm would measure the wrong floor" % [
				floor_num, int(castle.current_floor)])

		var marks: Dictionary = castle._EXAMINE_MARKS.get(floor_num, {})
		var want_props: Array = []
		var want_beats: Array = []
		for examine_id in marks.keys():
			var entry: Dictionary = authored.get(examine_id, {}) if authored.get(examine_id, {}) is Dictionary else {}
			if str((entry as Dictionary).get("prop", "")) == "room_beat":
				want_beats.append(str((entry as Dictionary).get("text", "")))
			else:
				want_props.append(str(examine_id))
		want_props.sort()

		var built_props: Array = []
		var sign_texts: Array = []
		var cells: Dictionary = {}
		var stack: Array = [castle]
		while not stack.is_empty():
			var n = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is Node2D and (n is ReadableProp or n is Signpost):
				var cell: String = str(Vector2i((n as Node2D).position / float(castle.TILE_SIZE)))
				if cells.has(cell):
					fail_test("floor %d: two readable things on cell %s: '%s' and '%s' — nearest-wins would hide one" % [
						floor_num, cell, str(cells[cell]), str(n.name)])
				cells[cell] = str(n.name)
			if n is Signpost:
				sign_texts.append(str((n as Signpost).sign_text))
			if n is ReadableProp and str(n.name).begins_with("Examine_"):
				built_props.append(str(n.name).trim_prefix("Examine_"))
		built_props.sort()
		assert_eq(built_props, want_props,
			"floor %d should hold a ReadableProp for exactly its non-room_beat examines. built=%s expected=%s" % [
				floor_num, str(built_props), str(want_props)])
		for beat in want_beats:
			assert_true(beat in sign_texts,
				"floor %d: a room beat must reach the player as a Signpost carrying its authored text, and none does" % floor_num)
		placed_total += want_props.size() + want_beats.size()
		covered.append("f%d: %d props + %d beats" % [floor_num, want_props.size(), want_beats.size()])

	assert_eq(covered.size(), 4, "CONTROL: all four floors must have been measured, got %s" % str(covered))
	assert_eq(placed_total, authored.size(),
		"CONTROL: the floors together must account for all %d authored entries, not %d — a mark on no floor reaches nobody" % [
			authored.size(), placed_total])
	gut.p("  " + ", ".join(covered))


## And one must actually open with the authored text, not an empty panel.
func test_an_examine_opens_with_its_authored_text() -> void:
	var castle = await CastleFloor.build(self, 1)
	assert_not_null(castle, "CONTROL: the castle must build on floor 1")
	if castle == null:
		return

	var authored := _castle_entries()
	var found: ReadableProp = null
	var stack: Array = [castle]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is ReadableProp and str(n.name).begins_with("Examine_"):
			found = n
			break
	assert_not_null(found, "SCOPE: at least one examine prop must exist to be pressed")
	if found == null:
		return
	var examine_id: String = str(found.name).trim_prefix("Examine_")
	found.interact(null)
	assert_true(found.is_open(), "pressing %s opened nothing" % examine_id)
	var want: String = str((authored[examine_id] as Dictionary).get("text", ""))
	assert_eq(found._entry_at(0)["body"], want,
		"the panel must show the AUTHORED text for %s, not a placeholder" % examine_id)
	found._close_panel()
	assert_false(found.is_open(), "the panel must close, releasing the input lock")
