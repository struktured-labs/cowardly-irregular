extends GutTest

## ×10 numeric re-denomination, 2026-07-29 (struktured ruling: "these HP values are stupidly low
## ... multiply by 10 practically if we playing along canon Bravely Default / Octopath / FF6").
##
## At the World 1 FINAL BOSS the fighter hit for 21 and Mordaine had 1650 HP. Two-digit damage,
## four-digit boss HP, sixteen rounds.
##
## The damage formula is dealt = raw² / (raw + def), homogeneous of degree 1 — scale raw and def
## together and dealt scales with them. So ×10 on stats AND hp is a PURE RE-DENOMINATION: every
## fight plays identically, the numbers just read like a JRPG. That property is the entire
## justification for the change, so it is what this file pins.
##
## SCALED: monster/job max_hp, attack, defense, magic, magic_defense · equipment stat_mods attack,
##         defense, magic, max_hp · ability heal_amount + absorb_amount · item heal_hp + damage
## NOT SCALED, deliberately:
##   speed          purely comparative (turn order) — scaling it changes nothing and risks
##                  the `speed >= 18` assassin threshold
##   MP economy     max_mp, mp_cost, heal_mp are self-consistent; scaling one side breaks it
##   exp / gold     progression pacing must not move
##   *_percent      already scale-free
##   poison tick    int(max_hp * 0.05), a percentage
##
## ONE code constant had to move with the data: BattleManager's tank archetype gated on
## `max_hp >= 150`. At ×10 every combatant clears that, so the entire roster would have silently
## reclassified as "tank" — a game-wide AI change hiding inside a "pure re-denomination". It was
## the ONLY absolute HP threshold in src/, found by scanning for the shape rather than by reading.

const JRPG_FLOOR := 10000


func _dealt(raw: int, def_val: int) -> int:
	return maxi(1, int((raw * raw) / float(maxi(1, raw + def_val))))


# ── the property that makes ×10 safe ────────────────────────────────

func test_the_formula_is_scale_invariant() -> void:
	# Compared against the UNTRUNCATED value, not against 10x the small integer.
	#
	# Exact 10x does not hold, and the reason is worth stating: dealt() truncates to int, and at
	# small numbers that truncation is proportionally large. _dealt(15, 8) computes 9.78 and
	# returns 9; the x10 form computes 97.8 and returns 97. Asserting big == small * 10 would
	# demand 90 and fail on a change that is mathematically correct — it would be pinning the
	# OLD ROUNDING ERROR, not the fight.
	#
	# So the honest invariant is that the x10 game is the same fight computed MORE precisely:
	# every scaled result lands within a unit of ten times the real-valued formula.
	for raw in [15, 75, 260, 900]:
		for def_val in [8, 32, 52, 340]:
			var exact: float = float(raw * raw) / float(raw + def_val)
			var big := _dealt(raw * 10, def_val * 10)
			assert_almost_eq(float(big), exact * 10.0, 1.5,
				"raw=%d def=%d — ×10 must reproduce the real-valued fight, not a different one"
					% [raw, def_val])


func test_round_counts_are_unchanged_at_the_new_scale() -> void:
	# Measured pre-scale against the live formula: Rat King 8.8 rounds, Umbraxis 12.2, Mordaine
	# 16.5, using fighter power_strike + mage fire + rogue backstab at the boss's own level.
	var expected := {"cave_rat_king": 8.8, "shadow_dragon": 12.2, "chancellor_mordaine": 16.5}
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var abils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))

	for boss_id in expected:
		var boss: Dictionary = mons[boss_id]
		var bstats: Dictionary = boss["stats"]
		var lvl: int = int(boss["level"])
		var mult: float = 1.0 + (lvl - 1) * 0.04
		var per_round := 0
		for pair in [["fighter", "power_strike"], ["mage", "fire"], ["rogue", "backstab"]]:
			var mods: Dictionary = (jobs[pair[0]] as Dictionary)["stat_modifiers"]
			var ability: Dictionary = abils[pair[1]]
			var is_mag: bool = str(ability.get("type", "")) == "magic"
			var stat: int = int(int(mods["magic" if is_mag else "attack"]) * mult)
			var raw: int = int(stat * float(ability.get("damage_multiplier", 1.0)))
			var def_key: String = "magic_defense" if is_mag else "defense"
			per_round += _dealt(raw, int(bstats[def_key]))
		var rounds: float = float(int(bstats["max_hp"])) / float(maxi(1, per_round))
		assert_almost_eq(rounds, float(expected[boss_id]), 0.6,
			"%s must still take ~%.1f rounds — ×10 is a re-denomination, not a rebalance"
				% [boss_id, expected[boss_id]])


# ── the goal: numbers that read like the genre ──────────────────────

func test_the_w1_final_boss_reaches_the_jrpg_band() -> void:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var hp: int = int(((mons["chancellor_mordaine"] as Dictionary)["stats"] as Dictionary)["max_hp"])
	assert_gte(hp, JRPG_FLOOR,
		"Mordaine ends World 1 — her HP should read like a JRPG boss, not like an NES one (was 1650)")


