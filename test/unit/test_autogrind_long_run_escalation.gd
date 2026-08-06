extends GutTest

## Long-run escalation harness — asserts the autogrind danger ladder ESCALATES, not merely
## that each stage is reachable.
##
## Why this exists: every other autogrind test runs a handful of battles, and every ladder
## stage (fatigue, adaptation, region crack, corruption, collapse) is reachable inside the
## first five. So a game where the ladder is perfectly FLAT passes the entire existing suite.
## The design promise is "longer automation = higher multipliers BUT increased danger", which
## is a claim about a curve's SHAPE over a session, and nothing measured it until now.
##
## Drives the real chain: AutogrindSystem.on_battle_victory() -> update_csi + _check_region_crack
## + _increase_efficiency -> adaptation/corruption/collapse. That is the path AutogrindController
## :440 uses in a live grind.
##
## Assertions are RELATIONSHIPS (monotonic, accelerating, ordered), never pinned magnitudes —
## a pinned constant reds on a correct rebalance and stays green on a wrong one.
##
## NOTE: never pass a "gold" key to on_battle_victory here. That path reaches the live GameState
## autoload and credits party_gold for real (AutogrindSystem:610-615).

const BATTLES: int = 400
const REGION: String = "test_region_longrun"

var _saved: Dictionary = {}

const _FIELDS: Array[String] = [
	"battles_completed", "consecutive_wins", "battles_without_heal", "total_exp_gained",
	"efficiency_multiplier", "max_efficiency", "efficiency_growth_rate",
	"monster_adaptation_level", "meta_corruption_level", "corruption_threshold",
	"collapse_count", "post_collapse_debuff_battles", "fatigue_events_triggered",
	"meta_boss_spawn_chance", "current_region_id", "is_grinding",
]
const _DICTS: Array[String] = [
	"region_crack_levels", "_region_csi", "_csi_timestamps", "_grind_stats",
	"total_items_gained", "items_consumed", "per_character_exp",
]


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	for f in _FIELDS:
		_saved[f] = AutogrindSystem.get(f)
	for d in _DICTS:
		var v = AutogrindSystem.get(d)
		_saved[d] = v.duplicate(true) if v is Dictionary else v
	_saved["grind_party"] = AutogrindSystem.grind_party.duplicate()

	AutogrindSystem.grind_party.clear()
	AutogrindSystem.battles_completed = 0
	AutogrindSystem.consecutive_wins = 0
	AutogrindSystem.battles_without_heal = 0
	AutogrindSystem.total_exp_gained = 0
	AutogrindSystem.efficiency_multiplier = 1.0
	AutogrindSystem.monster_adaptation_level = 0.0
	AutogrindSystem.meta_corruption_level = 0.0
	AutogrindSystem.collapse_count = 0
	AutogrindSystem.post_collapse_debuff_battles = 0
	AutogrindSystem.meta_boss_spawn_chance = 0.0
	AutogrindSystem.region_crack_levels = {}
	AutogrindSystem._region_csi = {}
	AutogrindSystem._csi_timestamps = {}
	AutogrindSystem.current_region_id = REGION


func after_each() -> void:
	for f in _FIELDS:
		AutogrindSystem.set(f, _saved[f])
	for d in _DICTS:
		AutogrindSystem.set(d, _saved[d])
	AutogrindSystem.grind_party.assign(_saved["grind_party"])
	_saved.clear()


