extends GutTest

## An NPC has TWO id derivations, and they do not agree. Today that is invisible; one authoring
## flag makes it a silent reward failure.
##
##   OverworldNPC.get_npc_id()            name.to_lower().replace(" ","_").replace("'","").replace("-","_")
##   ConversationRewards.resolve_npc_id() name.to_lower().replace(" ","_").strip_edges()
##
## Both prefer an explicit `npc_id`, so they diverge only for an NPC that declares none and whose
## NAME carries an apostrophe or a hyphen. Measured live 2026-09-11 across 66 maps / 212 NPCs:
## EIGHT diverge -- ADMIN-01, DEBUG-7, FIREWALL-ALPHA, SUDO-1, User-7734, ARIA-9, Half-Grown Figure,
## Maint. Unit M-07 -- keyed `admin_01` by the quest system and `admin-01` by the reward ledger.
##
## ⚠️ THAT LIST IS A DATED SNAPSHOT AND IT SHRINKS ON ITS OWN. Any NPC granted an explicit npc_id
## leaves the set, for any reason -- @cowir-story's `239ba029` gives FIREWALL-ALPHA
## `firewall_attendant_w5` so a QUEST GIVER resolves, and it drops out as a side effect nobody
## intended (verified at that SHA: exactly one explicit id added, the other seven untouched).
## NOTHING BELOW COUNTS THEM. The asserts read the live tree, so a shrinking list is not a failure --
## and the list reaching ZERO is the one case that reds, deliberately, as "delete this test".
##
## 🔑 IT IS UNREACHABLE TODAY, AND THAT IS A MEASUREMENT, NOT AN ASSUMPTION. `resolve_npc_id` is
## called on exactly one path, `_run_dynamic_conversation`, gated on `dynamic and persona != ""`.
## Three NPCs in the game pass that gate -- Elder Theron, Scholar Milo, Guard Boris. All eight
## divergent NPCs are LLM=false.
##
## ⛔ CORRECTED 2026-09-12: this said the three "declare an explicit npc_id, so both derivations
## return it and agree". They declare NONE. `BaseVillage._create_npc` (:504) sets npc_name,
## npc_type, position and dialogue_lines and nothing else, and HarmoniaVillage sets an explicit
## npc_id only on aldwick/bram/rowan, which are not dynamic. So the three run BOTH slug transforms
## and agree only because their names carry no apostrophe and no hyphen -- a contingent agreement,
## not a structural one.
##
## THAT ADDS A SECOND TRIGGER THE OLD TEXT DENIED, and it takes TWO edits, not one. Measured both
## ways rather than reasoned:
##
##   rename the village display name ALONE        -> the persona lookup in
##   ("Guard Boris" -> "Guard O'Boris")              npc_showcase_personas.json is keyed by DISPLAY
##                                                   NAME, so persona becomes "" and the NPC leaves
##                                                   the reward path entirely. No divergence to
##                                                   find; the KNOWN_LLM_NPCS control is what reds.
##   rename the display name AND the persona key  -> persona resolves, the NPC is LLM-capable, and
##                                                   the two derivations split:
##                                                   'guard_oboris' to quests,
##                                                   "guard_o'boris" to the reward ledger. The
##                                                   two-id arm reds, naming both spellings.
##
## So the live-bug edit is a rename that keeps the persona working. The one-part rename is a
## different failure (an NPC silently stops being LLM-capable) and a different arm catches it.
## I drafted this paragraph claiming a one-part rename was enough; the mutation fired ONE assert
## where I predicted two, which is the only reason the difference surfaced. The two id spaces are also disjoint stores: quest ids go to QuestSystem, reward ids to
## the `llm_conversation_reward_claims` ledger, and nothing reads across.
##
## ⚠️ AND THE WALK HAS A BLIND POPULATION. `_walk` collects nodes with `get_npc_id`.
## `WanderingNPC` extends Area2D, has NO such method, and carries its own `dynamic` / `persona`
## exports plus a live `ConversationRewards.resolve_npc_id("", npc_name)` call
## (WanderingNPC:487). No wanderer is dynamic today -- measured, the only three `dynamic = true`
## assignments in src/ are HarmoniaVillage's -- but one flipped in the editor would reach the
## reward path INVISIBLY to this file. The arm below pins that population at zero rather than
## leaving the walk quietly short.
##
## ⚠️ SO THIS IS A TRIPWIRE ON THE PRECONDITION, NOT A FIX. The bug arrives the day someone sets
## `dynamic = true` and a persona on an NPC whose name has a hyphen -- a one-line authoring change,
## in this lane, with no other symptom: the reward table has a `default` entry, so the payout still
## resolves, it is the CLAIM LEDGER that keys under the other spelling. @cowir-autogrind flagged the
## restatement family; @cowir-ai narrowed the live divergence to this one site.

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")
const ConversationRewards := preload("res://src/llm/ConversationRewards.gd")

