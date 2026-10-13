extends GutTest

## A successful steal credited gold IN SILENCE, and the only sound the action made was the generic
## DESCENDING blip — which played identically whether the steal landed or whiffed.
##
## Two causes, and they are the same pair the cure defect had:
##   WRONG PLACE   BattleScene picks a cue by the ability's `effect` string, so it cannot know the
##                 OUTCOME. `steal` was in no arm, fell to the catch-all, is single_enemy, so
##                 play_status("steal") -> no status_steal on disk -> the descending blip. Success
##                 and failure are the same effect, so they drew the same negative cue.
##   WRONG SILENCE `_award_stolen_gold` is the ONE place that knows gold was credited (both the
##                 pure Steal handler and Mug's physical branch call it) and it played nothing,
##                 while EVERY other gold gain in the game cues `gold_pickup` — VictoryOverlay's
##                 count-up and TreasureChest both do.
##
## Fixed where the cure was: in the executor, which is the only place that knows what happened.
## `gold_pickup` on the pickup channel (its own AudioStreamPlayer, so a reward cue always follows
## the action that earned it), `attack_miss` on a whiff, and `steal` deferred out of BattleScene
## beside `cleanse`. No new assets — all three cues were already authored and on disk.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const GOLD := "gold_pickup"
const MISS := "attack_miss"

var _bm = null
var _gold_before: int = 0


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_gold_before = int(GameState.party_gold) if "party_gold" in GameState else 0
	_reset_audio()


func after_each() -> void:
	_reset_audio()
	## Both arms PLAY, so a stream is left on _pickup_player and _battle_player. A full suite is one
	## process and a leaked stream satisfies any other file's `assert_true(player.stream != null,
	## "CONTROL: ...")` exactly as a real cue does — measured in sfx_state.gd, where it disabled three
	## arms in a sibling lane. This is the shared teardown for it; do not hand-roll one.
	SfxState.release_streams()
	if "party_gold" in GameState:
		GameState.party_gold = _gold_before


func _reset_audio() -> void:
	SoundManager._sfx_cooldowns.erase(GOLD)
	SoundManager._sfx_cooldowns.erase(MISS)
	SoundManager._sfx_suppressed_by_cooldown = false