# ── the exclusions, each pinned so a later pass cannot quietly scale them ──

func test_speed_was_not_scaled() -> void:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var slime_speed: int = int(((mons["slime"] as Dictionary)["stats"] as Dictionary)["speed"])
	assert_lt(slime_speed, 100,
		"speed is comparative — scaling it gains nothing and breaks the `speed >= 18` assassin gate")


func test_mp_economy_was_not_scaled() -> void:
	var abils: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_lt(int((abils["fire"] as Dictionary).get("mp_cost", 0)), 100,
		"mp_cost must not scale — max_mp did not either, and moving one side breaks the economy")


func test_exp_and_gold_were_not_scaled() -> void:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var boss: Dictionary = mons["chancellor_mordaine"]
	assert_lt(int(boss.get("exp_reward", 0)), 5000,
		"exp must not scale — the level curve and every gate on it would move")


func test_the_tank_threshold_moved_with_the_data() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "combatant.max_hp >= 1500",
		"the tank archetype gate was the only absolute HP threshold in src/ — left at 150 the "
		+ "entire roster classifies as tank and enemy AI changes game-wide")


# ── lie-in-the-label ratchet ────────────────────────────────────────

func test_no_description_misstates_its_own_heal_value() -> void:
	# "Restores 50 HP" on an item that heals 500 is the failure this catches. Generalised rather
	# than pinned to the five that needed fixing, so the next rescale cannot reintroduce it.
	var offenders: Array = []
	var num := RegEx.create_from_string("([0-9]+)\\s*HP")
	for spec in [["res://data/items.json", "heal_hp"], ["res://data/abilities.json", "heal_amount"]]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec[0]))
		for id in data:
			var entry: Variant = data[id]
			if not (entry is Dictionary):
				continue
			var e: Dictionary = entry
			var effects: Dictionary = e.get("effects", e)
			if not effects.has(spec[1]):
				continue
			var m := num.search(str(e.get("description", "")))
			if m != null and int(m.get_string(1)) != int(effects[spec[1]]):
				offenders.append("%s says %s HP but heals %d" % [id, m.get_string(1), int(effects[spec[1]])])
	assert_eq(offenders, [], "descriptions contradicting their own effect:\n  %s" % "\n  ".join(offenders))


func test_no_monster_prose_misstates_its_own_hp() -> void:
	# Umbraxis is the dragon who knows he is in a game — "My HP is 1200 because someone typed it"
	# works ONLY because a player who checks finds it true. After ×10 he was citing a number the
	# player can see is wrong, which does not read as a stale constant; it reads as the meta-joke
	# failing, in the one character whose credibility is being right about the implementation.
	#
	# The line lived in TWO files (boss_dialogue.json and monsters.json) — the two-sources shape.
	# Four of my own W3/W4 setup_hints were stale the same way, written hours earlier in this
	# session. Prose asserting a stat has no mechanical coupling to the stat, so nothing but this
	# scan can catch it.
	var offenders: Array = []
	var hp_claim := RegEx.create_from_string("([0-9]{2,6})\\s*HP")
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for id in mons:
		var entry: Dictionary = mons[id]
		var real_hp: int = int((entry.get("stats", {}) as Dictionary).get("max_hp", 0))
		var texts: Array = [str((entry.get("one_shot", {}) as Dictionary).get("setup_hint", ""))]
		for line in ((entry.get("dialogue", {}) as Dictionary).get("opening_lines", []) as Array):
			texts.append(str(line))
		for text in texts:
			for m in hp_claim.search_all(text):
				if int(m.get_string(1)) != real_hp:
					offenders.append("%s claims '%s HP' but has %d" % [id, m.get_string(1), real_hp])
	assert_eq(offenders, [], "prose contradicting its own stat block:\n  %s" % "\n  ".join(offenders))


func test_umbraxis_still_names_a_true_number() -> void:
	# Pinned separately from the sweep above because it lives in a SECOND file the sweep cannot
	# see — the same line is authored in both boss_dialogue.json and monsters.json, and fixing
	# one is indistinguishable from fixing both until you look.
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var hp: int = int(((mons["shadow_dragon"] as Dictionary)["stats"] as Dictionary)["max_hp"])
	var bd := FileAccess.get_file_as_string("res://data/boss_dialogue.json")
	assert_string_contains(bd, "My HP is %d because someone typed it" % hp,
		"boss_dialogue.json is a SECOND home for this line — the joke needs the number true in "
		+ "both places, and monsters.json agreeing proves nothing about this file")


func test_the_label_ratchet_can_see_a_mismatch() -> void:
	# Positive control — an empty offender list and a broken regex read identically.
	var num := RegEx.create_from_string("([0-9]+)\\s*HP")
	var m := num.search("Restores 50 HP")
	assert_not_null(m, "the ratchet's regex must actually match the authored description shape")
	assert_eq(int(m.get_string(1)), 50, "and must extract the number it compares against")
