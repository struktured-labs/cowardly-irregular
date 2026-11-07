extends GutTest

## struktured 2026-11-07 (via cowir-main 23434): "I don't like the victory yellow line that splashes through after a W ...
## make it more SNES-like, similar to how the damage numbers look way better". The yellow sweep band (which had itself
## replaced the 2026-10-03 ring) is gone. VICTORY! is now the damage numbers' PixelText: letters drop in one at a time on
## whole pixels, a pixel starburst lands with the last one, a one-shot rank is stamped in. These arms build the real
## overlay and read what is on screen, frame by frame.

const OverlayScript := preload("res://src/battle/VictoryOverlay.gd")
const MONSTERS := "res://data/monsters.json"


class FakeScene:
	extends Node2D
	var party_sprite_nodes: Array = []


var _overlay: Control = null
var _saved_time_scale := 1.0


func before_each() -> void:
	_saved_time_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_time_scale
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _build(rank: String = ""):
	var scene := FakeScene.new()
	add_child_autofree(scene)
	_overlay = OverlayScript.new()
	add_child(_overlay)
	_overlay.build({"char_results": [], "gold": 0, "items": [], "one_shot_rank": rank}, scene)
	return _overlay


func _title(o: Control):
	return o.get_node_or_null("VictoryTitle")


func _labels_reading_victory(n: Node) -> int:
	var count := 0
	for c in n.get_children():
		if c is Label and str((c as Label).text).replace(" ", "").contains("VICTORY"):
			count += 1
		count += _labels_reading_victory(c)
	return count


