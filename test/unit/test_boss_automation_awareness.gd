extends GutTest

## Bosses notice when nobody is deciding.
##
## THE GAME'S THESIS is that automation isn't cheating, it's enlightenment —
## and the W1 bosses are faces of the Calibrant, a thing that MEASURES you. A
## boss that can be fought entirely by a rule table and never remarks on it is
## leaving the premise on the table.
##
## THIS WAS ALREADY HALF-AUTHORED AND UNWIRED. Pyrroth's persona reads: "You are
## meta-aware about combat — you know about autobattle and you hold it in
## CONTEMPT. You respect competence; you despise convenience. You will warm up
## to a party that fights you manually..." — and his defeat line is "And THIS is
## why you should have just let the script run." That characterization was
## written to receive a signal that nothing produced. Same shipped-unwired shape
## the fleet found four times this week, in my own lane's data.
##
## DESIGN — a gradient, not a boolean, because the thesis distinguishes:
##   ""           the player is deciding
##   "autobattle" rules were written, the player stepped back but is watching
##   "autogrind"  the player left entirely
## Voltharion is deliberately the inversion: an optimization obsessive APPROVES
## of a well-tuned script. One boss agreeing with you is what stops the feature
## from being five reskins of "how dare you automate".
##
## FIRES ONCE PER BATTLE. An observation lands; a refrain nags. Guarded by a
## combatant meta flag rather than a phase check, so it can't repeat on the
## 66%/33% gates.
##
## FLAVOUR ONLY: automation state reaches taunts and the LLM prompt. It does not
## touch intent selection, ability choice, or any stat — a boss that hit harder
## because you automated would be a balance change wearing a joke's clothes, and
## it would punish the pillar the game is built on.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const CTX := preload("res://src/battle/BossIntentContext.gd")
const BM_SRC: String = "res://src/battle/BattleManager.gd"

const LLM_BOSSES: Array[String] = [
	"chancellor_mordaine", "pyrroth", "glacius", "voltharion", "umbraxis",
]


func _boss_data() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string("res://data/boss_dialogue.json")
	var json := JSON.new()
	assert_eq(json.parse(raw), OK, "boss_dialogue.json must parse")
	return json.data as Dictionary


func _dlg() -> Node:
	var n: Node = get_node_or_null("/root/BossDialogue")
	assert_not_null(n, "BossDialogue autoload must exist")
	return n


# ── Data: every LLM boss reacts, and reacts differently ──────────────────────

func test_all_five_llm_bosses_have_automation_lines() -> void:
	var d: Dictionary = _boss_data()
	for bid in LLM_BOSSES:
		var block: Variant = (d[bid] as Dictionary).get("automation_lines")
		assert_true(block is Dictionary, "'%s' must author automation_lines — it's an LLM-strategy boss with a persona" % bid)
		for tier in ["autobattle", "autogrind"]:
			var lines: Variant = (block as Dictionary).get(tier)
			assert_true(lines is Array and not (lines as Array).is_empty(),
				"'%s' must have at least one '%s' line" % [bid, tier])


func test_every_line_is_nonempty_text() -> void:
	var d: Dictionary = _boss_data()
	for bid in LLM_BOSSES:
		var block: Dictionary = (d[bid] as Dictionary).get("automation_lines", {})
		for tier in ["autobattle", "autogrind"]:
			for line in (block.get(tier, []) as Array):
				assert_gt(str(line).strip_edges().length(), 10,
					"'%s'/%s has a stub line — a boss saying nothing is worse than a boss saying nothing" % [bid, tier])


func test_bosses_do_not_share_automation_lines() -> void:
	# Five distinct voices reacting to one event is the whole point; copy-paste
	# across bosses would make the feature read as a system message.
	var d: Dictionary = _boss_data()
	var seen: Dictionary = {}
	for bid in LLM_BOSSES:
		var block: Dictionary = (d[bid] as Dictionary).get("automation_lines", {})
		for tier in ["autobattle", "autogrind"]:
			for line in (block.get(tier, []) as Array):
				var key: String = str(line)
				assert_false(seen.has(key), "line duplicated between '%s' and '%s': %s" % [bid, seen.get(key, "?"), key])
				seen[key] = bid


func test_voltharion_approves_rather_than_sneers() -> void:
	# The deliberate inversion. If every boss disapproves, the feature is a
	# scold; his persona is optimization-obsessed and should RESPECT a script.
	var d: Dictionary = _boss_data()
	var block: Dictionary = (d["voltharion"] as Dictionary).get("automation_lines", {})
	var joined: String = ""
	for tier in ["autobattle", "autogrind"]:
		for line in (block.get(tier, []) as Array):
			joined += str(line).to_lower() + " "
	var approves: bool = (joined.find("respect") != -1 or joined.find("efficien") != -1
		or joined.find("proud") != -1 or joined.find("finally") != -1 or joined.find("commitment") != -1)
	assert_true(approves,
		"Voltharion must read as APPROVING automation — he is the counterweight that keeps this from being five bosses scolding the player for using the game's central mechanic")


