extends GutTest

## Four consumers fall back to the IDENTITY row order when a sheet declares none —
## `WanderingNPC:306` spells it out as `walk_down 0, walk_left 1, walk_right 2, walk_up 3`.
## 116 of the 145 `overworld_npc_sheets` declare no order at all, so that fallback is what
## actually decides which way 116 NPCs face.
##
## 🔑 THE FALLBACK IS SAFE ONLY BECAUSE THE CORPUS AGREES WITH IT: every sheet that DOES declare
## an order declares (0,1,2,3) — 53 of 53 across all three overworld sections, no exceptions.
## Nothing enforced that, so this arm does. It is a guard on a PREMISE, not on a defect.
##
## ⛔ If this reds, the fix is NOT to change the sheet back. It is that the undeclared sheets can
## no longer inherit a convention that now has a counterexample, and they need explicit rows.
##
## ⚠️ A PARTIAL declaration is the genuinely dangerous shape: the named rows come from the sheet
## and the unnamed ones from the fallback, so one sheet ends up half-declared and half-assumed.
const MANIFEST := "res://data/sprite_manifest.json"
## The fallback is DERIVED from the consumer, not copied here. A literal [0,1,2,3] in this file
## would be a SECOND IMPLEMENTATION of WanderingNPC's own default, and the premise this arm
## defends is that declarations match THE CONSUMER'S fallback — so a fallback that changes in
## WanderingNPC must red HERE. A copy cannot see that; it only sees the manifest moving.
const FALLBACK_OWNER := "res://src/exploration/WanderingNPC.gd"
const SECTIONS: Array[String] = ["overworld_npc_sheets", "overworld_monster_sheets", "overworld_player_sheets"]
const WALKS: Array[String] = ["walk_down", "walk_left", "walk_right", "walk_up"]


func test_every_declared_walk_order_is_the_one_the_fallback_assumes() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse")
	var m: Dictionary = parsed

	var expected := _fallback_order()
	assert_eq(expected.size(), WALKS.size(),
		("could not read the walk-row fallback out of %s — the arm cannot compare declarations "
		+ "against a fallback it failed to extract, so every result below would be free") % FALLBACK_OWNER)
	if expected.size() != WALKS.size():
		return

	var full := 0
	var undeclared := 0
	var wrong: Array = []
	var partial: Array = []

	for section in SECTIONS:
		var node = m.get(section, {})
		if not (node is Dictionary):
			continue
		for id in node:
			var e = node[id]
			if not (e is Dictionary):
				continue
			var anims = (e as Dictionary).get("animations", {})
			if not (anims is Dictionary):
				continue
			var rows: Array = []
			for w in WALKS:
				var a = (anims as Dictionary).get(w, null)
				if a is Dictionary and (a as Dictionary).has("row"):
					rows.append(int((a as Dictionary)["row"]))
				else:
					rows.append(-1)
			var named := 0
			for r in rows:
				if r >= 0:
					named += 1
			if named == 0:
				undeclared += 1
			elif named < WALKS.size():
				partial.append("%s/%s declares %d of 4 walk rows (%s) — the rest come from the fallback"
					% [section, id, named, rows])
			else:
				full += 1
				if rows != expected:
					wrong.append("%s/%s declares %s" % [section, id, rows])

	assert_gt(full, 50,
		"ANTI-VACUITY: only %d sheets declare a full walk order — the scan is measuring almost nothing" % full)
	assert_gt(undeclared, 0,
		("ANTI-VACUITY: no sheet relies on the fallback any more, so this premise no longer "
		+ "protects anything and this arm should be retired rather than left passing"))

	partial.sort()
	assert_eq(partial, [],
		("a sheet declaring SOME walk rows takes the rest from the identity fallback, so one sheet "
		+ "is half-declared and half-assumed. Declare all four or none: %s") % [partial])

	wrong.sort()
	assert_eq(wrong, [],
		("%d sheets rely on the identity fallback (walk_down 0, left 1, right 2, up 3) because they "
		+ "declare no order. That is safe only while every DECLARED order agrees with it, and one "
		+ "no longer does. Do not 'fix' the sheet — give the undeclared sheets explicit rows, since "
		+ "the convention they were inheriting now has a counterexample: %s") % [undeclared, wrong])


## The walk-row order the CONSUMER falls back to, read out of its source.
##
## `_resolve_dir_to_row` spells it as `rows.get("walk_down", 0), rows.get("walk_left", 1), …`.
## Reading it here means a change to that default reds this arm, which a literal could not do.
func _fallback_order() -> Array:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of(FALLBACK_OWNER)
	var out: Array = []
	for w in WALKS:
		var rx := RegEx.new()
		rx.compile("get\\(\\s*\"" + w + "\"\\s*,\\s*([0-9]+)\\s*\\)")
		var m := rx.search(code)
		if m == null:
			return []
		out.append(int(m.get_string(1)))
	return out
