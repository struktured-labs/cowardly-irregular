extends GutTest

## A conversation reward is keyed by a DERIVED id, so the key appears NOWHERE in src/ and a rename
## degrades the payout silently. `ConversationRewards.resolve_npc_id` slugs an NPC's DISPLAY NAME
## when it carries no explicit id — and village NPCs never carry one, because `_create_npc` sets
## `npc_name` and `npc_type` only. So:
##
##   "Guard Boris"  (HarmoniaVillage:559)  --slug-->  guard_boris  --> 60 gold + 2 potions
##   rename him to anything at all         --slug-->  guard_boris_the_gatekeeper
##   _entry_for misses, falls back to `default`       40 gold, no items, NO WARNING
##
## ⛔ WHICH IS WHY THIS FILE EXISTS RATHER THAN A GREP. I went looking for `guard_boris` in src/ and
## found ONE hit in the whole repo — his own reward entry — and nearly reported an unearnable reward
## for an NPC that does not exist. He exists; nothing SPELLS his id, because the id is computed at
## runtime from a string a writer is free to edit. A derived key has no spelling to grep for, and the
## only instrument is to derive it the same way the consumer does.
##
## 🔑 THE NAME SET IS AN ACCEPTANCE SET, so it is read through GdSource: prose in a village script
## naming `_create_npc("Guard Nobody", ...)` as an example would WIDEN what this guard accepts and a
## genuinely dead reward key would pass. Planted and measured (see the arm below) rather than assumed
## — @cowir-ai's identical guard was fooled by exactly that this hour, with a private stripper.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const REWARDS := "res://data/conversation_rewards.json"
const PERSONAS := "res://data/cutscenes/npc_showcase_personas.json"
const SRC_DIR := "res://src"
const MIN_NPC_NAMES := 100


## Every NPC display name src/ authors, comment- and docstring-stripped.
func _npc_names() -> Array[String]:
	var out: Array[String] = []
	var created := RegEx.create_from_string('_create_npc\\(\\s*"([^"]+)"')
	var assigned := RegEx.create_from_string('npc_name\\s*=\\s*"([^"]+)"')
	var in_dict := RegEx.create_from_string('"npc_name"\\s*:\\s*"([^"]+)"')
	var stack: Array[String] = [SRC_DIR]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append("%s/%s" % [dir, sub])
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var code: String = GdSource.code_of("%s/%s" % [dir, f])
			for rx in [created, assigned, in_dict]:
				for m in rx.search_all(code):
					var name: String = m.get_string(1)
					if not out.has(name):
						out.append(name)
	return out


## The runtime's own slug, never a reimplementation of it: the consumer decides what the key is.
func _slug(npc_name: String) -> String:
	return ConversationRewards.resolve_npc_id("", npc_name)


func _rewards() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REWARDS))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse" % REWARDS)
	return parsed


func test_the_name_corpus_is_real_and_survives_stripping() -> void:
	var names: Array[String] = _npc_names()
	assert_gt(names.size(), MIN_NPC_NAMES, "CONTROL: only %d NPC display names found in src/" % names.size())
	for expected in ["Elder Theron", "Guard Boris"]:
		assert_true(names.has(expected),
			"CONTROL: %s is authored in src/ and must survive the comment strip, or every verdict here is over-stripping" % expected)


func test_every_bespoke_reward_still_reaches_its_npc() -> void:
	## ⛔ THE ARM. A key that no living NPC slugs to pays `default` instead, with no warning anywhere.
	var slugs: Array[String] = []
	for name in _npc_names():
		slugs.append(_slug(name))
	var orphaned: Array[String] = []
	for key in (_rewards().get("by_npc", {}) as Dictionary):
		if not slugs.has(str(key)):
			orphaned.append(str(key))
	assert_eq(orphaned, ([] as Array[String]),
		"these bespoke rewards reach no NPC — a rename changes the slug and the payout silently drops to `default`: %s" % [orphaned])


func test_a_bespoke_reward_is_worth_more_than_the_default() -> void:
	## Makes the arm above a claim about the PLAYER rather than about a dictionary: if a bespoke entry
	## matched the default there would be nothing to lose, and no reason to guard the key.
	var table: Dictionary = _rewards()
	var default_gold: int = int((table.get("default", {}) as Dictionary).get("gold", 0))
	assert_gt(default_gold, 0, "CONTROL: the default reward must pay something")
	var same: Array[String] = []
	for key in (table.get("by_npc", {}) as Dictionary):
		var entry: Dictionary = (table["by_npc"] as Dictionary)[key]
		var gold: int = int(entry.get("gold", 0))
		var items: Array = entry.get("items", [])
		if gold == default_gold and items.is_empty():
			same.append(str(key))
	assert_eq(same, ([] as Array[String]), "a bespoke entry identical to the default is not bespoke: %s" % [same])


func test_every_showcase_persona_names_a_living_npc() -> void:
	## The same derived-key hazard one file over: npc_showcase_personas.json is keyed by DISPLAY NAME,
	## so a rename orphans the persona too — and an NPC with no persona falls back to scene defaults,
	## which is the bug OverworldNPC:46 records as already having shipped once.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse" % PERSONAS)
	var names: Array[String] = _npc_names()
	var checked := 0
	var orphaned: Array[String] = []
	for key in (parsed as Dictionary):
		if str(key).begins_with("_") or str(key) == "version":
			continue
		checked += 1
		if not names.has(str(key)):
			orphaned.append(str(key))
	assert_gt(checked, 2, "CONTROL: only %d showcase personas read" % checked)
	assert_eq(orphaned, ([] as Array[String]),
		"a showcase persona keyed to a name no NPC carries falls back to scene defaults: %s" % [orphaned])


func test_the_reward_and_persona_tables_name_the_same_npcs() -> void:
	## Two tables keyed off one derived identity, which CLAUDE.md's rule for redundant sources says to
	## join with an AGREEMENT assertion rather than a precedence rule. A showcase NPC with a persona
	## and no bespoke reward (or the reverse) is a half-finished promotion, not a design choice.
	var personas: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
	var persona_slugs: Array[String] = []
	for key in (personas as Dictionary):
		if not (str(key).begins_with("_") or str(key) == "version"):
			persona_slugs.append(_slug(str(key)))
	var reward_keys: Array[String] = []
	for key in (_rewards().get("by_npc", {}) as Dictionary):
		reward_keys.append(str(key))
	assert_gt(persona_slugs.size(), 2, "CONTROL: the persona table must be populated")
	var only_persona: Array = persona_slugs.filter(func(s): return not reward_keys.has(s))
	var only_reward: Array = reward_keys.filter(func(s): return not persona_slugs.has(s))
	assert_eq(only_persona, [], "these NPCs have a showcase persona and no bespoke reward: %s" % [only_persona])
	assert_eq(only_reward, [], "these NPCs have a bespoke reward and no showcase persona: %s" % [only_reward])
