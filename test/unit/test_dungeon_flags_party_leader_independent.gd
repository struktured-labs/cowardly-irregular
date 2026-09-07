extends GutTest

## tick 154 regression: dungeon_flags (boss-defeated state) lived
## on player_party[0]["dungeon_flags"]. The leader index can
## change via GameState.cycle_party_leader — so a player who
## promoted a different PC to leader after defeating a boss
## silently lost the defeated state, and the boss respawned on
## next dungeon re-entry.
##
## Moved to GameState.game_constants["dungeon_flags"] (party-
## leader-independent). All 5 callsites updated:
##   - DragonCave._load_boss_state (read)
##   - DragonCave._save_boss_state (write)
##   - WhisperingCave._load_boss_state (read)
##   - WhisperingCave._save_boss_state (write)
##   - GameLoop pending_boss_defeat write
##
## Read sites also fall back to the legacy player_party[0] location
## for save-format migration — old saves' flags still resolve.

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"
const WHISPERING_CAVE := "res://src/maps/dungeons/WhisperingCave.gd"
const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Read-side sites all consult game_constants first ────────────────────

func test_dragon_cave_load_uses_game_constants_with_legacy_fallback() -> void:
	var src := _read(DRAGON_CAVE)
	var idx: int = src.find("func _load_boss_state")
	assert_gt(idx, -1, "_load_boss_state must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# New canonical location.
	assert_true(body.contains("game_state.game_constants.has(\"dungeon_flags\")"),
		"DragonCave._load_boss_state must check game_constants first")
	assert_true(body.contains("game_state.game_constants[\"dungeon_flags\"]"),
		"DragonCave._load_boss_state must read from game_constants")
	# Legacy fallback for save-format migration.
	assert_true(body.contains("game_state.player_party[0].has(\"dungeon_flags\")"),
		"DragonCave._load_boss_state must fall back to legacy player_party[0] location for old saves")
	# Ordering: game_constants checked BEFORE legacy fallback (elif).
	var gc_idx: int = body.find("game_state.game_constants.has(\"dungeon_flags\")")
	var legacy_idx: int = body.find("game_state.player_party[0].has(\"dungeon_flags\")")
	assert_lt(gc_idx, legacy_idx,
		"game_constants check must be ordered BEFORE legacy fallback")


func test_whispering_cave_load_uses_game_constants_with_legacy_fallback() -> void:
	var src := _read(WHISPERING_CAVE)
	var idx: int = src.find("func _load_boss_state")
	assert_gt(idx, -1, "_load_boss_state must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("game_state.game_constants.has(\"dungeon_flags\")"),
		"WhisperingCave._load_boss_state must check game_constants")
	assert_true(body.contains("game_state.player_party[0].has(\"dungeon_flags\")"),
		"WhisperingCave._load_boss_state must keep legacy fallback")


# ── Write-side sites only write to game_constants ───────────────────────

func test_dragon_cave_save_writes_to_game_constants() -> void:
	var src := _read(DRAGON_CAVE)
	var idx: int = src.find("func _save_boss_state")
	assert_gt(idx, -1, "_save_boss_state must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("game_state.game_constants[\"dungeon_flags\"][boss_flag_key] = true"),
		"DragonCave._save_boss_state must write to game_constants")
	# Negative pin: must NOT still write to the legacy location.
	assert_false(body.contains("game_state.player_party[0][\"dungeon_flags\"][boss_flag_key] = true"),
		"DragonCave._save_boss_state must NOT write to legacy player_party[0] location — that's the bug being fixed")


func test_whispering_cave_save_writes_to_game_constants() -> void:
	var src := _read(WHISPERING_CAVE)
	var idx: int = src.find("func _save_boss_state")
	assert_gt(idx, -1)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("game_state.game_constants[\"dungeon_flags\"][\"cave_rat_king_defeated\"] = true"),
		"WhisperingCave._save_boss_state must write to game_constants")
	assert_false(body.contains("game_state.player_party[0][\"dungeon_flags\"][\"cave_rat_king_defeated\"] = true"),
		"WhisperingCave._save_boss_state must NOT write to legacy player_party[0] location")


