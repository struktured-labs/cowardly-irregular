extends GutTest

## data/inn_dialogue.json — 11 villages x 7 lines, authored 2026-04-21 and loaded by NOTHING
## until 2026-08-23. Wiring it introduces a second source for text INNKEEPERS already supplies,
## so these pin the precedence (authored wins, generic is the fallback) and pin that the
## 2026-08-22 rest-prompt fix survives whichever source wins.

const InnDialogueScript := preload("res://src/exploration/InnDialogue.gd")
const InnInteriorScript := preload("res://src/maps/interiors/InnInterior.gd")

const VILLAGE_MAP_IDS := [
	"harmonia_village", "eldertree_village", "frosthold_village", "grimhollow_village",
	"ironhaven_village", "sandrift_village", "maple_heights_village", "brasston_village",
	"rivet_row_village", "node_prime_village", "vertex_village",
]

const LINE_KINDS := [
	"greeting", "rest_prompt", "rest_confirm", "rest_complete",
	"save_prompt", "cant_afford", "farewell",
]


func test_the_loader_is_live() -> void:
	var keys: Array = InnDialogueScript.village_keys()
	assert_gt(keys.size(), 5, "loaded %d villages — a 0 means the reader is dead, not that the file is empty" % keys.size())
	assert_true(keys.has("harmonia"), "harmonia is authored in the file; its absence means the parse failed")


func test_every_real_village_resolves() -> void:
	for map_id in VILLAGE_MAP_IDS:
		var entry: Dictionary = InnDialogueScript.lines_for(map_id)
		assert_false(entry.is_empty(), "%s resolves to no inn dialogue" % map_id)


func test_no_authored_village_is_unreachable_from_a_real_map_id() -> void:
	# The other direction: prose that exists but no map_id can reach is still invisible.
	var reachable: Dictionary = {}
	for map_id in VILLAGE_MAP_IDS:
		reachable[InnDialogueScript.village_key(map_id)] = true
	var stranded: Array = []
	for key in InnDialogueScript.village_keys():
		if not reachable.has(key):
			stranded.append(str(key))
	assert_eq(stranded.size(), 0, "authored villages no map_id reaches: %s" % str(stranded))


func test_every_entry_carries_all_seven_line_kinds() -> void:
	for map_id in VILLAGE_MAP_IDS:
		var entry: Dictionary = InnDialogueScript.lines_for(map_id)
		for kind in LINE_KINDS:
			assert_true(entry.has(kind), "%s is missing '%s'" % [map_id, kind])
			assert_ne(str(entry.get(kind, "")), "", "%s has an empty '%s'" % [map_id, kind])


func test_rest_prompt_is_the_only_kind_carrying_a_format_specifier() -> void:
	# A stray %d in a verbatim line crashes the format call; a missing one in rest_prompt
	# silently drops the price. Measured 2026-08-23: exactly one %d, rest_prompt only.
	for map_id in VILLAGE_MAP_IDS:
		var entry: Dictionary = InnDialogueScript.lines_for(map_id)
		for kind in LINE_KINDS:
			var text: String = str(entry.get(kind, ""))
			var want: int = 1 if kind == "rest_prompt" else 0
			assert_eq(text.count("%"), want, "%s/%s carries %d '%%' — expected %d" % [map_id, kind, text.count("%"), want])


func test_cost_line_substitutes_the_live_cost() -> void:
	var out: String = InnDialogueScript.cost_line("harmonia_village", 50)
	assert_ne(out, "", "harmonia authored a rest_prompt, so this must not fall back")
	assert_true(out.contains("50"), "the cost was not substituted into: %s" % out)
	assert_false(out.contains("%d"), "an unsubstituted specifier reached the player: %s" % out)


func test_cost_line_refuses_a_line_it_cannot_substitute() -> void:
	# Degrade to the generic prompt rather than show a half-formatted one.
	assert_eq(InnDialogueScript.cost_line("no_such_village", 50), "", "an unknown village must yield nothing")


