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


## The session bar used to be a second ledger in GameLoop: battle EXP divided by the earner count,
## written before the payer applied yield and the time bonus. A party of four who each gained 100
## was shown +25. Putting that ledger back double-counts, because the payer now records the grant.
func test_the_headless_path_credits_a_mourner_too() -> void:
	## Reachability as a CHECK rather than prose — if nothing rosters the passive this is latent and
	## the arm's urgency is stale. `cleric` is a STARTER job, so an ordinary W1 party can carry it.
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_true(jobs is Dictionary, "CONTROL: jobs.json must parse, or the reachability claim is vacuous")
	var cleric_passives: String = str((jobs as Dictionary).get("cleric", {}).get("passive_abilities", []))
	assert_true(cleric_passives.contains("posthumous_credit"),
		"CONTROL: no starter job rosters posthumous_credit any more — this defect is latent, not live, and this arm's framing needs revisiting")

	var body := _fn_body("res://src/GameLoop.gd", "func _resolve_headless_battle")
	assert_false(body.is_empty(), "CONTROL: _resolve_headless_battle must exist")
	assert_false(body.contains("exp_gained / earners.size()"),
		"the headless grind divides battle EXP by the earner count. Each earner is paid the full amount.")
	assert_false(body.contains("track_character_exp"),
		"the headless path records per-character EXP itself, so the bar is a second ledger beside the amount paid")

	var pay := _fn_body(GRIND, "func on_battle_victory")
	assert_true(pay.contains("gain_job_exp(adjusted_exp)"),
		"CONTROL: on_battle_victory must still pay adjusted_exp, or this arm is reading the wrong function")
	assert_true(pay.contains("_earns_exp_while_dead(member)"),
		"the victory payout dropped the mourner predicate, so a KO'd Cleric with posthumous_credit is paid nothing")
	assert_true(pay.contains("track_character_exp(member.combatant_name, adjusted_exp)"),
		"the session bar must record the EXP each earner was paid, yield and time bonus included")


## The visual grind is a different function from the headless one, and it kept its own copy of the
## divided ledger. A watched boss fight never reaches on_battle_victory, so its bar has to be
## written where that fight's EXP and its bonus are accounted.
func test_the_live_visual_path_credits_a_mourner_too() -> void:
	var body := _fn_body("res://src/GameLoop.gd", "func _on_autogrind_battle_ended")
	assert_false(body.is_empty(), "CONTROL: _on_autogrind_battle_ended must exist")
	assert_false(body.contains("func _resolve_headless_battle"),
		"CONTROL: the slice must not include the headless function, or a fixed sibling greens a live bug")
	assert_false(body.contains("exp_gained / earners.size()"),
		"the visual grind divides battle EXP by the earner count. The portrait line and the Summary both read that share.")
	assert_false(body.contains("track_character_exp"),
		"the visual path records per-character EXP itself, so the bar is a second ledger beside the amount paid")
	assert_false(body.contains("alive_count"),
		"the visual path still sizes the EXP divisor from the living count alone")
	var boss := _fn_body(GRIND, "func account_boss_fight_rewards")
	assert_true(boss.contains("_earns_exp_while_dead(member)"),
		"CONTROL: the boss-fight ledger must use the same mourner predicate as the payout")
	assert_true(boss.contains("track_character_exp(member.combatant_name, exp_gained)"),
		"a boss fight's own EXP never reached the session bar, or reached it as a share of the pot")
	var bonus := _fn_body(GRIND, "func on_meta_boss_victory")
	assert_true(bonus.contains("track_character_exp(member.combatant_name, bonus_exp)"),
		"the meta-boss bonus is paid to each earner and was missing from the session bar")


## The session bar and the Summary read per_character_exp. on_battle_victory pays every earner the
## FULL battle amount (yield and time bonus included). The bar used to store that amount divided by
## the earner count, so a party of four who each gained 100 job EXP was shown +25, and a mourner
## who was left out of the count made everyone else's line larger still.
func test_the_nameplate_shows_the_exp_each_character_was_paid() -> void:
	AutogrindSystem.current_region_id = ""
	AutogrindSystem.is_grinding = false
	AutogrindSystem._grind_stats["elapsed_seconds"] = 0.0
	AutogrindSystem._grind_stats["start_time"] = 0.0
	AutogrindSystem.per_character_exp.clear()
	var living := _member("Living", true)
	var wearer := _member("Wearer", false)
	wearer.equipped_accessory = "mourners_ledger"
	var corpse := _member("Corpse", false)
	AutogrindSystem.grind_party = [living, wearer, corpse]
	AutogrindSystem.on_battle_victory(100, {})
	gut.p("    paid living %d · mourner %d · corpse %d · bar %s" % [
		living.job_exp, wearer.job_exp, corpse.job_exp, str(AutogrindSystem.per_character_exp)])
	assert_eq(living.job_exp, 100,
		"CONTROL: with no region yield and no time bonus the grant is the battle's 100 EXP")
	assert_eq(wearer.job_exp, living.job_exp,
		"CONTROL: a KO'd mourner is paid the same full amount, not a share")
	assert_eq(corpse.job_exp, 0,
		"CONTROL: a KO'd member with no ledger still earns nothing")
	assert_eq(int(AutogrindSystem.per_character_exp.get("Living", -1)), living.job_exp,
		"the session bar showed %s for Living, who gained %d job EXP" % [
			str(AutogrindSystem.per_character_exp.get("Living", 0)), living.job_exp])
	assert_eq(int(AutogrindSystem.per_character_exp.get("Wearer", -1)), wearer.job_exp,
		"the session bar showed %s for the mourner, who gained %d job EXP" % [
			str(AutogrindSystem.per_character_exp.get("Wearer", 0)), wearer.job_exp])
	assert_false(AutogrindSystem.per_character_exp.has("Corpse"),
		"a corpse who was paid nothing must not appear on the EXP line")


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


## Code of one function, comments stripped. Empty when the signature is absent.
func _fn_body(path: String, signature: String) -> String:
	var src: String = GdSource.code_of(path)
	var at: int = src.find(signature)
	if at < 0:
		return ""
	var stop: int = src.find("\nfunc ", at + signature.length())
	return src.substr(at, (stop - at) if stop > 0 else -1)


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