func _mk(name_: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = name_
	c.max_hp = 100
	c.current_hp = 100
	c.speed = 10
	c.is_alive = true
	return c


## The REAL steal ability, with only the roll pinned — a hand-made {effect: "steal"} would pass
## against a fiction if the effect string were ever renamed.
func _steal(rate: float, in_party: bool = true) -> Combatant:
	var ability: Dictionary = JobSystem.get_ability("steal").duplicate(true)
	assert_false(ability.is_empty(), "VOID: the steal ability is gone, so nothing below drives a steal")
	assert_eq(str(ability.get("effect", "")), "steal",
		"VOID: steal's effect string changed — re-point this guard rather than deleting it")
	ability["success_rate"] = rate
	var caster := _mk("Rogue")
	var target := _mk("Mark")
	## ⛔ EXPLICITLY TYPED. `_bm.player_party = [caster] if in_party else []` is a typed-array
	## assignment from an untyped literal: it ABORTS _steal, so the executor was never called at all
	## — gold stayed at 500, no cue fired, and the caster came back null. Every arm then failed for
	## the fixture rather than for its subject, which made five "red" mutations prove nothing.
	var party: Array[Combatant] = []
	if in_party:
		party.append(caster)
	_bm.player_party = party
	_bm._execute_support_ability(caster, ability, [target])
	return caster


func test_the_steal_cue_floor() -> void:
	## Own arm: the arms below touch these after their fixture preconditions, so a rename would
	## abort them with an assert already passed — green and silent.
	assert_true(_bm.has_method("_award_stolen_gold"),
		"BattleManager._award_stolen_gold is gone — it is the one place that knows gold was credited, and where the cue lives")
	assert_true(SoundManager.has_method("play_pickup"),
		"SoundManager.play_pickup is gone, so the reward channel the arms below assert cannot be reached")
	assert_true(SoundManager._sfx_manifest.has(GOLD) and SoundManager._sfx_manifest.has(MISS),
		"%s / %s are no longer authored; both were on disk and the fix needed no new assets" % [GOLD, MISS])
	## ⛔ THE SYMBOL THAT MADE THIS WHOLE FILE VACUOUS ONCE. Every arm below reads the party's gold to
	## prove a steal moved money, and my first draft read `GameState.gold`, which does not exist — the
	## property is `party_gold`. A missing property ABORTS the enclosing arm, and each arm had already
	## passed its fixture asserts by then, so all four scored PASSING with their real claims never
	## evaluated. Three mutations survived and that is the only reason it was found. A floor over the
	## two METHODS was not enough: it must name every symbol the file reaches, properties included.
	assert_true("party_gold" in GameState,
		"GameState.party_gold is gone — every arm below reads it to prove gold moved, and a missing property aborts the arm AFTER its preconditions pass, which scores green")


func test_a_landed_steal_sounds_like_a_reward() -> void:
	var caster := _steal(1.0)
	assert_gt(int(GameState.party_gold), _gold_before,
		"VOID: the fixture did not actually credit any gold, so the cue below proves nothing")
	assert_true(SoundManager._sfx_cooldowns.has(GOLD),
		"a steal that credited gold played no %s — every other gold gain in the game cues it" % GOLD)
	assert_false(SoundManager._sfx_cooldowns.has(MISS),
		"a LANDED steal played the miss cue")
	assert_true(caster != null, "CONTROL: the caster survived the action")


func test_a_whiffed_steal_does_not_sound_like_a_reward() -> void:
	_steal(0.0)
	assert_eq(int(GameState.party_gold), _gold_before,
		"VOID: a 0.0 success_rate still credited gold, so this arm is not testing a failure")
	assert_false(SoundManager._sfx_cooldowns.has(GOLD),
		"a FAILED steal played the gold cue, so the reward sound stops meaning 'you got something'")
	assert_true(SoundManager._sfx_cooldowns.has(MISS),
		"a failed steal is silent, so it sounds exactly like a successful one did before this fix")


func test_an_enemy_rifling_your_pack_credits_nothing_and_cues_nothing() -> void:
	## The early return in _award_stolen_gold: an enemy steal emits "comes up empty" and moves no
	## gold, so the PLAYER's reward cue must not fire for it.
	_steal(1.0, false)
	assert_eq(int(GameState.party_gold), _gold_before, "VOID: a non-party caster credited the player gold")
	assert_false(SoundManager._sfx_cooldowns.has(GOLD),
		"%s played for a steal that moved no gold to the player" % GOLD)


func test_steal_is_deferred_out_of_battlescene_and_the_executor_honours_it() -> void:
	## Both halves, because either alone is a defect: a cue in BOTH places doubles it (and the 80 ms
	## per-key cooldown hides the second from any log), and a deferral nobody honours is silence.
	var scene: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	assert_ne(scene, "", "CONTROL: BattleScene code must survive the comment strip")
	var at: int = scene.find("func _on_action_executed")
	assert_gt(at, -1, "CONTROL: the handler must survive the strip")
	var nxt: int = scene.find("\nfunc ", at + 1)
	var body: String = scene.substr(at, nxt - at) if nxt > at else scene.substr(at)
	assert_false(body.contains("play_status(\"steal\")") or body.contains("play_battle(\"steal\")"),
		"BattleScene cues `steal` again, so it sounds on both outcomes and on both paths — only the executor knows which happened")
	assert_true(body.contains("\"cleanse\", \"steal\":"),
		"`steal` is no longer in the deferred arm, so it falls to the catch-all's else branch and draws the generic descending blip again")

	## ⛔ SCOPED TO THE FUNCTION, AND IT WAS NOT. These started as file-wide `contains` over a
	## 7,000-line file, which is a QUANTIFIER error rather than a weak anchor: both can be satisfied
	## at two UNRELATED sites, so the cue could move to the victory path and this control would stay
	## green while its own message claimed co-location. Tightening the strings would not fix that
	## (@cowir-controller / @cowir-music, same class, three lanes in one evening). The half of this
	## arm above was already scoped to _on_action_executed; this half was not.
	var bm: String = GdSource.code_of("res://src/battle/BattleManager.gd")
	assert_ne(bm, "", "CONTROL: BattleManager code must survive the comment strip")
	var award: int = bm.find("func _award_stolen_gold")
	assert_gt(award, -1,
		"CONTROL: _award_stolen_gold is gone — it is the one place that knows gold was credited, and where the cue has to live")
	if award < 0:
		return
	var award_end: int = bm.find("\nfunc ", award + 1)
	var award_body: String = bm.substr(award, award_end - award) if award_end > award else bm.substr(award)
	assert_true(award_body.contains("SoundManager.play_pickup(\"%s\")" % GOLD),
		"the reward cue is not INSIDE _award_stolen_gold. Either nothing cues a landed steal, or the cue moved somewhere that does not know gold was credited — and a file-wide check cannot tell those apart")
