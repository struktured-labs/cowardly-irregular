extends GutTest

## struktured 2026-11-12, playing .792: "the sleep indicator with the moon and ZZZ is really lame" (the inn rest). The
## night was a black screen with a "☾ z z z" Label. It is a small scene now: InnNightSky draws a pixel sky from one
## `progress` (the moon crosses, dawn climbs), the rest is named in pixel letters as morning arrives, and the sequence
## announces its beats so the sound and the room's own lighting can follow. What a rest DOES is pinned in
## test_a_night_at_the_inn; these arms are about what it shows.

const VP := Vector2(1280, 720)

var _host: Node = null
var _phase_before := 0.0
var _beats: Array = []
var _lights: Array = []


class LitRoom:
	extends Node
	var seen: Array = []
	func rest_light(phase: String) -> void:
		seen.append(phase)


func before_each() -> void:
	_phase_before = GameState.day_phase
	_beats = []


func after_each() -> void:
	if _host and is_instance_valid(_host):
		_host.free()
	_host = null
	GameState.day_phase = _phase_before
	InputLockManager.pop_lock(InnRestSequence.LOCK_ID)
	if SoundManager:
		SoundManager.stop_music()


func _sky() -> InnNightSky:
	var sky := InnNightSky.new()
	add_child_autofree(sky)
	sky.size = VP
	return sky


func _on_beat(name: String) -> void:
	_beats.append(name)


func _until_skippable(seq: InnRestSequence) -> bool:
	var waited := 0
	while is_instance_valid(seq) and not seq._skippable and waited < 300:
		await get_tree().process_frame
		waited += 1
	return is_instance_valid(seq) and seq._skippable


func _labels_under(n: Node) -> int:
	var count := 0
	for c in n.get_children():
		count += 1 if (c is Label or c is RichTextLabel) else 0
		count += _labels_under(c)
	return count


## The moon rises from the left, peaks, and has set before morning; it is always on a whole cell.
func test_the_moon_crosses_the_sky_and_sets() -> void:
	var sky := _sky()
	sky.set_night(0.0, 0.0)
	var start: Vector2i = sky.moon_cell()
	sky.set_night(InnNightSky.MOON_SET * 0.5, 0.0)
	var high: Vector2i = sky.moon_cell()
	sky.set_night(InnNightSky.MOON_SET, 0.0)
	var low: Vector2i = sky.moon_cell()
	assert_gt(high.x, start.x, "the moon moves right across the night")
	assert_gt(low.x, high.x, "and keeps going")
	assert_lt(high.y, start.y, "it climbs to its peak (smaller y is higher)")
	assert_gt(low.y, high.y, "and comes back down to set")
	assert_gte(float(sky.cell()), 2.0, "a sky pixel is at least two screen pixels")
	assert_eq(sky.cell(), roundf(sky.cell()), "and a whole number of them")


func test_dawn_comes_at_the_end_of_the_night() -> void:
	var sky := _sky()
	sky.set_night(InnNightSky.DAWN_AT * 0.5, 0.0)
	assert_eq(sky.dawn(), 0.0, "CONTROL: mid-night there is no dawn")
	sky.set_night((InnNightSky.DAWN_AT + 1.0) / 2.0, 0.0)
	assert_almost_eq(sky.dawn(), 0.5, 0.01, "dawn is half up halfway through its span")
	sky.set_night(1.0, 0.0)
	assert_eq(sky.dawn(), 1.0, "morning is full dawn")
	assert_gt(InnNightSky.MOON_SET, InnNightSky.DAWN_AT, "the moon is still up as the sky starts to lighten")
	assert_lt(InnNightSky.MOON_SET, 1.0, "and has set by morning")


## A sky pixel follows the SCREEN, so the picture is the same on a small window and a large one.
func test_the_sky_scales_in_whole_pixels_with_the_screen() -> void:
	var small := _sky()
	small.size = Vector2(640, 360)
	var big := _sky()
	big.size = Vector2(2560, 1440)
	assert_eq(small.cell(), 2.0, "360 px tall: two-pixel cells")
	assert_eq(big.cell(), 8.0, "1440 px tall: eight-pixel cells")
	small.set_night(0.3, 0.0)
	big.set_night(0.3, 0.0)
	assert_almost_eq(float(small.moon_cell().x) * small.cell() / small.size.x, float(big.moon_cell().x) * big.cell() / big.size.x, 0.02,
		"the moon sits at the same place on both")


## The sequence shows the scene: no engine-font Label anywhere, the sky under the readout, and the beats in order. A skip
## jumps to the morning the night would have reached, so the last frame is dawn either way.
func test_a_rest_plays_the_scene_and_a_skip_lands_on_dawn() -> void:
	_host = Node.new()
	add_child(_host)
	var seq := InnRestSequence.start(_host)
	seq.beat.connect(_on_beat)
	assert_true(await _until_skippable(seq), "CONTROL: the night begins")
	assert_eq(_labels_under(seq), 0, "nothing under the night is an engine-font Label")
	assert_true(seq._sky is InnNightSky, "the night is the pixel sky")
	assert_eq(seq._readout.get_child_count(), 1, "one line names the rest by default")
	assert_true(seq._readout.get_child(0) is PixelText, "in the damage numbers' pixel letters")
	assert_eq(seq._readout.modulate.a, 0.0, "CONTROL: it is not shown while the night is young")
	seq.request_skip()
	await seq.finished
	assert_true(_beats.has("night"), "the night was announced: %s" % str(_beats))
	assert_true(_beats.has("stopped"), "a skip says the night was cut")
	assert_true(_beats.has("dawn"), "and the scene still lands on dawn")
	assert_lt(_beats.find("night"), _beats.find("dawn"), "night comes before dawn")


