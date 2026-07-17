extends GutTest

## MasteriteEncounter runtime integration (msg 2569 cadence, PR #139 followup).
##
## The static PR #139 test (test_w1_masterites_placed) source-pins the
## MasteriteEncounter contract: pending_boss_defeat + defeat_flag() + gate
## on w1_<archetype>_defeated. But no test actually EXERCISES the
## body_entered → pending_boss_defeat → _apply_pending_boss_defeat →
## story-flag-written round-trip. A future edit that stops staking
## story_flags, swaps to game_constants, or changes the defeat_flag
## naming convention would slip past static assertions.
##
## This test drives the trigger like a real player entering the encounter
## zone: instantiate the trigger in-tree, fake a body_entered with a
## player-group node, confirm the pending_boss_defeat spec, apply it via
## the actual GameLoop mechanism, verify the flag lands, then verify the
## trigger self-hides on scene re-entry (once-per-save contract).

const MasteriteEncounterScript := preload("res://src/exploration/MasteriteEncounter.gd")


func _fake_player() -> Node2D:
	var p := Node2D.new()
	p.add_to_group("player")
	return p


func _clear_flags(archetype: String) -> void:
	if GameState == null:
		return
	var flag := "w1_%s_defeated" % archetype
	GameState.set_story_flag(flag, false)
	GameState.pending_boss_defeat = {}


func before_each() -> void:
	_clear_flags("warden")
	_clear_flags("tempo")
	_clear_flags("arbiter")
	_clear_flags("curator")


func after_each() -> void:
	_clear_flags("warden")
	_clear_flags("tempo")
	_clear_flags("arbiter")
	_clear_flags("curator")


## When the player enters the trigger zone, MasteriteEncounter must stake
## pending_boss_defeat.story_flags with the archetype's defeat flag.
func test_body_entered_stakes_pending_boss_defeat() -> void:
	var trig := MasteriteEncounterScript.new()
	trig.archetype = "warden"
	trig.monster_id = "masterite_warden_medieval"
	add_child_autofree(trig)
	await get_tree().process_frame

	var player := _fake_player()
	add_child_autofree(player)
	await get_tree().process_frame

	# Drive the entry handler directly — the physics probe would need a
	# real CharacterBody2D on layer 2. Direct call exercises the same
	# code path minus the collision-mask filter.
	trig._on_body_entered(player)

	var spec: Dictionary = GameState.pending_boss_defeat
	assert_false(spec.is_empty(), "pending_boss_defeat is staked on entry")
	var story_flags: Array = spec.get("story_flags", [])
	assert_true(story_flags.has("w1_warden_defeated"),
		"pending story_flags carries w1_warden_defeated (got %s)" % str(story_flags))


## Source-level contract: GameLoop._apply_pending_boss_defeat must
## read spec.story_flags and clear pending_boss_defeat after applying.
## Verified at source rather than invoked at runtime — the real handler
## calls SaveSystem.auto_save() at the end, which writes to user://saves
## and would corrupt struktured's live saves on every full-suite run
## (feedback_test_isolation_from_user_save, msg 2586 PSA class).
func test_apply_pending_boss_defeat_consumes_story_flags() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn_idx := src.find("func _apply_pending_boss_defeat")
	assert_gt(fn_idx, 0, "GameLoop._apply_pending_boss_defeat exists")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("spec: Dictionary = GameState.pending_boss_defeat"),
		"reads pending_boss_defeat")
	assert_true(body.contains("spec.get(\"story_flags\", [])"),
		"consumes spec.story_flags — the field MasteriteEncounter stakes")
	assert_true(body.contains("GameState.set_story_flag(flag)"),
		"writes each story_flag entry via set_story_flag — same store MasteriteEncounter reads on _ready")
	assert_true(body.contains("GameState.pending_boss_defeat = {}"),
		"clears pending_boss_defeat after applying (one-shot contract)")


## Once the defeat flag is set, a fresh MasteriteEncounter must hide
## itself and stop monitoring on _ready — the once-per-save contract.
func test_defeated_trigger_hides_on_ready() -> void:
	GameState.set_story_flag("w1_arbiter_defeated", true)

	var trig := MasteriteEncounterScript.new()
	trig.archetype = "arbiter"
	trig.monster_id = "masterite_arbiter_medieval"
	add_child_autofree(trig)
	await get_tree().process_frame

	assert_false(trig.visible,
		"defeated MasteriteEncounter is hidden on scene re-entry")
	assert_false(trig.monitoring,
		"defeated MasteriteEncounter stops monitoring — no ghost collisions")


## Warden gates on cave_rat_king_defeated per the design doc. Prereq
## unmet → trigger hides; prereq met → trigger visible.
func test_prereq_flag_gates_visibility() -> void:
	GameState.set_story_flag("cave_rat_king_defeated", false)

	var trig := MasteriteEncounterScript.new()
	trig.archetype = "warden"
	trig.monster_id = "masterite_warden_medieval"
	trig.prereq_flag = "cave_rat_king_defeated"
	add_child_autofree(trig)
	await get_tree().process_frame

	assert_false(trig.visible,
		"Warden hidden until Rat King defeated (design doc 'legitimate business')")
	assert_false(trig.monitoring,
		"Warden not monitoring until prereq is met — no accidental fires")

	# Cleanup — the prereq flag is a shared W1 story flag; other tests
	# shouldn't inherit our stale set here.
	GameState.set_story_flag("cave_rat_king_defeated", false)


## Re-entry with the flag already set: even if body_entered fires
## (paranoid case), the trigger must not double-stake pending_boss_defeat.
func test_defeated_trigger_ignores_body_entered() -> void:
	GameState.set_story_flag("w1_curator_defeated", true)

	var trig := MasteriteEncounterScript.new()
	trig.archetype = "curator"
	trig.monster_id = "masterite_curator_medieval"
	add_child_autofree(trig)
	await get_tree().process_frame

	var player := _fake_player()
	add_child_autofree(player)
	trig._on_body_entered(player)

	assert_true(GameState.pending_boss_defeat.is_empty(),
		"defeated trigger must not stake pending_boss_defeat again")