func test_gameloop_pending_boss_defeat_writes_to_game_constants() -> void:
	var src := _read(GAME_LOOP)
	# The pending_boss_defeat dungeon_flag write block.
	assert_true(src.contains("GameState.game_constants[\"dungeon_flags\"][df] = true"),
		"GameLoop pending_boss_defeat dungeon_flag write must target game_constants")
	# Negative pin.
	assert_false(src.contains("GameState.player_party[0][\"dungeon_flags\"][df] = true"),
		"GameLoop pending_boss_defeat must NOT write to legacy player_party[0] location")


# ── Behavioral: leader change preserves flags ───────────────────────────

func test_runtime_dungeon_flag_survives_party_leader_cycle() -> void:
	# End-to-end: write a dungeon flag, cycle the leader, read it
	# back. Pre-fix the read would miss because it consulted the
	# new leader's empty dungeon_flags dict.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing in test env")
		return

	# Snapshot for isolation.
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_leader: int = gs.party_leader_index
	var pre_dungeon_flags = gs.game_constants.get("dungeon_flags", null)

	# Ensure ≥ 2 party members for the cycle test. The headless
	# test env may have an empty party; seed two dummy entries.
	if gs.player_party.size() < 2:
		var stub: Array[Dictionary] = [
			{"name": "TestA", "job_id": "fighter"},
			{"name": "TestB", "job_id": "cleric"},
		]
		gs.player_party = stub
		gs.party_leader_index = 0

	# Simulate writing a boss-defeat flag (mimic
	# DragonCave._save_boss_state).
	if not gs.game_constants.has("dungeon_flags"):
		gs.game_constants["dungeon_flags"] = {}
	gs.game_constants["dungeon_flags"]["tick_154_test_boss_defeated"] = true

	# Cycle the leader (the bug's trigger).
	gs.cycle_party_leader(1)
	assert_ne(gs.party_leader_index, pre_leader,
		"sanity: cycle_party_leader changes the index")

	# Simulate reading the flag (mimic DragonCave._load_boss_state's
	# canonical path).
	var flags: Dictionary = {}
	if gs.game_constants.has("dungeon_flags"):
		flags = gs.game_constants["dungeon_flags"]
	var boss_defeated: bool = flags.get("tick_154_test_boss_defeated", false)

	# Restore state.
	gs.party_leader_index = pre_leader
	if pre_party != null:
		gs.player_party = pre_party
	if pre_dungeon_flags == null:
		gs.game_constants.erase("dungeon_flags")
	else:
		gs.game_constants["dungeon_flags"] = pre_dungeon_flags

	assert_true(boss_defeated,
		"dungeon_flag must survive party-leader cycle — was the silent-failure bug pre-tick-154")


# ── Sanity: legacy fallback path still works ────────────────────────────

func test_runtime_legacy_player_party_dungeon_flags_still_resolve() -> void:
	# Old saves stored flags on player_party[0]. The migration
	# fallback in _load_boss_state-style code must still resolve
	# those — without it, old saves' boss-defeat state vanishes.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing in test env")
		return

	# Snapshot.
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_canonical = gs.game_constants.get("dungeon_flags", null)

	# Ensure ≥ 1 party member for the legacy-fallback test.
	if gs.player_party.is_empty():
		var stub: Array[Dictionary] = [{"name": "TestA", "job_id": "fighter"}]
		gs.player_party = stub
	var pre_legacy = gs.player_party[0].get("dungeon_flags", null)

	# Set up a legacy save state: flag on player_party[0], nothing
	# on game_constants.
	gs.player_party[0]["dungeon_flags"] = {"tick_154_legacy_flag": true}
	gs.game_constants.erase("dungeon_flags")

	# Mimic the _load_boss_state lookup with legacy fallback.
	var flags: Dictionary = {}
	if gs.game_constants.has("dungeon_flags"):
		flags = gs.game_constants["dungeon_flags"]
	elif gs.player_party.size() > 0 and gs.player_party[0].has("dungeon_flags"):
		flags = gs.player_party[0]["dungeon_flags"]
	var legacy_flag: bool = flags.get("tick_154_legacy_flag", false)

	# Restore.
	if pre_legacy == null:
		gs.player_party[0].erase("dungeon_flags")
	else:
		gs.player_party[0]["dungeon_flags"] = pre_legacy
	if pre_party != null:
		gs.player_party = pre_party
	if pre_canonical != null:
		gs.game_constants["dungeon_flags"] = pre_canonical

	assert_true(legacy_flag,
		"legacy player_party[0] dungeon_flags must still resolve via the fallback path — for save-format migration")
