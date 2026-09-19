extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file leaked state a hand-listed teardown cannot name.
var _ag_state: Dictionary

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GRIND := "res://src/autogrind/AutogrindSystem.gd"
const LIVE := "res://src/battle/BattleManager.gd"

## mourners_ledger says "Its wearer keeps earning EXP while KO'd" and it did nothing in an autogrind.
## Live gates EXP at BattleManager:1023 — `if combatant.is_alive or earns_exp_while_dead(combatant)`
## — and the grind's award sites read a bare `member.is_alive`. So the accessory worked in a manual
## fight and was inert in the mode that runs hundreds of battles, which is the mode where a KO'd
## member misses the most EXP. struktured ruled it 2026-09-06: "they get no exp (unless they have a
## special item or passive)"; the grind did not honour the exception half.
##
## 🔑 THE FIX CALLS LIVE'S PREDICATE RATHER THAN MIRRORING IT. A twin here would be a THIRD copy of
## the equipment slot-walk, and the drift it invites is the exact defect this lane spent the night
## removing from _effect_to_stat. BattleManager owns both halves and resolves PassiveSystem from the
## TREE, which a detached grind Combatant cannot do for itself.

var _saved_persist: bool
var _saved_party: Array
var _saved_region: String


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_saved_persist = AutogrindSystem._test_disable_persistence
	AutogrindSystem._test_disable_persistence = true
	_saved_party = AutogrindSystem.grind_party.duplicate()
	_saved_region = AutogrindSystem.current_region_id
	AutogrindSystem.current_region_id = ""


func after_each() -> void:
	AutogrindSystem.grind_party = _saved_party
	AutogrindSystem.current_region_id = _saved_region
	AutogrindSystem._test_disable_persistence = _saved_persist
	AutogrindState.restore(_ag_state)



func _member(name: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 500, "max_mp": 50,
		"attack": 20, "defense": 20, "magic": 20, "speed": 20})
	add_child_autofree(c)
	c.job_level = 10
	c.job_exp = 0
	c.current_hp = c.max_hp if alive else 0
	c.is_alive = alive
	return c


## EXP actually credited by one grind victory. Level-ups cannot muddy it: job_level 10 needs 1000
## and the award is 100, so the delta stays in job_exp.
func _exp_from_one_victory(member: Combatant) -> int:
	AutogrindSystem.grind_party = [member]
	var before: int = member.job_exp
	AutogrindSystem.on_battle_victory(100, {})
	return member.job_exp - before


func test_the_ledger_is_still_authored_as_this_arm_assumes() -> void:
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var acc: Dictionary = (eq.get("accessories", {}) as Dictionary).get("mourners_ledger", {})
	assert_gt(float((acc.get("special_effects", {}) as Dictionary).get("exp_while_dead", 0.0)), 0.0,
		"mourners_ledger no longer authors exp_while_dead — this whole file is about that key")
	var pas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	var table: Dictionary = pas.get("passives", pas)
	var pc: Dictionary = table.get("posthumous_credit", {})
	assert_gt(float((pc.get("meta_effects", {}) as Dictionary).get("exp_while_dead", 0.0)), 0.0,
		"posthumous_credit no longer carries the meta_effect — the passive arm below needs it")


func test_a_living_member_earns_and_a_plain_corpse_does_not() -> void:
	## ⛔ THE CONTROL PAIR, and without it every arm below is unfalsifiable: "the KO'd wearer earned"
	## reads identically whether the exception works or the grind simply pays everybody.
	var living: int = _exp_from_one_victory(_member("Living", true))
	var corpse: int = _exp_from_one_victory(_member("Corpse", false))
	gut.p("    living %d · KO'd without gear %d" % [living, corpse])
	assert_gt(living, 0, "CONTROL: a living member must earn, or the fixture awards nothing at all")
	assert_eq(corpse, 0, "CONTROL: a KO'd member with no ledger and no passive must still earn NOTHING")