# ── Data-layer getter ────────────────────────────────────────────────────────

func test_getter_returns_a_line_for_each_tier() -> void:
	var dlg: Node = _dlg()
	for bid in LLM_BOSSES:
		for tier in ["autobattle", "autogrind"]:
			assert_false(str(dlg.get_automation_line(bid, tier)).is_empty(),
				"get_automation_line('%s','%s') must resolve" % [bid, tier])


func test_getter_is_silent_for_empty_tier() -> void:
	# "" is the player-is-deciding case and must never produce a line.
	assert_eq(str(_dlg().get_automation_line("pyrroth", "")), "",
		"an empty tier means the player IS deciding — the boss must say nothing")


func test_getter_is_silent_for_unknown_boss_and_tier() -> void:
	var dlg: Node = _dlg()
	assert_eq(str(dlg.get_automation_line("no_such_boss", "autobattle")), "",
		"unknown boss must degrade silently, never crash")
	assert_eq(str(dlg.get_automation_line("pyrroth", "telepathy")), "",
		"unknown tier must degrade silently — not every future tier will be authored")


func test_minibosses_stay_silent_by_design() -> void:
	# The spotlight duels are teaching fights; a boss mocking your automation
	# mid-tutorial fights the lesson. Absence here is a choice, so pin it.
	for mb in ["fighter_skeleton_knight", "mage_prismatic_construct"]:
		assert_eq(str(_dlg().get_automation_line(mb, "autobattle")), "",
			"'%s' is a teaching duel and must NOT comment on automation" % mb)


# ── LLM prompt injection ─────────────────────────────────────────────────────

func _ctx_dict(tier: String) -> Dictionary:
	var c = CTX.new()
	c.boss_id = "pyrroth"
	c.phase = 2
	c.available_intents = ["aggress", "turtle"]
	c.party_automation = tier
	return c.to_dict()


func test_context_defaults_to_not_automated() -> void:
	assert_eq(CTX.new().party_automation, "", "unset must mean the player is deciding")


func test_prompt_omits_block_when_player_is_deciding() -> void:
	var p: String = DP.build_boss_intent("Pyrroth", _ctx_dict(""))
	assert_true(p.find("not choosing their actions") == -1 and p.find("autogrind") == -1,
		"no automation block when the player is present — backward compatible with every existing caller")


func test_prompt_explains_autobattle_rather_than_naming_it() -> void:
	var p: String = DP.build_boss_intent("Pyrroth", _ctx_dict("autobattle"))
	assert_true(p.find("wrote an autobattle script") != -1,
		"the prompt must EXPLAIN the state — a bare token like 'autobattle: true' gives the model nothing to be in character about")
	assert_true(p.find("watching, but not deciding") != -1,
		"the autobattle tier's distinguishing fact is that someone is still present")


func test_prompt_distinguishes_the_two_tiers() -> void:
	var ab: String = DP.build_boss_intent("Pyrroth", _ctx_dict("autobattle"))
	var ag: String = DP.build_boss_intent("Pyrroth", _ctx_dict("autogrind"))
	assert_ne(ab, ag, "the two tiers must produce different prompts — 'watching' and 'gone' deserve different reactions")
	assert_true(ag.find("Nobody is watching") != -1, "autogrind's fact is total absence")
	assert_true(ag.find("being farmed") != -1, "and that the boss is a means to an end")


# ── The flavour-not-balance boundary ─────────────────────────────────────────

func test_automation_does_not_change_available_intents() -> void:
	var manual: Dictionary = _ctx_dict("")
	var farmed: Dictionary = _ctx_dict("autogrind")
	assert_eq(manual["available_intents"], farmed["available_intents"],
		"automation must NEVER alter the intent set — a boss that fought differently because you automated would punish the pillar the game is built on")


func test_source_hook_fires_once_per_battle() -> void:
	var src: String = FileAccess.get_file_as_string(BM_SRC)
	assert_true(src.find("boss_noticed_automation") != -1,
		"the hook must be guarded by a per-combatant meta flag")
	assert_true(src.find("get_automation_line(persona_id, auto_tier)") != -1,
		"the hook must consult the data layer rather than inlining text")


func test_source_autobattle_tier_requires_every_living_pc() -> void:
	var src: String = FileAccess.get_file_as_string(BM_SRC)
	assert_true(src.find("scripted == living") != -1,
		"'autobattle' must require EVERY living PC to be scripted — one manual character means a person is still choosing, and the boss would be lying")
	assert_true(src.find("_get_character_id(member)") != -1,
		"must use the canonical id helper — a hand-rolled derivation would silently never match")
