extends GutTest

## Corruption roster completion (2026-07-10): bp_instability and
## ability_corruption were the last two effects with NO runtime handler
## (documented-unwired with a loud-warn since the tick-178 era). Now:
## bp_instability jitters the player's natural AP gain 0/+1/+2; a corrupted
## cast misfires 10% of player abilities into another learned ability. This
## pins every roster entry to a live consumer so the roster can't grow a
## hollow effect again.

const ROSTER := ["visual_glitch", "stat_drain", "bp_instability",
	"encounter_surge", "ability_corruption"]

const CONSUMER_FILES := [
	"res://src/battle/BattleManager.gd",
	"res://src/battle/BattleScene.gd",
	"res://src/exploration/OverworldController.gd",
]


func test_every_corruption_effect_has_a_live_consumer() -> void:
	# The roster in GameState must match this test's (a new effect must come
	# with BOTH a consumer and a roster update here).
	var gs := FileAccess.get_file_as_string("res://src/meta/GameState.gd")
	for eff in ROSTER:
		assert_true("\"%s\"" % eff in gs, "%s still in the GameState roster" % eff)
	var consumers := ""
	for f in CONSUMER_FILES:
		consumers += FileAccess.get_file_as_string(f)
	for eff in ROSTER:
		var hits := consumers.count("\"%s\"" % eff)
		assert_gt(hits, 0, "corruption effect '%s' has NO consumer in the runtime files — hollow effect" % eff)


func test_ap_jitter_only_under_bp_instability() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i := src.find("bp_instability (corruption)")
	assert_gt(i, 0, "the jitter block exists at the natural-gain site")
	var block := src.substr(i, 900)
	assert_true("current_combatant in player_party" in block or "in player_party" in block,
		"jitter is PLAYER-only — enemy AP economy stays deterministic")
	assert_true("gain_ap(ap_gain)" in block, "the jittered value is what actually lands")


func test_ability_misfire_swaps_within_learned_kit() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i := src.find("ability_corruption (corruption)")
	assert_gt(i, 0, "the misfire block exists at the ability entry")
	var block := src.substr(i, 700)
	assert_true("learned_abilities" in block and "randi() % others.size()" in block,
		"misfire draws from the caster's OWN learned kit, never arbitrary ids")
	assert_true("caster in player_party" in block, "misfire is player-only")
	assert_true("CORRUPTED CAST" in block, "the misfire announces itself")
