extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## 🐛 TWO CLASSES OF IN-WORLD FLOATING LABEL DREW OFF-CENTRE, BY AN AMOUNT THAT VARIED WITH THE TEXT.
## Renamed from `test_a_readables_name_sits_over_the_thing_it_names` because the invariant is not
## about readables: it is that a label floating over a world object is centred on that object. The
## old name would have under-described it, which is the shape that let the second instance live for
## a morning after I fixed the first.
##
## ⛔ THE SECOND INSTANCE IS WORSE AND IT IS ON EVERY DOOR IN THE GAME. `AreaTransition`'s prompt
## does the same thing with `FLAT_OFFSET.x = -40`, and door prompts are the widest-ranging strings
## we have: "Exit" is ~25 px and "Descend into the Suburban Underground" ~230 px, across 26 authored
## strings and four defaults — so the drift ran BOTH WAYS, about -27 px to +75 px. I found it by
## re-running this guard's own lens across the lane instead of assuming one instance was the only
## one ([[a fix hides its own siblings]]).
##
## 🐛 FIRST INSTANCE, FOR THE RECORD: EVERY READABLE PROP'S FLOATING NAME.
## `FLAT_OFFSET.x = -40` centres a label 80 px wide, and nothing held the label at 80: it drew at
## content width, so the centre sat `(width - 80) / 2` from the prop. Measured before the fix:
##
##     "Stone Well"                    52 px  ->  14.0 px LEFT
##     "The Order Board"               81 px  ->   0.5 px right   (the accidental good case)
##     "The Prayer Request Board"     126 px  ->  23.0 px right
##     "The Shelf Behind the Curtain" 139 px  ->  29.5 px right — nearly a whole 32 px tile
##
## So neighbouring props labelled themselves in different directions, and the longest authored names
## — the examines that landed this week — were the worst offenders.
##
## 🔑 `horizontal_alignment = CENTER` WAS ALREADY SET AND IS A NO-OP AT CONTENT WIDTH. The intent was
## never ambiguous; only the width was missing. Signpost does not have this bug because its
## `_layout_flat` sets a width and then positions at `-width * 0.5`. ReadableProp's comment claimed
## "Signpost's recipe verbatim" while copying the two constants and neither of those two lines — a
## comment asserting parity is the reason nobody looked.
##
## ⚠️ MEASURED AFTER SETTLING, NOT AFTER ASSIGNMENT. Three benches in this repo disagree about
## whether an assigned `Control.size` holds, and @cowir-adhoc's reading that fits all three is that
## the assignment is a REQUEST clamped on the first layout pass — so a rect read immediately agrees
## with whatever you just wrote. This file reads `get_minimum_size()` (which the fix also derives
## from, making the fix independent of that dispute) and reads it two frames after the prop is built.

const VILLAGES := ["HarmoniaVillage.gd", "VertexVillage.gd", "ScripturaPlaza.gd"]
## Doors live here too, and the widest prompts are the dungeon descents.
## \u26d4 ALL SIX, not a sample. Three of them measured a widest door prompt of 156 px while the
## catalogue holds "Descend into the Grand Mechanism" and "Descend into the Root Process" at ~230 px
## \u2014 the widest strings live in the worlds I had left out, which is the corpus error this guard's
## own history is made of. ⚠️ BUT ADDING THEM CHANGED NOTHING: 17 prompts either way, widest
## still 156 px — those worlds do not build their transitions at bare instantiation, so the ~230 px
## descents are unreachable from a test. Stated rather than implied: this arm judges 17 door
## prompts, not the catalogue's 26 authored strings.
const OVERWORLDS := ["res://src/exploration/OverworldScene.gd",
	"res://src/exploration/SuburbanOverworld.gd", "res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/IndustrialOverworld.gd", "res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/AbstractOverworld.gd"]
const INTERIORS := ["ScripturaBookshopInterior.gd", "HarmoniaChapelInterior.gd",
	"BlacksmithInterior.gd", "HarmoniaLibraryInterior.gd"]

## A name is centred when its drawn box straddles the prop. One pixel of slack for odd widths.
const SLACK: float = 1.0

var _vp: SubViewport = null


