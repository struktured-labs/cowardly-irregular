extends GutTest

## One named NPC, two PORTRAIT_SPRITES keys, two DIFFERENT faces. struktured found Mordaine's
## cutscene key wearing a placeholder knight (092b1e31) and pinned HER; this pins the CLASS.
## Two batches wrote the keys: Batch B 2026-07-16 (name-keyed: theron, milo) and the 2026-07-31
## "portraits for all NPCs" batch (archetype-keyed: elder_theron, scholar_milo, chancellor_mordaine).
## Cutscenes ask for the name key; OverworldNPC._portrait_key() asks for the archetype key.
## Both render. A player who talks to Theron in Harmonia then sees him in a cutscene meets two men.

const CD := "res://src/cutscene/CutsceneDialogue.gd"

## Known name-key -> archetype-key pairs. Named-member controls; the derived arm below finds new ones.
const KNOWN_PAIRS := {
	"mordaine": "chancellor_mordaine",
	"theron": "elder_theron",
	"milo": "scholar_milo",
}


func _portrait_map() -> Dictionary:
	var src := FileAccess.get_file_as_string(CD)
	assert_ne(src, "", "CutsceneDialogue.gd must be readable")
	var i := src.find("const PORTRAIT_SPRITES")
	assert_gt(i, -1, "PORTRAIT_SPRITES must exist")
	var j := src.find("\n}", i)
	var block := src.substr(i, j - i)
	var out := {}
	var re := RegEx.new()
	re.compile('"([a-z0-9_]+)"\\s*:\\s*"(res://[^"]+)"')
	for m in re.search_all(block):
		out[m.get_string(1)] = m.get_string(2)
	assert_gt(out.size(), 90, "CONTROL: parser must see the whole dict, not a fragment (%d keys)" % out.size())
	return out


func test_known_named_npcs_resolve_both_keys_to_one_face() -> void:
	var map := _portrait_map()
	var split: Array = []
	for name_key in KNOWN_PAIRS:
		var arch_key: String = KNOWN_PAIRS[name_key]
		assert_true(map.has(name_key), "CONTROL: name key '%s' must be in the dict" % name_key)
		assert_true(map.has(arch_key), "CONTROL: archetype key '%s' must be in the dict" % arch_key)
		if map.get(name_key, "") != map.get(arch_key, ""):
			split.append("%s -> %s  BUT  %s -> %s" % [name_key, map.get(name_key, "?").get_file(), arch_key, map.get(arch_key, "?").get_file()])
	assert_eq(split, [],
		"one character, two faces — cutscenes use the name key, village talk uses the archetype key: %s" % [split])


## Every archetype an OverworldNPC is actually given via `sprite_archetype = "..."` — the village-talk
## surface by construction. (A directory-based discriminator admitted king/boss_rat_king; a boss is never bound.)
func _bound_archetypes() -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile('sprite_archetype\\s*=\\s*"([a-z0-9_]+)"')
	for root in ["res://src/maps", "res://src/exploration"]:
		for path in _gd_files_under(root):
			for m in re.search_all(FileAccess.get_file_as_string(path)):
				out[m.get_string(1)] = path
	return out


func _gd_files_under(root: String, acc: Array = []) -> Array:
	var d := DirAccess.open(root)
	if d == null:
		return acc
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := root.path_join(n)
		if d.current_is_dir():
			_gd_files_under(p, acc)
		elif n.ends_with(".gd"):
			acc.append(p)
		n = d.get_next()
	return acc


func test_no_new_named_npc_has_grown_a_second_face() -> void:
	# Derived arm: a bound archetype key <prefix>_<name> whose bare <name> is ALSO a portrait key is one
	# character reachable from two surfaces. Bindings are read from the code, not from a hand-kept list.
	# Reach limit, stated: an NPC routed via npc_type -> NPC_TYPE_TO_ARCHETYPE (not sprite_archetype) is not seen here.
	var map := _portrait_map()
	var bound := _bound_archetypes()
	assert_gt(bound.size(), 0, "CONTROL: the binding walk must see real sprite_archetype assignments (%d)" % bound.size())
	var found: Array = []
	var candidates: Array = []
	for k2 in bound:
		if not map.has(k2):
			continue
		for k in map:
			if k == k2 or not k2.ends_with("_" + k):
				continue
			candidates.append(k2)
			if map[k] != map[k2]:
				found.append("%s -> %s  BUT  %s -> %s  (bound in %s)" % [k, map[k].get_file(), k2, map[k2].get_file(), bound[k2].get_file()])
	candidates.sort()
	assert_true(candidates.has("elder_theron") and candidates.has("scholar_milo"),
		"CONTROL: the derived arm must reach the two known bound pairs, got %s" % [candidates])
	found.sort()
	assert_eq(found, [],
		"a named NPC is bound to an archetype key whose face differs from its name key — reconcile, never add a sibling: %s" % [found])


func test_every_resolved_portrait_file_exists() -> void:
	# A repoint that typos the path is the same bug as a split: a generic face where hers should be.
	var map := _portrait_map()
	var missing: Array = []
	for k in KNOWN_PAIRS:
		for key in [k, KNOWN_PAIRS[k]]:
			if map.has(key) and not ResourceLoader.exists(map[key]):
				missing.append("%s -> %s" % [key, map[key]])
	assert_eq(missing, [], "portrait key points at a file that does not exist: %s" % [missing])
