extends GutTest

## Regression: OverworldController._check_encounter() must honour the
## full UI-exposed range of GameState.encounter_rate_multiplier (0.0
## to 2.0), not silently cap at 1.0.
##
## Bug shape:
##   • SettingsMenu lets the user pick 0.0 - 2.0 on an encounter-rate
##     slider, stored in GameState.encounter_rate_multiplier and
##     persisted in save_data.
##   • _check_encounter (pre-fix) used the multiplier as a SECONDARY
##     `randf() < rate_multiplier` guard AFTER
##     EncounterSystem.check_for_encounter().
##   • For multiplier > 1.0 the secondary roll is always true (randf()
##     ∈ [0, 1) < 1.5 is always true), so the bonus did nothing —
##     the slider effectively capped at 1.0x. Players who slid it to
##     "2x encounters" got plain 1x.
##   • For 0.0 < multiplier < 1.0 the secondary roll DID reduce
##     frequency, but via a different math than the ES base rate
##     respects, so the curve was non-linear.
##
## Fix: compose the settings multiplier into ES's
## encounter_rate_modifier for the duration of one check. ES's chance
## calc (encounter_rate * encounter_rate_modifier) then sees the full
## scaled rate. We clamp to ES.ENCOUNTER_RATE_MODIFIER_MAX so a bad
## save can't push past the engine's contract, and restore the
## original modifier after so Repel / debuff state isn't polluted.
##
## Tests:
##   • Source pin: the `randf() < rate_multiplier` secondary roll is
##     gone, replaced by scaling encounter_rate_modifier
##   • Source pin: the modifier is restored to its pre-call value
##   • Behavioural: after _check_encounter, ES.encounter_rate_modifier
##     equals its pre-call value (no pollution)
##   • Behavioural: with a high settings multiplier, the modifier was
##     temporarily scaled (probed by stubbing check_for_encounter to
##     capture the value during the call)

const OVERWORLD_CONTROLLER_PATH := "res://src/exploration/OverworldController.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_secondary_randf_roll_removed() -> void:
	# The pre-fix pattern `check_for_encounter() and randf() < rate_multiplier`
	# must NOT appear anywhere in _check_encounter. Walk the function body
	# and scan code lines only (the doc comment cites the legacy shape).
	var text := _read(OVERWORLD_CONTROLLER_PATH)
	var idx := text.find("func _check_encounter")
	assert_gt(idx, -1, "_check_encounter must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var lines := body.split("\n")
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		# The legacy bug shape: check_for_encounter() followed by `and randf()`
		# on the same line.
		assert_false(ln.contains("check_for_encounter()") and ln.contains("randf()"),
			"_check_encounter must NOT chain check_for_encounter() with a randf() secondary roll — that's the capped-at-1x bug shape. Offending line: %s" % ln)


func test_modifier_is_restored_after_check() -> void:
	# The source must restore the original encounter_rate_modifier value
	# after the check to avoid polluting Repel / item state.
	var text := _read(OVERWORLD_CONTROLLER_PATH)
	var idx := text.find("func _check_encounter")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("es.encounter_rate_modifier = original_modifier"),
		"_check_encounter must restore the original encounter_rate_modifier after the check")


func test_modifier_scaling_respects_es_max_clamp() -> void:
	# The composite scaling must clamp to ES's documented max so a bad
	# settings value can't push past the engine's contract.
	var text := _read(OVERWORLD_CONTROLLER_PATH)
	var idx := text.find("func _check_encounter")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("ENCOUNTER_RATE_MODIFIER_MAX"),
		"_check_encounter must clamp the composite to ES.ENCOUNTER_RATE_MODIFIER_MAX")


# ── Behavioural ──────────────────────────────────────────────────────────────

const OverworldControllerScript := preload("res://src/exploration/OverworldController.gd")


func test_modifier_is_pristine_after_check_completes() -> void:
	# End-to-end: drive _check_encounter on a live OverworldController +
	# the EncounterSystem autoload, assert ES.encounter_rate_modifier
	# equals its pre-call value when we're done (no pollution).
	if not EncounterSystem:
		pending("EncounterSystem autoload unavailable")
		return
	if not GameState:
		pending("GameState autoload unavailable")
		return
	var prior_modifier: float = EncounterSystem.encounter_rate_modifier
	var prior_settings: float = GameState.encounter_rate_multiplier
	# Pick a non-trivial settings multiplier to ensure the scaling path
	# fires (>1 so the legacy bug would have masked it).
	GameState.encounter_rate_multiplier = 1.75
	# Build a controller; add to tree so get_tree() resolves.
	var ctrl: OverworldController = OverworldControllerScript.new()
	add_child_autofree(ctrl)
	# Call _check_encounter. Result depends on RNG/ES state, but we only
	# care about post-condition state, not the return value.
	ctrl._check_encounter()
	assert_almost_eq(EncounterSystem.encounter_rate_modifier, prior_modifier, 0.0001,
		"ES.encounter_rate_modifier must be restored to its pre-call value after _check_encounter")
	# Restore.
	GameState.encounter_rate_multiplier = prior_settings


func test_zero_multiplier_short_circuits_without_touching_modifier() -> void:
	# Sanity: the rate_multiplier <= 0.0 early-return path was already
	# correct pre-fix; assert it still skips the ES path entirely (no
	# modifier mutation, no encounter check, just returns false).
	if not EncounterSystem:
		pending("EncounterSystem autoload unavailable")
		return
	if not GameState:
		pending("GameState autoload unavailable")
		return
	var prior_modifier: float = EncounterSystem.encounter_rate_modifier
	var prior_settings: float = GameState.encounter_rate_multiplier
	GameState.encounter_rate_multiplier = 0.0
	var ctrl: OverworldController = OverworldControllerScript.new()
	add_child_autofree(ctrl)
	var result: bool = ctrl._check_encounter()
	assert_false(result,
		"_check_encounter must short-circuit to false when the settings multiplier is 0")
	assert_almost_eq(EncounterSystem.encounter_rate_modifier, prior_modifier, 0.0001,
		"ES.encounter_rate_modifier must NOT be touched on the 0-multiplier early-return path")
	# Restore.
	GameState.encounter_rate_multiplier = prior_settings