## The caller may name who was restored; each line is drawn, in capitals (the pixel face has no lowercase).
func test_the_morning_names_what_the_caller_says_was_restored() -> void:
	_host = Node.new()
	add_child(_host)
	var seq := InnRestSequence.start(_host)
	seq.restored_lines = PackedStringArray(["Fighter  HP +52", "Mage  MP +30"])
	assert_true(await _until_skippable(seq), "CONTROL: the night begins")
	assert_eq(seq._readout.get_child_count(), 2, "two lines, two rows")
	assert_eq((seq._readout.get_child(0) as PixelText).text, "FIGHTER  HP +52", "drawn in capitals")
	assert_gt((seq._readout.get_child(1) as PixelText).position.y, (seq._readout.get_child(0) as PixelText).position.y, "the second row is under the first")
	seq.request_skip()
	await seq.finished


## The room's own lighting follows the night when it has a rig (the seam for cowir-overworld's InteriorLighting).
func test_a_room_with_a_lighting_rig_is_told_night_and_dawn() -> void:
	var room := LitRoom.new()
	_host = room
	add_child(room)
	var seq := InnRestSequence.start(room)
	assert_true(await _until_skippable(seq), "CONTROL: the night begins")
	assert_eq(room.seen, ["night"], "the room is told night as it falls")
	seq.request_skip()
	await seq.finished
	assert_eq(room.seen, ["night", "dawn"], "and dawn as it comes")


## A sequence that is not running, with a 5.7 s ditty and a position the arm dictates.
func _clocked(position: Array) -> InnRestSequence:
	var seq := InnRestSequence.new()
	autofree(seq)
	seq._ditty_len = 5.7
	seq.night_sec = 5.7
	seq._ditty_position = func() -> float: return float(position[0])
	return seq


## The night is as long as the ditty is HEARD (cowir-music 24561), not as long as a clock says.
func test_the_night_follows_the_ditty_not_the_clock() -> void:
	var at := [2.85]
	var seq := _clocked(at)
	assert_almost_eq(seq.night_progress(0.1), 0.5, 0.001, "half the ditty heard is half the night, though the clock says 0.1 s")
	assert_almost_eq(seq.night_progress(5.0), 0.5, 0.001, "and still half when the clock says 5 s (a slow or a fast capture)")
	at[0] = 4.104
	assert_almost_eq(seq.night_progress(5.0), 4.104 / 5.7, 0.001, "dawn (0.72) lands where the music is")
	assert_gt(4.104 / 5.7, InnNightSky.DAWN_AT - 0.001, "CONTROL: that position is dawn")
	at[0] = 4.0
	assert_almost_eq(seq.night_progress(5.0), 4.104 / 5.7, 0.001, "a stair backwards in the mixer's position does not move the moon back")


func test_a_ditty_that_was_heard_and_stopped_ends_the_night() -> void:
	var at := [3.0]
	var seq := _clocked(at)
	assert_lt(seq.night_progress(3.0), 1.0, "CONTROL: mid-ditty the night is not over")
	at[0] = -1.0
	assert_eq(seq.night_progress(3.1), 1.0, "the ditty ended and the room's bed is back: that is morning, not a reason to start a clock")
	var looped := [5.0]
	var again := _clocked(looped)
	again.night_progress(5.0)
	looped[0] = 0.2
	assert_eq(again.night_progress(5.3), 1.0, "a ditty that starts over does not give a second night")


func test_a_ditty_that_never_sounds_still_reaches_dawn() -> void:
	var seq := _clocked([-1.0])
	assert_eq(seq.night_progress(0.2), 0.0, "inside the grace the night waits for the first note")
	assert_almost_eq(seq.night_progress(2.85), 0.5, 0.001, "past it the frame clock carries the night")
	assert_eq(seq.night_progress(5.7), 1.0, "to its end")
	var silent := InnRestSequence.new()
	autofree(silent)
	silent.night_sec = InnRestSequence.MIN_NIGHT_SEC
	assert_almost_eq(silent.night_progress(InnRestSequence.MIN_NIGHT_SEC / 2.0), 0.5, 0.001, "with no ditty at all the clock runs the minimum night")
	var stuck := _clocked([0.0])
	assert_eq(stuck.night_progress(5.7 + InnRestSequence.NIGHT_OVERRUN_SEC + 0.1), 1.0, "and a ditty stuck at its first sample cannot hold the night open")
	assert_lt(stuck.night_progress(1.0), 1.0, "CONTROL: before the bound it does hold it")
