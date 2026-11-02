extends GutTest

## A night at the inn is a beat: fade out, the rest ditty, morning, fade in (struktured 2026-11-01).
##
## The heal stays in InnInterior._do_rest, in the same step as the payment (test_inn_interior_charges_gold_regression
## pins it synchronous). InnRestSequence is the presentation around it, so these arms are about what the beat owes:
## the input lock held and released, morning reached THROUGH the signal the soundscape and lighting listen to, a skip
## that still ends cleanly, the night never shorter than MIN_NIGHT_SEC, the music handed back, and an inn that goes away
## mid-night leaving no lock behind.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"

var _host: Node = null
var _phase_before := 0.0


func before_each() -> void:
	_host = Node.new()
	add_child(_host)
	_phase_before = GameState.day_phase


func after_each() -> void:
	if _host and is_instance_valid(_host):
		_host.free()
	_host = null
	GameState.day_phase = _phase_before
	InputLockManager.pop_lock(InnRestSequence.LOCK_ID)


func _until_skippable(seq: InnRestSequence) -> bool:
	var waited := 0
	while is_instance_valid(seq) and not seq._skippable and waited < 300:
		await get_tree().process_frame
		waited += 1
	return is_instance_valid(seq) and seq._skippable


func test_the_beat_holds_input_then_gives_it_back() -> void:
	var seq := InnRestSequence.start(_host)
	await get_tree().process_frame
	assert_true(InputLockManager.is_locked(), "the inn's night holds input from its first frame")
	assert_true(await _until_skippable(seq), "CONTROL: the night begins")
	seq.request_skip()
	await seq.finished
	assert_false(InputLockManager.is_locked(), "and releases it when the morning has faded in")


func test_morning_arrives_through_the_signal() -> void:
	GameState.set_day_phase(0.8)
	assert_eq(GameState.get_time_of_day_name(), "night", "CONTROL: the night band is set up")
	watch_signals(GameState)
	var seq := InnRestSequence.start(_host)
	assert_true(await _until_skippable(seq), "the night begins")
	assert_eq(GameState.get_time_of_day_name(), "dawn", "the party wakes at first light")
	assert_signal_emitted_with_parameters(GameState, "time_of_day_changed", ["dawn"])
	seq.request_skip()
	await seq.finished


func test_set_day_phase_is_silent_within_a_band() -> void:
	GameState.set_day_phase(0.20)
	watch_signals(GameState)
	GameState.set_day_phase(0.30)
	assert_signal_not_emitted(GameState, "time_of_day_changed", "a jump inside one band is not a change")
	GameState.set_day_phase(0.70)
	assert_signal_emitted(GameState, "time_of_day_changed", "CONTROL: crossing into night is")


func test_the_night_is_never_a_blink() -> void:
	var seq := InnRestSequence.start(_host)
	assert_true(await _until_skippable(seq), "the night begins")
	assert_gte(seq.night_sec, InnRestSequence.MIN_NIGHT_SEC, "a missing or short ditty still gives the night its length")
	seq.request_skip()
	await seq.finished


func test_a_skip_ends_the_night_early_and_cleanly() -> void:
	var seq := InnRestSequence.start(_host)
	assert_true(await _until_skippable(seq), "the night begins")
	var t0 := Time.get_ticks_msec()
	seq.request_skip()
	var was_skipped: bool = await seq.finished
	assert_true(was_skipped, "the skip is reported")
	assert_lt(float(Time.get_ticks_msec() - t0) / 1000.0, InnRestSequence.MIN_NIGHT_SEC,
		"a skip shortens the night: it does not wait it out")
	assert_false(InputLockManager.is_locked(), "a skipped night still gives input back")


func test_no_skip_before_the_night() -> void:
	var seq := InnRestSequence.start(_host)
	await get_tree().process_frame
	seq.request_skip()
	assert_false(seq._skip_requested, "a press during the fade-out is not a skip")
	assert_true(await _until_skippable(seq), "the night still begins")
	seq.request_skip()
	await seq.finished


func test_the_music_is_handed_back() -> void:
	SoundManager.play_area_music("cave")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(SoundManager._current_area, "cave", "CONTROL: an area bed is playing")
	var seq := InnRestSequence.start(_host)
	assert_true(await _until_skippable(seq), "the night begins")
	seq.request_skip()
	await seq.finished
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(SoundManager._current_area, "cave", "the field bed comes back after the night")
	SoundManager.stop_music()


func test_an_inn_that_goes_away_leaves_no_lock_behind() -> void:
	var seq := InnRestSequence.start(_host)
	await get_tree().process_frame
	assert_true(InputLockManager.is_locked(), "CONTROL: the lock is held")
	var done := [false, false]
	seq.finished.connect(func(s: bool) -> void:
		done[0] = true
		done[1] = s)
	_host.free()
	_host = null
	assert_true(done[0], "the beat ends the moment its inn leaves the tree")
	assert_true(seq.aborted, "and says it was cut short, so the inn does not carry on")
	assert_false(InputLockManager.is_locked(), "no lock outlives the inn")


func test_a_night_freed_mid_beat_gives_input_back() -> void:
	var seq := InnRestSequence.start(_host)
	await get_tree().process_frame
	assert_true(InputLockManager.is_locked(), "CONTROL: the lock is held")
	seq.free()
	assert_false(InputLockManager.is_locked(), "a night freed before it ends releases the lock on its way out")


const _STUB_GAMELOOP := "extends Node\nvar party: Array = []\n"


func test_the_inn_heals_first_then_plays_the_night() -> void:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	get_tree().root.add_child(stub)
	var member: Combatant = Combatant.new()
	add_child_autofree(member)
	member.max_hp = 1000
	member.current_hp = 1
	member.is_alive = true
	stub.party = [member]
	var inn: Node2D = load(INN_PATH).new()
	add_child_autofree(inn)
	var gold_before: int = GameState.party_gold
	GameState.party_gold = 500
	inn._do_rest()
	assert_eq(member.current_hp, member.max_hp, "the paid rest heals at once, before any fade")
	var seq: InnRestSequence = null
	for n in get_tree().root.get_children():
		if n is InnRestSequence:
			seq = n
	assert_not_null(seq, "and the inn starts the night")
	if seq != null:
		assert_true(await _until_skippable(seq), "the night begins")
		seq.request_skip()
		await seq.finished
	## _do_rest then shows its rested line on a 1.6 s timer; let it resolve before teardown frees the inn.
	await get_tree().create_timer(1.8).timeout
	stub.free()
	GameState.party_gold = gold_before


func test_a_keeper_with_several_morning_lines_never_repeats_back_to_back() -> void:
	var lines := ["Morning!", "Sleep well?", "Breakfast is on."]
	var seen: Array = []
	for i in 6:
		seen.append(InnDialogue.pick(lines, "zz_test/rest_complete"))
	for i in range(1, seen.size()):
		assert_ne(seen[i], seen[i - 1], "the same morning line twice in a row: %s" % str(seen))
	for l in lines:
		assert_true(seen.has(l), "every authored morning line gets its turn: %s" % str(seen))


func test_a_single_line_and_an_empty_list_still_work() -> void:
	assert_eq(InnDialogue.pick("Dawn already.", "zz_test/one"), "Dawn already.", "a plain string is used as it is")
	assert_eq(InnDialogue.pick([], "zz_test/none"), "", "an empty list falls back to the inn's own text")
	assert_eq(InnDialogue.pick(["Only one."], "zz_test/single"), "Only one.", "a one-line list repeats, which is all it can do")
