extends GutTest

## struktured 2026-11-11 (via cowir-main 23756/23772): every ability fantastic; "the party-wide songs should visibly wash
## over all five members", and a landed effect must read apart from one that did nothing. The Cleric's wards and the Bard's
## songs play sequences built from three kinds this tip adds to the shared vocabulary (cowir-battle 23774): `plates` (a
## ward assembling), `ribbon` (staff lines from the singer) and `glyphs` (notes, Z's), plus a sequence-level `travel` so a
## song reaches a farther ally later. These arms drive the real runner and read what it put on screen.

const FX := preload("res://src/battle/FractalFX.gd")
const SCENE_SRC := "res://src/battle/BattleScene.gd"
const CASTS := {"protect": "protect_battle", "shell": "shell_battle", "battle_hymn": "battle_hymn_battle",
	"inspiring_melody": "inspiring_melody_battle", "lullaby": "lullaby_battle", "discord": "discord_battle"}
const PARTY_WIDE := ["battle_hymn_battle", "inspiring_melody_battle", "discord_battle"]


func _seq(id: String) -> Dictionary:
	return FX.load_sequence(id)


func _phases(seq: Dictionary, kind: String) -> Array:
	var out: Array = []
	for ph in seq.get("phases", []):
		if str((ph as Dictionary).get("kind", "")) == kind:
			out.append(ph)
	return out


## Runs ONE phase now and returns the host it drew on.
func _draw(phase: Dictionary, from := Vector2(700, 300), to := Vector2(300, 300)) -> Node2D:
	var host := Node2D.new()
	add_child_autofree(host)
	var fx = FX.new(host, 11)
	fx.play({"phases": [phase]}, from, to)
	return host


func _count(host: Node, type_name: String) -> int:
	var n := 0
	for c in host.get_children():
		if c.is_class(type_name):
			n += 1
	return n


func test_every_ward_and_song_names_a_sequence_that_exists() -> void:
	for id in CASTS:
		var ability: Dictionary = JobSystem.get_ability(id)
		assert_eq(str(AbilityVFX.resolve(ability).get("sequence", "")), str(CASTS[id]), "%s plays its sequence" % id)
		assert_false(_seq(str(CASTS[id])).is_empty(), "%s exists" % CASTS[id])
	var riff = JobSystem.get_ability("riff").get("vfx", {})
	assert_eq(str(riff.get("melee", "")) if riff is Dictionary else "", "melee_riff", "Riff's chord rides the melee path, not a cast")
	assert_false(_seq("melee_riff").is_empty(), "melee_riff exists")
	assert_eq(str(AbilityVFX.resolve(JobSystem.get_ability("dark_bolt")).get("sequence", "")), "",
		"CONTROL: an ability on the plain path resolves to no sequence")


## A ward is BUILT in front of you: the plates exist, they start away from their slots, and they arrive.
func test_a_ward_assembles_plate_by_plate() -> void:
	var wall: Dictionary = _phases(_seq("protect_battle"), "plates")[0]
	var dome: Dictionary = _phases(_seq("shell_battle"), "plates")[0]
	var host := _draw(wall)
	assert_eq(_count(host, "Polygon2D"), 7, "Protect's wall is a honeycomb of seven plates")
	var first: Polygon2D = null
	for c in host.get_children():
		if c is Polygon2D:
			first = c
			break
	var began: Vector2 = first.position
	var frames := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(float(wall.get("dur", 0.35)) * 1000.0) + 120:
		await get_tree().process_frame
		frames += 1
	assert_gt(frames, 3, "CONTROL: the assembly was given time to run (%d frames)" % frames)
	assert_true(is_instance_valid(first) and first.position.distance_to(began) > 20.0,
		"a plate flew in to its slot (moved %.0f px)" % (first.position.distance_to(began) if is_instance_valid(first) else -1.0))
	assert_eq(_count(_draw(dome), "Polygon2D"), int(dome.get("count", 0)), "Shell's dome has the plates its data asks for")
	assert_almost_eq(FX.phase_duration(wall), float(wall["dur"]) + float(wall["hold"]) + FX.PLATE_FADE, 0.001,
		"the runner knows how long a ward stays up")


## Protect and Shell must read apart at a glance: a different SHAPE and a different COLOUR, not one of the two.
func test_the_two_wards_read_apart() -> void:
	var wall: Dictionary = _phases(_seq("protect_battle"), "plates")[0]
	var dome: Dictionary = _phases(_seq("shell_battle"), "plates")[0]
	assert_ne(str(wall.get("shape", "wall")), str(dome.get("shape", "wall")), "a wall and a dome")
	assert_ne(str(wall.get("palette", "")), str(dome.get("palette", "")), "in two colours")
	for key in [wall.get("palette", ""), dome.get("palette", "")]:
		assert_true(FX.PALETTES.has(str(key)), "'%s' is a FractalFX palette" % key)


