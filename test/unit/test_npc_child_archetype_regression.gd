extends GutTest

## Regression: "Young Pip" was placed as npc_type "villager" (author's own var is `kid`),
## so _resolve_archetype name-hashed him to young_man/young_woman — both ADULTS — while
## child/overworld.png sat on disk. struktured reported it as "young pip: no sprite"; he had
## a sprite, it was the wrong person. Every coverage join we own measures PRESENCE, so all of
## them were green throughout. This guards the appropriateness axis instead.
## The predicate is NOT "must be child" — it is "must carry an EXPLICIT archetype". An author
## who means a teenager can write young_man and pass; what fails is falling to the adult
## default silently. That requires the deliverable rather than granting a way to skip.

const VILLAGE_DIR := "res://src/maps/villages"
const SHEET_DIR := "res://assets/sprites/npcs"

## Name tokens that mark a character as a child. Derived from the name, not a hand-list of NPCs.
const CHILD_TOKENS := ["young ", "little ", "kid", "child", "boy", "girl", " lad", "lass"]


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			out.append_array(_gd_files(dir + "/" + f))
		elif f.ends_with(".gd"):
			out.append(dir + "/" + f)
		f = d.get_next()
	return out


## Returns [{name, type, var, src, explicit}] for every _create_npc call site under src/maps.
func _placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var re := RegEx.create_from_string('(?:var\\s+(\\w+)\\s*=\\s*)?_create_npc\\(\\s*"([^"]+)"\\s*,\\s*"([^"]+)"')
	for path in _gd_files(VILLAGE_DIR):
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var vname := m.get_string(1)
			var explicit := false
			if vname != "":
				# Bind by VARIABLE, not by line proximity — a window can't see the real scope.
				var ar := RegEx.create_from_string("\\b" + vname + "\\.sprite_archetype\\s*=")
				explicit = ar.search(src) != null
			out.append({
				"name": m.get_string(2), "type": m.get_string(3),
				"var": vname, "src": path.get_file(), "explicit": explicit,
			})
	return out


func _is_child_named(npc_name: String) -> bool:
	var lower := " " + npc_name.to_lower() + " "
	for tok in CHILD_TOKENS:
		if tok in lower:
			return true
	return false


func test_child_named_npcs_carry_an_explicit_archetype() -> void:
	var offenders: Array[String] = []
	for p in _placements():
		if _is_child_named(p["name"]) and not p["explicit"]:
			offenders.append("%s (%s, npc_type=%s)" % [p["name"], p["src"], p["type"]])
	# Size + joined string, not the array: GUT truncates array rendering and hid 3 of 5 offenders.
	assert_eq(offenders.size(), 0,
		"child-named NPCs fell to the name-hash adult default; set sprite_archetype explicitly (child, or another sheet if they are not a kid) -- %s" % "; ".join(offenders))


func test_young_pip_resolves_to_the_child_sheet() -> void:
	# The reported instance, pinned by identity rather than by coordinate.
	var pip: Dictionary = {}
	for p in _placements():
		if p["name"] == "Young Pip":
			pip = p
	assert_false(pip.is_empty(), "Young Pip is still placed in Harmonia — if this fails the guard above lost its only member")
	assert_true(pip.get("explicit", false), "Young Pip must carry an explicit sprite_archetype")
	var src := FileAccess.get_file_as_string(VILLAGE_DIR + "/HarmoniaVillage.gd")
	assert_string_contains(src, '%s.sprite_archetype = "child"' % pip["var"],
		"Young Pip renders from the child sheet, not young_man/young_woman")


func test_every_named_archetype_has_a_sheet_on_disk() -> void:
	# A typo'd archetype falls back to procedural SILENTLY — same wrong-render class, no error.
	var on_disk := {}
	var d := DirAccess.open(SHEET_DIR)
	assert_true(d != null, "archetype sheet dir is readable — if this fails everything below is vacuous")
	if d == null:
		return
	for sub in d.get_directories():
		if FileAccess.file_exists("%s/%s/overworld.png" % [SHEET_DIR, sub]):
			on_disk[sub] = true
	assert_gt(on_disk.size(), 10, "CONTROL: found a real sheet population, not an empty listing")

	var missing: Array[String] = []
	var re := RegEx.create_from_string('sprite_archetype\\s*=\\s*"([^"]+)"')
	for path in _gd_files("res://src"):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var a := m.get_string(1)
			if a != "" and not on_disk.has(a) and not missing.has(a):
				missing.append("%s (%s)" % [a, path.get_file()])
	assert_eq(missing, [] as Array[String],
		"sprite_archetype names a sheet that does not exist; the NPC renders procedurally with no error: %s" % str(missing))


func test_control_the_placement_parser_reads_real_call_sites() -> void:
	# Every assertion above is a join over _placements(); a silent regex miss makes them all vacuous.
	var all := _placements()
	assert_gt(all.size(), 40, "CONTROL: parser must find the real _create_npc population")
	var names := []
	var explicit_count := 0
	for p in all:
		names.append(p["name"])
		if p["explicit"]:
			explicit_count += 1
	assert_has(names, "Young Pip", "CONTROL: parser sees the NPC this file is about")
	assert_gt(explicit_count, 0, "CONTROL: the explicit-archetype detector can return true")
	var child_named := 0
	for n in names:
		if _is_child_named(n):
			child_named += 1
	assert_gt(child_named, 0, "CONTROL: the child-name token scan matches at least one real NPC — a zero here makes the main guard vacuous")
