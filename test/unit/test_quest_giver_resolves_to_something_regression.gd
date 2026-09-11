extends GutTest
## A quest whose giver npc_id matches nothing is UNSTARTABLE, and the codebase enforced that with a
## COMMENT ("Without this the quest is UNSTARTABLE — QuestSystem.gd:125") on ONE npc. This makes it
## an invariant. Mirrors OverworldNPC.get_npc_id(): explicit npc_id, else snake_case(npc_name);
## plus prop givers (BulletinBoard/TallyWall) which declare their own npc_id.
##
## W4-W6 quests are inert BY DESIGN (no maps authored yet). They are listed as a DEBT that EXPIRES:
## the assert is EQUALITY, so wiring one -- or adding a new unresolvable giver -- goes red and the
## list must be edited deliberately. A "these legitimately fall through" comment would never expire.

const QUEST_DIR := "res://data/quests/"
## ⚠️ WAS a hand-written 3-directory list, which is the same defect as scoping a loop guard by an
## "ambient_" name prefix while the keys that break the contract are named "weather_*" (cowir-sfx,
## 2026-09-11): a guard whose CORPUS is authored by hand is blind wherever the author did not look.
## src/cutscene/ also calls _create_npc and was outside the list. It contributed 0 ids, so this was a
## LATENT gap and not a live one — recorded as such, not claimed as a finding.
## Now walks ALL of src/ recursively, so a giver placed in a new directory cannot hide.
const SRC_ROOT := "res://src/"

## Unresolvable givers, WITH THE REASON EACH IS ACTUALLY UNRESOLVABLE.
## ⛔ My first version said "W4-W6 have no authored maps". That was FALSE -- RivetRow, NodePrime and
## Vertex are all authored villages with interiors. The entries were right and the stated reason was
## never true, which is the worst kind: it reads as a decision and can never expire, because the
## condition it names never held. Audited 2026-09-09 against the fleet's three-shape taxonomy
## (INERT / EXPIRED / FALSE); this list was FALSE.
##
## A) DELIBERATELY UNSET, documented at the site -- RivetRowVillage:302 says wiring madame_orrery_w4
##    makes world4_deviation_report offerable while its step 2 talks to union_rep_w4, which nothing
##    answers to. Gating a quest whose second step is unreachable is the correct call.
## B) THE CHARACTER EXISTS UNDER A DIFFERENT ID -- the quest names <role>_w4, the village creates a
##    NAMED person who snake_cases to something else. Not missing content; a naming mismatch, and
##    the likeliest of these to be a real defect rather than a decision.
##      foreman_w4 -> shift_foreman_grix · union_rep_w4 -> union_rep_voss
##      dorrit_w4 -> dorrit             · firewall_attendant_w5 -> firewall_alpha
## C) NO CANDIDATE NPC ANYWHERE -- a location/prop/pair not yet placed.
const UNWIRED_BY_DESIGN := [
	# A -- deliberate, documented at RivetRowVillage:302
	"madame_orrery_w4",
	# B -- character present under a different id (see above); resolve by naming, not by authoring
	"foreman_w4", "union_rep_w4", "dorrit_w4", "firewall_attendant_w5",
	# C -- no candidate NPC exists yet
	"rat_patrol_junction", "memory_leak_district", "race_condition_pair",
	"madame_orrery_w5", "traveler_w6", "madame_orrery_w6", "last_shopkeeper_w6",
]


func _snake(n: String) -> String:
	return n.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")


