extends GutTest

## struktured (main 23405/23406/23410): "I don't love the new fire magic animation … the original one was cooler and
## more on point with fire", then "more phases", then "really really really over the top". Fire, Fira and Firaga are
## sequences in Fire's OWN look: heat gathers, a flame flies, the ORIGINAL eruption lands (boosted), and each tier adds
## a phase (Fira a pillar, Firaga a second detonation). The fractal that was Fire's is Edit Formula's, in glitch cyan.
## This is the reference sequence for the authoring guide (docs/vfx/sequence-authoring-guide.md).

const FIRE_KINDS := ["gather", "bolt", "eruption", "pillar", "fall", "flash", "ring", "shake"]
const FRACTAL_KINDS := ["emit", "spin_fling"]


func _seq(id: String) -> Dictionary:
	var s: Dictionary = FractalFX.load_sequence(id)
	assert_false(s.is_empty(), "CONTROL: the sequence %s exists" % id)
	return s


func _kinds(seq: Dictionary) -> Array:
	var out: Array = []
	for ph in seq.get("phases", []):
		out.append(str(ph.get("kind", "")))
	return out


## Phases a tier-1 caster sees.
func _base(seq: Dictionary) -> int:
	var n := 0
	for ph in seq.get("phases", []):
		if int(ph.get("min_tier", 1)) <= 1:
			n += 1
	return n


func _first(seq: Dictionary, kind: String) -> Dictionary:
	for ph in seq.get("phases", []):
		if str(ph.get("kind", "")) == kind:
			return ph
	return {}


func _ability_sequence(id: String) -> String:
	var vfx = JobSystem.get_ability(id).get("vfx", {})
	return str(vfx.get("sequence", vfx.get("glory", ""))) if vfx is Dictionary else ""


func test_each_fire_tier_plays_its_own_sequence_in_fires_own_look() -> void:
	var problems: Array = []
	for pair in [["fire", "fire_battle"], ["fira", "fira_battle"], ["firaga", "glory_firaga"]]:
		assert_eq(_ability_sequence(pair[0]), pair[1], "%s plays %s" % pair)
		var kinds := _kinds(_seq(pair[1]))
		for k in kinds:
			if k in FRACTAL_KINDS:
				problems.append("%s still uses the fractal '%s'" % [pair[1], k])
			elif not (k in FIRE_KINDS):
				problems.append("%s uses '%s', which is not in Fire's vocabulary" % [pair[1], k])
		for must in ["gather", "bolt", "eruption", "fall"]:
			if not (must in kinds):
				problems.append("%s has no '%s' phase" % [pair[1], must])
	assert_eq(problems, [], "every fire tier is gather → flame → the original eruption → falling embers, with no fractal shapes")


func test_each_tier_is_visibly_bigger_than_the_last() -> void:
	var fire := _seq("fire_battle")
	var fira := _seq("fira_battle")
	var firaga := _seq("glory_firaga")
	var b1 := float(_first(fire, "eruption").get("boost", 1.0))
	var b2 := float(_first(fira, "eruption").get("boost", 1.0))
	var b3 := float(_first(firaga, "eruption").get("boost", 1.0))
	assert_gt(b1, 1.0, "even plain Fire erupts harder than the original did (his 'over the top')")
	assert_gt(b2, b1, "Fira's eruption is bigger than Fire's")
	assert_gt(b3, b2, "Firaga's is bigger still")
	assert_false("pillar" in _kinds(fire), "CONTROL: plain Fire has no pillar")
	assert_true("pillar" in _kinds(fira), "Fira adds a pillar of flame")
	assert_eq(_kinds(firaga).count("eruption"), 2, "Firaga adds a SECOND detonation")
	assert_gt(_base(fira), _base(fire), "more phases per tier (for the same caster)")
	assert_gt(_base(firaga), _base(fira), "more phases per tier (for the same caster)")
	assert_gt(int(_first(firaga, "gather").get("count", 0)), int(_first(fire, "gather").get("count", 0)), "and a bigger gather")


func test_damage_lands_on_the_eruption_and_the_hold_stays_in_budget() -> void:
	for id in ["fire_battle", "fira_battle", "glory_firaga"]:
		var seq := _seq(id)
		var start := float(seq.get("start", 0.0))
		var impact := FractalFX.impact_time(seq) - start
		assert_almost_eq(impact, float(_first(seq, "eruption").get("at", -1.0)), 0.001, "%s lands its damage when the eruption does" % id)
		var bolt := _first(seq, "bolt")
		assert_almost_eq(float(bolt.get("at", 0.0)) + float(bolt.get("dur", 0.0)), impact, 0.001, "%s: the flame arrives as it erupts" % id)
		assert_lte(FractalFX.impact_time(seq), CAST_RELEASE + 0.70, "%s lands within 0.7 s of the cast's release, so a turn holds no longer than a boss signature" % id)


## main 23890: nothing happened for the cast pose's first 0.75 s (2 s real at 1.5x). The wind-up now starts WITH the pose
## and the flame leaves on the pose's release frame.
const CAST_RELEASE := 0.75


