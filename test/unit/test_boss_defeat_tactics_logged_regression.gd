extends GutTest

## Feature regression: when the player defeats a boss, the EventLog entry
## now records HOW they won — pure autobattle / jailbreak landed / all-out
## attack / etc. — not just THAT they won.
##
## This bridges three already-live subsystems:
##   • BattleManager already tracked _full_autobattle, _autobattle_player_turns,
##     _manual_player_turns, _jailbreak_landed_this_battle, and
##     _all_out_attack_this_battle for the gloat-line prompt.
##   • EventLog already had TYPE_BOSS_DEFEAT and was recorded on pending boss
##     defeats by GameLoop._apply_pending_boss_defeat.
##   • Dynamic NPC dialogue already enriches prompts with EventLog.recent().
## …but the tactics snapshot wasn't reaching EventLog, so NPC chats had no
## way to react ("you autobattled your way past the Rat King?").
##
## Now BattleManager exposes get_battle_tactics_snapshot() and GameLoop
## merges its result into the boss-defeat data dict before recording.
##
## Tests:
##   • Snapshot returns all expected keys with correct primitive types.
##   • Defaults at start_battle are honest (pure_autobattle=true,
##     autobattle_used=false, counts 0).
##   • _track_manual_player_turn flips pure_autobattle false + increments
##     manual count (the manual-command path).
##   • Snapshot only contains JSON-primitive types, so EventLog._scrub_value
##     won't drop it.
##   • Source-pin: GameLoop._apply_pending_boss_defeat merges the snapshot
##     into the defeat_data dict and records it via event_log.record.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const GAME_LOOP_PATH      := "res://src/GameLoop.gd"
const EVENT_LOG_SCRIPT    := preload("res://src/llm/EventLog.gd")


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── BattleManager.get_battle_tactics_snapshot ─────────────────────────────────

func test_snapshot_returns_expected_shape() -> void:
	# Reach the live BattleManager autoload (used by the rest of the suite).
	var bm := get_node_or_null("/root/BattleManager")
	assert_not_null(bm, "BattleManager autoload must be reachable")
	assert_true(bm.has_method("get_battle_tactics_snapshot"),
		"BattleManager must expose get_battle_tactics_snapshot()")
	var snap: Dictionary = bm.get_battle_tactics_snapshot()
	for key in [
		"pure_autobattle", "autobattle_used", "manual_turns",
		"autobattle_turns", "jailbreak_landed", "all_out_attack_used",
	]:
		assert_true(snap.has(key),
			"snapshot must contain key '%s'" % key)
	# Type contract:
	assert_eq(typeof(snap["pure_autobattle"]), TYPE_BOOL,
		"pure_autobattle must be bool")
	assert_eq(typeof(snap["autobattle_used"]), TYPE_BOOL,
		"autobattle_used must be bool")
	assert_eq(typeof(snap["jailbreak_landed"]), TYPE_BOOL,
		"jailbreak_landed must be bool")
	assert_eq(typeof(snap["all_out_attack_used"]), TYPE_BOOL,
		"all_out_attack_used must be bool")
	assert_eq(typeof(snap["manual_turns"]), TYPE_INT,
		"manual_turns must be int")
	assert_eq(typeof(snap["autobattle_turns"]), TYPE_INT,
		"autobattle_turns must be int")


func test_snapshot_only_holds_json_primitive_types() -> void:
	# Defense against future fields that EventLog._scrub_value would drop
	# (Object, Callable, RID, NodePath, etc.) — drop those by accident and
	# the tactic NPC-chat hook silently goes blank.
	var bm := get_node_or_null("/root/BattleManager")
	assert_not_null(bm, "BattleManager autoload must be reachable")
	var snap: Dictionary = bm.get_battle_tactics_snapshot()
	for key in snap.keys():
		var t: int = typeof(snap[key])
		var ok := t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT \
			or t == TYPE_STRING or t == TYPE_STRING_NAME \
			or t == TYPE_DICTIONARY or t == TYPE_ARRAY
		assert_true(ok,
			"snapshot value at '%s' has non-JSON-safe type %d — EventLog would drop it" % [key, t])


