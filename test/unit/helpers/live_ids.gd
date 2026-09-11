extends RefCounted
## NPC ids resolved from a LIVE scene, because `get_npc_id()` DERIVES them and they exist as strings
## nowhere in src/.
##
## `OverworldNPC.npc_id` is an @export defaulting to "", and the accessor falls back to
## snake_case(npc_name). So `git grep brigadier_flux src/` returns NOTHING for an NPC that answers to
## exactly that at runtime. I nearly reported W3's whole quest chain unwired on that zero
## (2026-09-11); cowir-story nearly published the opposite conclusion about W4's from the same cause,
## measuring the FIELD instead of the ACCESSOR. Source cannot answer this question. A live map can.
##
## 🔑 THE HELPER DOES THE AWAITS, AND THAT IS THE WHOLE POINT OF IT BEING A HELPER. cowir-story's
## first hand-rolled run walked the map immediately after add_child, before _ready had populated
## children, and reported every id absent — on the branch where they had just assigned them. Their
## only control was a fabricated id coming back NO, which proves a probe can say NO and says nothing
## about whether it can say YES. An empty walk and a real absence are the same output.
##
## ⚠️ SO THIS RETURNS THE WHOLE SET, NEVER A MEMBERSHIP ANSWER. A probe that emits its corpus cannot
## have a missing positive control: the caller sees `canteen_cook_murl` in the list and knows the
## walk found real nodes. Ask membership of the returned array, never of the scene.
##
## ⛔ I BUILT A TEST ON THIS HELPER AND HAD TO WITHDRAW IT — read this before building another.
## `test_quest_giver_ids_resolve_in_a_live_map` asserted that every W1-W3 quest giver answers in a
## live map. It failed on four, and all four were CORRECT content:
##     warden_tally_wall        WhisperingCave, and only on floor_num == 5
##     casper_kid               an interior, and in MapleHeights only after the Annex rescue
##     community_bulletin_board an interior prop
##     madame_orrery_w1         conditionally placed
## Two corpus defects at once: my map list omitted dungeons and interiors, and even with them, floor-
## and flag-gated givers cannot exist in a cold build. Widening it to be right means reproducing
## test_quest_giver_resolves_to_something_regression's allowlist — a SECOND place for the same debt
## to go stale. That test reads source, models the accessor by hand, and is the correct instrument
## for "is every giver wired". This helper answers a different question: what does THIS map actually
## produce. Do not make it answer the first one.
##
## ⚠️ AND IT STILL CANNOT SEE A CONDITIONAL NPC. A village that creates someone only behind a story
## flag reads as absent here exactly as it does in source — the same cold-instance limit that made a
## village census report a correct, flag-gated quest chest as missing. An empty result for one id is
## "not present in a cold build", never "not authored".

## Every id a freshly built copy of `scene_path` answers to, sorted. Empty only if the map builds none.
static func npc_ids_in(scene_path: String, tree: SceneTree) -> Array:
	var scene = load(scene_path)
	if scene == null:
		return []
	var node: Node = scene.new()
	tree.root.add_child(node)
	# _ready populates children; walking before this is the documented way to get a false empty.
	for i in range(6):
		await tree.process_frame
	var ids: Array = []
	_walk(node, ids)
	node.queue_free()
	await tree.process_frame
	ids.sort()
	return ids


## ⛔ SELECTED BY THE PROPERTY, NOT BY THE ACCESSOR'S NAME. This first collected only nodes with
## get_npc_id(), and missed every PROP giver: TallyWall and BulletinBoard declare `var npc_id` and
## have no accessor at all, so `warden_tally_wall` — wired, live, answering quests — read as absent.
## Ten minutes after writing the header above about grepping the accessor instead of the field, I
## scoped this walk by the accessor's NAME instead of by what makes a node a giver: it answers to an
## npc_id, however that id is produced.
static func _walk(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c.has_method("get_npc_id"):
			acc.append(str(c.get_npc_id()))
		elif "npc_id" in c and str(c.get("npc_id")) != "":
			acc.append(str(c.get("npc_id")))
		_walk(c, acc)
