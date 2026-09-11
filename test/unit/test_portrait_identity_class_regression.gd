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
	var seen := {}
	for k in out:
		seen[out[k]] = true
	# a parse that collapses every key onto one path makes every PAIR below trivially equal
	assert_gt(seen.size(), 50, "CONTROL: %d distinct paths for %d keys — the parse collapsed, so every identity check below is vacuous" % [seen.size(), out.size()])
	assert_true(str(out.get("queen", "")).ends_with("queen.png"), "CONTROL: a known key must map to its OWN file, got %s" % out.get("queen", "<missing>"))
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


## Registered keys whose art has never been made. They render a BLANK PANEL -- the key resolves,
## the file does not exist, and nothing reports it. Measured 2026-09-11: 16 of 105 keys, every one
## a masterite per-world variant. Only medieval was ever produced; steampunk was made in this
## commit. So every masterite cutscene outside World 1 shows an empty portrait, and World 2 is
## reachable today.
##
## Listed rather than omitted so the debt is visible, and EARNED by the arm below -- make the art
## and the entry must go, or it starts excusing something that is no longer true.
const KNOWN_MISSING_PORTRAITS := [
	"masterite_warden_industrial",
	"masterite_warden_futuristic", "masterite_warden_abstract",
	"masterite_tempo_suburban", "masterite_tempo_industrial",
	"masterite_tempo_futuristic", "masterite_tempo_abstract",
	"masterite_arbiter_suburban", "masterite_arbiter_industrial",
	"masterite_arbiter_futuristic", "masterite_arbiter_abstract",
	"masterite_curator_suburban", "masterite_curator_industrial",
	"masterite_curator_futuristic", "masterite_curator_abstract",
]


## The sweep was scoped to KNOWN_PAIRS -- 6 keys of 105 -- so 16 dead paths sat outside it. I found
## them by measuring the disk AFTER measuring the register and getting different answers, which is
## the reader defect this file already carries a fix for one function above.
func test_no_registered_portrait_points_at_a_missing_file() -> void:
	var map := _portrait_map()
	var known := {}
	for k in KNOWN_MISSING_PORTRAITS:
		known[k] = true
	var undeclared: Array = []
	for key in map:
		if FileAccess.file_exists(map[key]):
			continue
		if not known.has(key):
			undeclared.append("%s -> %s" % [key, map[key]])
	undeclared.sort()
	assert_eq(undeclared, [],
		("a registered portrait key points at a file that does not exist -- the panel renders EMPTY " +
		 "and nothing reports it: %s") % [undeclared])


func test_every_known_missing_portrait_is_still_missing() -> void:
	# EARNED. Make the art and this entry must be deleted, or it excuses something already fixed.
	var map := _portrait_map()
	assert_gt(KNOWN_MISSING_PORTRAITS.size(), 10,
		"CONTROL: the declared-missing list holds %d entries (16 at time of writing) -- if it drains, the sweep above has nothing to compare and its clean result is free" % KNOWN_MISSING_PORTRAITS.size())
	var now_present: Array = []
	var not_a_key: Array = []
	for k in KNOWN_MISSING_PORTRAITS:
		if not map.has(k):
			not_a_key.append(k)
		elif FileAccess.file_exists(map[k]):
			now_present.append(k)
	assert_eq(not_a_key, [], "declared-missing entry is not a registered key at all: %s" % [not_a_key])
	assert_eq(now_present, [],
		"the art for these EXISTS now -- delete them from KNOWN_MISSING_PORTRAITS: %s" % [now_present])


func test_every_resolved_portrait_file_exists() -> void:
	# A repoint that typos the path is the same bug as a split: a generic face where hers should be.
	var map := _portrait_map()
	var missing: Array = []
	for k in KNOWN_PAIRS:
		for key in [k, KNOWN_PAIRS[k]]:
			# FileAccess, not ResourceLoader: a deleted PNG keeps its .ctex, so ResourceLoader
			# answers about the import cache. Measured 2026-09-11 -- deleting
			# chancellor_mordaine.png and re-importing left this test GREEN. It catches a TYPO
			# either way (no artifact for a bogus path) and was blind to the deletion.
			if map.has(key) and not FileAccess.file_exists(map[key]):
				missing.append("%s -> %s" % [key, map[key]])
	assert_eq(missing, [], "portrait key points at a file that does not exist: %s" % [missing])


