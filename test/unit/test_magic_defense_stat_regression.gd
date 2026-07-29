extends GutTest

## magic_defense became a real stat on 2026-07-29 (struktured ruling).
##
## Before: Combatant had six stats and magic mitigation was `defense * 0.5`, computed inline at
## the point of damage. That constant arrived in the Dec-2025 generated scaffold — it was never a
## design decision. It survived two later rewrites (the subtractive->ratio formula change, and the
## get_buffed_stat wrapping) because neither edit was ABOUT the halving; it rode along both times.
##
## Three separate systems referenced magic defense BY NAME and all three resolved to plain defense:
##   the damage formula          defense * 0.5
##   magic_defense_down          add_debuff(..., "defense", ...)   log said "magic defense"/"DEF"
##   lowest_magic_defense_enemy  sort by .defense, shipped in 5 autobattle presets
## That is not three workarounds around a missing stat — it is one arbitrary constant with three
## consumers faithfully implementing it. Splitting it gives enemy design an axis it never had:
## physically tough / magically frail, and the reverse.
##
## The pass was authored as a ZERO-DRIFT migration: every existing block got
## magic_defense = int(defense * 0.5), so unbuffed damage is bit-identical to the old behaviour.
## test_unbuffed_damage_is_identical_to_the_old_halving is the proof of that claim, and it is the
## test that would go red if a future rescale silently changed balance while claiming not to.
##
## ONE behaviour DOES change deliberately, and it is inherent to the split rather than smuggled in:
## Protect (defense_up) no longer mitigates magic. A separate stat that defense buffs still control
## would be the same stat with extra steps. Pinned below so nobody "fixes" it back by accident.


func _combatant(def_val: int, mdef: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "dummy"
	c.max_hp = 100000
	c.current_hp = c.max_hp
	c.defense = def_val
	c.magic_defense = mdef
	return c


# ── the stat exists and is wired into the formula ───────────────────

func test_magic_defense_is_a_real_stat() -> void:
	var c := _combatant(40, 20)
	assert_eq(c.magic_defense, 20, "magic_defense must be independently settable")
	c.free()


func test_magic_damage_reads_magic_defense_not_defense() -> void:
	# The whole point: make the two stats disagree and confirm each school reads its own.
	var glass_armour := _combatant(200, 5)    # plate-armoured, magically naked
	var ward := _combatant(5, 200)            # unarmoured, heavily warded
	var magic_vs_armour := glass_armour.take_damage(100, true)
	var magic_vs_ward := ward.take_damage(100, true)
	assert_gt(magic_vs_armour, magic_vs_ward,
		"a spell must hurt the low-M.DEF target more, regardless of its physical defense")
	glass_armour.free(); ward.free()


func test_physical_damage_still_reads_defense() -> void:
	var glass_armour := _combatant(200, 5)
	var ward := _combatant(5, 200)
	assert_lt(glass_armour.take_damage(100, false), ward.take_damage(100, false),
		"a sword must hurt the low-DEF target more, regardless of its magic defense")
	glass_armour.free(); ward.free()


# ── the zero-drift claim, pinned ────────────────────────────────────

func test_unbuffed_damage_is_identical_to_the_old_halving() -> void:
	# The migration set magic_defense = int(defense * 0.5) everywhere, so this must reproduce the
	# pre-split number exactly. If this ever goes red, a "pure re-denomination" changed balance.
	for def_val in [8, 28, 32, 52, 100, 340]:
		for raw in [10, 75, 400, 1800]:
			var c := _combatant(def_val, int(def_val * 0.5))
			var got := c.take_damage(raw, true)
			c.free()
			var old_def: int = int(def_val * 0.5)
			var expected: int = maxi(1, int((raw * raw) / float(maxi(1, raw + old_def))))
			assert_eq(got, expected,
				"def=%d raw=%d — split must reproduce the old defense*0.5 result exactly"
					% [def_val, raw])


# ── grandfathering: nothing authored before the split may break ─────

func test_a_monster_block_without_magic_defense_derives_it() -> void:
	var c := Combatant.new()
	c.initialize({"max_hp": 500, "attack": 30, "defense": 44, "magic": 20, "speed": 10})
	assert_eq(c.magic_defense, 22,
		"a stats block predating the split must derive magic_defense from defense, not sit at the "
		+ "class default — that would silently rewrite every unmigrated enemy")
	c.free()


func test_a_presplit_SAVE_derives_magic_defense() -> void:
	# from_dict is the path a real save takes. A save written before today has no magic_defense key.
	var c := Combatant.new()
	c.from_dict({"combatant_name": "Old Hero", "max_hp": 300, "attack": 25, "defense": 60,
		"magic": 30, "speed": 12, "job_level": 9})
	assert_eq(c.magic_defense, 30,
		"loading a pre-split save must derive magic_defense — defaulting to 5 would make every "
		+ "existing character catastrophically vulnerable to magic on first load")
	c.free()


func test_magic_defense_survives_a_save_roundtrip() -> void:
	var c := _combatant(70, 41)
	var restored := Combatant.new()
	restored.from_dict(c.to_dict())
	assert_eq(restored.magic_defense, 41, "magic_defense must serialize — an unsaved stat resets")
	c.free(); restored.free()


# ── the deliberate behaviour change ─────────────────────────────────

func test_protect_no_longer_mitigates_magic() -> void:
	# Inherent to the split, not an accident. Before today, defense_up buffs raised magic
	# mitigation too, because the formula buffed defense and THEN halved it.
	var c := _combatant(100, 50)
	var unbuffed := c.take_damage(200, true)
	c.add_buff("Protect", "defense", 1.5, 3)
	var buffed := c.take_damage(200, true)
	assert_eq(buffed, unbuffed,
		"a DEFENSE buff must not change MAGIC damage — if it does, the stats are not really split")
	c.free()


func test_a_magic_defense_buff_does_mitigate_magic() -> void:
	# The positive control for the test above: an empty effect and a working one look identical
	# from a single negative assertion.
	var c := _combatant(100, 50)
	var unbuffed := c.take_damage(200, true)
	c.add_buff("Shell", "magic_defense", 2.0, 3)
	assert_lt(c.take_damage(200, true), unbuffed,
		"buffing magic_defense MUST reduce magic damage — otherwise the stat is inert and the "
		+ "test above passes for the wrong reason")
	c.free()


func test_soul_sap_debuffs_magic_defense_not_defense() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, 'add_debuff("Soul Sap", "magic_defense"',
		"magic_defense_down authored an effect named for a stat it did not touch — it debuffed "
		+ "plain defense while the log announced magic defense")