func test_the_title_is_drawn_in_pixel_glyphs() -> void:
	var o = _build()
	var title = _title(o)
	assert_not_null(title, "the overlay slammed a VictoryTitle")
	if title == null:
		return
	assert_true(title.glyphs is PixelText, "the title draws with the damage numbers' PixelText")
	assert_eq(title.glyphs.text, "VICTORY!", "and spells the word")
	assert_eq(title.glyphs.glyph_sprites.size(), 8, "one glyph per letter, the ! included")
	assert_eq(_labels_reading_victory(o), 0, "no smooth-font Label spells VICTORY anywhere under the overlay")
	assert_eq(title.glyphs.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the glyphs are nearest-filtered")


## The one the band failed: nothing in the beat may sit between pixels or scale by a fraction on ANY frame.
func test_every_frame_of_the_beat_is_on_whole_pixels() -> void:
	var o = _build("S")
	var title = _title(o)
	assert_not_null(title, "CONTROL: a title to watch")
	if title == null:
		return
	var frames := 0
	var bad := ""
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2200 and bad == "":
		await get_tree().process_frame
		frames += 1
		bad = _off_grid(o)
	assert_gt(frames, 20, "the beat was actually sampled (%d frames)" % frames)
	assert_eq(bad, "", "integer position and integer glyph scale on every frame")


func _off_grid(o: Control) -> String:
	for n in [o.get_node_or_null("VictoryTitle"), o.get_node_or_null("VictoryRankStamp"), o.get_node_or_null("VictorySubtitle")]:
		if n == null or not is_instance_valid(n):
			continue
		if n.position != n.position.round() or n.scale != Vector2.ONE:
			return "%s at %s scale %s" % [n.name, n.position, n.scale]
		for spr in n.glyphs.glyph_sprites:
			if spr.position != spr.position.round():
				return "%s glyph '%s' between pixels at %s" % [n.name, spr.get_meta("char"), spr.position]
			if spr.scale != spr.scale.round() or spr.scale.x < 1.0:
				return "%s glyph '%s' scaled %s" % [n.name, spr.get_meta("char"), spr.scale]
	for c in o.get_children():
		if c is Node2D and c.name.begins_with("VictoryStarburst") and (c as Node2D).position != (c as Node2D).position.round():
			return "starburst at %s" % (c as Node2D).position
	return ""


## Letters arrive one at a time, left to right: each glyph's first visible frame is no earlier than the one before it,
## and the word is not all there at once.
func test_the_letters_drop_in_one_at_a_time() -> void:
	var o = _build()
	var title = _title(o)
	if title == null:
		assert_not_null(title, "CONTROL: a title to watch")
		return
	var letters: Array = title.glyphs.glyph_sprites
	var first_seen: Array = []
	first_seen.resize(letters.size())
	first_seen.fill(-1)
	var partial := false
	var frame := 0
	while frame < 200 and first_seen.has(-1):
		await get_tree().process_frame
		frame += 1
		var shown := 0
		for i in letters.size():
			if letters[i].visible:
				shown += 1
				if first_seen[i] == -1:
					first_seen[i] = frame
		partial = partial or (shown > 0 and shown < letters.size())
	assert_false(first_seen.has(-1), "every letter appeared: %s" % str(first_seen))
	assert_true(partial, "some frame showed part of the word: the letters do not arrive together")
	for i in range(1, first_seen.size()):
		assert_true(int(first_seen[i]) >= int(first_seen[i - 1]), "letter %d is not ahead of letter %d: %s" % [i, i - 1, str(first_seen)])
	assert_gt(int(first_seen[-1]), int(first_seen[0]), "the last letter lands after the first")


func test_the_band_is_gone_and_a_starburst_marks_the_landing() -> void:
	var o = _build()
	var saw_burst := false
	var saw_band := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1200:
		await get_tree().process_frame
		for c in o.get_children():
			saw_burst = saw_burst or c.name.begins_with("VictoryStarburst")
			saw_band = saw_band or c.name.begins_with("VictorySweepBand")
	assert_true(saw_burst, "the slam's frame put a pixel starburst on screen")
	assert_false(saw_band, "the yellow sweep band never appears")


## Timing the cards and music build on: the word lands inside a second, and the cards' wait is derived from that landing.
func test_the_word_lands_inside_a_second_and_the_cards_wait_for_it() -> void:
	var o = _build()
	assert_gt(o._title_land, 0.0, "CONTROL: the landing time was computed")
	assert_lte(o._title_land, 1.0, "the whole word is down within a second (cowir-music 23438)")
	assert_almost_eq(o._title_clear_at, (o._title_land + float(OverlayScript.GRADE_HOLD[OverlayScript.Grade.NORMAL]) + 0.3) * Engine.time_scale,
		0.001, "a card under the title waits for the landing, the hold and the dock, in game seconds")
	assert_true(o._title_rest.encloses(o._title_docked), "the title's footprint includes its dock")


## One press snaps the beat to its end: the word docked where the cards and strip expect it, every letter shown at rest.
## The beat runs on the WALL clock (cowir-music 23438, main 23488): at 2x the word still takes its full real time to land,
## where on game time it would be down in half. Measured as real ms until the last letter first shows.
func test_at_double_speed_the_word_lands_on_real_time() -> void:
	Engine.time_scale = 2.0
	var o = _build()
	var title = _title(o)
	if title == null:
		assert_not_null(title, "CONTROL: at 2x the flourish still plays")
		return
	var last: Sprite2D = title.glyphs.glyph_sprites[-1]
	var want_ms: float = float(OverlayScript.LETTER_STAGGER) * float(title.glyphs.glyph_sprites.size() - 1) * 1000.0
	var start := Time.get_ticks_msec()
	while not last.visible and Time.get_ticks_msec() - start < 2000:
		await get_tree().process_frame
	var took: float = float(Time.get_ticks_msec() - start)
	assert_true(last.visible, "CONTROL: the last letter appeared")
	assert_gt(took, want_ms * 0.8, "the last letter starts after ~%.0f ms of REAL time at 2x, not half that (took %.0f)" % [want_ms, took])
	assert_almost_eq(o._title_clear_at, (o._title_land + float(OverlayScript.GRADE_HOLD[OverlayScript.Grade.NORMAL]) + 0.3) * 2.0, 0.001,
		"so the cards' game-time wait doubles to cover the same real beat")


func test_a_press_snaps_the_word_to_its_dock() -> void:
	var o = _build()
	var title = _title(o)
	if title == null:
		assert_not_null(title, "CONTROL: a title to watch")
		return
	await get_tree().process_frame
	o.complete_now()
	assert_eq(title.position, o._title_docked.position, "the title sits at the dock the stack is laid out under")
	assert_eq(title.size, o._title_docked.size, "at the dock's size")
	assert_gte(title.glyphs.pixel_scale.x, 2, "docked, a glyph pixel is still at least 2 screen pixels")
	for spr in title.glyphs.glyph_sprites:
		assert_true(spr.visible, "'%s' is shown after the snap" % spr.get_meta("char"))
		assert_eq(spr.position, title.glyphs.rest_position(spr), "'%s' rests on its line" % spr.get_meta("char"))


func test_a_rank_is_stamped_only_when_there_is_one() -> void:
	var ranked = _build("S")
	var stamp = ranked.get_node_or_null("VictoryRankStamp")
	assert_not_null(stamp, "an S-rank one-shot is stamped in")
	if stamp != null:
		assert_eq(stamp.text, "S-RANK!", "with its rank")
	_overlay.queue_free()
	var plain = _build("")
	assert_null(plain.get_node_or_null("VictoryRankStamp"), "CONTROL: no rank, no stamp")


## Every boss name can be billed in the pixel face: a missing glyph would draw as '?' in the subtitle.
func test_every_boss_name_is_drawable() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	var names: Array = []
	if data is Dictionary:
		for k in data:
			var v = data[k]
			if v is Dictionary and v.get("boss", false):
				names.append(str(v.get("name", k)))
	assert_gt(names.size(), 10, "floor: the bosses were read (%d)" % names.size())
	var missing: Array = []
	for n in names:
		var line := "BARD TAKES THE SPOTLIGHT — %s FELLED" % n.to_upper()
		for ch in line:
			if not PixelText.can_draw(ch) and not missing.has(ch):
				missing.append(ch)
	assert_eq(missing, [], "characters in a billed boss line with no glyph")


## The ticks are pitched by what plays under them (cowir-sfx 23509). With no bed playing, the key falls back to this world's
## victory bed, and that key is one the transpose table knows, so the fallback lands on a real row rather than a silent 0.
func test_the_ticks_key_to_a_bed_the_transpose_table_knows() -> void:
	var o = _build()
	var mp: AudioStreamPlayer = SoundManager._music_player
	var was_playing := mp != null and mp.playing
	if was_playing:
		mp.stop()
	var key: String = o._letters_under_key()
	var table = JSON.parse_string(FileAccess.get_file_as_string("res://data/victory_letter_transpose.json"))
	assert_true(table is Dictionary and (table as Dictionary).has("transpose"), "CONTROL: the transpose table was read")
	assert_eq(key, "victory_" + SoundManager.get_current_world_suffix(), "nothing playing: this world's victory bed")
	if table is Dictionary:
		assert_true(((table as Dictionary).get("transpose", {}) as Dictionary).has(key), "'%s' has a row in the transpose table" % key)