const DIRS := [
	"res://src/maps/villages", "res://src/maps/interiors",
	"res://src/maps/dungeons", "res://src/exploration",
]
## Named, not counted: a total can stay green with the walk half dead.
const KNOWN_LLM_NPCS := ["Elder Theron", "Scholar Milo", "Guard Boris"]
## The maps this guard makes claims ABOUT: the eight divergent NPCs live in these five, plus
## Harmonia which holds all three LLM-capable NPCs. Losing any one hides the very thing being pinned.
const MUST_BUILD := [
	"NodePrimeVillage.gd", "NodePrimeDaemonLoungeInterior.gd", "EldertreeGraftingHouseInterior.gd",
	"FuturisticOverworld.gd", "IndustrialOverworld.gd", "HarmoniaVillage.gd",
]


## `acc` is the population this guard can compare (both derivations available).
## `blind` is the one it cannot: nodes that carry the reward path's own gate
## (`dynamic` + `persona`) but expose no `get_npc_id` — WanderingNPC, today.
func _walk(n: Node, acc: Array, blind: Array) -> void:
	for c in n.get_children():
		if c.has_method("get_npc_id"):
			acc.append(c)
		elif c.get("dynamic") != null and c.get("persona") != null:
			blind.append(c)
		_walk(c, acc, blind)


func _reward_id(npc: Node) -> String:
	var authored = npc.get("npc_id")
	return ConversationRewards.resolve_npc_id(
		str(authored) if authored != null else "", str(npc.get("npc_name")))


