extends GutTest

## Regression: the headless mix thread spun forever in AudioStreamGeneratorPlayback::_mix_internal (spinwatch capture, .542b gate, 2026-09-28).
## Godot 4.4.1's generator playback holds a RAW AudioStreamGenerator*; _play_sound built a new generator per cue on a shared player, so the next stream swap freed it while its playback was still fading out in the mix list.

var _player: AudioStreamPlayer


func before_each() -> void:
	_player = AudioStreamPlayer.new()
	add_child_autofree(_player)


func after_each() -> void:
	if is_instance_valid(_player):
		SoundManager._procedural_generators.erase(_player.get_instance_id())


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