func test_the_wind_up_fills_the_cast_pose() -> void:
	for id in ["fire_battle", "fira_battle", "glory_firaga"]:
		var seq := _seq(id)
		var start := float(seq.get("start", 0.0))
		var gather := _first(seq, "gather")
		var bolt := _first(seq, "bolt")
		assert_lte(start + float(gather.get("at", 9.0)), 0.2, "%s: heat gathers from the first frames of the cast, not after it" % id)
		assert_almost_eq(start + float(bolt.get("at", 0.0)), CAST_RELEASE, 0.02, "%s: the flame leaves on the pose's release frame" % id)
		assert_almost_eq(float(gather.get("at", 0.0)) + float(gather.get("dur", 0.0)), float(bolt.get("at", 0.0)), 0.02,
			"%s: the gather lasts until the launch, so the screen is never idle" % id)
	assert_eq(str(_seq("glory_firaga").get("windup", {}).get("kind", "")), "gather", "Firaga gathers under its title card too")
	assert_true(_seq("fire_battle").get("windup", {}).is_empty(), "CONTROL: plain Fire has no title card, so no windup phase")


func test_the_fractal_moved_to_edit_formula_and_carries_no_fire() -> void:
	assert_eq(_ability_sequence("edit_formula"), "edit_formula_battle", "Edit Formula plays the fractal that was Fire's")
	var seq := _seq("edit_formula_battle")
	assert_true("emit" in _kinds(seq) and "spin_fling" in _kinds(seq), "CONTROL: it is the fractal sequence")
	var text := JSON.stringify(seq)
	for fire_word in ["\"flame\"", "\"fire\"", "\"ember\"", "beat_fire"]:
		assert_false(fire_word in text, "Edit Formula's sequence still names %s" % fire_word)
	assert_true(FractalFX.PALETTES.has("glitch"), "and its glitch palette exists")


func test_an_element_phase_draws_and_boost_draws_more() -> void:
	var container: Node2D = EffectSystem._effects_container
	assert_not_null(container, "CONTROL: EffectSystem has its container")
	if container == null:
		return
	for kind in ["eruption", "pillar", "gather", "fall", "rise"]:
		var before := container.get_child_count()
		EffectSystem.run_element_phase(kind, Vector2(300, 300), Vector2(900, 300), 1.0, {"dur": 0.1})
		assert_gt(container.get_child_count(), before, "a '%s' phase draws something" % kind)
	var base := _eruption_particles(1.0)
	var boosted := _eruption_particles(3.0)
	assert_gt(base, 0, "CONTROL: an eruption has particles")
	assert_gt(boosted, base * 2, "boost 3.0 erupts with far more flame than boost 1.0 (%d vs %d)" % [boosted, base])


func _eruption_particles(boost: float) -> int:
	var container: Node2D = EffectSystem._effects_container
	var before: Dictionary = {}
	for c in container.get_children():
		before[c] = true
	EffectSystem.run_element_phase("eruption", Vector2(300, 300), Vector2.ZERO, 1.0, {"boost": boost})
	for c in container.get_children():
		if not before.has(c):
			return c.get_child_count()
	return 0


## Turbo and the grind console (autogrind 23412): only the impact's own phases, at once, so a cast costs no wall time.
var _ran: Array = []


func _note_phase(kind: String, _at: Vector2, _from: Vector2, _power: float, phase: Dictionary) -> void:
	_ran.append("%s:%s" % [kind, phase.get("palette", "")] if phase.has("note_palette") else kind)


func test_compact_plays_only_the_impact() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var seq := _seq("glory_firaga")
	_ran = []
	var fx := FractalFX.new(host, 7)
	fx.on_element_phase = _note_phase
	fx.play(seq, Vector2(900, 300), Vector2(300, 300), 1.0, true)
	assert_eq(_ran, ["eruption"], "compact runs the impact eruption at once and nothing else of Fire's own (no gather, pillar, second blast or embers)")
	_ran = []
	var full := FractalFX.new(host, 7)
	full.on_element_phase = _note_phase
	full.play({"phases": [{"kind": "gather", "at": 0.0}, {"kind": "eruption", "at": 0.3}]}, Vector2(900, 300), Vector2(300, 300), 1.0, false)
	assert_eq(_ran, ["gather"], "CONTROL: a full sequence starts with its first phase and waits for the rest")
	_ran = []
	var cold := FractalFX.new(host, 7)
	cold.on_element_phase = _note_phase
	cold.play({"phases": [{"kind": "rise", "at": 0.0, "palette": "frost", "note_palette": true}]}, Vector2.ZERO, Vector2.ZERO)
	assert_true("rise:frost" in _ran, "the shared mote phases carry their palette, so another lane's sequence is not fire-coloured")
	## A sequence outlives this arm on its own timers: it must not keep a callback into a finished test.
	for f in [fx, full, cold]:
		f.on_element_phase = Callable()
	await get_tree().create_timer(0.5).timeout