func test_two_villages_actually_differ() -> void:
	# Without this, a loader returning one village's entry for every key passes everything above.
	var a: String = InnDialogueScript.line("harmonia_village", "greeting")
	var b: String = InnDialogueScript.line("vertex_village", "greeting")
	assert_ne(a, b, "two villages returned identical greetings — the key lookup is not discriminating")


func test_ambient_lines_are_speaker_prefixed_and_ordered() -> void:
	var lines: Array = InnDialogueScript.ambient_lines("harmonia_village", "Mira")
	assert_eq(lines.size(), 2, "greeting and farewell, in that order")
	for l in lines:
		assert_true(str(l).begins_with("Mira: "), "unprefixed line: %s" % str(l))
	assert_true(str(lines[0]).contains(InnDialogueScript.line("harmonia_village", "greeting")), "greeting must come first")


func test_an_unknown_village_yields_nothing_so_the_caller_falls_back() -> void:
	assert_true(InnDialogueScript.lines_for("not_a_village").is_empty(), "unknown village must resolve empty")
	assert_true(InnDialogueScript.ambient_lines("not_a_village", "X").is_empty(), "and produce no ambient lines")


func test_inn_interior_prefers_the_authored_lines_over_the_generic_ones() -> void:
	var inn = InnInteriorScript.new()
	add_child_autofree(inn)
	var keeper: Dictionary = {"name": "Mira", "lines": ["Mira: generic fallback line"]}
	var got: Array = inn._keeper_lines_for("harmonia_village", keeper)
	assert_eq(got.size(), 2, "authored greeting + farewell should win")
	assert_false(str(got).contains("generic fallback line"), "the generic line survived where authored text exists")


func test_inn_interior_falls_back_without_a_village_origin() -> void:
	# ARM+. Without this the wiring could return authored lines unconditionally and the
	# fallback path would be dead without any test noticing.
	var inn = InnInteriorScript.new()
	add_child_autofree(inn)
	var keeper: Dictionary = {"name": "Mira", "lines": ["Mira: generic fallback line"]}
	var got: Array = inn._keeper_lines_for("", keeper)
	assert_eq(got.size(), 1, "no origin means no authored match, so the generic lines must survive")
	assert_true(str(got[0]).contains("generic fallback line"), "the fallback was lost")


func test_the_rest_prompt_keeps_the_purse_line_whichever_source_wins() -> void:
	# struktured 2026-08-22: "the prompt hid your gold and had no way to say no." Layering
	# authored prose on top must not undo that, so assert the CONTROLS and the purse survive
	# in the authored branch as well as the generic one.
	var inn = InnInteriorScript.new()
	add_child_autofree(inn)
	var authored: String = InnDialogueScript.cost_line("harmonia_village", inn.REST_COST)
	assert_ne(authored, "", "harmonia authors a rest_prompt, so the authored branch is reachable")
	# EVERY purse branch, both text sources. The first version of this test asserted against
	# _rest_prompt_text() alone, which reads live gold and so only ever exercised ONE branch —
	# deleting the [B] from another branch left it green. Mutation found that; this is the fix.
	for origin in ["harmonia_village", ""]:
		for purse in [-1, 0, inn.REST_COST - 1, inn.REST_COST, inn.REST_COST * 10]:
			var text: String = inn._rest_prompt_for(origin, purse)
			assert_true(text.contains("[B]"),
				"no way to say no at purse=%d origin='%s': %s" % [purse, origin, text])
			# The PRICE, not the letter "G": harmonia's authored line spells it "50 gold".
			assert_true(text.contains(str(inn.REST_COST)),
				"the price (%d) is unstated at purse=%d origin='%s': %s" % [inn.REST_COST, purse, origin, text])
			if purse >= 0:
				assert_true(text.contains(str(purse)),
					"the player's purse (%d) is not shown at origin='%s': %s" % [purse, origin, text])
