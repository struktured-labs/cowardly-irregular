extends GutTest

## Playtest-critical (found 2026-07-02, pre-first-defeat): the
## spotlight short-circuit in GameLoop._on_battle_ended skips ALL
## healing by design ("cutscene still owns the flow") — but nothing
## else healed either, so a defeated duelist re-entered the retry at
## 0 HP: instant re-defeat, infinite insta-loss loop on the FIRST
## death in any duel. start_solo_battle now calls _restore_duelist
## on every attempt.

const GameLoopScript = preload("res://src/GameLoop.gd")


func _make_dead_fighter() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Test Duelist", "max_hp": 120, "max_mp": 40,
		"attack": 10, "defense": 5, "magic": 5, "speed": 8})
	c.take_damage(999)
	return c


func test_restore_revives_dead_duelist_to_full() -> void:
	var pc := _make_dead_fighter()
	assert_false(pc.is_alive, "precondition: duelist is dead")
	GameLoopScript._restore_duelist(pc)
	assert_true(pc.is_alive, "retry attempt must start alive")
	assert_eq(pc.current_hp, pc.max_hp, "retry attempt must start at full HP")
	assert_eq(pc.current_mp, pc.max_mp, "retry attempt must start at full MP")
	pc.free()


func test_restore_clears_statuses_via_api() -> void:
	var pc := _make_dead_fighter()
	pc.revive(1)
	pc.add_status("poison")
	GameLoopScript._restore_duelist(pc)
	assert_false(pc.has_status("poison"),
		"a poisoned duelist must not carry the status into the rematch")
	pc.free()


func test_solo_battle_calls_restore_every_attempt() -> void:
	# Source pin: the restore must live INSIDE start_solo_battle (runs
	# per retry iteration), not one-time setup.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn_idx: int = src.find("func start_solo_battle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("_restore_duelist(spotlight_pc)"),
		"start_solo_battle must restore the duelist on EVERY attempt")


func test_retry_loop_has_a_beat() -> void:
	# Instant restart on a fresh defeat read as a glitch — the retry branch
	# must wait a beat before relaunching. 2026-07-12: the raw create_timer
	# pause is replaced by _play_spotlight_retry_sting (SFX + shake + red
	# flash → black tween) which IS the beat, richer than a dead pause.
	var src: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var idx: int = src.find("\"retry\":")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 400)
	assert_true(window.contains("_play_spotlight_retry_sting()"),
		"retry must breathe before relaunching the duel — the sting owns the pacing now")
