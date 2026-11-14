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
	var amounts: Array = []
	func take_damage(amount: int, is_magical: bool = false, defence_scale: float = 1.0) -> int:
		hits += 1
		amounts.append(amount)
		return super(amount, is_magical, defence_scale)


## Records when each held number actually lands, in game seconds.
class TimedScene extends "res://src/battle/BattleScene.gd":
	var landed: Array = []
	func _on_damage_dealt(target: Combatant, amount: int, is_crit: bool, element: String = "", elemental_mod: float = 1.0) -> void:
		if _full_render_dmg_buffer != null:
			super(target, amount, is_crit, element, elemental_mod)
			return
		landed.append([amount, Time.get_ticks_msec() * 0.001 * Engine.time_scale, Engine.get_process_frames()])


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _job(job_id: String) -> Dictionary:
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	assert_not_null(js, "CONTROL: JobSystem autoload")
	var j = js.get_job(job_id) if js else {}
	return j if j is Dictionary else {}


func _make(name_str: String, job_id: String, counting: bool = false, defense: int = 0, speed: int = 10) -> Combatant:
	var c: Combatant = CountingTarget.new() if counting else Combatant.new()
	c.initialize({"name": name_str, "max_hp": 999999, "max_mp": 50,
		"attack": 60, "defense": defense, "magic": 10, "speed": speed})
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


## Live: up to two numbers per attack, and each strike rolls its own miss and its own crit.
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
	var crit_split := 0
	var one_landed := 0
	for i in TRIALS:
		var before: int = hits.size()
		bm._execute_attack(rogue, target)
		var n: int = hits.size() - before
		per_attack.append(n)
		if n == 2 and crits[before] != crits[before + 1]:
			crit_split += 1
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


## The ruling is 0.6 of an Attack's DAMAGE per strike, so the attack is ~1.2x a swing at EVERY defence, not only at 0
## (autogrind 25200: two strikes each meeting the full defence came to 0.97x on W1 armour). Defence meets the attack once.
## A kill ends the attack; the dummy's HP outlasts every trial so no total here is cut short by one.
const DEF_PER_ATK := [0.0, 0.5, 1.0, 2.0]


func _live_mean_per_attack(bm, attacker: Combatant, target: Combatant) -> float:
	var total := [0]
	var cb := func(t, amount, _c, _e, _m):
		if t == target:
			total[0] += int(amount)
	bm.damage_dealt.connect(cb)
	for i in TRIALS:
		bm._execute_attack(attacker, target)
	bm.damage_dealt.disconnect(cb)
	return float(total[0]) / TRIALS


func test_live_deals_six_tenths_per_strike_at_every_defence() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "CONTROL: BattleManager autoload")
	if bm == null:
		return
	var rogue := _make("Rogue", "rogue", false, 0, 100)
	var plain := _make("Plain", "", false, 0, 100)
	for d in DEF_PER_ATK:
		var target := _make("Dummy", "", false, int(60 * d))
		var ratio: float = _live_mean_per_attack(bm, rogue, target) / maxf(1.0, _live_mean_per_attack(bm, plain, target))
		assert_between(ratio, 1.05, 1.35, "live: the Rogue's attack must deal ~1.2x a swing at DEF/ATK %.1f; measured %.2f" % [d, ratio])


func test_the_grind_deals_six_tenths_per_strike_at_every_defence() -> void:
	var res = RESOLVER.new()
	var rogue := _make("Rogue", "rogue", false, 0, 100)
	var plain := _make("Plain", "", false, 0, 100)
	for d in DEF_PER_ATK:
		var target := _make("Dummy", "", true, int(60 * d)) as CountingTarget
		var rogue_total := 0
		for i in TRIALS:
			rogue_total += res._resolve_attack(rogue, target)
		var rogue_hits: int = target.hits
		target.hits = 0
		var plain_total := 0
		for i in TRIALS:
			plain_total += res._resolve_attack(plain, target)
		assert_gt(float(rogue_hits) / maxf(1.0, target.hits), 1.7, "the grind's Rogue must land ~2 strikes per attack at DEF/ATK %.1f (%d vs %d)" % [d, rogue_hits, target.hits])
		var ratio: float = float(rogue_total) / maxf(1.0, plain_total)
		assert_between(ratio, 1.05, 1.35, "grind: the Rogue's attack must deal ~1.2x a swing at DEF/ATK %.1f; measured %.2f" % [d, ratio])
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
	assert_eq([landed[0][0], landed[1][0]], [11, 22], "the blade's number first, the bolt's second")
	var frames: int = int(landed[1][2]) - int(landed[0][2])
	assert_gt(frames, 1, "turbo must land the bolt's number on a later frame than the blade's, not the same one (%d frames apart)" % frames)


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / a.size()