## Runs `n` victories and returns a sample of the ladder afterwards.
##
## Emulates the Controller's collapse round-trip. _trigger_system_collapse does NOT reset
## corruption — the reset lives in apply_post_collapse_penalty, which AutogrindController:397
## calls after the collapse-BOSS battle resolves. Driving on_battle_victory alone leaves
## corruption above threshold forever, so collapse re-fires every single battle: measured
## 341 collapses in 400 battles, which is a property of the harness and not of the game.
## Without this the curve is fiction and `collapses > 0` passes trivially.
func _grind(n: int) -> Dictionary:
	for i in n:
		var before: int = AutogrindSystem.collapse_count
		AutogrindSystem.on_battle_victory(100)
		if AutogrindSystem.collapse_count > before:
			AutogrindSystem.apply_post_collapse_penalty()
	return {
		"battles": AutogrindSystem.battles_completed,
		"efficiency": AutogrindSystem.efficiency_multiplier,
		"adaptation": AutogrindSystem.monster_adaptation_level,
		"corruption": AutogrindSystem.meta_corruption_level,
		"collapses": AutogrindSystem.collapse_count,
		"csi": AutogrindSystem.get_csi(REGION),
		"yield": AutogrindSystem.get_yield_multiplier(REGION),
		"boss_chance": AutogrindSystem.meta_boss_spawn_chance,
	}


func test_the_ladder_is_not_flat_across_a_long_session() -> void:
	# The headline: sample four checkpoints and require the danger metrics to keep MOVING.
	# A flat or early-plateauing ladder passes every other test in the repo and fails here.
	var marks: Array[Dictionary] = []
	for step in 4:
		marks.append(_grind(100))

	for i in range(1, marks.size()):
		assert_gt(marks[i]["adaptation"], marks[i - 1]["adaptation"],
			"monster adaptation stalled between checkpoint %d and %d (%.3f -> %.3f) — enemies stop adapting, so a longer grind stops being more dangerous" % [i - 1, i, marks[i - 1]["adaptation"], marks[i]["adaptation"]])
		assert_gt(marks[i]["csi"], marks[i - 1]["csi"],
			"region CSI stalled between checkpoint %d and %d — the region stops registering wear" % [i - 1, i])

	assert_gt(marks[3]["collapses"], 0,
		"no system collapse in %d battles — the design's headline consequence never fires in a session-length grind" % (BATTLES))


func test_risk_grows_faster_than_it_starts() -> void:
	# ACCELERATION, not just increase. corruption gain is 0.02 * efficiency, and efficiency
	# climbs, so the second stretch must cost more corruption than the first. A linear ladder
	# would pass a monotonic check and still feel like a plateau.
	var first := _grind(40)
	var corruption_after_first: float = AutogrindSystem.meta_corruption_level
	var collapses_after_first: int = AutogrindSystem.collapse_count
	var eff_after_first: float = AutogrindSystem.efficiency_multiplier

	var second := _grind(40)
	var gained_second: float = AutogrindSystem.meta_corruption_level - corruption_after_first

	# A collapse resets corruption to 0, so only compare when none fired in the second stretch.
	if AutogrindSystem.collapse_count == collapses_after_first:
		assert_gt(gained_second, corruption_after_first,
			"the second 40 battles added no more risk than the first (%.3f vs %.3f) — the ladder is linear, not escalating" % [gained_second, corruption_after_first])
	else:
		# Collapse fired, which is itself the escalation landing. Assert it was EARNED by
		# rising efficiency rather than reachable from a standing start.
		assert_gt(eff_after_first, 1.0,
			"a collapse fired but efficiency never rose — collapse is reachable without grinding for it")
	assert_gt(second["efficiency"], first["efficiency"] if first["efficiency"] < AutogrindSystem.max_efficiency else 0.0,
		"efficiency did not grow across the run")


func test_reward_is_paid_for_by_falling_yield() -> void:
	# The "no free lunch" promise: grinding a region must make that region pay less.
	var before: float = AutogrindSystem.get_yield_multiplier(REGION)
	_grind(150)
	var after: float = AutogrindSystem.get_yield_multiplier(REGION)
	assert_lt(after, before,
		"yield did not fall after 150 battles in one region (%.3f -> %.3f) — grinding a region forever costs nothing, which is the hidden-free-lunch the design forbids" % [before, after])


func test_efficiency_plateaus_at_its_cap_and_the_rest_keeps_climbing() -> void:
	# efficiency is DESIGNED to cap (max_efficiency). Pin that the cap is real AND that the
	# ladder does not stop when it lands — otherwise the whole curve flattens at the cap.
	_grind(BATTLES)
	assert_almost_eq(AutogrindSystem.efficiency_multiplier, AutogrindSystem.max_efficiency, 0.001,
		"efficiency should reach its cap within %d battles" % BATTLES)

	var adaptation_at_cap: float = AutogrindSystem.monster_adaptation_level
	_grind(50)
	assert_gt(AutogrindSystem.monster_adaptation_level, adaptation_at_cap,
		"once efficiency caps, adaptation stops too — the ladder flattens permanently after the cap and every later battle is identical")


## ── Mechanism-level: the session tests above pass on a DEAD per-battle rung ────────────
## Adaptation and corruption each have TWO sources — per-battle (_increase_efficiency) and
## on-crack (_apply_meta_adaptation / the crack path). Zeroing the per-battle contribution
## leaves the session-level curves still rising on crack income alone, so those tests stay
## green while half the ladder is dead. Measured: two mutations, both survived. These isolate
## the per-battle rung by measuring a single battle, which cannot crack.

func test_a_single_battle_adds_adaptation() -> void:
	AutogrindSystem.consecutive_wins = 0
	var before: float = AutogrindSystem.monster_adaptation_level
	AutogrindSystem.on_battle_victory(100)
	assert_gt(AutogrindSystem.monster_adaptation_level, before,
		"one battle added no monster adaptation — the per-battle rung is dead and only region cracks still feed it, which the session-level tests cannot see")


func test_corruption_cost_per_battle_RISES_with_efficiency() -> void:
	# The acceleration mechanism itself: corruption gain is 0.02 * efficiency, so the same
	# single battle must cost more at high efficiency than at low. A relationship, not a
	# magnitude — a rebalance of the constant keeps this green, a linear ladder reds it.
	AutogrindSystem.consecutive_wins = 0
	AutogrindSystem.efficiency_multiplier = 1.0
	AutogrindSystem.meta_corruption_level = 0.0
	AutogrindSystem.on_battle_victory(100)
	var cheap: float = AutogrindSystem.meta_corruption_level

	AutogrindSystem.consecutive_wins = 0
	AutogrindSystem.efficiency_multiplier = 8.0
	AutogrindSystem.meta_corruption_level = 0.0
	AutogrindSystem.on_battle_victory(100)
	var dear: float = AutogrindSystem.meta_corruption_level

	assert_gt(dear, cheap,
		"a battle at 8x efficiency cost no more corruption than one at 1x (%.4f vs %.4f) — risk does not scale with reward, so the whole ladder is linear no matter how long you grind" % [dear, cheap])


func test_the_harness_actually_drove_the_real_path() -> void:
	# Control: without this, every assertion above could be passing on a run that did nothing.
	var before: int = AutogrindSystem.battles_completed
	_grind(10)
	assert_eq(AutogrindSystem.battles_completed, before + 10,
		"on_battle_victory did not register — the harness measured nothing")
	assert_gt(AutogrindSystem.get_csi(REGION), 0.0,
		"CSI never moved, so update_csi was not reached and the region half of the ladder is unmeasured")


func test_no_gold_is_credited_to_the_live_player() -> void:
	# Guards the hazard this file's header names: on_battle_victory reaches the real GameState.
	# If a future edit adds a gold key to the drive loop, this fires before it reaches a save.
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs == null or not ("party_gold" in gs):
		pass_test("GameState/party_gold unavailable in this context")
		return
	var before: int = gs.party_gold
	_grind(25)
	assert_eq(gs.party_gold, before,
		"the harness credited real player gold — on_battle_victory writes GameState.party_gold when items_gained carries a 'gold' key")
