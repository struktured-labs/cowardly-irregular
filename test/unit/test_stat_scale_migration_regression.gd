extends GutTest

## Pre-scale saves loaded a 1/10th-strength party into a ×10 world. 2026-07-29.
##
## The ×10 re-denomination rewrote every stat in monsters.json and jobs.json, but Combatant.from_dict
## RESTORES saved values rather than recomputing them from the job. So a save written before the pass
## kept its old numbers while every enemy grew tenfold.
##
## Measured against struktured's actual local saves, not hypothesised:
##   save_00.json  (Jul 25, his manual save)   lvl 5-7 party, max_hp 91-208, atk 7-42
##   save_98.json  (Jul 29, this session)      post-scale
## Loading save_00 gives a level-7 party ~126 HP against a 6,500 HP Rat King. Unwinnable, and
## unrecoverable — no amount of play fixes stats that are an order of magnitude behind.
##
## Nothing could have caught this. Every test builds its combatants from current data, so the whole
## suite is blind to a file written under an older schema by construction. It surfaced only from
## asking what a save on disk actually contained.
##
## DETECTION: saves now carry `stat_scale`. Files predating the marker are dated by whether they
## carry `magic_defense`, which became a real stat minutes before the ×10 pass — the only thing
## separating the two eras. A file written inside that window would be under-migrated; none exist,
## and the marker makes the ambiguity unreachable going forward.


func _presave_party_member() -> Dictionary:
	# Shaped like a real entry from save_00.json — the Fighter at level 5.
	return {"combatant_name": "Hero", "job_id": "fighter", "job_level": 5,
		"max_hp": 208, "current_hp": 208, "max_mp": 36, "current_mp": 36,
		"attack": 42, "defense": 39, "magic": 14, "speed": 22}


# ── the migration itself ────────────────────────────────────────────

func test_a_prescale_block_is_multiplied() -> void:
	# SWEPT, not sampled. cowir-ai 2026-07-29: "one string is a coordinate; the sweep is the
	# relationship." The property is "ANY pre-scale block migrates" — my original single fixture
	# was a level-5 fighter, and a migration restricted to `job_id == "fighter"` passed 9/9 against
	# it. The mutation applied, the guard ran, the code was broken, and it printed green; nothing
	# about the experiment was wrong except its input.
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var checked: int = 0
	for job_id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		if not jobs.has(job_id):
			continue
		for lvl in [1, 5, 20]:
			var block := {"combatant_name": "P", "job_id": job_id, "job_level": lvl,
				"max_hp": 208, "current_hp": 130, "max_mp": 36,
				"attack": 42, "defense": 39, "magic": 14, "speed": 22}
			var out := Combatant.migrate_stat_scale(block)
			checked += 1
			assert_eq(int(out["max_hp"]), 2080,
				"%s L%d — every job and level must migrate, not just the one this test was written "
					% [job_id, lvl] + "against")
			assert_eq(int(out["attack"]), 420, "%s L%d attack" % [job_id, lvl])
			assert_eq(int(out["defense"]), 390, "%s L%d defense" % [job_id, lvl])
			assert_eq(int(out["current_hp"]), 1300,
				"%s L%d — current_hp must move with max_hp, not stay at 1/10th" % [job_id, lvl])
	assert_eq(checked, 15, "positive control — 5 jobs × 3 levels must actually be exercised")


func test_migration_does_not_depend_on_job_or_level_being_present() -> void:
	# A save from a corrupted or partial write may carry stats without job_id. The migration is
	# about the DENOMINATION, which is a property of the numbers, not of who owns them.
	var bare := {"max_hp": 208, "attack": 42}
	var out := Combatant.migrate_stat_scale(bare)
	assert_eq(int(out["max_hp"]), 2080,
		"migration must key on the scale marker alone — gating it on job_id or level makes it "
		+ "silently partial for any block that lacks them")


func test_the_unscaled_stats_are_left_alone() -> void:
	# The ×10 data pass deliberately skipped the MP economy and turn order. A migration that
	# scaled them would break the thing the original pass was careful not to touch.
	var out := Combatant.migrate_stat_scale(_presave_party_member())
	assert_eq(int(out["max_mp"]), 36, "MP must not scale — mp_cost did not either")
	assert_eq(int(out["speed"]), 22, "speed is comparative; scaling it moves the assassin gate")
	assert_eq(int(out["job_level"]), 5, "level must not be touched")