func _build(path: String) -> Node2D:
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	_vp = SubViewport.new()
	_vp.size = Vector2i(640, 480)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var n = scr.new()
	_vp.add_child(n)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return n


func _teardown(n: Node2D) -> void:
	n.queue_free()
	await get_tree().process_frame
	_vp.queue_free()
	await get_tree().process_frame


## Every ReadableProp in the tree, with its label's drawn centre relative to the prop's own origin.
func _offsets(root: Node, where: String, out: Array) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node2D) or n.get_script() == null:
			continue
		var cls := str(n.get_script().resource_path).get_file()
		if cls != "ReadableProp.gd" and cls != "AreaTransition.gd":
			continue
		## ⛔ FLAT MODE ONLY. Under Mode 7 the prompt is LIFTED to its own CanvasLayer and placed by
		## `Mode7Prompt.place` in screen space, where `FLAT_OFFSET` does not apply and centring on a
		## world object is not the question. Judging a lifted label would red on correct behaviour.
		if n.get("_prompt_layer") != null:
			continue
		var lab: Label = null
		for c in n.get_children():
			if c is Label:
				lab = c
				break
		if lab == null:
			continue
		lab.visible = true
		await get_tree().process_frame
		await get_tree().process_frame
		var w: float = max(lab.size.x, lab.get_minimum_size().x)
		if w <= 0.0:
			continue
		out.append({"where": "%s/%s" % [where, cls.get_basename()], "text": lab.text, "w": w, "centre": lab.position.x + w / 2.0})


func test_every_readable_name_is_centred_on_its_prop() -> void:
	var rows: Array = []
	for f in VILLAGES:
		var n = await _build("res://src/maps/villages/" + f)
		if n == null:
			continue
		await _offsets(n, f.get_basename(), rows)
		await _teardown(n)
	for f in INTERIORS:
		var n = await _build("res://src/maps/interiors/" + f)
		if n == null:
			continue
		await _offsets(n, f.get_basename(), rows)
		await _teardown(n)
	for p in OVERWORLDS:
		var n = await _build(p)
		if n == null:
			continue
		await _offsets(n, str(p).get_file().get_basename(), rows)
		await _teardown(n)
	assert_gt(rows.size(), 6,
		"CONTROL: only %d readable labels measured — a short corpus would clear nothing" % rows.size())
	## The corpus has to contain a LONG name or the defect's own range is untested: at 80 px the old
	## code was accidentally right, so a corpus of short names passes either way.
	var widest := 0.0
	for r in rows:
		widest = max(widest, float(r["w"]))
	var saw: Dictionary = {}
	for r in rows:
		saw[str(r["where"]).get_slice("/", 1)] = true
	assert_true(saw.has("ReadableProp") and saw.has("AreaTransition"),
		"CONTROL: the corpus holds %s — both classes must appear or a green is about one of them" % str(saw.keys()))
	assert_gt(widest, 110.0,
		"CONTROL: widest label measured is %.0f px; under ~110 the old fixed offset was nearly correct and this arm proves little" % widest)
	var off: Array = []
	for r in rows:
		if abs(float(r["centre"])) > SLACK:
			off.append("%s: \"%s\" (%.0f px wide) draws centred %+.1f px from the object it labels — a floating label must sit over its own owner" % [
				str(r["where"]), str(r["text"]), float(r["w"]), float(r["centre"])])
	off.sort()
	for o in off:
		gut.p("OFFCENTRE %s" % str(o))
	assert_eq(off, [], "a readable's name is not centred on it: %s" % "; ".join(off))
	## \u26a0\ufe0f PER CLASS, because one number cannot say whether both halves were judged. This line
	## read "readable names" after the guard was widened to doors — a summary that describes the
	## scope it USED to have is the same lie as a filename that does.
	var per: Dictionary = {}
	var widest_of: Dictionary = {}
	for r in rows:
		var c: String = str(r["where"]).get_slice("/", 1)
		per[c] = int(per.get(c, 0)) + 1
		widest_of[c] = max(float(widest_of.get(c, 0.0)), float(r["w"]))
	for c in per.keys():
		gut.p("  %-16s %d labels centred, widest %.0f px" % [str(c), int(per[c]), float(widest_of[c])])


func after_all() -> void:
	SoundState.restore()