## Blank GDScript comments, preserving line count. A commented-out `.npc_id = "x"` must NOT
## count as wiring -- that is what a real removal looks like, unlike an outright delete.
func _decomment(src: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		# Cut at the first # OUTSIDE a string: `_create_npc("Worker #4471")` is code, not a comment.
		var in_str := false
		var cut := -1
		for i in line.length():
			var ch: String = line[i]
			if ch == "\"":
				in_str = not in_str
			elif ch == "#" and not in_str:
				cut = i
				break
		out.append(line.substr(0, cut) if cut >= 0 else line)
	return "\n".join(out)


func _read_all(dir_path: String) -> String:
	var blob := ""
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return blob
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			var fh := FileAccess.open(dir_path + f, FileAccess.READ)
			if fh != null:
				blob += _decomment(fh.get_as_text()) + "\n"
				fh.close()
		f = dir.get_next()
	dir.list_dir_end()
	return blob


## Every id a giver lookup could resolve to, by the three shapes get_npc_id()/props actually use.
## Walks the whole tree: the corpus is "everywhere a giver could be declared", not a list I maintain.
func _read_all_recursive(dir_path: String) -> String:
	var blob := ""
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return blob
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path + f
		if dir.current_is_dir():
			blob += _read_all_recursive(full + "/")
		elif f.ends_with(".gd"):
			var fh := FileAccess.open(full, FileAccess.READ)
			if fh != null:
				blob += _decomment(fh.get_as_text()) + "\n"
				fh.close()
		f = dir.get_next()
	dir.list_dir_end()
	return blob


func _giver_capable_ids() -> Dictionary:
	var blob := _read_all_recursive(SRC_ROOT)
	var ids := {}
	for m in RegEx.create_from_string('_create_npc\\(\\s*"([^"]+)"').search_all(blob):
		ids[_snake(m.get_string(1))] = true
	for m in RegEx.create_from_string('\\.npc_id\\s*=\\s*"([a-z0-9_]+)"').search_all(blob):
		ids[m.get_string(1)] = true
	for m in RegEx.create_from_string('var npc_id: String = "([a-z0-9_]+)"').search_all(blob):
		ids[m.get_string(1)] = true
	return ids


func _quest_givers() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(QUEST_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var fh := FileAccess.open(QUEST_DIR + f, FileAccess.READ)
			if fh != null:
				var parsed: Variant = JSON.parse_string(fh.get_as_text())
				fh.close()
				var quests: Array = parsed if parsed is Array else [parsed]
				for q in quests:
					if q is Dictionary and (q as Dictionary).has("giver"):
						var g: Variant = (q as Dictionary)["giver"]
						if g is Dictionary:
							out[str((q as Dictionary).get("id", f))] = str((g as Dictionary).get("npc_id", ""))
		f = dir.get_next()
	dir.list_dir_end()
	return out


func test_both_corpora_actually_loaded() -> void:
	## Domain claims. Either read coming back empty makes every assert below vacuous.
	var ids := _giver_capable_ids()
	var givers := _quest_givers()
	assert_gt(ids.size(), 100, "giver-capable id set looks unread: " + str(ids.size()))
	assert_gt(givers.size(), 25, "quest corpus looks unread: " + str(givers.size()))
	assert_true(ids.has("scholar_milo"),
		"control: 'Scholar Milo' must resolve via the snake_case fallback (he has no explicit npc_id)")
	assert_true(ids.has("community_bulletin_board"),
		"control: a PROP giver must resolve (BulletinBoard declares its own npc_id)")
	## ONE CONTROL PER AUTHORING FORM (cowir-overworld, 2026-09-11). Three regexes resolve three ways
	## to declare a giver and this one had NO arm — if its pattern broke, every explicitly-assigned
	## npc_id would vanish from the corpus and nothing here would fire.
	assert_true(ids.has("elder_vesper"),
		"control: an EXPLICIT `.npc_id = \"...\"` assignment must resolve (Elder Vesper, EldertreeVillage)")
	assert_false(ids.has("zzq_not_an_npc"), "control: a fabricated id must not resolve")


func test_every_live_world_quest_giver_resolves() -> void:
	var ids := _giver_capable_ids()
	var broken: Array = []
	for qid in _quest_givers():
		if not (qid.begins_with("world1") or qid.begins_with("world2") or qid.begins_with("world3")):
			continue
		var nid: String = _quest_givers()[qid]
		if nid == "" or not ids.has(nid):
			broken.append("%s -> '%s'" % [qid, nid])
	assert_eq(broken, [],
		"UNSTARTABLE quest(s): the giver npc_id matches no NPC name, no explicit npc_id, and no " +
		"prop giver, so nothing in the world can offer them: " + str(broken))


func test_the_unwired_debt_list_is_exact() -> void:
	## EQUALITY, not subset. Wiring a W4-W6 giver, or adding a new unresolvable one, MUST go red so
	## the list is edited on purpose. This is the difference between a debt and a permission.
	var ids := _giver_capable_ids()
	var unresolved: Array = []
	for qid in _quest_givers():
		var nid: String = _quest_givers()[qid]
		if nid != "" and not ids.has(nid):
			unresolved.append(nid)
	unresolved.sort()
	var expected: Array = UNWIRED_BY_DESIGN.duplicate()
	expected.sort()
	assert_eq(unresolved, expected,
		"the set of unresolvable givers CHANGED. If a world was wired, delete its entries from " +
		"UNWIRED_BY_DESIGN. If a new quest appeared with an unresolvable giver, that is the bug.")


## A guard armed only against an OUTRIGHT DELETE is defenceless against what actually happens:
## someone comments the line out and leaves a note. This pins the messy removal, not the tidy one.
func test_a_commented_out_npc_id_does_not_count_as_wiring() -> void:
	var live := "\tforeman.npc_id = \"foreman_w4\"\n"
	var removed := "\t# foreman.npc_id = \"foreman_w4\"  -- removed, see ticket\n"
	var re := RegEx.create_from_string('\\.npc_id\\s*=\\s*"([a-z0-9_]+)"')
	assert_ne(re.search(_decomment(live)), null,
		"control: a real assignment must still be seen after decommenting")
	assert_eq(re.search(_decomment(removed)), null,
		"a commented-out .npc_id must NOT register as wiring — that is how removals actually look")


## A `#` inside a string literal is CODE. Blanking from the first `#` truncated
## `_create_npc("Worker #4471", ...)` and silently dropped that NPC from the id set.
func test_decomment_does_not_truncate_a_hash_inside_a_string() -> void:
	var code := "\tvar w = _create_npc(\"Worker #4471\", \"villager\", Vector2(1,2), [])"
	assert_true(_decomment(code).contains("Worker #4471"),
		"a # inside a string is code — decommenting must not cut the line there")
	var commented := "\tvar w = _create_npc(\"Worker\", \"villager\")  # dropped for now"
	assert_false(_decomment(commented).contains("dropped for now"),
		"control: a real trailing comment must still be blanked")
