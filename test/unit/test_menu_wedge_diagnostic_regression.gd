extends GutTest

## Cowir-main msg 2400: the "menu never spawned" bug also fires in normal
## battles (not just spotlight duels). Root cause is unknown until we can
## observe a live trip.
##
## This pins the diagnostic surface so a future refactor can't gut it and
## leave us blind for the next repro round:
## - BattleCommandMenu.last_silent_return_reason tracks WHICH gate bailed
## - _menu_wd_diag helper in BattleScene reads that reason + related state
## - Watchdog trip logs (both push_warning and push_error) include the diag

const BCM_PATH: String = "res://src/battle/BattleCommandMenu.gd"
const BS_PATH: String = "res://src/battle/BattleScene.gd"


func test_bcm_exposes_last_silent_return_reason_field() -> void:
	# Field name is load-bearing: the watchdog reads it by that exact name.
	# Textual pin so a rename can't silently disconnect the wiring.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	assert_string_contains(src, "var last_silent_return_reason: String",
		"BCM must expose a String field named last_silent_return_reason for the watchdog to read")


func test_every_silent_return_gate_sets_the_reason() -> void:
	# Each early-out branch must stamp the reason before returning, else the
	# watchdog trip log reports 'unknown' and diagnostics are useless.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	assert_string_contains(src, 'last_silent_return_reason = "spotlight_locked"',
		"spotlight gate must stamp reason")
	assert_string_contains(src, 'last_silent_return_reason = "combatant_idx_out_of_range',
		"party-idx gate must stamp reason")
	assert_string_contains(src, 'last_silent_return_reason = "sprite_invalid',
		"sprite-invalid gate must stamp reason")
	assert_string_contains(src, 'last_silent_return_reason = ""',
		"the success path must CLEAR the reason so the watchdog can tell built-then-closed from silent-return")


func test_reason_stamped_before_return_on_spotlight_branch() -> void:
	# Ordering matters: if `return` runs before the reason is stamped, the
	# watchdog reads whatever was left from the previous call. Textual pin
	# that the stamp precedes the return within the spotlight block.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	var stamp_idx: int = src.find('last_silent_return_reason = "spotlight_locked"')
	assert_gt(stamp_idx, -1)
	var window: String = src.substr(stamp_idx, 400)
	var return_idx: int = window.find("\n\t\t\treturn")
	assert_gt(return_idx, -1, "return must exist after the stamp")


## ── Watchdog diagnostic ────────────────────────────────────────────────

func test_watchdog_has_diag_helper() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _menu_wd_diag(pc: Combatant) -> String:",
		"watchdog diagnostic helper must exist so trip logs can include reason + state")


func test_diag_reads_bcm_reason_and_relevant_state() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _menu_wd_diag(pc: Combatant) -> String:")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 1200)
	# Must consult the BCM reason field — that's the whole point.
	assert_string_contains(body, "last_silent_return_reason",
		"diag must pull the reason from BCM")
	# Success-then-closed is a distinct failure mode from silent-return —
	# the empty-reason case must be labeled distinctly.
	assert_string_contains(body, "spawn_ok_then_closed",
		"empty reason must be labeled — an empty string in a log is useless")
	# State dump: the four fields that would pinpoint every known silent-return path.
	assert_string_contains(body, "ab_locked", "spotlight-lock state matters — dump it")
	assert_string_contains(body, "ab_enabled", "per-char autobattle_enabled state matters")
	assert_string_contains(body, "in_party", "party-membership state matters")
	assert_string_contains(body, "sprite_ct", "sprite-node population state matters")


func test_watchdog_trip_logs_include_diag() -> void:
	# Both trip paths (force-spawn retry AND terminal fallback) must include
	# the diag string. If a refactor drops it from one, half the trips log
	# blindly again.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var wd_idx: int = src.find("func _tick_menu_watchdog() -> void:")
	var body: String = src.substr(wd_idx, 3500)
	# Force-spawn retry log includes diag.
	var force_idx: int = body.find("PLAYER_SELECTING sat")
	assert_gt(force_idx, -1)
	var force_line: String = body.substr(force_idx, 400)
	assert_string_contains(force_line, "_menu_wd_diag(pc)",
		"force-spawn retry log must include diag")
	# Terminal fallback log includes diag.
	var term_idx: int = body.find("force-spawn failed")
	assert_gt(term_idx, -1)
	var term_line: String = body.substr(term_idx, 400)
	assert_string_contains(term_line, "_menu_wd_diag(pc)",
		"terminal fallback log must include diag")
