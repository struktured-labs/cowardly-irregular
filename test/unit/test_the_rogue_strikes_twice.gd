extends GutTest

## struktured 2026-11-13 (cowir-main 25159): the Rogue's basic attack hits TWICE — the blade on the swing's
## frame 1, the crossbow bolt on frame 4. Each strike is 0.6 of a full swing and rolls its own miss and crit,
## live and in the grind alike (both loop over Combatant.basic_attack_strikes), and each number lands on its own beat.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const SCENE := preload("res://src/battle/BattleScene.gd")
const ANIMATOR := preload("res://src/battle/BattleAnimator.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const TRIALS := 300

var _saved_scale := 1.0


## A target that counts the strikes that reach it, in either engine.
class CountingTarget extends Combatant:
	var hits: int = 0
	func take_damage(amount: int, is_magical: bool = false) -> int:
		hits += 1
		return super(amount, is_magical)


## Records when each held number actually lands, in game seconds.
class TimedScene extends "res://src/battle/BattleScene.gd":
	var landed: Array = []
	func _on_damage_dealt(target: Combatant, amount: int, is_crit: bool, element: String = "", elemental_mod: float = 1.0) -> void:
		if _full_render_dmg_buffer != null:
			super(target, amount, is_crit, element, elemental_mod)
			return
		landed.append([amount, Time.get_ticks_msec() * 0.001 * Engine.time_scale])


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _job(job_id: String) -> Dictionary:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	assert_not_null(js, "CONTROL: JobSystem autoload")
	var j = js.get_job(job_id) if js else {}
	return j if j is Dictionary else {}


func _make(name_str: String, job_id: String, counting: bool = false) -> Combatant:
	var c: Combatant = CountingTarget.new() if counting else Combatant.new()
	c.initialize({"name": name_str, "max_hp": 999999, "max_mp": 50,
		"attack": 60, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	if job_id != "":
		c.job = _job(job_id)
	return c


func test_the_rogue_authors_two_strikes_at_six_tenths() -> void:
	var rogue := _make("Rogue", "rogue")
	var strikes: Array = rogue.basic_attack_strikes()
	assert_eq(strikes.size(), 2, "the Rogue's basic attack must be two strikes")
	for s in strikes:
		assert_almost_eq(float(s["scale"]), 0.6, 0.001, "each strike is 0.6 of a full swing")
	assert_eq(str(strikes[1]["weapon"]), "bolt", "the second strike is the crossbow bolt")
	var fighter := _make("Fighter", "fighter")
	assert_eq(fighter.basic_attack_strikes(), [{"scale": 1.0, "weapon": ""}], "CONTROL: every other job swings once, at full")


## A second impact is real data: after the first and inside its animation, so a re-export that shortens ATK reds by name.
func test_a_second_impact_frame_lands_after_the_first_and_inside_the_swing() -> void:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(m is Dictionary, "VOID: sprite_manifest.json did not parse")
	if not (m is Dictionary):
		return
	HybridSpriteLoader._load_manifest()
	var authored := 0
	for job in (m.get("sheets", {}) as Dictionary).keys():
		var entry = m["sheets"][job]
		if not (entry is Dictionary) or not entry.has("second_impact_frames"):
			continue
		var frames: SpriteFrames = HybridSpriteLoader._load_external_sheet(entry, str(job))
		for anim in entry["second_impact_frames"].keys():
			authored += 1
			var second := int(entry["second_impact_frames"][anim])
			var first := int((entry.get("impact_frames", {}) as Dictionary).get(anim, 0))
			assert_true(frames != null and frames.has_animation(anim), "%s declares a second impact for a pose it lacks: %s" % [job, anim])
			if frames == null or not frames.has_animation(anim):
				continue
			assert_gt(second, first, "%s %s: the second impact (%d) must come after the first (%d)" % [job, anim, second, first])
			assert_lt(second, frames.get_frame_count(anim), "%s %s: the second impact (%d) is outside its %d frames" % [job, anim, second, frames.get_frame_count(anim)])
	assert_gt(authored, 0, "VOID: no sheet authors a second impact; the Rogue's bolt has no beat")


## Live: two damage_dealt per attack, independent miss rolls, and each strike 0.6 of a full swing's damage.
func test_live_strikes_twice_with_its_own_rolls() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "CONTROL: BattleManager autoload")
	if bm == null:
		return
	var hits: Array = []
	var crits: Array = []
	var cb := func(_t, amount, is_crit, _e, _m):
		hits.append(int(amount))
		crits.append(bool(is_crit))
	bm.damage_dealt.connect(cb)
	var rogue := _make("Rogue", "rogue")
	var target := _make("Dummy", "", true)
	var per_attack: Array = []
	var one_landed := 0
	var crit_split := 0
	for i in TRIALS:
		var before: int = hits.size()
		bm._execute_attack(rogue, target)
		var n: int = hits.size() - before
		per_attack.append(n)
		if n == 2 and crits[before] != crits[before + 1]:
			crit_split += 1
	var rogue_hits: Array = hits.duplicate()
	hits.clear()
	var plain := _make("Plain", "")
	for i in TRIALS:
		bm._execute_attack(plain, target)
	var plain_hits: Array = hits.duplicate()
	rogue.add_status("blind", 99)
	for i in TRIALS:
		var b: int = hits.size()
		bm._execute_attack(rogue, target)
		if hits.size() - b == 1:
			one_landed += 1
	bm.damage_dealt.disconnect(cb)
	assert_eq(per_attack.max(), 2, "a Rogue attack must land up to TWO numbers; it landed at most %d" % per_attack.max())
	assert_gt(_mean(per_attack), 1.6, "most Rogue attacks land both strikes (misses are ~10%% each)")
	assert_gt(one_landed, 0, "blinded, some attacks must land exactly one strike — each strike rolls its own miss")
	assert_gt(crit_split, 0, "some attacks must crit on one strike and not the other — each strike rolls its own crit")
	var ratio: float = _mean(rogue_hits) / maxf(1.0, _mean(plain_hits))
	assert_between(ratio, 0.5, 0.7, "a strike must deal ~0.6 of a full swing; measured %.2f" % ratio)


## The grind resolves the same two strikes: twice the hits reach the target, at ~1.2x the total.
func test_the_grind_strikes_twice_like_live() -> void:
	var res = RESOLVER.new()
	var rogue := _make("Rogue", "rogue")
	var plain := _make("Plain", "")
	var target := _make("Dummy", "", true) as CountingTarget
	var rogue_total := 0
	for i in TRIALS:
		rogue_total += res._resolve_attack(rogue, target)
	var rogue_hits: int = target.hits
	target.hits = 0
	var plain_total := 0
	for i in TRIALS:
		plain_total += res._resolve_attack(plain, target)
	var plain_hits: int = target.hits
	assert_gt(plain_hits, int(TRIALS * 0.7), "CONTROL: a plain swing lands most of the time")
	assert_gt(float(rogue_hits) / plain_hits, 1.7, "the grind's Rogue must land ~2 strikes per attack (%d vs %d)" % [rogue_hits, plain_hits])
	var total_ratio: float = float(rogue_total) / maxf(1.0, plain_total)
	assert_between(total_ratio, 1.0, 1.4, "two 0.6 strikes total ~1.2x a swing; measured %.2f" % total_ratio)
	res.free()


func _rogue_animator(parent: Node) -> ANIMATOR:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	HybridSpriteLoader._load_manifest()
	var frames: SpriteFrames = HybridSpriteLoader._load_external_sheet(m["sheets"]["rogue"], "rogue")
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.position = Vector2(600, 0)
	parent.add_child(sprite)
	sprite.play("idle")
	var animator: ANIMATOR = ANIMATOR.new()
	animator.setup(sprite)
	parent.add_child(animator)
	return animator


## Feed one two-strike attack through the scene the way BattleManager does, and return the landings.
func _swing(turbo: bool) -> Array:
	var scene := TimedScene.new()
	add_child_autofree(scene)
	scene.turbo_mode = turbo
	var animator := _rogue_animator(scene)
	animator.swing_budget_provider = scene.swing_budget
	var target := AnimatedSprite2D.new()
	target.position = Vector2(100, 0)
	scene.add_child(target)
	var victim := _make("Dummy", "")
	scene._animate_melee_attack(animator.sprite, target, animator, null, 0.0, "", true)
	scene._on_strike_starting(null, 0, 2, "")
	scene._on_damage_dealt(victim, 11, false)
	scene._on_strike_starting(null, 1, 2, "bolt")
	scene._on_damage_dealt(victim, 22, false)
	await wait_seconds(2.5)
	return scene.landed


func test_each_strike_lands_on_its_own_beat_at_spotlight_pace() -> void:
	Engine.time_scale = 0.375
	var probe := Node.new()
	add_child_autofree(probe)
	var animator := _rogue_animator(probe)
	var beat1: float = animator.impact_time("attack")
	var beat2: float = animator.second_impact_time("attack")
	assert_gt(beat2, beat1 + 0.1, "CONTROL: the rogue's sheet authors a bolt beat after the blade's")
	var landed: Array = await _swing(false)
	assert_eq(landed.size(), 2, "both strikes' numbers must land")
	if landed.size() < 2:
		return
	assert_eq([landed[0][0], landed[1][0]], [11, 22], "the blade's number first, the bolt's second")
	var gap: float = landed[1][1] - landed[0][1]
	assert_gt(gap, (beat2 - beat1) * 0.7, "the bolt's number must wait for its own frame (%.3f s after the blade, beat gap %.3f)" % [gap, beat2 - beat1])


func test_turbo_still_lands_two_separate_numbers() -> void:
	Engine.time_scale = 1.0
	var landed: Array = await _swing(true)
	assert_eq(landed.size(), 2, "both strikes' numbers must land in turbo")
	if landed.size() < 2:
		return
	var gap: float = landed[1][1] - landed[0][1]
	assert_gt(gap, SCENE.STRIKE_STAGGER * 0.6, "turbo must still stagger the bolt's number off the blade's (%.3f s)" % gap)


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / a.size()
