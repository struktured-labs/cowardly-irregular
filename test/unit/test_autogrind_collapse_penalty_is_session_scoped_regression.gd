extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

## A system collapse halves the efficiency CAP for 10 battles. Both `max_efficiency` and
## `post_collapse_debuff_battles` were in NONE of the three session sets — not reset by
## start_autogrind, not snapshotted, not restored. So a session that collapsed and stopped
## before the debuff expired started the NEXT grind with a halved cap and a live counter,
## against the one pillar the whole mode is built on: the multiplier that climbs.
##
## test_autogrind_session_scope_symmetry_regression could not see this. It iterates
## reset.keys() and snap.keys(), so it catches a field in ONE set and missing from another —
## a field in ZERO sets is never iterated. The guard built for this class is structurally
## blind to its worst form. That is why these arms are behavioural, not a census.
##
## Both edges also reached the player through print() only: the multiplier stopped climbing
## for ten battles and nothing said why.

const SystemScript = preload("res://src/autogrind/AutogrindSystem.gd")

const TOUCHED := [
	"max_efficiency", "post_collapse_debuff_battles", "efficiency_multiplier",
	"meta_corruption_level", "meta_boss_spawn_chance", "is_grinding",
]

var _saved: Dictionary = {}


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	for f in TOUCHED:
		_saved[f] = AutogrindSystem.get(f)


func after_each() -> void:
	for f in _saved:
		AutogrindSystem.set(f, _saved[f])
	_saved.clear()