func test_a_mourners_ledger_keeps_a_corpse_earning() -> void:
	var wearer := _member("Wearer", false)
	wearer.equipped_accessory = "mourners_ledger"
	var earned: int = _exp_from_one_victory(wearer)
	gut.p("    KO'd wearing mourners_ledger: %d" % earned)
	assert_gt(earned, 0,
		"a KO'd mourners_ledger wearer earned nothing in a grind — live pays them (BattleManager.earns_exp_while_dead) and the accessory's whole text is that it keeps paying while KO'd")


func test_the_posthumous_credit_passive_does_it_too() -> void:
	## The other half of struktured's ruling — "a special item OR passive". Both reach the same
	## predicate, so wiring only the accessory would honour half a sentence.
	var bearer := _member("Bearer", false)
	bearer.equipped_passives = ["posthumous_credit"] as Array[String]
	var earned: int = _exp_from_one_victory(bearer)
	gut.p("    KO'd with posthumous_credit: %d" % earned)
	assert_gt(earned, 0,
		"a KO'd posthumous_credit bearer earned nothing — the passive half of the 2026-09-06 ruling is not wired")


func test_the_meta_boss_bonus_pays_the_dead_wearer_too() -> void:
	## The second reachable award site. It was the same bare is_alive, and a meta-boss is exactly the
	## fight a party arrives at with someone down.
	var wearer := _member("Wearer", false)
	wearer.equipped_accessory = "mourners_ledger"
	var plain := _member("Plain", false)
	AutogrindSystem.grind_party = [wearer, plain]
	var w0: int = wearer.job_exp
	var p0: int = plain.job_exp
	AutogrindSystem.on_meta_boss_victory({"exp_reward": 100})
	gut.p("    meta-boss — wearer +%d · plain corpse +%d" % [wearer.job_exp - w0, plain.job_exp - p0])
	assert_gt(wearer.job_exp - w0, 0, "the meta-boss bonus skipped a KO'd mourners_ledger wearer")
	assert_eq(plain.job_exp - p0, 0, "CONTROL: the meta-boss bonus must still skip an unequipped corpse")


func test_the_grind_asks_live_rather_than_carrying_its_own_copy() -> void:
	## ⛔ THE ANTI-TWIN ARM. A local reimplementation would pass every arm above and then drift the
	## first time live's predicate changes — which is how this lane's magnitude bug was born.
	var grind: String = GdSource.code_of(GRIND)
	## ⛔ THE RECEIVER DOT IS LOAD-BEARING. This was `contains("earns_exp_while_dead")`, and
	## AutogrindSystem's own wrapper is `func _earns_exp_while_dead(...)` — whose NAME CONTAINS the
	## string. Measured: delete the delegation `bm.earns_exp_while_dead(member)` and keep the wrapper
	## shell, and the bare substring still occurs 4 times, so this arm stayed GREEN.
	##
	## ⚠️ AND THIS IS THE ARM THAT HAS TO WORK ALONE. The behavioural arms DID catch that mutation —
	## but they cannot catch the thing this arm exists for: a local REIMPLEMENTATION behaves
	## correctly, passes every behavioural arm, and drifts the day live's predicate changes. A twin
	## is invisible to behaviour by construction. @cowir-music's `_setup_weather()` shape, with the
	## substring hidden inside a differently-named wrapper rather than its own definition.
	assert_true(grind.contains(".earns_exp_while_dead("),
		"the grind no longer DELEGATES to live's predicate — a bare mention is satisfied by this file's own _earns_exp_while_dead wrapper name")
	assert_false(grind.contains("exp_while_dead\", 0.0"),
		"AutogrindSystem is reading the exp_while_dead KEY itself — that is a second copy of live's slot walk, and the two will disagree the day either moves")
	var live: String = GdSource.code_of(LIVE)
	assert_true(live.contains("func earns_exp_while_dead("),
		"CONTROL: live must still own the predicate this file delegates to")


