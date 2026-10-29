extends GutTest

## Ability animations played FLAT: every frame of Cleave got 125 ms, so the wind-up and the frame the
## hit actually reads on were held exactly as long. That is the defect struktured rejected for victory
## on 2026-09-26 ("the mage's 50 ms flurry and 500 ms final beat"), and the per-frame fix he chose was
## gated to `anim_name == "victory"` by one `if` in HybridSpriteLoader. Abilities now read the same
## `frame_durations_ms` map. Victory keeps VICTORY_PACE and BattleAnimator's real-time rate; an
## ability keeps battle-speed scaling, so only the rhythm is shared.
##
## Every authored total equals the flat duration it replaces, so this redistributes time INSIDE an
## animation and never changes how long an ability takes. Battle pacing is cowir-battle's and is not
## touched here -- that equality is arm 3, and it is what makes the claim checkable.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const PACE := 2.0


func _sheets() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return (parsed as Dictionary).get("sheets", {}) if parsed is Dictionary else {}


## [job, anim, authored_ms] for every NON-victory authored rhythm -- DERIVED, never listed, so a
## rhythm added later joins this corpus instead of sitting unguarded.
func _authored() -> Array:
	var out: Array = []
	var sheets := _sheets()
	for job in sheets:
		var declared = (sheets[job] as Dictionary).get("frame_durations_ms", {})
		if not (declared is Dictionary):
			continue
		for anim in declared:
			if str(anim) != "victory":
				out.append([str(job), str(anim), declared[anim]])
	return out


func _frame_seconds(sf: SpriteFrames, anim: StringName, i: int) -> float:
	var speed := sf.get_animation_speed(anim)
	return sf.get_frame_duration(anim, i) / speed if speed > 0.0 else 0.0


func test_the_corpus_holds_the_abilities_that_were_polished() -> void:
	var rows := _authored()
	assert_gt(rows.size(), 0,
		"ANTI-VACUITY: no non-victory rhythm is authored, so every arm below would pass on nothing")
	var seen: Array = []
	for r in rows:
		seen.append("%s/%s" % [r[0], r[1]])
	for named in ["fighter/cleave", "fighter/power_strike", "bard/lullaby", "bard/discord"]:
		assert_has(seen, named, "%s is a real ability with its own art and must carry a rhythm" % named)


func test_each_authored_frame_lasts_its_own_duration() -> void:
	var checked := 0
	for r in _authored():
		var job: String = r[0]
		var anim: StringName = StringName(r[1])
		var ms: Array = r[2]
		var sf := Loader.load_sprite_frames(null, job, "", "", "", "")
		assert_not_null(sf, "CONTROL: %s must load sprite frames" % job)
		if sf == null or not sf.has_animation(anim):
			continue
		assert_eq(ms.size(), sf.get_frame_count(anim),
			"%s/%s: one authored duration per frame" % [job, anim])
		if ms.size() != sf.get_frame_count(anim):
			continue
		for i in ms.size():
			assert_almost_eq(_frame_seconds(sf, anim, i), float(ms[i]) / 1000.0, 0.0005,
				"%s/%s frame %d must last %d ms -- an ability is NOT paced like victory" % [job, anim, i, int(ms[i])])
		checked += 1
	assert_eq(checked, _authored().size(), "every authored ability must have been timed, not skipped")


## The polish redistributes time; it must not lengthen an ability. Without this, a rhythm could
## quietly stretch Cleave and shift the battle pacing that is not this lane's to change.
func test_an_authored_total_equals_the_flat_timing_it_replaced() -> void:
	var sheets := _sheets()
	var checked := 0
	for r in _authored():
		var job: String = r[0]
		var ms: Array = r[2]
		var fps: float = float((sheets[job] as Dictionary).get("fps", 8))
		if fps <= 0.0:
			continue
		var total := 0.0
		for v in ms:
			total += float(v)
		assert_almost_eq(total, ms.size() * 1000.0 / fps, 1.0,
			"%s/%s must still run %.0f ms in total" % [job, r[1], ms.size() * 1000.0 / fps])
		checked += 1
	assert_gt(checked, 0, "CONTROL: at least one total was measured")


## A rhythm that is accidentally uniform would satisfy every arm above and polish nothing. This is
## the arm that says the timing is actually SHAPED.
func test_an_authored_rhythm_is_not_flat() -> void:
	for r in _authored():
		var ms: Array = r[2]
		var lo := 1.0e9
		var hi := 0.0
		for v in ms:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		assert_gt(hi / maxf(lo, 1.0), 1.5,
			"%s/%s is authored but near-flat (%d..%d ms) -- it holds no anticipation or impact" % [r[0], r[1], int(lo), int(hi)])


## CONTROL: the change is OPT-IN. An animation with no authored rhythm keeps one uniform duration,
## which is what proves generalising the gate did not retime every sheet in the game.
func test_an_unauthored_animation_is_still_uniform() -> void:
	var sheets := _sheets()
	var checked := 0
	for pair in [["fighter", "attack"], ["fighter", "idle"], ["bard", "attack"], ["cleric", "walk"]]:
		var job: String = pair[0]
		var anim := StringName(pair[1])
		var declared = (sheets[job] as Dictionary).get("frame_durations_ms", {})
		assert_false((declared as Dictionary).has(String(anim)),
			"CONTROL: %s/%s must carry no authored rhythm, or it cannot test the default path" % [job, anim])
		var sf := Loader.load_sprite_frames(null, job, "", "", "", "")
		if sf == null or not sf.has_animation(anim) or sf.get_frame_count(anim) < 2:
			continue
		var first := _frame_seconds(sf, anim, 0)
		for i in range(1, sf.get_frame_count(anim)):
			assert_almost_eq(_frame_seconds(sf, anim, i), first, 0.0005,
				"%s/%s frame %d must keep the flat sheet timing" % [job, anim, i])
		checked += 1
	assert_gt(checked, 0, "CONTROL: at least one unauthored animation was measured")


## CONTROL: victory is untouched by the generalisation -- it still runs at the artist's rhythm x2.
func test_victory_still_runs_at_half_speed() -> void:
	var sheets := _sheets()
	var checked := 0
	for job in sheets:
		var ms = ((sheets[job] as Dictionary).get("frame_durations_ms", {}) as Dictionary).get("victory", [])
		if not (ms is Array) or ms.is_empty():
			continue
		var sf := Loader.load_sprite_frames(null, str(job), "", "", "", "")
		if sf == null or not sf.has_animation(&"victory") or sf.get_frame_count(&"victory") != ms.size():
			continue
		for i in ms.size():
			assert_almost_eq(_frame_seconds(sf, &"victory", i), float(ms[i]) * PACE / 1000.0, 0.0005,
				"%s victory frame %d must still last %d ms x %.0f" % [job, i, int(ms[i]), PACE])
		checked += 1
	assert_gt(checked, 0, "CONTROL: at least one artist victory was measured")
