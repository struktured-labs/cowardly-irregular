extends GutTest

## Quest rewards (gold/EXP/items) were granted in TOTAL silence —
## _grant_rewards mutated state with no announcement or SFX of any
## kind. Completion dialogue now ends with "Received: …" + the
## item_obtain chime. These tests drive _grant_rewards directly and
## inspect the stashed summary line.

var _saved_gold: int


func before_each() -> void:
	_saved_gold = GameState.party_gold
	QuestSystem._last_reward_summary = ""


func after_each() -> void:
	GameState.party_gold = _saved_gold
	QuestSystem._last_reward_summary = ""


func test_exp_grant_uses_the_real_combatant_method() -> void:
	# Review find 2026-07-02: the grant called member.gain_exp behind a
	# has_method guard — that method never existed (it's gain_job_exp),
	# so quest EXP was silently never awarded while the completion line
	# ANNOUNCED it. The announcement is also gated on an actual grant.
	var src: String = FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	assert_true(src.contains("gain_job_exp(exp_total)"),
		"quest EXP must go through Combatant.gain_job_exp")
	assert_false(src.contains("member.gain_exp(exp_total)"),
		"the phantom gain_exp call must not return")
	var idx: int = src.find("var exp_granted")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("if exp_granted:"),
		"the EXP announcement must be gated on an actual grant")
	# And the real method exists on Combatant — the guard can't lie again.
	var c := Combatant.new()
	assert_true(c.has_method("gain_job_exp"))
	c.free()


func test_gold_reward_builds_summary() -> void:
	QuestSystem._grant_rewards({"rewards": {"gold": 200}})
	assert_eq(QuestSystem._last_reward_summary, "Received: 200 gold.")
	assert_eq(GameState.party_gold, _saved_gold + 200, "gold must actually land too")


func test_empty_rewards_stay_silent() -> void:
	QuestSystem._grant_rewards({"rewards": {}})
	assert_eq(QuestSystem._last_reward_summary, "",
		"no rewards → no announcement line (word_from_capital is zero-reward BY DESIGN)")


func test_item_names_resolve_through_item_system() -> void:
	# unwritten_chord is a real authored quest reward — its display
	# name (not the snake_case id) must appear.
	var display: String = QuestSystem._item_display_name("unwritten_chord")
	assert_false(display.contains("_"), "item ids must render as display names, got: %s" % display)
	assert_true(display.length() > 0)


func test_consume_fetch_removes_traded_items() -> void:
	# Story ruling 2026-07-02: `"consume": true` on a fetch objective
	# trades the item away at completion (thirty_seven's returned
	# book); default (absent) keeps it (memento shape). Source pins —
	# behavioral coverage needs a live GameLoop party.
	var src: String = FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	var idx: int = src.find("obj.get(\"consume\", false)")
	assert_gt(idx, -1, "fetch consumption must be opt-in with a FALSE default")
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("remove_item"),
		"consume fetches must remove the traded items from the holder")


func test_final_fetch_hands_quest_id_back_for_presentation() -> void:
	# A quest ENDING on a fetch completes inside notify_talk's
	# opportunistic check — the id must be returned so the caller
	# presents completion + rewards (they landed silently before).
	# Latent: no W1 quest ends on a fetch yet. Source pin.
	var src: String = FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	var idx: int = src.find("_fetch_satisfied(obj)")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 500)
	assert_true(window.contains("get_state(qid) == \"complete\""),
		"opportunistic fetch completion must detect quest completion")
	assert_true(window.contains("return qid"),
		"...and hand the id back for completion presentation")


func test_dialogue_shaping_reads_own_portrait_key() -> void:
	# Copy-paste slip: the portrait field read l.get("theme") — any
	# authored "portrait" on a quest line was silently eaten. Latent
	# (no data authored it yet) but exactly the silent-failure class:
	# story would have written portraits that never render.
	var src: String = FileAccess.get_file_as_string("res://src/quests/QuestSystem.gd")
	var idx: int = src.find("\"portrait\": l.get(")
	assert_gt(idx, -1, "line shaping must set a portrait")
	var window: String = src.substr(idx, 60)
	assert_true(window.contains("l.get(\"portrait\""),
		"portrait must read its OWN key (theme stays the fallback)")


func test_announce_consumes_the_summary_once() -> void:
	QuestSystem._last_reward_summary = "Received: 5 gold."
	# _announce_rewards plays dialogue (needs an npc node) — use a bare
	# Node2D shell; NPCDialogue attaches to it.
	var shell := Node2D.new()
	add_child_autofree(shell)
	QuestSystem._announce_rewards(shell)
	assert_eq(QuestSystem._last_reward_summary, "",
		"summary must clear on announce so it can't replay on the next quest")


## _item_display_name was a FOURTH partial copy of ItemNameResolver — ItemSystem step only,
## blind to abilities and equipment. Both ids below are absent from items.json AND have a real
## name that differs from the pretty-cased fallback, so a pass cannot come from falling through.
func test_reward_names_resolve_through_the_shared_resolver() -> void:
	assert_true(ItemSystem.get_item("thiefs_glove").is_empty(),
		"control: thiefs_glove must NOT be in items.json, else this proves nothing about the "
		+ "equipment step")
	assert_eq(QuestSystem._item_display_name("thiefs_glove"), "Thief's Glove",
		"an EQUIPMENT reward must announce its equipment.json name. The pretty-cased fallback "
		+ "gives 'Thiefs Glove' — the apostrophe is what separates 'the resolver ran' from "
		+ "'it fell through', and hp_amulet/iron_sword would pass BOTH ways")

	assert_true(ItemSystem.get_item("press_the_edge").is_empty(),
		"control: press_the_edge must NOT be in items.json")
	assert_eq(QuestSystem._item_display_name("press_the_edge"), "Press the Edge",
		"an ABILITY reward must announce its abilities.json name; the fallback capitalises "
		+ "every word and gives 'Press The Edge'")

	## The common path must not regress — a consumable still resolves through step 1.
	assert_eq(QuestSystem._item_display_name("potion"), "Potion")
	## And an id no autoload knows still prettifies rather than returning empty.
	assert_eq(QuestSystem._item_display_name("zzz_unknown_thing"), "Zzz Unknown Thing")
