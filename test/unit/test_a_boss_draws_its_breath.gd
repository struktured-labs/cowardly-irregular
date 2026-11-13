extends GutTest

## BossCadence: a boss with a `cadence` row plays `every` ordinary turns, charges visibly, then releases its signature.
## A stun or silence landing mid-charge breaks the breath and the count starts over.


func _beats(cfg: Dictionary, n: int) -> Array:
	var st := BossCadence.fresh_state()
	var out: Array = []
	for i in n:
		var r: Dictionary = BossCadence.next(st, cfg)
		out.append(r["beat"])
		st = r["state"]
	return out


func _cfg(every: int, charge: int) -> Dictionary:
	return BossCadence.config({"cadence": {"signature": "absolute_zero", "every": every, "charge_turns": charge}})


func test_a_row_without_a_cadence_only_plays_plain_turns() -> void:
	assert_eq(BossCadence.config({}), {}, "no cadence key, no clock")
	assert_eq(BossCadence.config({"cadence": {"every": 2}}), {}, "a cadence naming no signature is no clock")
	assert_eq(_beats({}, 6), ["plain", "plain", "plain", "plain", "plain", "plain"])


func test_every_three_then_one_charge_then_the_release_and_round_again() -> void:
	assert_eq(_beats(_cfg(3, 1), 10),
		["plain", "plain", "plain", "charge", "release", "plain", "plain", "plain", "charge", "release"])


func test_a_longer_charge_holds_for_its_turns() -> void:
	assert_eq(_beats(_cfg(1, 2), 5), ["plain", "charge", "charge", "release", "plain"])


func test_a_stun_mid_charge_breaks_the_breath_and_the_count_restarts() -> void:
	var cfg := _cfg(2, 1)
	var st := BossCadence.fresh_state()
	for i in 3:
		st = BossCadence.next(st, cfg)["state"]
	assert_true(BossCadence.is_charging(st), "control: after plain, plain, charge the boss is charging")
	st = BossCadence.on_status(st, cfg, "stun")
	assert_false(BossCadence.is_charging(st), "the stun broke the charge")
	assert_true(bool(st["interrupted"]), "the break is reported, so the scene can say so")
	var after: Array = []
	for i in 3:
		var r: Dictionary = BossCadence.next(st, cfg)
		after.append(r["beat"])
		st = r["state"]
	assert_eq(after, ["plain", "plain", "charge"], "no release follows a broken charge; the clock starts over")


func test_a_status_that_does_not_interrupt_leaves_the_charge() -> void:
	var cfg := _cfg(1, 1)
	var st: Dictionary = BossCadence.next(BossCadence.next(BossCadence.fresh_state(), cfg)["state"], cfg)["state"]
	assert_true(BossCadence.is_charging(st), "control: charging")
	st = BossCadence.on_status(st, cfg, "poison")
	assert_true(BossCadence.is_charging(st), "poison does not break a breath")
	assert_eq(BossCadence.next(st, cfg)["beat"], "release")


func test_a_stun_while_building_does_not_reset_the_count() -> void:
	var cfg := _cfg(3, 1)
	var st: Dictionary = BossCadence.next(BossCadence.fresh_state(), cfg)["state"]
	st = BossCadence.next(st, cfg)["state"]
	st = BossCadence.on_status(st, cfg, "stun")
	assert_false(bool(st["interrupted"]), "nothing to interrupt before the charge")
	assert_eq(int(st["count"]), 2, "the count it had is kept")


func test_every_authored_cadence_names_a_signature_its_boss_can_cast() -> void:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	mons = mons.get("monsters", mons)
	var abil: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	abil = abil.get("abilities", abil)
	var seen := 0
	for id in mons:
		var row: Variant = mons[id]
		if not row is Dictionary or not (row as Dictionary).has("cadence"):
			continue
		seen += 1
		var cfg := BossCadence.config(row)
		assert_false(cfg.is_empty(), "%s: its cadence parses" % id)
		var sig := str(cfg.get("signature", ""))
		assert_has((row as Dictionary).get("abilities", []), sig, "%s: the signature is in its own kit" % id)
		assert_true(abil.has(sig), "%s: %s resolves in abilities.json" % [id, sig])
	assert_true(mons.has("ice_dragon") and (mons["ice_dragon"] as Dictionary).has("cadence"), "Glacius carries the first cadence")
	assert_gt(seen, 0, "floor: the walk found an authored cadence")
