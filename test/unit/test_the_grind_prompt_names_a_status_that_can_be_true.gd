extends GutTest

## `member_status` carries the status NAME in `value` and `Combatant.has_status` matches it
## literally. The grind prompt named no status ids at all, so the model answered in English.
##
## MEASURED on live llama3, sequential, 20 samples per arm, 0 malformed in either, one intent
## held fixed ("stop grinding if anybody gets frozen or poisoned, and heal whoever is burned"):
##
##     as shipped        41 of 41 member_status conditions named a status has_status() can
##                       never be true for — frozen 18, poisoned 17, burned 6
##     vocabulary in     see test_the_prompt_is_what_was_measured below
##
## `validate_rule` checks only that the value is a NON-EMPTY STRING — the source comment at
## AutogrindSystem:358 records an earlier instance of this same defect, where the console's
## numeric default asked `has_status("0")` on every character forever. The shape was known;
## the missing-vocabulary half was not.
##
## The applicability arm derives its truth from BattleManager rather than re-typing a list,
## because a list typed here is a second copy of the thing it is checking.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const AUTOGRIND_UI := preload("res://src/ui/autogrind/AutogrindUI.gd")

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _grind_prompt() -> String:
	return DP.build_rule_composition("autogrind", "stop if anyone is hurt", [], {})


## Every status id the engine can ever put into `status_effects`, read out of BattleManager's
## own source: the literal `add_status("x")` sites, plus the simple-status match arm that maps
## an authored effect string straight through. Comments are stripped first — one of them names
## `has_status("blind")` in prose, and a corpus that counts prose can never fail.
func _applicable_statuses() -> Array:
	var code: String = GdSource.code_of(BATTLE_MANAGER)
	assert_false(code.is_empty(), "CONTROL: BattleManager's source must be readable")
	var found: Array = []
	var re_lit := RegEx.create_from_string("add_status\\(\"([a-z_0-9]+)\"")
	for m in re_lit.search_all(code):
		if not found.has(m.get_string(1)):
			found.append(m.get_string(1))
	var re_arm := RegEx.create_from_string("\\n\\t*(\"barrier\",[^\\n]*):\\n")
	var arm := re_arm.search(code)
	assert_not_null(arm, "CONTROL: the simple-status match arm must still be findable")
	if arm != null:
		var re_id := RegEx.create_from_string("\"([a-z_]+)\"")
		for m in re_id.search_all(arm.get_string(1)):
			if not found.has(m.get_string(1)):
				found.append(m.get_string(1))
	assert_gt(found.size(), 15, "CONTROL: the derived set must be a real corpus, not a few strays")
	return found


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_grind_prompt_names_the_status_ids() -> void:
	## THE ARM. Before the fix this prompt contained no status id whatsoever.
	var p: String = _grind_prompt()
	var at: int = p.find("STATUS IDS")
	assert_gt(at, -1, "the grind prompt must name the status ids it asks for")
	for id in DP.AUTOGRIND_STATUS_VOCABULARY.keys():
		assert_true(p.substr(at).find(str(id)) != -1, "it must name %s" % id)


func test_it_says_an_english_word_is_never_true() -> void:
	## The three the model actually emitted. Naming the ids without saying the near-misses
	## are wrong leaves `poisoned` looking like a reasonable spelling of `poison`.
	var p: String = _grind_prompt()
	for word in ["frozen", "poisoned", "burned"]:
		assert_true(p.find(word) != -1, "the prompt must warn against %s by name" % word)


func test_every_id_offered_is_one_has_status_can_be_true_for() -> void:
	## THE RATCHET. `slow` is the shape this defends: it reads like a status, the console
	## offers it, BattleScene has an icon for it — and nothing ever calls add_status("slow").
	## The slowdown is an add_debuff("Slow", "speed", ...) entry in a DIFFERENT container,
	## which has_status cannot see.
	var applicable: Array = _applicable_statuses()
	var unreachable: Array = []
	for id in DP.AUTOGRIND_STATUS_VOCABULARY.keys():
		if not applicable.has(str(id)):
			unreachable.append(str(id))
	assert_eq(unreachable, [],
		"these are offered to the model and can never be true: %s" % str(unreachable))


func test_the_prompt_renders_the_constant_rather_than_a_copy() -> void:
	## Two lists is the drift shape this codebase has fixed repeatedly. The grammar points
	## at the vocabulary; only one place spells it.
	var p: String = _grind_prompt()
	for id in DP.AUTOGRIND_STATUS_VOCABULARY.keys():
		assert_true(p.find("%s   for %s" % [str(id), ", ".join(DP.AUTOGRIND_STATUS_VOCABULARY[id])]) != -1,
			"the rendered row must be the constant's own pair for %s" % id)


# ── the console and the model must not learn different vocabularies ───────────

func test_every_id_offered_is_one_the_console_also_offers() -> void:
	## One vocabulary for both authoring routes. A player cycling the console ring and a
	## player asking the composer must not end up with different sets of legal statuses.
	##
	## ONE-DIRECTIONAL BY INTENT: the ring holds one entry this list does not — `slow`,
	## which can never be true. That is AutogrindUI's to remove and is reported, not
	## asserted here, because a red arm in someone else's file is a worse handover than a
	## message. The direction that IS asserted is the one this file can be wrong about.
	var ring: Array = AUTOGRIND_UI.MEMBER_STATUS_RING
	var absent: Array = []
	for id in DP.AUTOGRIND_STATUS_VOCABULARY.keys():
		if not ring.has(str(id)):
			absent.append(str(id))
	assert_eq(absent, [],
		"the prompt offers ids the console ring does not: %s" % str(absent))


# ── controls ──────────────────────────────────────────────────────────────────

func test_an_autobattle_composition_does_not_get_this_block() -> void:
	## Autobattle conditions carry their own status vocabulary through a different editor;
	## this block is the grind grammar's, and must not leak into the per-character prompt.
	var p: String = DP.build_rule_composition("autobattle", "burn things", [],
		{"resolved": true, "job_id": "mage", "kit": ["fire"], "full_kit": ["fire"],
		"max_mp": 70, "costs": {"fire": 8}})
	assert_true(p.find("STATUS IDS") == -1, "the grind status block must not reach autobattle")


func test_the_grammar_still_asks_for_a_status_name() -> void:
	## This guard's own premise. If member_status stops carrying a name, every arm above is
	## defending a requirement that no longer exists.
	var p: String = _grind_prompt()
	assert_true(p.find("member_status") != -1, "the grind grammar must still offer member_status")
	assert_true(p.find("the status NAME in \"value\"") != -1,
		"and must still say the value is a name")