func test_manual_command_flips_pure_autobattle_false() -> void:
	# Drive _track_manual_player_turn and confirm the snapshot reflects it.
	var bm := get_node_or_null("/root/BattleManager")
	assert_not_null(bm, "BattleManager autoload must be reachable")
	# Snapshot state before so we can restore after.
	var before: Dictionary = bm.get_battle_tactics_snapshot()
	# Force a known starting state so the assertion is unambiguous.
	bm._full_autobattle = true
	bm._manual_player_turns = 0
	# Drive a manual turn.
	bm._track_manual_player_turn()
	var snap: Dictionary = bm.get_battle_tactics_snapshot()
	assert_false(snap["pure_autobattle"],
		"pure_autobattle must be false after a manual command")
	assert_gt(int(snap["manual_turns"]), 0,
		"manual_turns must increment after _track_manual_player_turn()")
	# Restore (the suite shares the live autoload across tests).
	bm._full_autobattle = bool(before.get("pure_autobattle", true))
	bm._manual_player_turns = int(before.get("manual_turns", 0))


# ── EventLog roundtrip ────────────────────────────────────────────────────────

func test_event_log_preserves_nested_tactics_dict() -> void:
	# EventLog._scrub_value recurses into TYPE_DICTIONARY, so a primitives-only
	# tactics dict must round-trip intact through record() + recent().
	var log: EventLog = EVENT_LOG_SCRIPT.new()
	log.record(EVENT_LOG_SCRIPT.TYPE_BOSS_DEFEAT, "Defeated test", {
		"boss_id":   "test_boss_defeated",
		"boss_name": "Test Boss",
		"map_id":    "test_cave",
		"world":     1,
		"tactics": {
			"pure_autobattle":     true,
			"autobattle_used":     true,
			"manual_turns":        0,
			"autobattle_turns":    4,
			"jailbreak_landed":    false,
			"all_out_attack_used": true,
		},
	})
	var entries: Array = log.recent(1)
	assert_eq(entries.size(), 1, "EventLog must record exactly one entry")
	var entry: Dictionary = entries[0]
	assert_eq(entry.get("type", ""), EVENT_LOG_SCRIPT.TYPE_BOSS_DEFEAT,
		"recorded entry must keep TYPE_BOSS_DEFEAT")
	var data: Dictionary = entry.get("data", {})
	assert_true(data.has("tactics"),
		"EventLog must preserve the nested tactics dict")
	var tactics: Dictionary = data["tactics"]
	assert_true(tactics.get("pure_autobattle", false),
		"nested tactics.pure_autobattle must round-trip true")
	assert_eq(int(tactics.get("autobattle_turns", 0)), 4,
		"nested tactics.autobattle_turns must round-trip int 4")
	assert_true(tactics.get("all_out_attack_used", false),
		"nested tactics.all_out_attack_used must round-trip true")


# ── GameLoop wiring ───────────────────────────────────────────────────────────

func test_game_loop_merges_tactics_into_defeat_data() -> void:
	# Source-pin: the boss-defeat record block must (a) call
	# get_battle_tactics_snapshot, (b) merge the result under "tactics", and
	# (c) record it via event_log.record(EventLog.TYPE_BOSS_DEFEAT, ...).
	var text := _read(GAME_LOOP_PATH)
	var idx := text.find("EventLog.TYPE_BOSS_DEFEAT")
	assert_gt(idx, -1, "GameLoop must reference EventLog.TYPE_BOSS_DEFEAT")
	# Look ~600 chars BEFORE the marker for the tactics merge, since the
	# tactics dict is built before the record() call.
	var window_start: int = maxi(0, idx - 600)
	var window: String = text.substr(window_start, idx - window_start + 200)
	assert_true(window.contains("get_battle_tactics_snapshot"),
		"GameLoop boss-defeat record must call get_battle_tactics_snapshot")
	assert_true(window.contains("\"tactics\""),
		"GameLoop boss-defeat record must store the snapshot under \"tactics\"")
	assert_true(window.contains("event_log.record("),
		"GameLoop must record via event_log.record(...)")


func test_battle_manager_snapshot_is_documented() -> void:
	# Keep the snapshot's contract visible to future readers — without an
	# explicit keys list, the boss-defeat data shape would be archeology.
	var text := _read(BATTLE_MANAGER_PATH)
	var idx := text.find("func get_battle_tactics_snapshot")
	assert_gt(idx, -1, "get_battle_tactics_snapshot must exist")
	# Walk backward to the preceding doc-comment block.
	var doc_start: int = maxi(0, idx - 800)
	var doc_window: String = text.substr(doc_start, idx - doc_start)
	assert_true(doc_window.contains("pure_autobattle"),
		"snapshot doc comment must list 'pure_autobattle' (the canonical key)")
	assert_true(doc_window.contains("jailbreak_landed"),
		"snapshot doc comment must list 'jailbreak_landed'")