func test_a_postscale_block_is_not_scaled_twice() -> void:
	# The dangerous case. save_98.json was written THIS SESSION: already ×10, and with no
	# stat_scale marker because the marker did not exist yet. Migrating it would produce an
	# 18,000 HP level-1 fighter — a bug strictly worse than the one being fixed.
	var already := {"combatant_name": "Hero", "job_id": "fighter", "job_level": 1,
		"max_hp": 1816, "current_hp": 1816, "attack": 400, "defense": 370,
		"magic": 140, "magic_defense": 70, "speed": 22}
	var out := Combatant.migrate_stat_scale(already.duplicate(true))
	assert_eq(int(out["max_hp"]), 1816,
		"a block carrying magic_defense post-dates the split and must be left alone")
	assert_eq(int(out["attack"]), 400)


func test_the_marker_makes_it_idempotent() -> void:
	var once := Combatant.migrate_stat_scale(_presave_party_member())
	var twice := Combatant.migrate_stat_scale(once.duplicate(true))
	assert_eq(int(twice["max_hp"]), int(once["max_hp"]),
		"migrating a migrated block must be a no-op — loads happen more than once per session")
	assert_eq(int(once["stat_scale"]), Combatant.STAT_SCALE, "the marker must be stamped")


# ── the seams it has to run at ──────────────────────────────────────

func test_the_migration_runs_at_the_FILE_boundary_not_in_from_dict() -> void:
	# First attempt wired this into Combatant.from_dict and 14 existing tests went red: that
	# deserializer is also fed by fixtures, time-rewind restore and in-memory snapshots whose
	# values are already current, and a small fixture without magic_defense looks exactly like a
	# pre-scale save. A file on disk is the ONLY input that can predate the denomination, so the
	# migration belongs where a file is parsed and nowhere else.
	var save_src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_string_contains(save_src, "_migrate_stat_denomination(json.data)",
		"_read_save_file is the single point every save on disk passes through")
	var comb_src := FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_false(comb_src.contains("data = migrate_stat_scale(data)"),
		"from_dict must NOT migrate — it would ×10 every non-save caller, which is how this was "
		+ "caught: 14 red tests holding small fixture stats")


func test_a_prescale_party_array_migrates_end_to_end() -> void:
	# The shape _read_save_file actually receives.
	var save := {"game_state": {"player_party": [_presave_party_member()]}}
	var party: Array = (save["game_state"] as Dictionary)["player_party"]
	party[0] = Combatant.migrate_stat_scale(party[0])
	assert_eq(int((party[0] as Dictionary)["max_hp"]), 2080,
		"a pre-scale party inside a save envelope must come out at the current denomination")


func test_to_dict_stamps_the_scale_so_the_next_load_is_unambiguous() -> void:
	var c := Combatant.new()
	c.combatant_name = "Hero"
	c.max_hp = 1320
	var saved := c.to_dict()
	assert_eq(int(saved.get("stat_scale", 0)), Combatant.STAT_SCALE,
		"every save written from now on must record its denomination — the magic_defense "
		+ "heuristic is a one-time bridge, not a permanent detector")
	c.free()


func test_the_gamestate_snapshot_inherits_the_migration() -> void:
	# player_party is read directly by menus and shops without constructing Combatants, so it is a
	# second consumer of the same dicts and would show 1/10th stats if it were missed.
	#
	# It is NOT separately migrated, and that is deliberate: _read_save_file rewrites the envelope
	# in place, and SaveSystem then hands that same migrated game_state to GameState.from_dict.
	# Migrating twice would be harmless (the marker makes it idempotent) but would state the
	# ownership wrongly — the file boundary owns this, and one owner is the point.
	var src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	var mig: int = src.find("_migrate_stat_denomination(json.data)")
	var handoff: int = src.find('GameState.from_dict(data["game_state"])')
	assert_gt(mig, -1, "the file boundary must migrate")
	assert_gt(handoff, -1, "SaveSystem must hand game_state to GameState — if this call moved, "
		+ "the snapshot no longer inherits the migration and needs its own")


# ── positive control ────────────────────────────────────────────────

func test_the_migration_can_be_observed_to_do_nothing_when_current() -> void:
	# An assertion that a value is unchanged passes identically against a migration that runs
	# correctly and one that never runs at all. Prove the function is reached and discriminating.
	var pre := Combatant.migrate_stat_scale(_presave_party_member())
	var post := Combatant.migrate_stat_scale({"max_hp": 500, "stat_scale": Combatant.STAT_SCALE})
	assert_eq(int(pre["max_hp"]), 2080, "pre-scale input must change")
	assert_eq(int(post["max_hp"]), 500, "current input must not")
