extends GutTest

## struktured 2026-11-11 (via cowir-main 23756/23760): "make the battle animations FANTASTIC", every ability. The Cleric's
## heals played one pose and one burst. Each now plays a data/vfx_sequences.json sequence in cowir-battle's phase vocabulary
## (23774): light gathers, travels, lands at IMPACT, and leaves something behind. Raise is the showcase. These arms judge the
## RELATIONSHIPS the design promises (a tier is bigger than the one under it, the free move is the smallest, Raise the
## largest), not their numbers, and that every sequence still shows something at turbo.

const FX := preload("res://src/battle/FractalFX.gd")
## ability id -> the sequence its row must name. regenerate shares regen's.
const HEALS := {"cure": "cure_battle", "cura": "cura_battle", "crystal_heal": "crystal_heal_battle", "regen": "regen_battle",
	"regenerate": "regen_battle", "esuna": "esuna_battle", "pray": "pray_battle", "raise": "raise_battle"}


func _seq(id: String) -> Dictionary:
	return FX.load_sequence(id)


func _motes(seq: Dictionary) -> int:
	var n := 0
	for ph in seq.get("phases", []):
		n += int((ph as Dictionary).get("count", 0))
	return n


func _largest(seq: Dictionary, kind: String, field: String) -> float:
	var best := 0.0
	for ph in seq.get("phases", []):
		if str((ph as Dictionary).get("kind", "")) == kind:
			best = maxf(best, float((ph as Dictionary).get(field, 0.0)))
	return best


func _length(seq: Dictionary) -> float:
	var end := 0.0
	for ph in seq.get("phases", []):
		end = maxf(end, float((ph as Dictionary).get("at", 0.0)) + FX.phase_duration(ph))
	return end


func test_every_heal_names_a_sequence_that_exists() -> void:
	for id in HEALS:
		var ability: Dictionary = JobSystem.get_ability(id)
		assert_false(ability.is_empty(), "CONTROL: %s is an ability" % id)
		assert_eq(str(AbilityVFX.resolve(ability).get("sequence", "")), str(HEALS[id]), "%s plays its sequence" % id)
		assert_false(_seq(str(HEALS[id])).is_empty(), "%s exists in vfx_sequences.json" % HEALS[id])
	assert_eq(str(AbilityVFX.resolve(JobSystem.get_ability("dark_bolt")).get("sequence", "")), "",
		"CONTROL: an ability on the plain path resolves to no sequence")


func test_every_phase_uses_the_shared_palettes() -> void:
	var seen := 0
	for id in HEALS.values():
		for ph in _seq(id).get("phases", []):
			for key in ["palette", "trail_palette", "palette_t3"]:
				if (ph as Dictionary).has(key):
					seen += 1
					assert_true(FX.PALETTES.has(str(ph[key])), "%s: '%s' is a FractalFX palette" % [id, ph[key]])
	assert_gt(seen, 20, "floor: the palettes were read (%d)" % seen)


## Turbo and the grind console play only the phases AT the impact (FractalFX.play's compact). A sequence with none there
## would show nothing at all at those speeds.
func test_every_heal_still_shows_its_landing_at_turbo() -> void:
	for id in HEALS.values():
		var seq := _seq(id)
		var impact: float = FX.impact_time(seq) - float(seq.get("start", 0.0))
		var at_impact := 0
		for ph in seq.get("phases", []):
			if absf(float((ph as Dictionary).get("at", 0.0)) - impact) <= 0.02:
				at_impact += 1
		assert_gt(at_impact, 0, "%s has a phase at its impact (%.2f s)" % [id, impact])
		assert_gt(impact, 0.0, "%s lands after it starts" % id)
		assert_lte(FX.impact_time(seq), float(BattleManager.IMPACT_HOLD_MAX), "%s lands inside the engine's hold cap" % id)


## The wind-up rule (cowir-main 23890): the first beat starts WITH the cast pose, not after it, and no hold grows.
## PRE_WINDUP is each sequence's start + impact as .792 shipped it: the bound a re-time may not pass.
const PRE_WINDUP := {"cure_battle": 0.95, "cura_battle": 1.0, "crystal_heal_battle": 0.75, "regen_battle": 0.9, "esuna_battle": 0.9,
	"pray_battle": 0.75, "raise_battle": 1.2, "protect_battle": 0.95, "shell_battle": 0.95, "battle_hymn_battle": 0.9,
	"inspiring_melody_battle": 0.9, "lullaby_battle": 1.1, "discord_battle": 0.8}


func test_a_cast_gathers_while_the_caster_poses() -> void:
	for id in PRE_WINDUP:
		var seq := _seq(id)
		assert_false(seq.is_empty(), "CONTROL: %s exists" % id)
		assert_lte(float(seq.get("start", 9.0)), 0.2, "%s starts with the pose (start %.2f)" % [id, float(seq.get("start", 9.0))])
		var opens := 0
		for ph in seq.get("phases", []):
			opens += 1 if float((ph as Dictionary).get("at", 1.0)) <= 0.05 else 0
		assert_gt(opens, 0, "%s has a beat in its first 0.05 s" % id)
		assert_lte(FX.impact_time(seq), float(PRE_WINDUP[id]) + 0.001, "%s lands no later than it did in .792 (%.2f vs %.2f)" % [id, FX.impact_time(seq), float(PRE_WINDUP[id])])
	assert_gt(float(_seq("melee_riff").get("start", 0.0)), 0.0, "CONTROL: a melee overlay still starts at contact, not with the pose")


