extends GutTest

## Two DIFFERENT placed NPCs shared a name (W3's clocktower keeper vs Brasston's cat, both "Cogsworth"), and name-keyed systems (MAY_STAND_OFF_GRID, personas, quest givers) merge whatever shares a name.
## A name placed in two scripts must be declared ONE character, with why. Scope: literal `_create_npc("Name", ...)` calls only; a name passed through a variable is invisible here.
## NOT covered: a placed NPC against a CUTSCENE speaker ("Aldric" in the shop vs "King Aldric"); the king is never placed, and story measured that corpus as all-exemptions (22568).

const ROOTS := ["res://src/maps", "res://src/exploration"]
const SAME_CHARACTER := {
	"???": "the unnamed stranger is a role, not a person; every '???' is anonymous by design",
	"Brigadier Flux": "the same retired Brasston engineer, met on the W3 field and at home in the village",
	"Sprocket": "the same W3 mechanic, met on the field and in Brasston",
	"Madame Orrery": "the travelling fortune-teller, deliberately in three worlds' towns",
}
const CREATE_NPC := "_create_npc\\(\"([^\"]+)\"\\s*,\\s*\""


func _sources() -> Dictionary:
	var out := {}
	for root in ROOTS:
		_walk(root, out)
	return out


func _walk(dir: String, out: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out[dir + "/" + f] = FileAccess.get_file_as_string(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d, out)


## Name -> sorted files that place it, for every name placed in more than one file.
static func shared_names(sources: Dictionary) -> Dictionary:
	var re := RegEx.create_from_string(CREATE_NPC)
	var where := {}
	for path in sources:
		for m in re.search_all(str(sources[path])):
			var n := m.get_string(1)
			if not where.has(n):
				where[n] = {}
			where[n][str(path).get_file()] = true
	var out := {}
	for n in where:
		if where[n].size() > 1:
			var files: Array = where[n].keys()
			files.sort()
			out[n] = files
	return out


func _placed_name_count(sources: Dictionary) -> int:
	var re := RegEx.create_from_string(CREATE_NPC)
	var names := {}
	for path in sources:
		for m in re.search_all(str(sources[path])):
			names[m.get_string(1)] = true
	return names.size()


func test_the_scan_sees_the_placed_cast() -> void:
	var n := _placed_name_count(_sources())
	assert_gt(n, 100, "FLOOR: the scan must find the placed cast (%d names), or every other arm judges nothing" % n)


func test_a_name_placed_twice_is_declared_one_character() -> void:
	var undeclared := []
	var shared := shared_names(_sources())
	for n in shared:
		if not SAME_CHARACTER.has(n):
			undeclared.append("%s in %s" % [n, ", ".join(shared[n])])
	assert_eq(undeclared, [], "two scripts place NPCs with one name; rename one, or declare them one character in SAME_CHARACTER with why")


func test_no_declaration_outlives_its_collision() -> void:
	var shared := shared_names(_sources())
	var stale := []
	for n in SAME_CHARACTER:
		if not shared.has(n):
			stale.append(n)
	assert_eq(stale, [], "SAME_CHARACTER names a shared NPC that no longer occurs in two scripts; drop the entry")


func test_the_rule_flags_an_undeclared_pair() -> void:
	var fixture := {
		"res://a/OneVillage.gd": 'var k = _create_npc("Cogsworth", "guard", Vector2.ZERO, [])\nvar s = _create_npc("Solo", "villager", Vector2.ZERO, [])',
		"res://b/OtherVillage.gd": 'var c = _create_npc("Cogsworth", "villager", Vector2.ZERO, [])',
	}
	var shared := shared_names(fixture)
	assert_eq(shared.keys(), ["Cogsworth"], "CONTROL: one name in two files must be found, and a name in one file must not")
	assert_eq(shared.get("Cogsworth", []), ["OneVillage.gd", "OtherVillage.gd"], "and the finding names both files")
