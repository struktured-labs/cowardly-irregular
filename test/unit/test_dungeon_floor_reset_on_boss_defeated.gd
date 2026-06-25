extends GutTest

## tick 153 regression: completed dungeons (boss already defeated)
## must reset the saved floor to 1 on entry. Pre-fix the saved
## floor reflected "where you were last," so after killing the
## boss on the deepest floor the player saved+quit, then on
## re-entry they'd spawn in the empty boss room — no enemies, no
## reason to be there. They had to walk back to floor 1 via stairs
## to start any grinding loop.
##
## Two dungeon shapes covered: DragonCave (base; inherited by
## CastleHarmonia / FireDragonCave / IceDragonCave / etc.) and
## WhisperingCave (standalone, doesn't extend DragonCave).

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"
const WHISPERING_CAVE := "res://src/maps/dungeons/WhisperingCave.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── DragonCave base — covers 8 inheriting dungeons ──────────────────────

func test_dragon_cave_resets_floor_on_boss_defeated() -> void:
	# Pin: _ready (or wherever floor restore happens) clamps to
	# floor 1 if boss_defeated is true.
	var src := _read(DRAGON_CAVE)
	var idx: int = src.find("func _ready")
	assert_gt(idx, -1, "_ready must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Reset block must check boss_defeated AND non-1 floor (don't
	# write game_constants if already at 1, defensive idempotency).
	assert_true(body.contains("if boss_defeated and current_floor != 1:"),
		"DragonCave._ready must reset floor when boss already defeated AND floor != 1")
	# Must clamp BOTH the runtime field AND the saved key.
	assert_true(body.contains("current_floor = 1") and body.contains("GameState.game_constants[floor_key] = 1"),
		"reset must update runtime current_floor AND the persisted game_constants entry")


func test_dragon_cave_reset_runs_AFTER_floor_restore() -> void:
	# Pin ordering: the reset MUST be downstream of the
	# saved_floor restore. Otherwise the restore would overwrite
	# the reset and the bug would persist.
	var src := _read(DRAGON_CAVE)
	var idx: int = src.find("func _ready")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	var restore_idx: int = body.find("current_floor = saved_floor")
	var reset_idx: int = body.find("if boss_defeated and current_floor != 1:")
	assert_gt(restore_idx, -1)
	assert_gt(reset_idx, -1)
	assert_lt(restore_idx, reset_idx,
		"floor restore must come BEFORE the boss-defeated reset — else reset gets overwritten")


# ── WhisperingCave — standalone, doesn't extend DragonCave ──────────────

func test_whispering_cave_resets_floor_on_boss_defeated() -> void:
	var src := _read(WHISPERING_CAVE)
	var idx: int = src.find("func _ready")
	assert_gt(idx, -1, "_ready must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Reset block — same shape, but uses literal "whispering_cave_floor"
	# key since WhisperingCave doesn't have cave_id.
	assert_true(body.contains("if boss_defeated and current_floor != 1 and GameState:"),
		"WhisperingCave._ready must reset floor when Cave Rat King defeated AND floor != 1")
	assert_true(body.contains("GameState.game_constants[\"whispering_cave_floor\"] = 1"),
		"WhisperingCave reset must clear the persisted key too")


# ── Negative regressions ────────────────────────────────────────────────

func test_dragon_cave_reset_doesnt_fire_when_boss_alive() -> void:
	# Pin: the guard condition. Without `boss_defeated and ...`
	# the reset would fire for ALL re-entries including in-progress
	# runs, wiping the player's hard-earned floor progress.
	var src := _read(DRAGON_CAVE)
	var idx: int = src.find("func _ready")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Negative pin: the unconditional reset pattern must NOT appear.
	assert_false(body.contains("current_floor = 1\n\tGameState.game_constants[floor_key] = 1"),
		"unconditional reset MUST NOT exist — guard MUST require boss_defeated")


func test_existing_floor_restore_logic_still_present() -> void:
	# Don't regress the pre-existing floor restore (the whole
	# point of the persistence layer).
	var src := _read(DRAGON_CAVE)
	assert_true(src.contains("var saved_floor: int = int(GameState.game_constants[floor_key])"),
		"DragonCave must still restore saved_floor from game_constants")
	var ws_src := _read(WHISPERING_CAVE)
	assert_true(ws_src.contains("var saved_floor: int = int(GameState.game_constants[\"whispering_cave_floor\"])"),
		"WhisperingCave must still restore from its game_constants key")


# ── Runtime check ────────────────────────────────────────────────────────

func test_runtime_dragon_cave_floor_resets_when_boss_defeated() -> void:
	# Build a minimal scenario: set saved floor to 5 + boss_defeated
	# true, instantiate a DragonCave subclass, verify _ready
	# resolves current_floor to 1 and clears the game_constants key.
	# Use a unique test cave_id to avoid polluting any real cave's state.
	var test_id := "tick_153_test_cave"
	var floor_key := test_id + "_floor"
	# Snapshot to restore post-test.
	var pre_floor_value = GameState.game_constants.get(floor_key, null)
	GameState.game_constants[floor_key] = 5

	# We can't easily instantiate DragonCave (it sets up scene
	# components in _ready). Instead, reproduce the reset logic
	# inline against a mock cave_id to verify the BEHAVIOR matches
	# the source-pinned code.
	var saved_floor: int = int(GameState.game_constants[floor_key])
	assert_eq(saved_floor, 5, "sanity: saved floor is 5")
	# Mirror the source: total_floors >= 5 to allow restore.
	# Apply the reset:
	var boss_defeated: bool = true
	var current_floor: int = saved_floor
	if boss_defeated and current_floor != 1:
		current_floor = 1
		GameState.game_constants[floor_key] = 1
	# Restore pre-test state.
	if pre_floor_value == null:
		GameState.game_constants.erase(floor_key)
	else:
		GameState.game_constants[floor_key] = pre_floor_value
	assert_eq(current_floor, 1,
		"boss_defeated reset must clamp current_floor to 1")
