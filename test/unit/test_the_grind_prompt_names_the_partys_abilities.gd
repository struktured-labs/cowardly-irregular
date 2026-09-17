extends GutTest

## The autogrind grammar asks `member_ability` for "an ability id that member knows".
## The prompt named no abilities at all: `RuleComposer` built `kit_context` only for
## DOMAIN_AUTOBATTLE, so the grind composition got `{}` and rendered an empty kit block.
##
## MEASURED on live llama3, sequential, 20 samples per arm, 0 malformed in either, one
## intent held fixed ("if the mage is dead have the cleric cast a revive on them, and
## have the cleric heal whoever is hurt between fights"):
##
##     as shipped        24 of 24 member_ability actions named an id absent from
##                       abilities.json — `revive` and `heal` for the real
##                       `raise` and `cure`
##     party kit in      1 of 23
##
## The engine does not reject an unknown id: `AutogrindSystem` prints
## "[AUTOGRIND] member_ability skipped" to stdout and moves on. So a player's rule
## was accepted, saved, shared as a COWIR1: code, and silently never fired.
##
## Both halves are pinned here because either alone restores the defect: the composer
## must GATHER the party's kits, and the prompt must FORMAT them.

const RC := preload("res://src/llm/RuleComposer.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")

const STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

## The replay backend discards the prompt it is handed. This keeps it, so the
## routing arm can ask what actually reached the model rather than rebuilding it.
const CAPTURING_BACKEND := """
extends "res://tools/replay_backend.gd"
var last_prompt: String = ""
func submit(id: String, _prompt: String, _opts: Dictionary = {}) -> void:
	last_prompt = _prompt
	super.submit(id, _prompt, _opts)
"""

var _stub: Node = null
var _svc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	## Never shadow a real GameLoop: with one in the tree this file would measure it
	## instead, and the stub would be the two-writers class.
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no real GameLoop may be in the tree when this file runs")


func after_each() -> void:
	_remove_replay_backend()
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
	_stub = null


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


## Named after the job so character_id resolves to the job id, the same path
## get_deep_check_kit(<job>) takes.
func _member(job_id: String, level: int) -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.combatant_name = job_id.capitalize()
	c.job = JobSystem.get_job(job_id)
	c.job_level = level
	return c


func _party_of(jobs: Array) -> void:
	var script := GDScript.new()
	script.source_code = STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	var members: Array = []
	for j in jobs:
		members.append(_member(str(j), 1))
	_stub.party = members
	get_tree().root.add_child(_stub)


func _ctx_for(jobs: Array) -> Dictionary:
	_party_of(jobs)
	return _rc()._party_kit_context()


func _grind_prompt(ctx: Dictionary) -> String:
	return DP.build_rule_composition("autogrind", "heal between fights", [], ctx)


## Only the per-member roster lines. A whole-prompt search cannot answer "is this id
## OFFERED" — the grammar's own prose carries ids, and the block's closing sentence
## ends "that rule never fires", which a substring search for `fire` matches.
## Anchored on the two most stable strings in the block — its own heading and the sentence
## that closes it. An earlier version keyed on the heading's WORDING and went stale the day
## the block gained its between-battle lines, reding three arms that were all still correct.
func _roster(p: String) -> String:
	var at: int = p.find("PARTY KITS.")
	if at == -1:
		return ""
	var end: int = p.find("member_ability's \"ability\" MUST come from", at)
	return p.substr(at, end - at) if end > at else p.substr(at)


## Ids are printed as `<id> (N MP)`, so the trailing paren is the word boundary.
func _offers(p: String, id: String) -> bool:
	return _roster(p).find("%s (" % id) != -1


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_grind_composition_names_the_ability_ids_it_asks_for() -> void:
	## THE ARM. Before the fix this prompt contained no ability id whatsoever.
	var ctx: Dictionary = _ctx_for(["mage", "cleric"])
	assert_true(bool(ctx.get("resolved", false)),
		"CONTROL: the party kit must resolve, or this file measures nothing")
	var p: String = _grind_prompt(ctx)
	assert_true(_offers(p, "cure"), "the cleric's heal must be named: the intent asks for one")
	assert_true(_offers(p, "fire"), "and the mage's attack spell")


func test_each_id_is_listed_under_the_member_who_knows_it() -> void:
	## member_ability carries BOTH a member and an ability; a flat id list would pass
	## the arm above while still letting the model hand the mage's fire to the cleric.
	var p: String = _grind_prompt(_ctx_for(["mage", "cleric"]))
	var mage_at: int = p.find("mage [mage]:")
	var cleric_at: int = p.find("cleric [cleric]:")
	assert_gt(mage_at, -1, "the mage must have its own line")
	assert_gt(cleric_at, -1, "and the cleric its own")
	var mage_line: String = p.substr(mage_at, p.find("\n", mage_at) - mage_at)
	var cleric_line: String = p.substr(cleric_at, p.find("\n", cleric_at) - cleric_at)
	assert_true(mage_line.find("fire") != -1, "fire belongs to the mage: %s" % mage_line)
	assert_true(cleric_line.find("fire") == -1, "and not to the cleric: %s" % cleric_line)
	assert_true(cleric_line.find("cure") != -1, "cure belongs to the cleric: %s" % cleric_line)