## The two W1 machine self-heals battle's family table left to this family (24017) mend in sparks.
func test_a_construct_mends_itself_in_the_heal_family() -> void:
	for id in ["emergency_repair", "reconstruct"]:
		assert_eq(str(AbilityVFX.resolve(JobSystem.get_ability(id)).get("sequence", "")), "family_heal_self", "%s plays the self-heal family" % id)
	var seq := _seq("family_heal_self")
	assert_false(seq.is_empty(), "family_heal_self exists")
	var impact: float = FX.impact_time(seq) - float(seq.get("start", 0.0))
	var at_impact := 0
	for ph in seq.get("phases", []):
		at_impact += 1 if absf(float((ph as Dictionary).get("at", 0.0)) - impact) <= 0.02 else 0
	assert_gt(at_impact, 0, "and it shows at turbo")


func test_cura_is_cure_one_tier_up() -> void:
	var cure := _seq("cure_battle")
	var cura := _seq("cura_battle")
	assert_gt(_motes(cura), _motes(cure), "more light")
	assert_gt(_largest(cura, "pillar", "height"), _largest(cure, "pillar", "height"), "a taller column")
	assert_gt(_largest(cura, "ring", "scale"), _largest(cure, "ring", "scale"), "a wider ring")
	assert_gte(FX.impact_time(cura), FX.impact_time(cure), "and it never lands sooner")


func test_raise_is_the_showcase_and_pray_the_smallest() -> void:
	var raise := _seq("raise_battle")
	var pray := _seq("pray_battle")
	for id in HEALS.values():
		if id == "raise_battle":
			continue
		var other := _seq(id)
		assert_gt(_motes(raise), _motes(other), "Raise throws more light than %s" % id)
		assert_gt(_largest(raise, "ring", "scale"), _largest(other, "ring", "scale"), "Raise's halo is wider than %s's ring" % id)
		assert_gt(_length(raise), _length(other), "Raise runs longer than %s" % id)
		if id != "pray_battle":
			assert_lt(_motes(pray), _motes(other), "Pray (a free move) is smaller than %s" % id)
	assert_gt(_largest(raise, "shake", "intensity"), 0.0, "Raise shakes the screen")
	assert_eq(_largest(pray, "shake", "intensity"), 0.0, "CONTROL: Pray does not")


## struktured's ruling (heal landing A/B, he picked "choir only", cowir-sfx 23773): a heal's landing is silent under the cast.
func test_a_cure_lands_without_a_second_sound() -> void:
	for id in ["cure_battle", "cura_battle"]:
		for ph in _seq(id).get("phases", []):
			assert_false((ph as Dictionary).has("sfx"), "%s: its %s phase carries no sound" % [id, ph.get("kind", "")])
	var fire := _seq("fire_battle")
	var fire_sfx := 0
	for ph in fire.get("phases", []):
		fire_sfx += 1 if (ph as Dictionary).has("sfx") else 0
	assert_gt(fire_sfx, 0, "CONTROL: a sequence CAN carry phase sounds (Fire does)")


var _drawn: Array = []


func _record_phase(kind: String, _at: Vector2, _from: Vector2, _power: float, _phase: Dictionary) -> void:
	_drawn.append(kind)


func _record_shake(_intensity: float, _dur: float) -> void:
	_drawn.append("shake")


## Every heal actually runs through the player: played with every phase already due, each element phase and shake in its
## data reaches a drawer at once, and the rest put sprites on the host. Method callbacks, cleared before the arm ends: a
## lambda held by a FractalFX that outlives the test aborted godot at exit (cowir-battle 23864, and this arm's first run).
func test_every_heal_plays_through_the_runner() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	for id in HEALS.values():
		var fx = FX.new(host, 7)
		_drawn = []
		fx.on_element_phase = _record_phase
		fx.on_shake = _record_shake
		var seq := _seq(id)
		seq["start"] = -10.0
		var want := 0
		for ph in seq.get("phases", []):
			want += 1 if str((ph as Dictionary).get("kind", "")) in ["eruption", "pillar", "gather", "fall", "rise", "shake"] else 0
		var before: int = host.get_child_count()
		fx.play(seq, Vector2(600, 300), Vector2(300, 300))
		fx.on_element_phase = Callable()
		fx.on_shake = Callable()
		assert_gt(want, 0, "CONTROL: %s has element phases to reach" % id)
		assert_eq(_drawn.size(), want, "%s: every element phase and shake reached its drawer at once (%d of %d)" % [id, _drawn.size(), want])
		assert_gt(host.get_child_count(), before, "%s: and the runner's own kinds (bolt, ring, flash) put nodes on the host" % id)
