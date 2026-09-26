extends GutTest

## A spotlight duel picks its ally by job. Staking or the Permadeath Reaper can leave that
## ally in the party at 0 HP with the permakilled marker, and revive() will not raise them.
## Fielding the corpse ends the fight before they act. Every W1 spotlight is on_defeat:retry,
## skip is inert while the battle step owns the screen, and the scene starts again — forever.
## The missing-job refusal already exists: do not start, do not write the unlock (that flag
## means the duel was won), leave the gate open for a living holder. A permakilled holder
## must take that path. An ordinary KO still starts — _restore_duelist can raise them.

const GameLoopScript := preload("res://src/GameLoop.gd")

const SCENES := {
	"world1_spotlight_mage_ch3": "mage",
	"world1_spotlight_fighter_ch2": "fighter",
	"world1_spotlight_bard_ch7": "bard",
}


class RecordingDirector extends Node:
	signal cutscene_finished(cutscene_id: String)
	var real: CutsceneDirector = null
	var played: Array = []
	func can_play(_cutscene_id: String) -> bool:
		return true
	func battle_duelists(cutscene_id: String) -> Array:
		return real.battle_duelists(cutscene_id)
	func play_cutscene(cutscene_id: String, _replay: bool = false) -> void:
		played.append(cutscene_id)


func _pc(job_id: String, permakilled: bool, knocked_out: bool = false) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = job_id.capitalize()
	c.job = {"id": job_id}
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	if permakilled or knocked_out:
		c.is_alive = false
		c.current_hp = 0
	if permakilled:
		c.add_status("permakilled", -1)
	return c


func _director() -> RecordingDirector:
	var d := RecordingDirector.new()
	autofree(d)
	d.real = autofree(CutsceneDirector.new())
	return d


func _loop(director: Node, members: Array) -> Node:
	var gl: Node = autofree(GameLoopScript.new())
	gl._cutscene_director = director
	gl.current_state = gl.LoopState.EXPLORATION
	gl._cutscene_cooldown = false
	for m in members:
		gl.party.append(m)
	return gl


func _flag(job_id: String, which: String) -> String:
	return "cutscene_flag_spotlight_%s_%s" % [which, job_id]


func _stash(keys: Array) -> Dictionary:
	var saved := {}
	for k in keys:
		saved[k] = GameState.game_constants.get(k, null)
		GameState.game_constants.erase(k)
	return saved


func _restore(saved: Dictionary) -> void:
	for k in saved:
		if saved[k] == null:
			GameState.game_constants.erase(k)
		else:
			GameState.game_constants[k] = saved[k]


func test_floor_the_refusal_this_file_drives() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_play_story_cutscene", "_party_member_with_job", "start_solo_battle"]:
		assert_true(gl.has_method(m), "GameLoop must still expose %s()" % m)
	var real: CutsceneDirector = autofree(CutsceneDirector.new())
	assert_true(real.has_method("battle_duelists"), "CutsceneDirector must still expose battle_duelists()")


func test_a_permakilled_duelist_does_not_start_and_does_not_unlock() -> void:
	for scene_id in SCENES:
		var job_id: String = str(SCENES[scene_id])
		var saved := _stash([_flag(job_id, "watched"), _flag(job_id, "unlocked")])
		var d := _director()
		var corpse := _pc(job_id, true)
		var gl: Node = _loop(d, [corpse])
		assert_null(gl._party_member_with_job(job_id),
			"%s still selects the permakilled %s — the duel will field a corpse" % [scene_id, job_id])
		assert_false(gl._play_story_cutscene(scene_id),
			"%s started with a permakilled %s — on_defeat retry then loops before they can act" % [scene_id, job_id])
		assert_eq(d.played, [], "%s asked the director to play a duel the corpse cannot win" % scene_id)
		assert_eq(gl.current_state, gl.LoopState.EXPLORATION,
			"%s committed the loop to CUTSCENE, so the pause menu and movement stay locked" % scene_id)
		assert_false(gl._cutscene_cooldown, "%s set the cooldown on a duel that never began" % scene_id)
		assert_false(bool(GameState.game_constants.get(_flag(job_id, "watched"), false)),
			"%s wrote the watched flag — the scene could never be fought once a living %s returns" % [scene_id, job_id])
		assert_false(bool(GameState.game_constants.get(_flag(job_id, "unlocked"), false)),
			"%s granted spotlight_unlocked_%s without a win" % [scene_id, job_id])
		_restore(saved)


func test_a_permakilled_duelist_is_unavailable_so_the_retry_loop_stops() -> void:
	# start_solo_battle is what _step_battle retries on "defeat". "unavailable" is the sentinel
	# that aborts after one attempt. This must answer before any battle begins.
	var prev_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	var gl: Node = autofree(GameLoopScript.new())
	gl.party.append(_pc("mage", true))
	var result: String = gl.start_solo_battle("mage", "mage_prismatic_construct")
	BattleManager.current_state = prev_state
	assert_eq(result, "unavailable",
		"a permakilled mage returned '%s' — 'defeat' retries forever, and anything else that awaits a battle hangs the scene" % result)
	assert_false(gl._spotlight_duel_active, "the refused duel left the spotlight latch on")
	assert_eq(gl.party.size(), 1, "the refused duel benched the party down to the corpse")


func test_a_living_holder_still_fights_when_a_corpse_shares_the_job() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	var corpse := _pc("mage", true)
	var living := _pc("mage", false)
	gl.party.append(corpse)
	gl.party.append(living)
	assert_eq(gl._party_member_with_job("mage"), living,
		"the scan stopped on the permakilled mage and never reached the living one")
	var d := _director()
	var loop: Node = _loop(d, [corpse, living])
	assert_true(loop._play_story_cutscene("world1_spotlight_mage_ch3"),
		"CONTROL: a living mage in the party must still start the duel")
	assert_eq(d.played, ["world1_spotlight_mage_ch3"], "CONTROL: the director was not asked to play the runnable duel")


func test_an_ordinary_ko_still_starts_the_duel() -> void:
	# _restore_duelist raises a normal KO. Refusing here would skip a winnable rematch.
	var d := _director()
	var gl: Node = _loop(d, [_pc("fighter", false, true)])
	assert_not_null(gl._party_member_with_job("fighter"),
		"an ordinary KO was treated as permakilled — the retry restore can still raise them")
	assert_true(gl._play_story_cutscene("world1_spotlight_fighter_ch2"),
		"CONTROL: a knocked-out fighter who is not permakilled must still start the duel")
	assert_eq(d.played, ["world1_spotlight_fighter_ch2"])
