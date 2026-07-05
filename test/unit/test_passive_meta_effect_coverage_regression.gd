extends GutTest

## Data-integrity guard (2026-07-05): completes the silent-failure coverage
## trilogy — abilities (test_support_ability_effect_coverage), items
## (test_item_effect_coverage), and now passive meta_effects. Every meta_effect
## key authored in passives.json must be classified as HANDLED (wired somewhere),
## DYNAMIC (consumed via a constructed key), or KNOWN_UNIMPLEMENTED (planned
## meta/advanced-job content, deliberately inert for now). A newly-authored
## meta_effect that's in none of these fails CI, forcing a triage decision rather
## than silently no-op'ing on a passive the player equipped.

const PASSIVES_PATH := "res://data/passives.json"

# meta_effects with a live consumer somewhere in src/ (verified 2026-07-05).
const HANDLED := [
	"auto_cover_threshold", "auto_save_before_boss", "auto_save_interval",
	"autobattle_advanced", "boss_damage_share", "boss_pattern_memory",
	"bp_regen_bonus", "corruption_resistance", "death_resist_chance",
	"encounter_skip_chance", "movement_speed_bonus", "mp_regen_percent",
	"preview_enemy_actions", "show_boss_hp", "show_boss_intent",
	"show_boss_weakness", "show_formulas", "show_secrets", "show_splits",
	"show_timer", "show_treasure", "song_duration_bonus",
	"summon_duration_bonus", "volatility_scaling",
]

# Consumed via a runtime-constructed key, so no literal string appears in src:
# undead_affinity's dark_absorb is read as `element + "_absorb"` in
# Combatant.take_elemental_damage (covered by test_elemental_absorb_passive).
const DYNAMIC := ["dark_absorb"]

# Authored but deliberately not wired yet — meta/advanced-job stubs (Skiptrotter
# overworld traversal, Speculator/debug HUD read-outs). Gated behind debug mode,
# not reachable in normal play. Move to HANDLED when implemented.
const KNOWN_UNIMPLEMENTED := [
	"overworld_double_jump", "overworld_wall_climb", "preview_turns",
	"show_critical_path", "show_debug_info", "show_error_log",
	"show_optional_markers", "track_personal_best",
]


func test_every_passive_meta_effect_is_classified() -> void:
	var passives = JSON.parse_string(FileAccess.get_file_as_string(PASSIVES_PATH))
	assert_eq(typeof(passives), TYPE_DICTIONARY, "passives.json must parse to a Dictionary")
	var root: Dictionary = passives.get("passives", passives)

	var classified := {}
	for arr in [HANDLED, DYNAMIC, KNOWN_UNIMPLEMENTED]:
		for k in arr:
			classified[k] = true

	var unclassified: Array[String] = []
	for pid in root:
		var passive = root[pid]
		if typeof(passive) != TYPE_DICTIONARY:
			continue
		var me = passive.get("meta_effects", {})
		if typeof(me) == TYPE_DICTIONARY:
			for key in me.keys():
				if not classified.has(str(key)):
					unclassified.append("%s (on passive '%s')" % [str(key), pid])

	assert_eq(unclassified.size(), 0,
		"passive meta_effect(s) not in HANDLED / DYNAMIC / KNOWN_UNIMPLEMENTED — a passive " +
		"granting one would silently no-op. Wire it and add to HANDLED, or list it: %s" % str(unclassified))
