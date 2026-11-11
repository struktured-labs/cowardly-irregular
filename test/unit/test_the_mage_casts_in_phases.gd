extends GutTest

## main 23993: finish the Mage. Blizzard/Blizzara, Thunder/Thundara, Dark Bolt and Chain Lightning are sequences in each
## element's ORIGINAL look (the eruption EffectSystem always drew for it), with Fire's shape: the wind-up fills the cast
## pose, something leaves the hand on the release frame, and the damage lands on the eruption.

const CAST_RELEASE := 0.75
const FRACTAL_KINDS := ["emit", "spin_fling"]
## ability → [sequence, the element whose original effect erupts, the palette its motes are drawn in]
const SPELLS := {
	"blizzard": ["blizzard_battle", "ice", "frost"], "blizzara": ["blizzara_battle", "ice", "frost"],
	"thunder": ["thunder_battle", "lightning", "spark"], "thundara": ["thundara_battle", "lightning", "spark"],
	"dark_bolt": ["dark_bolt_battle", "dark", "void"], "chain_lightning": ["chain_lightning_battle", "lightning", "spark"],
}
const TIERS := [["blizzard_battle", "blizzara_battle"], ["thunder_battle", "thundara_battle"]]


func _seq(id: String) -> Dictionary:
	var s: Dictionary = FractalFX.load_sequence(id)
	assert_false(s.is_empty(), "CONTROL: the sequence %s exists" % id)
	return s


func _kinds(seq: Dictionary) -> Array:
	var out: Array = []
	for ph in seq.get("phases", []):
		out.append(str(ph.get("kind", "")))
	return out


func _first(seq: Dictionary, kind: String) -> Dictionary:
	for ph in seq.get("phases", []):
		if str(ph.get("kind", "")) == kind:
			return ph
	return {}


## Phases a tier-1 caster sees.
func _base(seq: Dictionary) -> int:
	var n := 0
	for ph in seq.get("phases", []):
		if int(ph.get("min_tier", 1)) <= 1:
			n += 1
	return n


func test_each_spell_names_its_sequence_in_its_own_element() -> void:
	for id in SPELLS:
		var ability: Dictionary = JobSystem.get_ability(id)
		var vfx = ability.get("vfx", {})
		assert_eq(str(vfx.get("sequence", "")) if vfx is Dictionary else "", SPELLS[id][0], "%s plays %s" % [id, SPELLS[id][0]])
		assert_eq(str(ability.get("element", "")), SPELLS[id][1], "CONTROL: %s is still a %s spell" % [id, SPELLS[id][1]])
		var seq := _seq(SPELLS[id][0])
		assert_true(EffectSystem.ERUPTION_TYPES.has(SPELLS[id][1]), "CONTROL: EffectSystem has an original effect for %s" % SPELLS[id][1])
		for ph in seq.get("phases", []):
			var kind := str(ph.get("kind", ""))
			assert_false(kind in FRACTAL_KINDS, "%s uses the fractal '%s'" % [SPELLS[id][0], kind])
			if kind == "eruption":
				assert_eq(str(ph.get("element", "")), SPELLS[id][1], "%s erupts in its own element, not Fire's default" % SPELLS[id][0])
			if ph.has("palette"):
				assert_eq(str(ph["palette"]), SPELLS[id][2], "%s: a '%s' phase is drawn in %s" % [SPELLS[id][0], kind, SPELLS[id][2]])
		for must in ["gather", "bolt", "eruption"]:
			assert_true(must in _kinds(seq), "%s has a '%s' phase" % [SPELLS[id][0], must])