## The wash: a party-wide song carries a ribbon from the singer and reaches a farther member LATER.
func test_a_party_wide_song_reaches_the_far_end_later() -> void:
	var singer := Vector2(900, 300)
	var near := Vector2(800, 320)
	var far := Vector2(500, 360)
	for id in PARTY_WIDE:
		var seq := _seq(id)
		assert_gt(_phases(seq, "ribbon").size(), 0, "%s draws a staff ribbon" % id)
		assert_gt(FX.travel_delay(seq, singer, far), FX.travel_delay(seq, singer, near), "%s lands later on the farther target" % id)
		assert_lt(FX.travel_delay(seq, singer, far), 0.35, "%s: the far end waits under a third of a second" % id)
	assert_eq(FX.travel_delay(_seq("lullaby_battle"), singer, far), 0.0, "CONTROL: a single-target song has no travel")
	## And the runner honours it: the same sequence played to the far target ends later by that delay.
	var seq := _seq("battle_hymn_battle")
	var host := Node2D.new()
	add_child_autofree(host)
	var t_near: float = FX.new(host, 3).play(seq, singer, near)
	var t_far: float = FX.new(host, 3).play(seq, singer, far)
	assert_almost_eq(t_far - t_near, FX.travel_delay(seq, singer, far) - FX.travel_delay(seq, singer, near), 0.001,
		"play() starts the far target's phases later by the travel")


## Turbo and the grind console (compact) play the impact at once: the wash adds NO time there, near or far (autogrind 23825).
func test_at_turbo_the_wash_costs_no_time() -> void:
	var singer := Vector2(900, 300)
	var seq := _seq("battle_hymn_battle")
	var host := Node2D.new()
	add_child_autofree(host)
	var t_near: float = FX.new(host, 3).play(seq, singer, Vector2(800, 320), 1.0, true)
	var t_far: float = FX.new(host, 3).play(seq, singer, Vector2(500, 360), 1.0, true)
	assert_almost_eq(t_far, t_near, 0.001, "compact: the far target ends when the near one does")
	var src := FileAccess.get_file_as_string("res://src/battle/EffectSystem.gd")
	assert_true(src.contains('"impact": 0.01 if compact else FractalFX.impact_time(seq) + FractalFX.travel_delay(seq, from, to)'),
		"and spawn_sequence reports the compact impact without the travel")


func test_a_ribbon_and_its_notes_are_drawn() -> void:
	var ribbon: Dictionary = _phases(_seq("battle_hymn_battle"), "ribbon")[0]
	var host := _draw(ribbon)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(float(ribbon.get("dur", 0.3)) * 1000.0) + 80:
		await get_tree().process_frame
	assert_gt(_count(host, "Sprite2D"), 10, "the staff lines were stroked from the singer to the target (%d strokes alive)" % _count(host, "Sprite2D"))
	var notes := _draw({"kind": "glyphs", "glyph": "note", "count": 3, "dur": 0.2})
	await get_tree().create_timer(0.15).timeout
	var seen := 0
	for c in notes.get_children():
		if c is Sprite2D:
			seen += 1
			assert_eq((c as Sprite2D).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "a note is a crisp pixel glyph")
	assert_gt(seen, 0, "notes popped")
	assert_ne(FX._glyph_tex("note").get_size(), FX._glyph_tex("z").get_size(), "CONTROL: a note and a Z are different glyphs")


## The outcome rule (the guide, section 6): Lullaby's own sequence never draws the sleep. The Z's belong to the LANDED beat,
## which the engine plays only when the status lands, so a resisted lullaby cannot look like a landed one.
func test_the_sleep_is_the_landed_beats_not_the_songs() -> void:
	for ph in _phases(_seq("lullaby_battle"), "glyphs"):
		assert_ne(str((ph as Dictionary).get("glyph", "note")), "z", "Lullaby's cast draws notes, never Z's")
	var landed := _seq("landed_sleep")
	assert_false(landed.is_empty(), "landed_sleep exists")
	var zs := 0
	for ph in _phases(landed, "glyphs"):
		zs += 1 if str((ph as Dictionary).get("glyph", "")) == "z" else 0
	assert_gt(zs, 0, "the landed beat draws the Z's")
	var beats: Dictionary = load(SCENE_SRC).get_script_constant_map().get("LANDED_BEATS", {})
	assert_gt(beats.size(), 2, "floor: BattleScene.LANDED_BEATS was read")
	assert_eq(str(beats.get("sleep", "")), "landed_sleep", "a landed sleep plays it")


## Inside the guide's budgets, and still something to see at turbo (only the phases AT the impact play there).
func test_every_one_lands_inside_its_budget_and_shows_at_turbo() -> void:
	for id in CASTS.values():
		var seq := _seq(id)
		var impact: float = FX.impact_time(seq) - float(seq.get("start", 0.0))
		assert_lte(impact, 0.65, "%s lands by 0.65 s (the guide's tier-2 budget)" % id)
		var at_impact := 0
		for ph in seq.get("phases", []):
			at_impact += 1 if absf(float((ph as Dictionary).get("at", 0.0)) - impact) <= 0.02 else 0
		assert_gt(at_impact, 0, "%s has a phase at its impact" % id)
