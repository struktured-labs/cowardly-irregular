extends GutTest

## The corruption envelope's wobble and flicker were FROZEN (2026-10-13).
##
## `_render_music_envelope` composes two meters into `_music_player.pitch_scale` and `volume_db`.
## Two of its terms are not functions of the meters at all:
##   wobble  = sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.8) * depth     <- WALL CLOCK
##   flicker = randf_range(0.0, (corruption - 0.6) * 4.0)                  <- RNG
## Both only advance when the renderer RUNS, and its only callers were the two meter appliers
## (driven by tweens of 0.5s and 1.5s) plus reset_corruption. So once corruption SETTLED at a
## level, the sine froze at whatever phase the last tween step happened to sample and the flicker
## froze at one random value — for as long as the player stayed at that corruption. The source
## claims "drifts flat with a slow wobble at high levels" and "Volume flicker only above 0.6
## (reality destabilizing)": the flat drift worked, the two time-varying halves did not.
##
## Fixed by re-rendering per frame while corruption is live. ⚠️ GATED ON THE CROSSFADE, and that
## gate is load-bearing rather than tidy: `_crossfade_tween` tweens `_music_player.volume_db` down
## to <= -40 for a fade-out, and an ungated per-frame write would fight it and keep the music up.
## Arm 3 pins that, so a later simplification cannot drop the gate and break fades instead.

const SETTLE_S: float = 0.22
var _sm = null
var _saved: Dictionary = {}


func before_each() -> void:
	_sm = SoundManager
	if _sm == null:
		return
	_saved = {
		"corruption": _sm._corruption_intensity,
		"save_corruption": _sm._save_corruption,
		"grind": _sm._grind_corruption,
		"danger": _sm._danger_intensity,
		"pitch": _sm._music_player.pitch_scale if _sm._music_player else 1.0,
		"db": _sm._music_player.volume_db if _sm._music_player else 0.0,
	}
	_kill_tweens()
	## ZEROED, not merely saved: the danger meter also writes pitch (1.0 + danger * 0.15), so a test
	## that left it raised would push pitch ABOVE 1.0 and red the flat-drift arm for a reason that has
	## nothing to do with corruption — passing today only by coincidence of suite order.
	_sm._danger_intensity = 0.0
	_sm._corruption_intensity = 0.0
	_sm._grind_corruption = 0.0
	_sm._save_corruption = 0.0


func after_each() -> void:
	if _sm == null:
		return
	_kill_tweens()
	_sm._corruption_intensity = _saved.get("corruption", 0.0)
	_sm._save_corruption = _saved.get("save_corruption", 0.0)
	_sm._grind_corruption = _saved.get("grind", 0.0)
	_sm._danger_intensity = _saved.get("danger", 0.0)
	if _sm._music_player:
		_sm._music_player.pitch_scale = _saved.get("pitch", 1.0)
		_sm._music_player.volume_db = _saved.get("db", 0.0)


func _kill_tweens() -> void:
	for t in ["_corruption_tween", "_danger_tween", "_crossfade_tween"]:
		var tw = _sm.get(t)
		if tw != null and tw.is_valid():
			tw.kill()
		_sm.set(t, null)


## Samples pitch_scale n times, waiting real seconds between — the wobble is a function of WALL
## CLOCK, so awaiting FRAMES would advance it by almost nothing in a fast headless run.
func _sample_pitch(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		await get_tree().create_timer(SETTLE_S).timeout
		## The timer is load-bearing (the sine advances in REAL time, so awaiting frames alone would
		## move it by almost nothing headless); this frame is what GUARANTEES a render happened at the
		## new time, instead of trusting that >= 1 _process landed inside the gap.
		await get_tree().process_frame
		out.append(_sm._music_player.pitch_scale)
	return out


func test_the_members_this_file_drives_exist() -> void:
	assert_not_null(_sm, "SoundManager autoload missing")
	assert_true(_sm.has_method("_render_music_envelope"), "the renderer this guard samples is gone")
	for f in ["_corruption_intensity", "_crossfade_tween", "_music_player", "_save_corruption"]:
		assert_true(f in _sm, "SoundManager.%s is gone — later arms would abort after asserting" % f)


## THE DEFECT: at a SETTLED corruption level the pitch must still move.
func test_a_settled_corruption_still_wobbles_the_pitch() -> void:
	_sm._corruption_intensity = 1.0
	var seen: Array = await _sample_pitch(4)
	var distinct: Dictionary = {}
	for v in seen:
		distinct[snappedf(v, 0.000001)] = true
	assert_gt(distinct.size(), 1,
		"pitch_scale never changed across %.2fs of settled corruption — the wobble is a frozen sample of its own sine: %s" % [SETTLE_S * 4.0, str(seen)])


## THE SAME DEFECT THROUGH THE PUBLIC PATH, which is what a player actually drives: autogrind calls
## set_corruption_intensity, its 1.5s tween renders repeatedly, and then STOPS. Settle the tween,
## then sample — pre-fix the pitch sits detuned at the phase the final tween step happened to hit.
func test_the_wobble_survives_the_settling_tween() -> void:
	_sm.set_corruption_intensity(1.0)
	## POLLED, not slept. A fixed wait past the 1.5s tween is the shape that flaked test_menu_input
	## twice in long runs, and 2.0/1.5 = 1.33x was TIGHTER than the 0.2/0.13 = 1.54x that failed there.
	var waited: float = 0.0
	while _sm._corruption_intensity < 0.999 and waited < 5.0:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	assert_almost_eq(_sm._corruption_intensity, 1.0, 0.01, "the meter did not reach 1.0 in %.2fs — the arms below would sample a clean envelope" % waited)
	var seen: Array = await _sample_pitch(4)
	assert_lt(float(seen[0]), 1.0, "corruption must drift the pitch FLAT (below 1.0); got %s" % str(seen))
	var distinct: Dictionary = {}
	for v in seen:
		distinct[snappedf(v, 0.000001)] = true
	assert_gt(distinct.size(), 1,
		"pitch_scale froze after the tween settled — the wobble only moved while the meter was changing: %s" % str(seen))


## CONTROL, the healthy direction: a clean save must NOT jitter. Without this the arm above passes
## on a fix that simply renders every frame unconditionally, which would also detune clean music.
func test_a_clean_save_does_not_jitter() -> void:
	_sm._corruption_intensity = 0.0
	_sm._save_corruption = 0.0
	_sm._grind_corruption = 0.0
	_sm._danger_intensity = 0.0
	_sm._render_music_envelope()
	var seen: Array = await _sample_pitch(3)
	for v in seen:
		assert_almost_eq(float(v), float(seen[0]), 0.0000001,
			"pitch moved with corruption at 0.0 — the per-frame render is not gated: %s" % str(seen))


## CONTROL for the GATE: while a crossfade owns volume_db the envelope must stand off, or the
## per-frame write fights the fade-out tween and the music never fades.
func test_a_crossfade_is_not_fought() -> void:
	_sm._corruption_intensity = 1.0
	_sm._crossfade_tween = _sm.create_tween()
	_sm._crossfade_tween.tween_interval(5.0)
	var seen: Array = await _sample_pitch(3)
	for v in seen:
		assert_almost_eq(float(v), float(seen[0]), 0.0000001,
			"the envelope re-rendered during a crossfade — it would fight the fade-out on volume_db: %s" % str(seen))