## KNOWN_PAIRS could be DRAINED silently and I published it as load-bearing from READING the file.
## Measured 2026-09-11 with the delete-the-entry method instead: removing "mordaine" left this file
## Passing 3 / EC 0. The presence assertions fire only for members still in the list, so deleting a
## member deletes its check -- and Mordaine is the character this file exists for.
##
## She is also NOT reachable by the derived arm, and that is correct rather than a bug: the arm
## requires an archetype BOUND via `sprite_archetype =`, and she is a boss, never bound. Dropping
## that requirement re-admits exactly the false positives the arm's comment already warned about
## (king/boss_rat_king, mage/hooded_mage, mage/time_mage -- different characters, rightly different
## faces). So KNOWN_PAIRS is her SOLE coverage, legitimately, and a sole coverage that can drain
## quietly is the worst of both.
##
## Fixed by making the drain ITSELF the violation: every suffix-pair in PORTRAIT_SPRITES must be
## classified as one that must AGREE (KNOWN_PAIRS) or one that must DIFFER (below). Remove an entry
## from either and its pair becomes unclassified and reds. An empty KNOWN_PAIRS is maximal exposure
## rather than zero work -- cowir-adhoc's set-difference shape, 2026-09-11.
##
## The DIFFER half is not bookkeeping: nothing previously stopped someone repointing hooded_mage at
## mage.png, which is the same "two characters, one face" defect in the other direction.
const DISTINCT_CHARACTERS := {
	"boss_rat_king": "the Cave Rat King is a boss, not the king of Harmonia",
	"hooded_mage": "a distinct NPC, not the Mage job portrait",
	"time_mage": "the Time Mage job, not the Mage job",
}


func _suffix_pairs(map: Dictionary) -> Array:
	var out: Array = []
	for k in map:
		for k2 in map:
			if k2 != k and k2.ends_with("_" + k):
				out.append([k, k2])
	out.sort_custom(func(a, b): return str(a) < str(b))
	return out


func test_every_portrait_suffix_pair_is_classified() -> void:
	var map := _portrait_map()
	var pairs := _suffix_pairs(map)
	assert_gt(pairs.size(), 3,
		"CONTROL: only %d suffix-pairs derived from %d keys -- the derivation is broken and any clean result below is free" % [pairs.size(), map.size()])

	var unclassified: Array = []
	for pair in pairs:
		var name_key: String = pair[0]
		var arch_key: String = pair[1]
		var claims_same: bool = KNOWN_PAIRS.has(name_key) and str(KNOWN_PAIRS[name_key]) == arch_key
		if not claims_same and not DISTINCT_CHARACTERS.has(arch_key):
			unclassified.append("%s <-> %s" % [name_key, arch_key])
	assert_eq(unclassified, [],
		("a portrait key pair is neither declared SAME-character (KNOWN_PAIRS) nor DIFFERENT " +
		 "(DISTINCT_CHARACTERS). Two keys that look like one character must be ruled on, or the " +
		 "next split ships unnoticed: %s") % [unclassified])


## THE BACKWARD ARM, and it was missing from the table I shipped 20 minutes ago. Measured with
## cowir-adhoc's inert-by-deletion probe: remove "hooded_mage" from PORTRAIT_SPRITES entirely and
## its DISTINCT_CHARACTERS entry orphans -- Passing 5, EC 0, silent. The classification sweep
## quantifies over pairs that EXIST, so a deleted subject produces no pair to leave unclassified.
##
## KNOWN_PAIRS does not have this hole: its per-pair `map.has(...)` controls red on the same
## deletion (measured, Failing 1). Two tables in one file, one with a backward arm and one without,
## and the one I wrote today was the one without.
func test_no_distinct_characters_entry_is_orphaned() -> void:
	var map := _portrait_map()
	var pairs := _suffix_pairs(map)
	var live: Dictionary = {}
	for pair in pairs:
		live[pair[1]] = true
	var orphaned: Array = []
	for arch_key in DISTINCT_CHARACTERS:
		if not map.has(arch_key):
			orphaned.append("%s: no longer a PORTRAIT_SPRITES key — the entry excuses nothing" % arch_key)
		elif not live.has(arch_key):
			orphaned.append("%s: still a key but no longer forms a suffix-pair — the entry excuses nothing" % arch_key)
	assert_eq(orphaned, [],
		("a DISTINCT_CHARACTERS entry names something the classification sweep can no longer emit. " +
		 "An exemption that suppresses nothing cannot be observed to be WRONG, so delete it: %s") % [orphaned])


func test_the_distinct_characters_really_are_distinct() -> void:
	# The DIFFER half must be EARNED, not asserted. Without this, DISTINCT_CHARACTERS is a
	# suppression list that would happily excuse a genuine collision.
	var map := _portrait_map()
	var collided: Array = []
	for arch_key in DISTINCT_CHARACTERS:
		for pair in _suffix_pairs(map):
			if pair[1] != arch_key:
				continue
			if map.get(pair[0], "") == map.get(arch_key, "^"):
				collided.append("%s and %s now share %s, but %s is declared a different character (%s)" % [
					pair[0], arch_key, str(map.get(arch_key, "")).get_file(), arch_key, DISTINCT_CHARACTERS[arch_key]])
	assert_eq(collided, [],
		"two characters declared distinct now render the same face: %s" % [collided])