## ⛔ MY CORPUS WAS ONE FILE, AND THAT IS HOW A FOURTH AWARD SITE SURVIVED THIS GUARD.
## Every arm above reads AutogrindSystem. The per-character EXP attribution for a HEADLESS grind
## lives in GameLoop._resolve_headless_battle, so it kept a bare `is_alive` while this file reported
## the class closed and its own declaration arm named a THIRD site as the last one.
##
## It failed twice over: a mourner was credited nothing, AND the same bare predicate shrank the
## divisor, inflating every living member's share of the same pot.
func test_the_headless_path_credits_a_mourner_too() -> void:
	## Reachability as a CHECK rather than prose — if nothing rosters the passive this is latent and
	## the arm's urgency is stale. `cleric` is a STARTER job, so an ordinary W1 party can carry it.
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_true(jobs is Dictionary, "CONTROL: jobs.json must parse, or the reachability claim is vacuous")
	var cleric_passives: String = str((jobs as Dictionary).get("cleric", {}).get("passive_abilities", []))
	assert_true(cleric_passives.contains("posthumous_credit"),
		"CONTROL: no starter job rosters posthumous_credit any more — this defect is latent, not live, and this arm's framing needs revisiting")

	var gl: String = GdSource.code_of("res://src/GameLoop.gd")
	assert_ne(gl, "", "CONTROL: GameLoop source must survive the comment strip")
	var at: int = gl.find("func _resolve_headless_battle")
	assert_gt(at, -1, "CONTROL: _resolve_headless_battle must exist")
	var stop: int = gl.find("\nfunc ", at + 20)
	var body: String = gl.substr(at, (stop - at) if stop > 0 else -1)
	assert_true(body.contains("track_character_exp"),
		"CONTROL: the per-character attribution must be inside the extracted range, or this arm reads the wrong function")

	assert_true(body.contains("earns_exp_while_dead"),
		("the headless grind attributes EXP by a bare is_alive. A Cleric carrying posthumous_credit " +
		"EARNS that exp — AutogrindSystem's two award sites and BattleManager.earns_exp_while_dead all say so — and " +
		"is credited none here, while the shrunken divisor inflates everyone else's share."))


func test_the_third_award_site_is_still_unreachable() -> void:
	## ⚠️ THE DECLARATION. A third award site exists and did NOT get the exception, deliberately:
	## _process_battle_results is called only by _run_automated_battle, which has NO callers. If
	## someone wires that path up, it starts paying the dead by the OLD rule and this arm says so.
	## ⛔ THE CORPUS WAS THREE HAND-LISTED PATHS FOR A CLAIM ABOUT ALL OF src/, and one of the three
	## ("res://GameLoop.gd") DOES NOT EXIST — guarded by ResourceLoader.exists, so it silently
	## contributed 0 and read as a checked file. A caller added anywhere else was invisible.
	## @cowir-sfx hit the same shape in a guard they had held up as the derived one: a predicate
	## naming receivers under a message claiming a population. Walked now, so a new caller in a new
	## file reds the day it lands.
	var grind: String = GdSource.code_of(GRIND)
	var callers: int = grind.count("_run_automated_battle(") - grind.count("func _run_automated_battle(")
	var elsewhere: int = 0
	var scanned: int = 0
	for path in _src_files():
		if path == GRIND:
			continue
		scanned += 1
		elsewhere += GdSource.code_of(path).count("_run_automated_battle(")
	assert_gt(scanned, 100, "CONTROL: the src walk must reach a real corpus, got %d files" % scanned)
	gut.p("    _run_automated_battle callers — in-file %d · across %d other src files %d" % [callers, scanned, elsewhere])
	assert_eq(callers + elsewhere, 0,
		"_run_automated_battle has a caller now, so its award site is live and still reads a bare is_alive — give it the exception the other two carry")


## Every .gd under res://src, recursively. Same walk as
## test_autogrind_no_invented_key_reaches_the_disk_regression's, rather than a tenth private copy.
func _src_files() -> Array:
	var out: Array = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if str(f).ends_with(".gd"):
				out.append("%s/%s" % [d, str(f)])
	return out