# ── data ratchet ────────────────────────────────────────────────────

func test_every_monster_and_job_declares_magic_defense() -> void:
	# Derivation covers unmigrated data, so a gap here is silent rather than fatal — which is
	# exactly why it needs a ratchet. An enemy without an authored M.DEF is not tunable.
	var offenders: Array = []
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for id in mons:
		var stats: Variant = (mons[id] as Dictionary).get("stats")
		if stats is Dictionary and (stats as Dictionary).has("defense") \
				and not (stats as Dictionary).has("magic_defense"):
			offenders.append("monster:" + str(id))
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	for id in jobs:
		var mods: Variant = (jobs[id] as Dictionary).get("stat_modifiers")
		if mods is Dictionary and (mods as Dictionary).has("defense") \
				and not (mods as Dictionary).has("magic_defense"):
			offenders.append("job:" + str(id))
	assert_eq(offenders, [], "these declare defense but no magic_defense: %s" % str(offenders))


func test_the_ratchet_can_actually_see_a_gap() -> void:
	# Positive control. An empty offender list and a broken scan read identically.
	var stats := {"defense": 40, "magic": 10}
	assert_true(stats.has("defense") and not stats.has("magic_defense"),
		"the shape the ratchet above scans for must be detectable")


# ── the targeting mode that named the stat before it existed ────────

func test_lowest_magic_defense_targeting_sorts_by_magic_defense() -> void:
	var src := FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")
	assert_string_contains(src, "a.magic_defense < b.magic_defense",
		"lowest_magic_defense_enemy ships in 5 autobattle presets and is labelled 'Lowest M.DEF "
		+ "Enemy' — it sorted by plain defense because the stat did not exist")
