extends GutTest

## struktured's ask (2026-10-28): quips when they land a crit or kill a monster. Neither moment existed
## — the party-line system had five event kinds (turn_start, low_hp, big_hit_taken,
## used_signature_ability, victory) and none of them fires on a crit or on an enemy dying.
##
## 🔑 THE HOOK IS ON THE SIGNAL, NOT ON THE SITES. `is_crit` is assigned in five separate places in
## BattleManager (the basic attack, the ability path, the multi-hit loop, …). Calling a notifier at each
## is the shape that produced THIS WEEK's one-shot defect: `_record_first_damage` had three call sites,
## all correct, while nine `take_damage` sites in the pooled paths recorded nothing, and no grep over
## the mechanism's name could name a non-caller. `damage_dealt` already carries `is_crit` and every
## damage path emits it, so one connection covers a sixth path nobody has written yet.
##
## ⚠️ damage_dealt carries the TARGET but no ATTACKER, so the speaker is `current_combatant`. That is
## correct for every shipped path and knowingly wrong under a Bossbinder mind-swap, where a controlled
## enemy fights its own side — it would credit the acting PC. Named rather than silently accepted.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

## The shared guard, not a teardown of my own: its surface is derived from get_property_list(), so it
## covers the two party-line dicts below and anything added to BattleManager tomorrow.
var _bm_guard = BattleStateGuard.new()


func before_each() -> void:
	_bm_guard.snapshot()
	## ESTABLISH as well as snapshot. restore() puts back the PRIOR value by design, which makes it a
	## conduit for dirt an earlier file left rather than a barrier — so these arms set what they need.
	BattleManager._party_line_cooldowns = {}
	BattleManager._party_line_last_kind = {}
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	BattleManager.current_round = 1


func after_each() -> void:
	_bm_guard.restore()


