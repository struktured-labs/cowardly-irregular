extends GutTest

## A Guardian left on autobattle did NOTHING, every turn, for the whole fight.
##
## Guardian Default's second rule is `not_has_buff defense AND mp_percent >= 10 -> iron_guard`.
## `iron_guard` is a brass_golem ability; no player job has it, so BattleManager refuses it at
## can_use_ability and logs "can't use Iron Guard right now". The turn is consumed — and because
## the cast never happened, the defense buff never lands, so the SAME rule matches again next turn.
## First match wins, so taunt, protect and the attack fallback beneath it were unreachable forever.
##
## The fix is in the ladder, not the authoring: a rule whose every action is an ability the
## character cannot know is not a match, so evaluation falls through. Scoped to knows_ability — a
## STRUCTURAL impossibility. Transient blocks (MP, silence) still match, so authored priority holds
## and the log still names the reason. Which in-kit ability should replace iron_guard is a design
## call routed out; this file does not assume the answer, and stays green either way.

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []

const UNKNOWN_RULE := {
	"conditions": [{"type": "not_has_buff", "stat": "defense"}, {"type": "mp_percent", "op": ">=", "value": 10}],
	"actions": [{"type": "ability", "id": "iron_guard", "target": "self"}]
}


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_p_backup = _bm.player_party.duplicate()
		_e_backup = _bm.enemy_party.duplicate()
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		for c in _p_backup:
			_bm.player_party.append(c)
		for c in _e_backup:
			_bm.enemy_party.append(c)
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _guardian(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 400, "max_mp": 80,
		"attack": 20, "defense": 30, "magic": 20, "speed": 12
	})
	c.job = JobSystem.get_job("guardian")
	c.job_level = 10
	add_child_autofree(c)
	return c


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({
		"name": "Pinned Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


func _arm(g: Combatant, foe: Combatant) -> String:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(g)
	_bm.enemy_party.append(foe)
	var cid: String = _abs._get_character_id(g)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, _abs._create_guardian_default_script(cid))
	return cid


func test_the_guardian_really_cannot_know_the_ability_its_default_script_reaches_for() -> void:
	## CONTROL for every arm below. If iron_guard were in the kit there would be no bug to fix, and
	## the fall-through arms would be passing because the rule was fine, not because it was skipped.
	var g := _guardian("Premise Guardian")
	assert_false(g.knows_ability("iron_guard"), "iron_guard must be outside the Guardian's kit")
	assert_false(JobSystem.can_use_ability(g, "iron_guard"), "and the battle refuses it")
	assert_false(JobSystem.get_ability("iron_guard").is_empty(),
		"CONTROL: it IS a real ability — so the player saw 'can't use Iron Guard', not a silent no-op")


func test_the_pinning_rule_would_otherwise_have_matched_every_turn() -> void:
	## The other half of the premise: the skip is what changed the outcome, not a false condition.
	## A fresh Guardian has no defense buff and full MP, and casting never happens, so this stays
	## true turn after turn — which is what made it a PIN rather than one wasted turn.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var g := _guardian("Premise Conditions")
	_arm(g, _foe())
	for cond in (UNKNOWN_RULE["conditions"] as Array):
		assert_true(_abs._evaluate_grid_condition(g, cond),
			"CONTROL: condition %s matches, so the rule would win first-match-wins" % str(cond))


func test_a_rule_the_character_cannot_perform_is_not_a_match() -> void:
	var g := _guardian("Performable Guardian")
	assert_false(_abs._rule_is_performable(g, UNKNOWN_RULE),
		"every action is an ability the Guardian cannot know — the rule is dead")
	assert_true(_abs._rule_is_performable(g, {"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}),
		"a plain attack is always performable")


func test_it_is_the_ABILITY_that_makes_it_unperformable_not_something_else_about_the_rule() -> void:
	## Same rule dictionary, same combatant — only knowledge of the ability changes between the two
	## measurements. Rules out the arm above passing because of the conditions, the target or the
	## shape of the dict.
	var g := _guardian("Learner Guardian")
	assert_false(_abs._rule_is_performable(g, UNKNOWN_RULE), "before: cannot")
	g.learned_abilities.append("iron_guard")
	assert_true(_abs._rule_is_performable(g, UNKNOWN_RULE),
		"after learning it, the very same rule is performable — knowledge is the only variable")


func test_transient_blocks_still_match_so_the_log_can_name_them() -> void:
	## Deliberately NOT skipped. Out of MP is the player's own priority failing on this turn, and
	## the battle log says so; silently retargeting would hide a boss debuff. Only "can never"
	## falls through.
	var g := _guardian("Silenced Guardian")
	g.learned_abilities.append("iron_guard")
	g.current_mp = 0
	assert_true(_abs._rule_is_performable(g, UNKNOWN_RULE),
		"no MP is transient — the rule still matches and the log explains it")
	g.add_status("silence")
	assert_true(_abs._rule_is_performable(g, UNKNOWN_RULE), "silence likewise stays visible")


func test_the_guardian_picks_something_it_can_actually_do_turn_after_turn() -> void:
	## The player-facing property, and the one that survives an authoring fix: whatever the default
	## script reaches for, what comes back is an action this Guardian can perform. Ten consecutive
	## turns because ONE good turn would not have caught the pin either — the bug was repetition.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var g := _guardian("Unpinned Guardian")
	_arm(g, _foe())
	var unusable: Array = []
	var seen: Array = []
	for turn in range(10):
		for action in _abs.execute_grid_autobattle(g):
			var a: Dictionary = action
			var t: String = str(a.get("type", ""))
			seen.append(t)
			if t != "ability":
				continue
			var aid: String = str(a.get("ability_id", ""))
			if not g.knows_ability(aid):
				unusable.append("turn %d: %s" % [turn, aid])
	assert_gt(seen.size(), 9, "CONTROL: turns were actually resolved (%d actions)" % seen.size())
	assert_eq(unusable.size(), 0,
		"autobattle handed the Guardian an ability it cannot cast — the turn is consumed for nothing: " + str(unusable))


func test_the_same_pin_is_gone_for_the_other_jobs_that_had_it() -> void:
	## The Guardian is the worst case, not the only one: ninja reaches for backstab/steal and
	## summoner for cure, all outside their own kits. The fix is in the ladder, so it should cover
	## them without naming them — this arm is what says "mechanism", not "one script patched".
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var unusable: Array = []
	var resolved: int = 0
	for job_id in ["ninja", "summoner"]:
		var c := Combatant.new()
		c.initialize({
			"name": "Unpinned " + job_id, "max_hp": 400, "max_mp": 80,
			"attack": 20, "defense": 20, "magic": 20, "speed": 12
		})
		c.job = JobSystem.get_job(job_id)
		c.job_level = 10
		add_child_autofree(c)
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		_bm.player_party.append(c)
		_bm.enemy_party.append(_foe())
		var cid: String = _abs._get_character_id(c)
		_fixture_ids.append(cid)
		_abs.set_character_script(cid, _abs.call("_create_%s_default_script" % job_id, cid))
		for turn in range(4):
			for action in _abs.execute_grid_autobattle(c):
				var a: Dictionary = action
				resolved += 1
				if str(a.get("type", "")) == "ability" and not c.knows_ability(str(a.get("ability_id", ""))):
					unusable.append("%s turn %d: %s" % [job_id, turn, str(a.get("ability_id", ""))])
	assert_gt(resolved, 7, "CONTROL: both jobs actually resolved turns (%d actions)" % resolved)
	assert_eq(unusable.size(), 0, "a default script still hands out an uncastable ability: " + str(unusable))


func test_a_character_we_cannot_interrogate_keeps_its_rules() -> void:
	## Found by the neighbour sweep, not by this file. The grid editor's Simulate probe is a scratch
	## Combatant, and with no character open it carries no job — so "does it know this?" answered NO
	## for every ability in the game and the panel reported "no rule matches" for a sound grid.
	## Undecidable is not empty: only a combatant we can actually interrogate gets a rule taken away.
	var blank := Combatant.new()
	blank.initialize({"name": "Probe", "max_hp": 100, "max_mp": 50, "attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(blank)
	assert_true(blank.job == null or (blank.job is Dictionary and (blank.job as Dictionary).is_empty()),
		"CONTROL: this fixture really has no kit — otherwise the arm below proves nothing")
	assert_true(_abs._rule_is_performable(blank, UNKNOWN_RULE),
		"a combatant with no kit and nothing learned tells us nothing; the rule must stand")
	## And the discriminator: give it a kit and the same question becomes answerable — and the
	## answer is no. Without this arm the one above would also pass if the check never ran at all.
	blank.job = JobSystem.get_job("guardian")
	assert_false(_abs._rule_is_performable(blank, UNKNOWN_RULE),
		"once there IS a kit to read, an ability outside it is refused")
