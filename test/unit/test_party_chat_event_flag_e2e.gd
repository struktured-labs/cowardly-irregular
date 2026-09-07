extends GutTest

## tick 251: end-to-end coverage of the event-chat wiring sweep.
##
## Closes the loop on ticks 247-250. The previous wiring test
## (test_party_chat_event_flag_wiring.gd) verifies each flag is
## WRITTEN somewhere in src/. This file verifies the contract on the
## consumer side: setting the flag actually makes the corresponding
## REGISTRY entry available via PartyChatSystem.is_available().
##
## Catches regressions where:
##   - flag name in the writer drifts from the REGISTRY unlock list
##     (e.g. a refactor renames event_flag_X but only patches one side)
##   - is_available's `_is_unlocked` logic regresses
##   - REGISTRY entry gets a second unlock flag that the writer doesn't
##     set, silently locking the chat behind a missing fixture

const PARTY_CHAT := "res://src/cutscene/PartyChatSystem.gd"

## Pairing every wired event_flag_* with its REGISTRY id. If any flag
## is added to REGISTRY, the entry here must grow OR
## test_every_event_chat_id_in_pairing_table fails. Forces ongoing
## maintenance.
const FLAG_TO_CHAT: Dictionary = {
	"event_flag_first_magic_shop_visited": "event_chat_first_magic_shop",
	"event_flag_first_party_wipe":          "event_chat_first_party_wipe",
	"event_flag_level_10_reached":          "event_chat_level_10",
	"event_flag_rare_drop_found":           "event_chat_rare_drop",
	"event_flag_dragon_cave_entered":       "event_chat_dragon_cave",
	"event_flag_first_autobattle_enabled":  "event_chat_first_autobattle",
	"event_flag_first_group_attack":        "event_chat_first_group_attack",
	"event_flag_one_hp_victory":            "event_chat_one_hp_victory",
	"event_flag_tent_blocked":              "event_chat_tent_rules",
	"event_flag_share_code_used":           "event_chat_share_code",
	"event_flag_fool_marks_three":          "event_chat_fool_marks_three",
}


func _make_system_with_empty_state() -> Object:
	# Fresh PartyChatSystem instance plus an isolated game_constants
	# holder. Avoids touching the real GameState autoload so test
	# ordering doesn't pollute state across files.
	var holder_script := GDScript.new()
	holder_script.source_code = "extends Node\nvar game_constants: Dictionary = {}\n"
	holder_script.reload()
	var holder: Node = holder_script.new()
	add_child_autofree(holder)
	var script: GDScript = load(PARTY_CHAT)
	var sys: Object = script.new()
	sys.game_state_override = holder
	return sys


# ── 1. Baseline: no flags set ⇒ no event chat available ──────────

func test_baseline_no_event_chats_available() -> void:
	var sys: Object = _make_system_with_empty_state()
	for chat_id in FLAG_TO_CHAT.values():
		assert_false(sys.is_available(chat_id),
			"no flags set — %s must NOT be available (got available=true; check baseline state isolation)" % chat_id)


# ── 2. Each flag unlocks exactly its paired chat ─────────────────

func test_each_event_flag_unlocks_its_paired_chat() -> void:
	for flag in FLAG_TO_CHAT:
		var expected_chat: String = FLAG_TO_CHAT[flag]
		var sys: Object = _make_system_with_empty_state()
		# Fire only this flag.
		sys.game_state_override.game_constants[flag] = true
		assert_true(sys.is_available(expected_chat),
			"firing %s must unlock %s — wiring↔registry pair drifted" % [flag, expected_chat])


# ── 3. Firing a flag doesn't leak unlock to OTHER chats ──────────

func test_event_flag_does_not_cross_unlock_other_chats() -> void:
	for flag in FLAG_TO_CHAT:
		var expected_chat: String = FLAG_TO_CHAT[flag]
		var sys: Object = _make_system_with_empty_state()
		sys.game_state_override.game_constants[flag] = true
		var stray: Array[String] = []
		for chat_id in FLAG_TO_CHAT.values():
			if chat_id == expected_chat:
				continue
			if sys.is_available(chat_id):
				stray.append(chat_id)
		assert_eq(stray.size(), 0,
			"firing %s leaked unlock to other chats: %s — REGISTRY unlock entries are too loose" % [flag, str(stray)])


# ── 4. Once viewed, available falls to false ─────────────────────

func test_mark_viewed_removes_chat_from_available() -> void:
	for flag in FLAG_TO_CHAT:
		var chat_id: String = FLAG_TO_CHAT[flag]
		var sys: Object = _make_system_with_empty_state()
		sys.game_state_override.game_constants[flag] = true
		assert_true(sys.is_available(chat_id), "precondition: chat unlocked")
		sys.mark_viewed(chat_id)
		assert_false(sys.is_available(chat_id),
			"after mark_viewed(%s), is_available must be false (viewed-flag write didn't land)" % chat_id)


# ── 5. has_available_chats / available_count reflect the unlock ──

func test_has_available_chats_flips_after_event_flag_set() -> void:
	for flag in FLAG_TO_CHAT:
		var sys: Object = _make_system_with_empty_state()
		assert_false(sys.has_available_chats(),
			"baseline: no chats available (flag=%s setup)" % flag)
		sys.game_state_override.game_constants[flag] = true
		assert_true(sys.has_available_chats(),
			"firing %s must flip has_available_chats to true" % flag)


# ── 6. Pairing table covers every event_chat_* in REGISTRY ───────

func test_every_event_chat_id_in_pairing_table() -> void:
	# If a new event_chat_* lands in REGISTRY without a FLAG_TO_CHAT
	# entry here, it's not e2e-tested — this test fails until the
	# coverage table is updated.
	var script: GDScript = load(PARTY_CHAT)
	var sys: Object = script.new()
	var registry: Dictionary = sys.REGISTRY
	var missing: Array[String] = []
	for id in registry.keys():
		if not str(id).begins_with("event_chat_"):
			continue
		if not (id in FLAG_TO_CHAT.values()):
			missing.append(str(id))
	assert_eq(missing.size(), 0,
		"FLAG_TO_CHAT missing entries for event_chat_* ids: %s (add to coverage table)" % str(missing))
