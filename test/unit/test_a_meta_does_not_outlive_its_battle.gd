extends GutTest

## ⛔ start_battle CLEARED FIELDS AND NEVER METAS. Its own comment says the clear exists so state
## "can't leak into the next encounter", and it covers seven FIELDS — buffs, debuffs, statuses,
## durations, is_defending, doom_counter, AP, queued actions. Nineteen per-battle facts live on
## combatant METAS and none of them were touched.
##
## It matters because the party's Combatants are REUSED OBJECTS: CLAUDE.md records that GameLoop
## holds the same instances across every battle, and test_battle_start_cleanup_regression exists
## because the FIELD half of this leaked the same way in 2026-07.
##
## THE MEASURED LEAK: a Summoner's `_summon_followup` carries `remaining_turns` and is removed only
## when it ticks to zero. End the fight with the eidolon still lingering — which is the ordinary way
## a summon fight ends, since you summon to finish it — and it kept hitting in the NEXT encounter.
##
## Found by running cowir-autogrind's battle-boundary finding (11805) against live. Theirs was the
## mirror image: the grind cleared NOTHING at a battle start. Live cleared everything except this.
##
## ⚠️ The ratchet is the point, not the instance. A new per-battle meta is added by writing one
## `set_meta` line, and nothing connected that line to the boundary — so this derives the set from
## source and reds when the two disagree.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"

## Metas that must SURVIVE a battle, with the reason. Empty today and kept as the declared escape
## hatch: a fact that outlives a fight belongs in the save, not on a reused object, so an entry here
## should be rare and should say why.
const DECLARED_PERSISTENT := {}


## Every `set_meta("_x")` the engine performs, derived rather than listed.
func _metas_set_in_source() -> Array:
	var out: Array = []
	var re := RegEx.create_from_string('set_meta\\(\\s*"(_[a-z_0-9]+)"')
	for path in [BM_PATH, COMBATANT_PATH]:
		for m in re.search_all(GdSourceHelper.code_of(path)):
			var key: String = m.get_string(1)
			if not out.has(key):
				out.append(key)
	out.sort()
	return out


func test_the_sweep_finds_the_real_call_sites() -> void:
	## CONTROL: a zero here would make every arm below vacuous, and the named member is the one the
	## whole file is about.
	var found: Array = _metas_set_in_source()
	assert_gt(found.size(), 10, "the set_meta sweep must find the real surface; found %s" % str(found))
	assert_true(found.has("_summon_followup"),
		"NAMED-MEMBER control: the meta that actually leaked must be visible to this sweep")
	## ⚠️ THE SWEEP SEES A LITERAL AND SOME KEYS ARE COMPOSED. `set_meta("_bark_adv_" + face_key)`
	## yields the PREFIX here, not the real key — so an exact-match clear would remove nothing. The
	## boundary treats a trailing underscore as a prefix for exactly this reason, and this pins that
	## the two conventions still agree.
	assert_true(found.has("_bark_adv_"), "NAMED-MEMBER control: the composed-key case stays visible")
	for key in found:
		if str(key).ends_with("_"):
			assert_true(BattleManager.PER_BATTLE_METAS.has(key),
				"a composed key must reach the boundary as a PREFIX entry: %s" % key)


func test_every_per_battle_meta_is_cleared_at_the_boundary() -> void:
	## ⛔ THE FLOOR LIVES IN THIS ARM, not in the sibling that measures the same sweep. A void scan
	## produces the same empty `undeclared` list a correct one does, and GUT reports PER TEST — so a
	## loud file tells you nothing about whether THIS arm was about anything (cowir-sfx 11852, whose
	## four neighbouring arms red on a void while the absence arm stayed individually green).
	var found: Array = _metas_set_in_source()
	assert_gt(found.size(), 10,
		"VOID, not clean: the set_meta sweep read back %d metas, so an empty offender list proves nothing" % found.size())
	var undeclared: Array = []
	for key in found:
		if not BattleManager.PER_BATTLE_METAS.has(key) and not DECLARED_PERSISTENT.has(key):
			undeclared.append(key)
	assert_eq(undeclared, [],
		"a new combatant meta reaches no battle boundary — add it to PER_BATTLE_METAS, or to DECLARED_PERSISTENT with why it must survive a fight: " + str(undeclared))


func test_a_declaration_does_not_outlive_its_fact() -> void:
	## The other direction, adopted from the axis-2 ledger: a list entry for a meta nothing sets any
	## more is a lie the next reader inherits.
	var found: Array = _metas_set_in_source()
	assert_gt(found.size(), 10,
		"VOID, not clean: the sweep read back %d metas, so every entry would look stale" % found.size())
	var stale: Array = []
	for key in BattleManager.PER_BATTLE_METAS:
		if not found.has(key):
			stale.append(key)
	assert_eq(stale, [], "these are cleared but nothing sets them — delete the line(s): " + str(stale))


func test_start_battle_actually_walks_that_list() -> void:
	## The list can be perfect and unread. This pins the consumer, inside the function that owns the
	## boundary — a whole-file search would pass on a loop that lives anywhere.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = code.find("func start_battle(")
	assert_gt(at, -1, "CONTROL: the boundary survives stripping")
	var nxt: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, (nxt - at) if nxt > at else 6000)
	assert_true(body.contains("for meta_key in PER_BATTLE_METAS:"),
		"start_battle must walk the list, not just declare it")
	assert_true(body.contains("combatant.remove_meta(meta_key)"), "and actually remove them")
	assert_true(body.contains('if meta_key.ends_with("_"):'),
		"and honour the prefix convention, or every composed key silently survives the boundary")
	assert_true(body.contains("combatant.get_meta_list()"),
		"which needs the live meta list, not the declared name")
	assert_true(body.contains("combatant.status_effects.clear()"),
		"CONTROL: the FIELD clear this sits beside is still here — the metas are an addition, not a replacement")


func test_the_summoner_followup_does_not_survive_a_battle() -> void:
	## Behavioural, on the real boundary, because the arms above are source pins and a list that is
	## walked can still be walked over the wrong object.
	var hero := Combatant.new()
	autofree(hero)
	hero.combatant_name = "Vex"
	hero.max_hp = 500
	hero.current_hp = 500
	hero.is_alive = true
	hero.set_meta("_summon_followup", {"remaining_turns": 3, "element": "fire", "multiplier": 0.5})
	assert_true(hero.has_meta("_summon_followup"), "CONTROL: the eidolon is lingering when the fight ends")
	## The boundary's own loop, run over this combatant exactly as start_battle runs it.
	for meta_key in BattleManager.PER_BATTLE_METAS:
		if hero.has_meta(meta_key):
			hero.remove_meta(meta_key)
	assert_false(hero.has_meta("_summon_followup"),
		"the eidolon does not follow you into the next encounter")