func test_the_wind_up_fills_the_cast_pose_and_something_leaves_on_the_release() -> void:
	for id in SPELLS:
		var sid: String = SPELLS[id][0]
		var seq := _seq(sid)
		var start := float(seq.get("start", 0.0))
		var gather := _first(seq, "gather")
		assert_eq(str(gather.get("origin", "")), "caster", "%s gathers at the caster" % sid)
		assert_lte(start + float(gather.get("at", 9.0)), 0.2, "%s gathers from the first frames of the cast" % sid)
		var gather_end := float(gather.get("at", 0.0)) + float(gather.get("dur", 0.0))
		assert_almost_eq(start + gather_end, CAST_RELEASE, 0.02, "%s: the gather lasts until the pose's release frame" % sid)
		var leaves := 0
		for ph in seq.get("phases", []):
			if str(ph.get("kind", "")) != "gather" and absf(float(ph.get("at", -9.0)) - gather_end) <= 0.02:
				leaves += 1
		assert_gt(leaves, 0, "%s: a phase starts on the release frame, so the screen is never idle" % sid)


func test_damage_lands_on_the_eruption_as_the_bolt_arrives() -> void:
	for id in SPELLS:
		var sid: String = SPELLS[id][0]
		var seq := _seq(sid)
		var impact := FractalFX.impact_time(seq) - float(seq.get("start", 0.0))
		assert_almost_eq(impact, float(_first(seq, "eruption").get("at", -1.0)), 0.001, "%s lands its damage when it erupts" % sid)
		var bolt := _first(seq, "bolt")
		assert_almost_eq(float(bolt.get("at", 0.0)) + float(bolt.get("dur", 0.0)), impact, 0.001, "%s: the bolt arrives as it erupts" % sid)
		assert_lte(FractalFX.impact_time(seq), CAST_RELEASE + 0.70, "%s holds the turn no longer than Fire does" % sid)
		assert_almost_eq(FractalFX.impact_time(seq), FractalFX.impact_time(_seq("fire_battle")), 0.001, "%s lands on Fire's beat" % sid)


func test_the_second_tier_is_visibly_bigger() -> void:
	for pair in TIERS:
		var low := _seq(pair[0])
		var high := _seq(pair[1])
		assert_gt(float(_first(high, "eruption").get("power", 1.0)), float(_first(low, "eruption").get("power", 1.0)), "%s erupts bigger" % pair[1])
		assert_gt(int(_first(high, "gather").get("count", 0)), int(_first(low, "gather").get("count", 0)), "%s gathers more" % pair[1])
		assert_gt(_base(high), _base(low), "%s has more phases for the same caster" % pair[1])
	assert_true("pillar" in _kinds(_seq("blizzara_battle")), "Blizzara adds a spire of frost")
	assert_false("pillar" in _kinds(_seq("blizzard_battle")), "CONTROL: Blizzard has none")
	assert_eq(_kinds(_seq("thundara_battle")).count("eruption"), 2, "Thundara's sky answers with a second strike")
	assert_eq(_kinds(_seq("thunder_battle")).count("eruption"), 1, "CONTROL: Thunder strikes once")


func test_every_cue_a_phase_names_is_in_the_manifest() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var text := JSON.stringify(raw)
	var named := 0
	for id in SPELLS:
		for ph in _seq(SPELLS[id][0]).get("phases", []):
			if ph.has("sfx"):
				named += 1
				assert_true(("\"%s\"" % ph["sfx"]) in text, "%s names the cue %s, which the manifest lacks" % [SPELLS[id][0], ph["sfx"]])
	assert_gt(named, 12, "FLOOR: the sequences name cues at all")


func test_each_original_effect_draws() -> void:
	var container: Node2D = EffectSystem._effects_container
	assert_not_null(container, "CONTROL: EffectSystem has its container")
	if container == null:
		return
	for element in ["ice", "lightning", "dark"]:
		var before := container.get_child_count()
		EffectSystem.run_element_phase("eruption", Vector2(300, 300), Vector2(900, 300), 1.0, {"element": element})
		assert_gt(container.get_child_count(), before, "the %s eruption draws something" % element)
	for palette in ["frost", "spark", "void"]:
		var before := container.get_child_count()
		EffectSystem.run_element_phase("gather", Vector2(300, 300), Vector2(300, 300), 1.0, {"dur": 0.1, "palette": palette})
		assert_gt(container.get_child_count(), before, "a gather in %s draws something" % palette)