## A stored "next attack xN" (burrow) is ONE charge for the WHOLE attack: both strikes carry it, it is spent once,
## and an attack that misses with both keeps it (cowir-battle 25289, answering cowir-main 25287).
const CHARGE := 1.5


## Mean blade and bolt numbers over attacks that landed both strikes, charged or not, plus the charge's fate.
func _per_strike_means(attack: Callable, rogue: Combatant, charged: bool) -> Dictionary:
	var blade: Array = []
	var bolt: Array = []
	var kept_on_full_miss := 0
	var left_after_a_hit := 0
	for i in TRIALS:
		rogue.set_meta("_next_attack_multiplier", CHARGE if charged else 0.0)
		var landed: Array = attack.call()
		var left: float = float(rogue.get_meta("_next_attack_multiplier", 0.0))
		if landed.size() == 2:
			blade.append(landed[0])
			bolt.append(landed[1])
		if charged and landed.is_empty() and is_equal_approx(left, CHARGE):
			kept_on_full_miss += 1
		if charged and not landed.is_empty() and left > 0.0:
			left_after_a_hit += 1
	return {"blade": _mean(blade), "bolt": _mean(bolt), "kept": kept_on_full_miss, "leaked": left_after_a_hit}


func _assert_whole_attack_charge(engine: String, attack: Callable, rogue: Combatant) -> void:
	var plain: Dictionary = _per_strike_means(attack, rogue, false)
	var charged: Dictionary = _per_strike_means(attack, rogue, true)
	assert_gt(float(plain["bolt"]), 0.0, "CONTROL: %s landed both strikes uncharged" % engine)
	assert_between(float(charged["blade"]) / maxf(1.0, plain["blade"]), 1.3, 1.7, "%s: the charge must multiply the blade (%.1f vs %.1f)" % [engine, charged["blade"], plain["blade"]])
	assert_between(float(charged["bolt"]) / maxf(1.0, plain["bolt"]), 1.3, 1.7, "%s: the charge must multiply the BOLT too — one charge, the whole attack (%.1f vs %.1f)" % [engine, charged["bolt"], plain["bolt"]])
	assert_eq(int(charged["leaked"]), 0, "%s: an attack that connects must spend the charge" % engine)
	assert_gt(int(charged["kept"]), 0, "%s: blinded, some attacks miss with both strikes and must keep the charge" % engine)


func test_live_a_stored_charge_carries_both_strikes() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	assert_not_null(bm, "CONTROL: BattleManager autoload")
	if bm == null:
		return
	var rogue := _make("Rogue", "rogue")
	rogue.add_status("blind", 999)
	var target := _make("Dummy", "")
	var nums: Array = []
	var cb := func(t, amount, _c, _e, _m):
		if t == target:
			nums.append(int(amount))
	bm.damage_dealt.connect(cb)
	var attack := func() -> Array:
		nums.clear()
		bm._execute_attack(rogue, target)
		return nums.duplicate()
	_assert_whole_attack_charge("live", attack, rogue)
	bm.damage_dealt.disconnect(cb)


func test_the_grind_a_stored_charge_carries_both_strikes() -> void:
	var res = RESOLVER.new()
	var rogue := _make("Rogue", "rogue")
	rogue.add_status("blind", 999)
	var target := _make("Dummy", "", true) as CountingTarget
	var attack := func() -> Array:
		target.amounts.clear()
		res._resolve_attack(rogue, target)
		return target.amounts.duplicate()
	_assert_whole_attack_charge("grind", attack, rogue)
	res.free()