func test_no_npc_on_the_reward_path_answers_to_two_ids() -> void:
	var two_ids: Array = []
	var divergent_anywhere: Array = []
	var llm_names: Array = []
	var blind_nodes: Array = []
	var live_blind: Array = []
	var npcs_seen := 0
	var maps_built := 0
	var built: Array = []

	for dir_path in DIRS:
		for path in MapScripts.maps_in(dir_path):
			var vp := SubViewport.new()
			vp.size = Vector2i(64, 64)
			vp.world_2d = World2D.new()
			add_child_autofree(vp)
			var map_node = load(path).new()
			vp.add_child(map_node)
			await get_tree().physics_frame
			await get_tree().process_frame
			maps_built += 1
			built.append(path.get_file())

			var npcs: Array = []
			_walk(map_node, npcs, blind_nodes)
			for npc in npcs:
				npcs_seen += 1
				var quest_id: String = str(npc.get_npc_id())
				var reward_id: String = _reward_id(npc)
				if quest_id != reward_id:
					divergent_anywhere.append("%s '%s' %s vs %s" % [path.get_file(), str(npc.get("npc_name")), quest_id, reward_id])
				var dyn = npc.get("dynamic")
				var persona = npc.get("persona")
				if not (dyn != null and bool(dyn) and persona != null and str(persona) != ""):
					continue
				llm_names.append(str(npc.get("npc_name")))
				if quest_id != reward_id:
					two_ids.append("%s: '%s' is '%s' to quests and '%s' to the reward ledger" % [
						path.get_file(), str(npc.get("npc_name")), quest_id, reward_id])

	## ⛔ A FLOOR IS BLIND TO PARTIAL LOSS, and this file shipped with one. `maps_built > 50` over a
	## 66-map corpus stays green with SIXTEEN maps gone — and a missing map contributes no divergent
	## NPCs, so `two_ids == []` passes for exactly the content that was not examined. @cowir-adhoc
	## named the shape, @cowir-controller measured a one-file loss sailing past their own floor, and
	## @cowir-sprites' head-lock gate passed with ALL 145 sheets deleted. The floor stays as a coarse
	## signal; NAMED MEMBERSHIP is what makes a partial loss loud.
	assert_gt(maps_built, 50, "CONTROL: only %d maps built — the walk is broken" % maps_built)
	for must in MUST_BUILD:
		assert_true(must in built,
			("CONTROL: %s did not build, so its NPCs were never examined — and a map that produces no " +
			"NPCs produces no divergences either, so the empty verdict below would be half a result " +
			"reported as a whole one. Built %d: %s") % [must, built.size(), str(built)])
	assert_gt(npcs_seen, 150, "CONTROL: only %d NPCs found — the zero below would be free" % npcs_seen)
	## ⚠️ BOTH LISTS BELOW ARE POSITIVE CONTROL SETS, AND THOSE DRAIN QUIETLY: removing a member
	## removes its own check and the survivors still pass. @cowir-sprites measured exactly this on a
	## set they had reasoned was safe, losing coverage of the one character their file exists for.
	## Sizes stated so a drain reds instead of shrinking the claim in silence.
	## ⚠️ `== 3` IS DELIBERATE AND IT IS NOT A CENSUS. @cowir-ai's split: an `== literal` belongs to a
	## set the guard OWNS and is WRONG for a corpus that legitimately grows — it forbids another
	## lane's correct addition. Here forbidding it is the POINT. This list is a PRECONDITION PIN:
	## the whole guard rests on "no divergent NPC reaches the reward path", and a FOURTH LLM-capable
	## NPC is exactly the event that could make the latent bug live. So growth must red, loudly,
	## and the message has to say so — the old one named only the shrink direction.
	assert_eq(KNOWN_LLM_NPCS.size(), 3,
		("KNOWN_LLM_NPCS holds %d names, not 3. BOTH directions are real and they mean opposite things:\n" +
		"  GREW — someone made another NPC dynamic+persona. CHECK THEIR NAME FOR A HYPHEN OR APOSTROPHE\n" +
		"         first; that is the precondition this whole file exists to watch. Then add them here.\n" +
		"  SHRANK — an NPC stopped being LLM-capable. Say so here deliberately; a quiet removal drops\n" +
		"         its own membership check with it.") % KNOWN_LLM_NPCS.size())
	## `gte`, not `eq` — @cowir-sfx's discriminator is MAY IT GROW, not who wrote it. A seventh map
	## holding a divergent NPC is correct work and must not red; losing one is the failure. A literal
	## floor catches minus-one (5 >= 6 fails) and permits growth, where `== 6` taxes the correct edit.
	## Contrast KNOWN_LLM_NPCS above, which stays `eq` BECAUSE growth there is the regression signal.
	assert_gte(MUST_BUILD.size(), 6,
		"MUST_BUILD holds %d maps, fewer than the 6 this guard makes claims about (5 holding the " % MUST_BUILD.size() +
		"divergent NPCs + Harmonia holding all three LLM-capable ones). A map removed takes its own " +
		"membership check with it; adding one is free.")
	for who in KNOWN_LLM_NPCS:
		assert_true(who in llm_names,
			"CONTROL: %s is an LLM showcase NPC and the walk did not reach them; found %s" % [who, str(llm_names)])

	## This guard exists BECAUSE the two derivations disagree. If they ever stop, it is dead weight
	## and this arm says so instead of quietly passing forever.
	assert_gt(divergent_anywhere.size(), 0,
		"the two id derivations now agree everywhere — unify them for real and DELETE this test, it guards nothing")

	## THE BLIND POPULATION. These reach ConversationRewards.resolve_npc_id (WanderingNPC:487)
	## and expose no get_npc_id, so the comparison above cannot see them at all. Pinned at zero
	## rather than left as a silent short-fall in the walk.
	for node in blind_nodes:
		var dyn = node.get("dynamic")
		if dyn != null and bool(dyn):
			live_blind.append(str(node.get("npc_name")))
	assert_eq(live_blind, [],
		("these are on the LLM reward path and INVISIBLE to this guard: %s. They carry dynamic + " +
		"persona but no get_npc_id, so the two-id comparison above skips them entirely. " +
		"FIX: widen _walk to derive a quest id for them too, or give the class a get_npc_id.") % str(live_blind))
	## ANTI-VACUITY: the arm above is an assertion of ABSENCE, so the walk must be finding
	## candidates at all. Zero here means the collector is broken, not that the game is clean.
	assert_gt(blind_nodes.size(), 0,
		"the walk found no dynamic/persona-bearing node without get_npc_id — it is broken, " +
		"not the tree; WanderingNPC instances exist in the overworld maps")

	assert_eq(two_ids, [],
		("an NPC on the LLM reward path answers to two different ids: %s\n" +
		"The payout still resolves (the table has a `default`), but the CLAIM LEDGER keys under the\n" +
		"reward spelling while everything else uses the quest one — so the claim never sticks.\n" +
		"FIX: give the NPC an explicit `npc_id`, which both derivations return unchanged.") % str(two_ids))