func _party() -> Array[Combatant]:
	var m := Combatant.new()
	m.initialize({"name": "T", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(m)
	var p: Array[Combatant] = [m]
	return p


# ── The leak ─────────────────────────────────────────────────────────────────

func test_a_fresh_grind_does_not_inherit_a_collapse_penalty() -> void:
	AutogrindSystem.is_grinding = false
	AutogrindSystem.max_efficiency = 5.0
	AutogrindSystem.post_collapse_debuff_battles = 7
	AutogrindSystem.start_autogrind(_party(), {}, {})
	assert_eq(AutogrindSystem.max_efficiency, SystemScript.DEFAULT_MAX_EFFICIENCY,
		"a new grind must start at the full efficiency cap — a halved cap carried from a previous session is invisible and permanent-feeling")
	assert_eq(int(AutogrindSystem.post_collapse_debuff_battles), 0,
		"a new grind must start with no debuff countdown left over from the last one")


func test_the_reset_is_not_a_blanket_that_would_pass_anyway() -> void:
	# Control: prove the drive above actually dirtied something start_autogrind had to clear.
	AutogrindSystem.max_efficiency = 5.0
	AutogrindSystem.post_collapse_debuff_battles = 7
	assert_ne(AutogrindSystem.max_efficiency, SystemScript.DEFAULT_MAX_EFFICIENCY,
		"control: the pre-seed must differ from the default, else the reset arm cannot discriminate")
	assert_gt(int(AutogrindSystem.post_collapse_debuff_battles), 0,
		"control: the counter must be non-zero before the reset")


func test_a_pause_carries_the_debuff_across_a_resume() -> void:
	# Resume continues the SAME session, so the penalty must survive it — the opposite
	# requirement to the reset above, and the reason both halves are needed.
	AutogrindSystem.max_efficiency = 5.0
	AutogrindSystem.post_collapse_debuff_battles = 6
	var snap: Dictionary = AutogrindSystem.build_snapshot_system_block(0.0)
	AutogrindSystem.max_efficiency = SystemScript.DEFAULT_MAX_EFFICIENCY
	AutogrindSystem.post_collapse_debuff_battles = 0
	AutogrindSystem.restore_system_from_snapshot(snap)
	assert_eq(AutogrindSystem.max_efficiency, 5.0,
		"the halved cap must survive a pause — resume is the same session still serving its penalty")
	assert_eq(int(AutogrindSystem.post_collapse_debuff_battles), 6,
		"the countdown must survive a pause, or pausing launders the penalty away")


func test_an_absent_snapshot_key_does_not_invent_a_penalty() -> void:
	# An old save predating these keys must resume clean, not debuffed.
	AutogrindSystem.max_efficiency = 5.0
	AutogrindSystem.post_collapse_debuff_battles = 6
	AutogrindSystem.restore_system_from_snapshot({})
	assert_eq(AutogrindSystem.max_efficiency, SystemScript.DEFAULT_MAX_EFFICIENCY,
		"an absent max_efficiency key must fall back to the full cap, never to a penalty")
	assert_eq(int(AutogrindSystem.post_collapse_debuff_battles), 0,
		"an absent counter key must fall back to no debuff")


func test_the_expiry_restores_the_declared_default() -> void:
	# The restore used a hardcoded 10.0 duplicating the declaration. Pinned to the const so
	# changing the default cannot leave the expiry restoring a stale number.
	AutogrindSystem.max_efficiency = SystemScript.DEFAULT_MAX_EFFICIENCY
	AutogrindSystem.apply_post_collapse_penalty()
	assert_lt(AutogrindSystem.max_efficiency, SystemScript.DEFAULT_MAX_EFFICIENCY,
		"control: the penalty must actually lower the cap")
	for i in 10:
		AutogrindSystem.tick_post_collapse_debuff()
	assert_eq(AutogrindSystem.max_efficiency, SystemScript.DEFAULT_MAX_EFFICIENCY,
		"after the last debuffed battle the cap must return to the DECLARED default")
	assert_eq(int(AutogrindSystem.post_collapse_debuff_battles), 0,
		"the counter must land exactly on zero after its ten battles")


# ── Both edges reach the player ──────────────────────────────────────────────

func test_applying_the_penalty_announces_it() -> void:
	watch_signals(AutogrindSystem)
	AutogrindSystem.max_efficiency = SystemScript.DEFAULT_MAX_EFFICIENCY
	AutogrindSystem.apply_post_collapse_penalty()
	assert_signal_emitted(AutogrindSystem, "post_collapse_penalty_applied",
		"the player must be told the cap dropped — print() is not a player surface")
	var params: Array = get_signal_parameters(AutogrindSystem, "post_collapse_penalty_applied", 0)
	assert_eq(int(params[1]), 10, "the announcement must carry the battle count so the toast can name it")
	assert_lt(float(params[0]), float(SystemScript.DEFAULT_MAX_EFFICIENCY),
		"the announcement must carry the CAPPED value, not the pre-penalty one")


func test_the_expiry_announces_itself() -> void:
	watch_signals(AutogrindSystem)
	AutogrindSystem.max_efficiency = SystemScript.DEFAULT_MAX_EFFICIENCY
	AutogrindSystem.apply_post_collapse_penalty()
	for i in 10:
		AutogrindSystem.tick_post_collapse_debuff()
	assert_signal_emitted(AutogrindSystem, "post_collapse_penalty_expired",
		"the player must be told the cap came back, or the recovery is as invisible as the penalty")


func test_the_expiry_does_not_announce_early() -> void:
	# Without this, an emit on every tick would pass the arm above and toast ten times.
	watch_signals(AutogrindSystem)
	AutogrindSystem.max_efficiency = SystemScript.DEFAULT_MAX_EFFICIENCY
	AutogrindSystem.apply_post_collapse_penalty()
	for i in 9:
		AutogrindSystem.tick_post_collapse_debuff()
	assert_signal_emit_count(AutogrindSystem, "post_collapse_penalty_expired", 0,
		"nine battles in, the debuff is still live — announcing recovery early is worse than not announcing")


func test_ticking_with_no_debuff_is_inert() -> void:
	watch_signals(AutogrindSystem)
	AutogrindSystem.post_collapse_debuff_battles = 0
	AutogrindSystem.tick_post_collapse_debuff()
	assert_signal_emit_count(AutogrindSystem, "post_collapse_penalty_expired", 0,
		"ticking with no debuff active must not fire a recovery announcement every battle")


# ── GameLoop carries both edges to a toast ───────────────────────────────────

func test_gameloop_connects_and_toasts_both_edges() -> void:
	# GameLoop is the MAIN SCENE, absent from the tree under GUT — read the source, located
	# by the CALL rather than a line number.
	var code := _code_only("res://src/GameLoop.gd", "func _on_autogrind_system_collapse")
	for sig in ["post_collapse_penalty_applied", "post_collapse_penalty_expired"]:
		assert_true(code.contains("AutogrindSystem.%s.connect(" % sig),
			"GameLoop must connect %s, or the signal reaches no player surface" % sig)
	for fn in ["_on_autogrind_post_collapse_penalty", "_on_autogrind_post_collapse_expired"]:
		var at := code.find("func %s(" % fn)
		assert_gt(at, -1, "control: %s must be findable in GameLoop" % fn)
		var window := code.substr(at, 500)
		assert_true(window.contains("_show_autogrind_toast("),
			"%s must toast — the whole defect was that this edge only reached print()" % fn)


# ── helpers ──────────────────────────────────────────────────────────────────


## must_survive is REQUIRED — no call site can omit the positive control. Stripping itself is
## the shared helper's, which is quote- and escape-aware where the private copy was not.
func _code_only(path: String, must_survive: String) -> String:
	## PATH-taking so the blank-control floor below is safe by construction.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped
