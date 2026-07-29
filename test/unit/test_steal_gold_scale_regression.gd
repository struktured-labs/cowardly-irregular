extends GutTest

## Steal/Mug gold broke when the ×10 pass landed. 2026-07-29.
##
## Both steal paths pay out `randi_range(5, 50) * (1 + int(target.max_hp / 50.0))`. That divisor is
## an ABSOLUTE magnitude. max_hp went ×10; the divisor did not; and `gold_reward` was deliberately
## left alone because the gold economy was not part of the re-denomination. So the steal formula and
## the authored economy diverged by exactly 10×.
##
##                    max_hp   gold_reward   steal payout
##   Slime  (broken)     680            10       70 – 700     ← 70× its own kill value
##   Slime  (pre-×10)     68            10       10 – 100
##   Mordaine (broken) 16,500          800    1,655 – 16,550  ← 20× her authored reward
##   Mordaine (pre)     1,650          800      170 – 1,700
##
## One steal from the weakest monster in the game netted up to 700 gold — nearly the entire reward
## for beating the World 1 final boss. Fixed by scaling the divisor, which reproduces the pre-scale
## payouts EXACTLY (verified against v3.33.205-alpha), so it is a re-denomination fix and not a
## balance change.
##
## Found by sweeping for a class nobody had: a stat used as a MAGNITUDE rather than a value — a loop
## count, a pixel size, a divisor. Those go ×10 silently because nothing about them looks like a
## stat comparison, so the absolute-threshold sweep that found the tank gate could not see them.


func _steal_range(max_hp: int) -> Array:
	var mult: int = 1 + int(max_hp / BattleManager.STEAL_GOLD_HP_DIVISOR)
	return [5 * mult, 50 * mult]


func _monsters() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))


# ── the invariant that actually broke ───────────────────────────────

func test_stealing_from_trash_cannot_outearn_killing_the_hardest_boss() -> void:
	# Derived from the corpus, not chosen: the largest authored gold_reward in the game. Robbing a
	# slime paying better than defeating the World 1 finale is the absurdity, and it states the
	# defect in terms a player would recognise rather than in terms of the divisor.
	var mons: Dictionary = _monsters()
	var best_reward: int = 0
	var weakest_id: String = ""
	var weakest_hp: int = 1 << 30
	for id in mons:
		var e: Dictionary = mons[id]
		best_reward = maxi(best_reward, int(e.get("gold_reward", 0)))
		var hp: int = int((e.get("stats", {}) as Dictionary).get("max_hp", 0))
		if hp > 0 and hp < weakest_hp:
			weakest_hp = hp
			weakest_id = str(id)
	assert_gt(best_reward, 0, "corpus must declare gold rewards or this test measures nothing")
	var worst_case: int = _steal_range(weakest_hp)[1]
	assert_lt(worst_case, best_reward,
		"a max-roll steal from %s (%d hp) pays %d, against the game's best authored reward of %d — "
			% [weakest_id, weakest_hp, worst_case, best_reward]
		+ "robbing the weakest monster must not beat killing the hardest")


func test_steal_stays_proportionate_to_each_monsters_own_reward() -> void:
	# The per-monster form. Pre-×10 the worst ratio in the corpus was 10× (a slime's 100-gold max
	# roll against its 10-gold kill). Anything far above that means the divisor has drifted from
	# the stat scale again.
	var mons: Dictionary = _monsters()
	var offenders: Array = []
	for id in mons:
		var e: Dictionary = mons[id]
		var reward: int = int(e.get("gold_reward", 0))
		var hp: int = int((e.get("stats", {}) as Dictionary).get("max_hp", 0))
		if reward <= 0 or hp <= 0:
			continue
		var ratio: float = float(_steal_range(hp)[1]) / float(reward)
		if ratio > 12.0:
			offenders.append("%s: max steal %d vs reward %d (%.0f×)"
				% [id, _steal_range(hp)[1], reward, ratio])
	assert_eq(offenders, [], "steal payout has drifted from the authored economy:\n  %s"
		% "\n  ".join(offenders))


# ── the relationship, not the literal ───────────────────────────────

func test_the_divisor_tracks_the_stat_scale() -> void:
	# Pinning `== 500.0` would go red on a correct future rescale and stay green on a wrong value
	# spelled the same way — the coincidental-magnitude trap. The divisor was 50 when stats were
	# at scale 1, so the relationship is what wants defending.
	assert_eq(BattleManager.STEAL_GOLD_HP_DIVISOR, 50.0 * float(Combatant.STAT_SCALE),
		"the divisor is an absolute magnitude and must move with Combatant.STAT_SCALE — leaving "
		+ "it behind is exactly how a slime came to pay out 700 gold")


func test_no_steal_site_hardcodes_the_old_divisor() -> void:
	# Two sites compute this independently (Mug's inline steal and the pure Steal handler). Fixing
	# one and missing the other is the partial-enumeration shape; the named constant is what makes
	# a third site cheap to get right, but only if nobody reintroduces the literal.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.contains("max_hp / 50.0"),
		"the pre-scale divisor must be gone from every steal path, not just the one that was found")
	assert_eq(src.count("STEAL_GOLD_HP_DIVISOR"), 3,
		"one declaration plus both steal sites — a count below 3 means a site was missed")


# ── positive control ────────────────────────────────────────────────

func test_the_payout_math_is_actually_exercised() -> void:
	# Every assertion above would pass identically against a helper that returned zeros. Prove the
	# formula runs and discriminates between a weak and a strong target.
	var weak: Array = _steal_range(680)
	var strong: Array = _steal_range(16500)
	assert_gt(weak[1], 0, "a real payout must be computed")
	assert_gt(strong[1], weak[1], "a bigger target must still pay more — the fix rescales the "
		+ "curve, it does not flatten it")
