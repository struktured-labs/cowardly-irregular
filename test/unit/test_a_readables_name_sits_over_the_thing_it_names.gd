extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## 🐛 EVERY READABLE PROP'S FLOATING NAME DREW OFF-CENTRE, BY AN AMOUNT THAT VARIED WITH THE NAME.
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
		if not str(n.get_script().resource_path).ends_with("ReadableProp.gd"):
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
		out.append({"where": where, "text": lab.text, "w": w, "centre": lab.position.x + w / 2.0})


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
	assert_gt(rows.size(), 6,
		"CONTROL: only %d readable labels measured — a short corpus would clear nothing" % rows.size())
	## The corpus has to contain a LONG name or the defect's own range is untested: at 80 px the old
	## code was accidentally right, so a corpus of short names passes either way.
	var widest := 0.0
	for r in rows:
		widest = max(widest, float(r["w"]))
	assert_gt(widest, 110.0,
		"CONTROL: widest label measured is %.0f px; under ~110 the old fixed offset was nearly correct and this arm proves little" % widest)
	var off: Array = []
	for r in rows:
		if abs(float(r["centre"])) > SLACK:
			off.append("%s: \"%s\" (%.0f px wide) draws centred %+.1f px from its prop — the name does not sit over the thing it names" % [
				str(r["where"]), str(r["text"]), float(r["w"]), float(r["centre"])])
	off.sort()
	for o in off:
		gut.p("OFFCENTRE %s" % str(o))
	assert_eq(off, [], "a readable's name is not centred on it: %s" % "; ".join(off))
	gut.p("  %d readable names centred, widest %.0f px" % [rows.size(), widest])


func after_all() -> void:
	SoundState.restore()