func _pc(who: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.is_alive = true
	return c


## The line that was requested of this speaker, or "" — stamped synchronously by _maybe_fire_party_line
## before it hands off to the async producer, so it is observable without driving the LLM path.
func _spoken_kind(who: String) -> String:
	return str(BattleManager._party_line_last_kind.get(who, ""))


func _arena() -> Dictionary:
	var hero: Combatant = _pc("Brom")
	var foe: Combatant = _pc("Slime")
	var foe2: Combatant = _pc("Rat")
	BattleManager.player_party.assign([hero])
	BattleManager.enemy_party.assign([foe, foe2])
	BattleManager.current_combatant = hero
	return {"hero": hero, "foe": foe, "foe2": foe2}


func test_a_crit_the_party_lands_gets_a_line() -> void:
	var a: Dictionary = _arena()
	BattleManager._on_damage_dealt_for_party_line(a["foe"], 99, true, "", 1.0)
	assert_eq(_spoken_kind("Brom"), PartyCombatLineContext.EVENT_CRIT_LANDED,
		"a crit on an enemy must ask Brom for a crit line")


func test_a_crit_the_party_TAKES_says_nothing() -> void:
	## ⛔ THE INVERTED-SUBJECT ARM. Without the `target in player_party` guard the party cheers while
	## being critically hit, which reads as a feature working — a line DID play, in the wrong mouth.
	var a: Dictionary = _arena()
	BattleManager._on_damage_dealt_for_party_line(a["hero"], 99, true, "", 1.0)
	assert_eq(_spoken_kind("Brom"), "", "a crit landed ON the party is not the party's crit")


func test_an_ordinary_hit_says_nothing() -> void:
	## CONTROL: the hook is on every damage event, so without the is_crit test it would fire constantly.
	var a: Dictionary = _arena()
	BattleManager._on_damage_dealt_for_party_line(a["foe"], 99, false, "", 1.0)
	assert_eq(_spoken_kind("Brom"), "", "a non-crit hit is not a moment")


func test_an_enemys_turn_does_not_put_words_in_a_pc_mouth() -> void:
	## An enemy crit-hitting another enemy (confusion, a mind-swapped ally) must not credit a PC who is
	## not acting. The speaker is the actor, and when the actor is not ours there is no speaker.
	var a: Dictionary = _arena()
	BattleManager.current_combatant = a["foe2"]
	BattleManager._on_damage_dealt_for_party_line(a["foe"], 99, true, "", 1.0)
	assert_eq(_spoken_kind("Brom"), "", "Brom was not acting and must not claim the crit")
	assert_eq(_spoken_kind("Rat"), "", "an enemy is not in player_party and gets no party line")


func test_a_felled_enemy_gets_a_line_while_the_fight_continues() -> void:
	var a: Dictionary = _arena()
	(a["foe"] as Combatant).is_alive = false
	BattleManager._dispatch_enemy_felled_party_line("Slime")
	assert_eq(_spoken_kind("Brom"), PartyCombatLineContext.EVENT_ENEMY_FELLED,
		"one of two enemies fell and the fight goes on — that is the moment")


func test_the_last_enemys_death_is_left_to_the_victory_line() -> void:
	## ⛔ THE COLLISION ARM. The last enemy's death and the victory are the same instant: end_battle calls
	## SoundManager.stop_voice() and then _dispatch_victory_party_line four lines later, so a felled line
	## fired here is started and then cut mid-word. Silent in tests, audible in play as a clipped quip.
	var a: Dictionary = _arena()
	(a["foe"] as Combatant).is_alive = false
	(a["foe2"] as Combatant).is_alive = false
	BattleManager._dispatch_enemy_felled_party_line("Rat")
	assert_eq(_spoken_kind("Brom"), "",
		"the last enemy's death belongs to the victory line, which speaks for it moments later")


func test_a_finished_battle_gets_no_moment_line() -> void:
	## `died` is deferred, so a death can arrive after the state has already moved to VICTORY.
	var a: Dictionary = _arena()
	(a["foe"] as Combatant).is_alive = false
	BattleManager.current_state = BattleManager.BattleState.VICTORY
	BattleManager._dispatch_enemy_felled_party_line("Slime")
	assert_eq(_spoken_kind("Brom"), "", "no moment line may land after the battle is decided")


func test_the_crit_hook_is_connected_to_the_signal_rather_than_the_sites() -> void:
	## The design claim, asserted rather than described. If someone later "simplifies" this into calls at
	## each is_crit site, the next damage path added silently stops speaking.
	var code: String = GdSource.code_of(BM_PATH)
	assert_gt(code.length(), 10000, "CONTROL: BattleManager was actually read")
	assert_true(code.contains("damage_dealt.connect(_on_damage_dealt_for_party_line)"),
		"the crit line must hang off the damage_dealt signal, so every damage path is covered by one hook")
	var sites: int = code.count("is_crit = true") + code.count("var is_crit = randf()")
	assert_gt(sites, 1,
		"CONTROL: if there were only one place that sets is_crit, hooking the signal would buy nothing — found %d" % sites)


func test_the_new_kinds_are_reactions_so_they_outrank_ambient_chatter() -> void:
	## turn_start fires on EVERY PC turn and claims the shared cooldown first. A reaction preempts it;
	## listing a new kind as ambient would make it unreachable for most of a battle.
	for kind in [PartyCombatLineContext.EVENT_CRIT_LANDED, PartyCombatLineContext.EVENT_ENEMY_FELLED]:
		assert_false(BattleManager.AMBIENT_PARTY_LINE_EVENTS.has(str(kind)),
			"%s must stay a reaction, or the turn_start cooldown buries it" % kind)


func test_every_starter_job_can_answer_both_new_moments() -> void:
	## A kind with no authored pool is silent for that job and nothing reports it — get_trigger_entries
	## returns [] for an unknown key by design, so the data is the only place this can be caught.
	var missing: Array[String] = []
	for job_id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		for kind in [PartyCombatLineContext.EVENT_CRIT_LANDED, PartyCombatLineContext.EVENT_ENEMY_FELLED]:
			var lines: Array = PartyPersonas.get_trigger_lines(job_id, str(kind))
			if lines.is_empty():
				missing.append("%s/%s" % [job_id, kind])
	assert_eq(missing, ([] as Array[String]),
		"these job/moment pairs have no line and would play silently: %s" % [missing])
