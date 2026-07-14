extends GutTest

## tick 42: wires RebalanceDaemon (tick 41's scaffold) to the actual
## event sites. Without this tick, the daemon exists but nothing ever
## calls consider() — so it never collects proposals.
##
## Three pieces:
##   1. GameLoop calls consider() after party_wipe + boss_defeat
##      records — opt-in via llm_rebalance_enabled flag
##   2. SettingsMenu has the user-facing toggle row
##   3. SaveSystem persists the flag in settings.json (per-machine)

const GAME_LOOP := "res://src/GameLoop.gd"
const SETTINGS_MENU := "res://src/ui/SettingsMenu.gd"
const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(file_path: String, func_name: String) -> String:
	var src := _read(file_path)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist in " + file_path)
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_game_loop_preloads_daemon_script() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("RebalanceDaemonScript = preload"),
		"GameLoop must preload RebalanceDaemon so the trigger constants are addressable without class_name lookups")


func test_party_wipe_triggers_daemon_when_enabled() -> void:
	# Wipe is the strongest 'this is too hard' signal. Wiring must
	# guard on the opt-in flag AND check the daemon instance exists.
	var src := _read(GAME_LOOP)
	# Find the wipe record block; the consider() call must be RIGHT
	# AFTER it.
	var idx := src.find("EventLog.TYPE_PARTY_WIPE")
	assert_gt(idx, -1, "wipe record site must exist")
	var window := src.substr(idx, 800)
	assert_true(window.contains("GameState.llm_rebalance_enabled"),
		"wipe trigger must guard on llm_rebalance_enabled — vanilla play stays unchanged")
	assert_true(window.contains("rebalance_daemon.consider"),
		"wipe site must call rebalance_daemon.consider")
	assert_true(window.contains("TRIGGER_PARTY_WIPE"),
		"wipe site must use the TRIGGER_PARTY_WIPE constant — magic strings rot")


func test_boss_defeat_triggers_daemon_when_enabled() -> void:
	# Boss wins are the 'curve looks right' signal (or 'too easy' if
	# the player one-shot it). Same guard pattern as wipe.
	var src := _read(GAME_LOOP)
	var idx := src.find("EventLog.TYPE_BOSS_DEFEAT")
	assert_gt(idx, -1, "boss defeat record site must exist")
	var window := src.substr(idx, 800)
	assert_true(window.contains("GameState.llm_rebalance_enabled"),
		"boss-defeat trigger must guard on llm_rebalance_enabled")
	assert_true(window.contains("rebalance_daemon.consider"),
		"boss-defeat site must call rebalance_daemon.consider")
	assert_true(window.contains("TRIGGER_BOSS_DEFEAT"),
		"boss-defeat site must use the TRIGGER_BOSS_DEFEAT constant")


func test_settings_menu_has_rebalance_toggle() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("var llm_rebalance_enabled"),
		"SettingsMenu must hold a local copy of the rebalance toggle state")
	assert_true(src.contains("LLM Auto-Rebalance"),
		"SettingsMenu must surface the rebalance toggle title to the user")
	# Dispatcher branch wires the toggle to the save handler.
	assert_true(src.contains("item[\"id\"] == \"llm_rebalance_enabled\""),
		"toggle dispatcher must handle llm_rebalance_enabled")
	# Save handler exists and mirrors to GameState.
	var body := _body_of(SETTINGS_MENU, "_save_llm_rebalance_setting")
	assert_true(body.contains("GameState.llm_rebalance_enabled = llm_rebalance_enabled"),
		"save handler must mirror local state to GameState")
	assert_true(body.contains("_persist_settings"),
		"save handler must persist (settings.json survives restart)")


func test_settings_menu_loads_rebalance_flag_on_ready() -> void:
	# Toggle row must reflect the persisted state, not always default
	# to false.
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("llm_rebalance_enabled = GameState.llm_rebalance_enabled"),
		"SettingsMenu must mirror GameState.llm_rebalance_enabled into the local var on load — otherwise the toggle visually resets to false every time the menu opens")


func test_save_system_persists_rebalance_flag() -> void:
	var src := _read(SAVE_SYSTEM)
	# Write side: settings["llm_rebalance_enabled"] = GameState.llm_rebalance_enabled
	assert_true(src.contains("settings[\"llm_rebalance_enabled\"]"),
		"SaveSystem.save_settings must write llm_rebalance_enabled to settings.json")
	# Read side: load_settings restores it.
	assert_true(src.contains("settings.has(\"llm_rebalance_enabled\")"),
		"SaveSystem.load_settings must restore llm_rebalance_enabled from settings.json")
