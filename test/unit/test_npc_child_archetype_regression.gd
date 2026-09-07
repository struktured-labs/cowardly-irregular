extends GutTest

## Regression: "Young Pip" was placed as npc_type "villager" (author's own var is `kid`),
## so _resolve_archetype name-hashed him to young_man/young_woman — both ADULTS — while
## child/overworld.png sat on disk. struktured reported it as "young pip: no sprite"; he had
## a sprite, it was the wrong person. Every coverage join we own measures PRESENCE, so all of
## them were green throughout. This guards the appropriateness axis instead.
## The predicate is NOT "must be child" — it is "must carry an EXPLICIT archetype". An author
## who means a teenager can write young_man and pass; what fails is falling to the adult
## default silently. That requires the deliverable rather than granting a way to skip.

## Scope is ALL of src/: the first version scanned only src/maps/villages and ran green past
## "Young Worker Pip" in src/exploration/IndustrialOverworld.gd. A guessed root is a silent hole.
const SRC_DIR := "res://src"
const VILLAGE_DIR := "res://src/maps/villages"
const SHEET_DIR := "res://assets/sprites/npcs"
const NPC_SCRIPT := "res://src/exploration/OverworldNPC.gd"

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


## The npc_type -> archetype table, read as DATA. A regex over the source missed it three
## separate times tonight across three lanes; a const map is invisible to a literal scan.
func _type_map() -> Dictionary:
	var scr := load(NPC_SCRIPT) as GDScript
	if scr == null:
		return {}
	return scr.get_script_constant_map().get("NPC_TYPE_TO_ARCHETYPE", {})


## Returns [{name, type, var, src, explicit, determined}] for every _create_npc site in src/.
## "determined" is the real predicate: the archetype is FIXED by the author, by either route --
## an explicit sprite_archetype, or an npc_type whose mapping is non-empty. Both are one visible
## word at the call site. Only the name-hash fallback (mapping == "") is undetermined.
func _placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tmap := _type_map()
	var re := RegEx.create_from_string('(?:var\\s+(\\w+)\\s*=\\s*)?_create_npc\\(\\s*"([^"]+)"\\s*,\\s*"([^"]+)"')
	for path in _gd_files(SRC_DIR):
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var vname := m.get_string(1)
			var npc_type := m.get_string(3)
			var assigned := ""
			if vname != "":
				# Bind by VARIABLE, not by line proximity — a window can't see the real scope.
				var ar := RegEx.create_from_string("\\b" + vname + "\\.sprite_archetype\\s*=\\s*\"([^\"]+)\"")
				var am := ar.search(src)
				if am != null:
					assigned = am.get_string(1)
			# Explicit assignment wins, exactly as _resolve_archetype() orders it.
			var archetype: String = assigned if assigned != "" else str(tmap.get(npc_type, ""))
			out.append({
				"name": m.get_string(2), "type": npc_type, "archetype": archetype,
				"var": vname, "src": path.get_file(), "explicit": assigned != "",
				"determined": archetype != "",
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
		if _is_child_named(p["name"]) and not p["determined"]:
			offenders.append("%s (%s, npc_type=%s)" % [p["name"], p["src"], p["type"]])
	# Array assert KEEPS the index diff; the message carries the untruncated list. GUT appends
	# custom text for arrays (test.gd assert_eq), so nothing is lost -- an earlier claim that it
	# truncated the evidence was my own grep reading the summary line instead of the message.
	assert_eq(offenders, [] as Array[String],
		"child-named NPCs whose archetype is name-hashed to an adult; fix via npc_type or sprite_archetype: %s" % str(offenders))


## The two reported instances, asserted on the RESOLVED archetype rather than on either
## spelling — sprite_archetype="child" and npc_type="child" both satisfy this, so the guard
## survives whichever fix route lands. Pinning the spelling would red on a correct render.
func test_the_reported_children_resolve_to_the_child_sheet() -> void:
	var want := ["Young Pip", "Young Worker Pip"]
	var seen: Array[String] = []
	var wrong: Array[String] = []
	for p in _placements():
		if p["name"] in want:
			seen.append(p["name"])
			if p["archetype"] != "child":
				wrong.append("%s -> '%s' (%s)" % [p["name"], p["archetype"], p["src"]])
	assert_eq(seen.size(), want.size(),
		"both reported children are still placed — a rename here would make the check below vacuous: found %s" % str(seen))
	assert_eq(wrong, [] as Array[String],
		"reported child NPCs must resolve to the child sheet by either route: %s" % str(wrong))


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
	assert_has(names, "Young Worker Pip",
		"CONTROL: the scan reaches src/exploration, not just src/maps/villages — this NPC is why the scope was widened")
	assert_gt(explicit_count, 0, "CONTROL: the explicit-archetype detector can return true")
	var child_named := 0
	for n in names:
		if _is_child_named(n):
			child_named += 1
	assert_gt(child_named, 0, "CONTROL: the child-name token scan matches at least one real NPC — a zero here makes the main guard vacuous")

	# The const table is the other half of "determined"; an empty read would silently make the
	# npc_type route look undetermined and red on correctly-rendering NPCs.
	var tmap := _type_map()
	assert_gt(tmap.size(), 10, "CONTROL: NPC_TYPE_TO_ARCHETYPE loaded as data, not an empty dict")
	assert_eq(str(tmap.get("child", "")), "child", "CONTROL: a known-present mapping reads back correctly")
	assert_eq(str(tmap.get("villager", "x")), "", "CONTROL: villager maps to the empty name-hash sentinel, which is what 'undetermined' means")