func test_the_ids_come_from_the_party_not_from_a_list_here() -> void:
	## A different party must produce a different block. A hardcoded roster passes
	## every arm above and fails this one.
	var p: String = _grind_prompt(_ctx_for(["rogue"]))
	assert_true(_offers(p, "steal"), "a rogue-only party must offer the rogue's kit")
	assert_false(_offers(p, "fire"), "and must not offer a spell nobody in it knows")
	assert_false(_offers(p, "cure"), "nor a heal nobody in it knows")


func test_the_stated_mp_cost_is_the_kits_own_number() -> void:
	## The block prints "N MP" per id, and the grind rules are guarded on MP. A
	## constant here would read correct and mis-guard every rule.
	var ctx: Dictionary = _ctx_for(["cleric"])
	var entry: Dictionary = (ctx.get("party", []) as Array)[0]
	var costs: Dictionary = entry.get("costs", {})
	assert_true(costs.has("cure"), "CONTROL: the kit must carry cure's cost")
	var p: String = _grind_prompt(ctx)
	assert_true(p.find("cure (%d MP)" % int(costs["cure"])) != -1,
		"the printed cost must be the kit's own: expected cure (%d MP)" % int(costs["cure"]))


# ── why this guard exists: the grammar makes the promise ──────────────────────

func test_the_grammar_still_asks_for_an_id_the_member_knows() -> void:
	## This arm is the guard's own premise. If the grammar stops asking for an ability
	## id, everything above is defending a requirement that no longer exists — and a
	## reword should red here rather than leave four green arms guarding nothing.
	var p: String = _grind_prompt(_ctx_for(["cleric"]))
	assert_true(p.find("member_ability") != -1, "the grind grammar must still offer member_ability")
	assert_true(p.find("ability id that member knows") != -1,
		"and must still promise the model that the id is one the member knows")


# ── controls ──────────────────────────────────────────────────────────────────

func test_no_party_renders_no_block_and_does_not_crash() -> void:
	## Headless, tests, and the console opened outside a run. An unresolved context
	## must render nothing rather than an empty heading the model would answer.
	var p: String = _grind_prompt({})
	## Match the HEADING, not the phrase: the prompt may legitimately mention the block by
	## name elsewhere, and a bare substring turns that prose into a failure.
	assert_true(p.find("PARTY KITS.") == -1, "an empty context must render no kit heading")
	assert_gt(p.length(), 500, "CONTROL: the rest of the prompt must still be built")


func test_an_autobattle_composition_is_untouched() -> void:
	## The per-character block is a different measured change; this one must not
	## reach it, and must not double-render on top of it.
	var p: String = DP.build_rule_composition("autobattle", "burn things", [],
		{"resolved": true, "job_id": "mage", "kit": ["fire"], "full_kit": ["fire"],
		"max_mp": 70, "costs": {"fire": 8}})
	assert_true(p.find("Ability ids you may use, and NOTHING else") != -1,
		"CONTROL: the per-character kit block must still render for autobattle")
	assert_true(p.find("PARTY KITS.") == -1, "and the party block must not appear beside it")


# ── the other half: the composer must GATHER it ───────────────────────────────

func _install_replay_backend(reply: String) -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	var script := GDScript.new()
	script.source_code = CAPTURING_BACKEND
	script.reload()
	_backend = Node.new()
	_backend.set_script(script)
	_backend.name = "CapturingBE"
	_backend.next_text = reply
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func _remove_replay_backend() -> void:
	if _backend == null or not is_instance_valid(_backend):
		return
	_backend.request_finished.disconnect(_svc._on_backend_finished)
	_svc.remove_child(_backend)
	_backend.free()
	_backend = null
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


func test_a_real_grind_composition_sends_the_roster_to_the_model() -> void:
	## Every arm above hands the kit context in by hand, so all seven stay green
	## if compose_async stops building one — which IS the shipped defect, in the
	## half that produced it. This drives the real path and asks the backend what
	## it was actually given.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	_party_of(["mage", "cleric"])
	_install_replay_backend(JSON.stringify(
		{"name": "n", "description": "d", "rules_json": "[]"}))
	await rc.compose_async("autogrind", "heal between fights", "", [])
	var sent: String = str(_backend.last_prompt)
	assert_false(sent.is_empty(), "CONTROL: a prompt must have reached the backend")
	assert_true(_offers(sent, "cure"),
		"the composer must gather the party's kit, not just be capable of formatting one")
	assert_true(_offers(sent, "fire"), "for every member, not only the first")
