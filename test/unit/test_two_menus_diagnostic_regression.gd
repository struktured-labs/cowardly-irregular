extends GutTest

## msg 2503: "the win98 menu system sometimes shows 2 menus at the same time
## still" — different shape from the earlier retry-loop double-fire. Live
## log evidence: reason=spawn_ok_then_closed (menu spawned past the
## silent-return gates, then closed WITHOUT submitting; state stayed in
## PLAYER_SELECTING). Watchdog respawn → old menu still visible during its
## queue_free delay → two menus.
##
## Root cause was not identified from static analysis. This pins a
## diagnostic surface — distinct [MENU-SPAWN] / [MENU-NULL] / [MENU-HIDE]
## tags at every relevant mutation site plus a menu= field in the watchdog
## trip log that distinguishes menu-freed (invalid) from menu-hidden
## (valid-but-invisible). The next repro cap timeline names the closer.

const BCM_PATH: String = "res://src/battle/BattleCommandMenu.gd"
const BS_PATH: String = "res://src/battle/BattleScene.gd"


## ── Spawn success emits a timestamped MENU-SPAWN line ──────────────────

func test_spawn_success_prints_menu_spawn_tag() -> void:
	# The spawn timestamp is the reference point every downstream tag
	# correlates against. Dropping this makes the timeline unreadable.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	assert_string_contains(src, "print(\"[MENU-SPAWN] t=%dms",
		"successful spawn must print a timestamped [MENU-SPAWN] tag for repro-cap correlation")


## ── Every active_win98_menu = null site is tagged with a distinct path ──

func test_null_sites_in_bcm_all_tagged_with_distinct_paths() -> void:
	# 5 null-writes in BCM (msg 2503 audit). Each must emit a [MENU-NULL] tag
	# with a distinct path=... value so a repro cap tells us WHICH handler
	# fired. Without this the timeline shows null happened but not where.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	assert_string_contains(src, "path=menu_closed_signal",
		"_on_win98_menu_closed handler must tag its null site")
	assert_string_contains(src, "path=actions_submitted",
		"_on_win98_actions_submitted handler must tag its null site")
	assert_string_contains(src, "path=defer_requested",
		"_on_win98_defer_requested handler must tag its null site")
	assert_string_contains(src, "path=go_back_requested",
		"_on_win98_go_back_requested handler must tag its null site")
	assert_string_contains(src, "path=close_win98_menu",
		"close_win98_menu (called during show_win98_command_menu's pre-rebuild step, and by external callers) must tag its null site")


func test_null_sites_in_battle_scene_tagged() -> void:
	# 2 null-writes in BattleScene (battle-end cleanup + restart cleanup).
	# Both must be tagged so they don't get mistaken for a mid-turn close.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "path=battle_ended_cleanup",
		"battle-end cleanup path must be distinct")
	assert_string_contains(src, "path=restart_battle_cleanup",
		"restart cleanup path must be distinct — retries can fire this multiple times per session")


## ── set_command_menu_visible prints a MENU-HIDE tag ────────────────────

func test_set_command_menu_visible_tagged() -> void:
	# Hidden-but-valid menu is the OTHER class of "2 menus" repro (autobattle
	# editor open, menu.visible=false, watchdog respawn creates a duplicate).
	# The [MENU-HIDE] tag captures the visibility toggle event.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "print(\"[MENU-HIDE] t=%dms visible=%s",
		"set_command_menu_visible must emit a [MENU-HIDE] tag with the target visibility for timeline reads")


## ── Watchdog diag: menu= field distinguishes freed vs hidden ───────────

func test_menu_wd_diag_dumps_menu_status_field() -> void:
	# Currently the watchdog reports reason=spawn_ok_then_closed for both
	# "menu was freed" and "menu is hidden" — same downstream. The menu=
	# field distinguishes the two. Freed = a null-path handler fired. Hidden
	# = something called set_command_menu_visible(false) and didn't restore.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _menu_wd_diag(pc: Combatant) -> String:")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 1800)
	assert_string_contains(body, "menu=%s",
		"diag output must include the menu= field")
	assert_string_contains(body, "menu_status = \"invalid\"",
		"invalid ref → \"invalid\" — the null-write path fired")
	assert_string_contains(body, "menu_status = \"valid_but_invisible\"",
		"valid ref but not visible → someone hid it without freeing")


func test_diag_menu_status_check_reads_active_win98_menu() -> void:
	# The predicate must consult BattleScene's active_win98_menu ref
	# (the same ref the watchdog uses to decide whether to fire), not
	# a stale copy or a different node.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _menu_wd_diag(pc: Combatant) -> String:")
	var body: String = src.substr(idx, 1800)
	assert_string_contains(body, "is_instance_valid(active_win98_menu)",
		"menu= status must be sourced from the same active_win98_menu the watchdog gates on")
	assert_string_contains(body, "active_win98_menu.visible",
		"the valid-but-invisible branch must actually consult .visible")
