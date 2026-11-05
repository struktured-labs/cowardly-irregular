extends GutTest

## Regression: the headless mix thread spun forever in AudioStreamGeneratorPlayback::_mix_internal (spinwatch capture, .542b gate, 2026-09-28).
## Godot 4.4.1's generator playback holds a RAW AudioStreamGenerator*; _play_sound built a new generator per cue on a shared player, so the next stream swap freed it while its playback was still fading out in the mix list.

var _player: AudioStreamPlayer


func before_each() -> void:
	_player = AudioStreamPlayer.new()
	add_child_autofree(_player)


func after_each() -> void:
	if is_instance_valid(_player):
		_release(_player)


## The teardown was the defect it guards (#224, 2026-11-05): it erased the keeper's entry, then autofree freed the PLAYING
## player, so the last ref to the generator went while its playback was still fading out in the mix list (story's spinwatch
## capture: _mix_internal <- Resampled::mix <- _mix_step). Stop, and leave the keeper's ref, as it is for every real player.
func _release(player: AudioStreamPlayer) -> void:
	player.stop()


func _blip() -> void:
	SoundManager._play_sound(_player, {"type": "blip", "duration": 0.05, "freq": 440.0})


func test_control_a_procedural_cue_plays_a_generator() -> void:
	_blip()
	assert_true(_player.stream is AudioStreamGenerator, "CONTROL: the procedural path puts a generator on the player (got %s)" % [_player.stream])


func test_the_generator_survives_the_next_stream_swap() -> void:
	_blip()
	var ref: WeakRef = weakref(_player.stream)
	assert_not_null(ref.get_ref(), "CONTROL: the generator is alive while it is the player's stream")
	_player.stream = AudioStreamWAV.new()
	assert_not_null(ref.get_ref(),
		"swapping the player's stream freed the generator while its playback can still be fading out in the mix list, and the mix thread then reads freed memory")


func test_a_player_reuses_one_generator() -> void:
	_blip()
	var first: Object = _player.stream
	_player.stream = AudioStreamWAV.new()
	_blip()
	assert_same(_player.stream, first, "each cue built a new generator, so every swap orphaned the last one")


func test_a_freed_fixture_leaves_its_generator_alive() -> void:
	var p := AudioStreamPlayer.new()
	add_child(p)
	SoundManager._play_sound(p, {"type": "blip", "duration": 0.05, "freq": 440.0})
	assert_true(p.stream is AudioStreamGenerator and p.playing, "CONTROL: the fixture really plays a generator")
	var ref: WeakRef = weakref(p.stream)
	_release(p)
	p.free()
	await wait_frames(2)
	assert_not_null(ref.get_ref(),
		"freeing a player that played a generator freed the generator too, while its playback can still be fading out in the mix list (#224)")


func test_no_test_drops_a_kept_generator() -> void:
	## Only the keeper's lifetime makes the raw pointer safe; a test that drops an entry under a live player brings #224 back.
	## Known hole (cowir-sfx): freeing a whole SoundManager INSTANCE frees its keeper too; this walk cannot see that.
	var drop := RegEx.create_from_string("_procedural_generators\\s*(\\.erase\\(|\\.clear\\(|=[^=])")
	var strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	var offenders: Array[String] = []
	for f in _gd_files("res://test"):
		var lines: PackedStringArray = FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var t: String = strings.sub(lines[i].strip_edges(), "\"\"", true)
			if t.begins_with("#"):
				continue
			if drop.search(t) != null:
				offenders.append("%s:%d" % [f, i + 1])
	assert_gt(_gd_files("res://test").size(), 100, "SCOPE: the walk reached the test tree")
	assert_eq(offenders, [] as Array[String], "a test drops a kept generator, so a player can outlive it mid-fade: %s" % [offenders])


func test_nothing_else_in_src_builds_a_generator() -> void:
	## A second construction site would bring the raw-pointer lifetime back; only the keeper may build one.
	var offenders: Array[String] = []
	for f in _gd_files("res://src"):
		var src: String = FileAccess.get_file_as_string(f)
		var from: int = 0
		while true:
			var at: int = src.find("AudioStreamGenerator.new()", from)
			if at < 0:
				break
			var fn_at: int = src.rfind("\nfunc ", at)
			var fn_line: String = src.substr(fn_at + 1, src.find("\n", fn_at + 1) - fn_at - 1)
			if not fn_line.begins_with("func _procedural_generator_for("):
				offenders.append("%s: %s" % [f, fn_line])
			from = at + 1
	assert_true(FileAccess.get_file_as_string("res://src/audio/SoundManager.gd").contains("func _procedural_generator_for("),
		"SCOPE: the keeper function exists, so the walk below judges something")
	assert_eq(offenders, [] as Array[String], "AudioStreamGenerator built outside the keeper: %s" % [offenders])


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			out.append_array(_gd_files(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out
