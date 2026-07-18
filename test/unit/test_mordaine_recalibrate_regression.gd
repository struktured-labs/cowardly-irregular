extends GutTest

## Cycle 18 (msg 2805) — Mordaine harder.
##
## Struktured verdict (live playtest): "Mordaine too easy." Design
## intent: meta-aware mechanics fit her identity (sorceress-usurper +
## first mask of the Calibrant) better than stat bloat. Shipped ONE
## nailed mechanic — Calibrant Recalibration — plus a conservative
## stat bump flagged to struktured.
##
## Recalibration mechanic:
##   Trigger: first time Mordaine crosses 50% HP in a battle.
##   Effect: authored via monsters.json calibrant_recalibrate_swap dict
##     - weakness_out: element to move from weaknesses → resistances
##     - weakness_in: element to move from resistances → weaknesses
##     - boss_line: dialogue emitted on trigger
##   Latch: `_calibrant_recalibrated` meta on the enemy prevents
##   re-fire in the same battle (freshly-recovered scene meta wipe
##   at battle start).
##
## Why data-driven: any future boss with "meta-aware" identity can
## get the same mechanic with a data entry — the seam is general
## rather than Mordaine-hardcoded.


## ── (1) Data shape ────────────────────────────────────────────────────

func test_mordaine_has_recalibrate_swap_authored() -> void:
	var f: FileAccess = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f)
	var ms: Dictionary = JSON.parse_string(f.get_as_text())
	assert_true(ms.has("chancellor_mordaine"))
	var m: Dictionary = ms["chancellor_mordaine"]
	assert_true(m.has("calibrant_recalibrate_swap"),
		"Mordaine must author calibrant_recalibrate_swap to enable the phase-2 mechanic")
	var swap: Dictionary = m["calibrant_recalibrate_swap"]
	assert_eq(str(swap.get("weakness_out", "")), "holy",
		"canonical Mordaine recalibrate: holy → resisted (matches struktured's set-up hint 'Holy magic ... canonical answer')")
	assert_eq(str(swap.get("weakness_in", "")), "fire",
		"canonical Mordaine recalibrate: fire → exposed. Player forced to pivot away from holy.")
	assert_true(swap.has("boss_line"),
		"boss_line must be authored — the mechanic reads as CALIBRANT identity through the dialogue")


func test_mordaine_stat_bump_pinned() -> void:
	# Conservative stat bump per struktured "raise her numbers
	# conservatively and flag the deltas for his tuning pass".
	# Pin the current values so a future silent stat retreat back
	# to 1500/72 (making her too easy again) fails the ratchet.
	# If struktured re-tunes upward or downward, edit this pin.
	var f: FileAccess = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f)
	var ms: Dictionary = JSON.parse_string(f.get_as_text())
	var m: Dictionary = ms["chancellor_mordaine"]
	var stats: Dictionary = m["stats"]
	assert_eq(int(stats.get("max_hp", 0)), 1650,
		"max_hp bumped 1500 → 1650 (+10%). If struktured re-tunes, update this pin.")
	assert_eq(int(stats.get("magic", 0)), 78,
		"magic bumped 72 → 78 (+8%). If struktured re-tunes, update this pin.")


## ── (2) Precondition: initial weaknesses + resistances allow the swap ─

func test_initial_weakness_matches_swap_out() -> void:
	# The swap only works if weakness_out is initially IN weaknesses.
	# If a future data edit removes holy from Mordaine's weaknesses
	# without updating calibrant_recalibrate_swap.weakness_out, the
	# swap silently no-ops. Guard against that.
	var f: FileAccess = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f)
	var ms: Dictionary = JSON.parse_string(f.get_as_text())
	var m: Dictionary = ms["chancellor_mordaine"]
	var swap: Dictionary = m["calibrant_recalibrate_swap"]
	assert_true(swap.get("weakness_out", "") in m.get("weaknesses", []),
		"calibrant_recalibrate_swap.weakness_out must be in initial weaknesses — otherwise the swap silently no-ops the outbound half")
	assert_true(swap.get("weakness_in", "") in m.get("resistances", []),
		"calibrant_recalibrate_swap.weakness_in must be in initial resistances — otherwise the pivot doesn't remove a resist (weakness gain still works but the reveal-a-hidden-vulnerability read is wrong)")


## ── (3) Engine: hook body exists + fires at the right threshold ───────

func test_recalibrate_helper_exists() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "func _maybe_trigger_mordaine_recalibrate() -> void:",
		"the phase-2 recalibrate helper must exist in BM")


func test_recalibrate_reads_data_field() -> void:
	# Data-driven: helper must key off calibrant_recalibrate_swap in
	# monster_data, NOT hardcode "chancellor_mordaine" and the specific
	# element names. Future bosses can inherit the mechanic by
	# authoring the same data field.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _maybe_trigger_mordaine_recalibrate")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "calibrant_recalibrate_swap",
		"helper must read the data field — no monster-name hardcode")
	assert_false(body.find("\"chancellor_mordaine\"") > -1,
		"no monster-id hardcode — mechanic is general via monsters.json")
	assert_false(body.find("== \"holy\"") > -1,
		"no element hardcode — the data supplies the pivot direction")


func test_recalibrate_hp_threshold_is_50pct() -> void:
	# Threshold: strictly cross 50% — enemy.current_hp * 2 <= enemy
	# .max_hp. Struktured's brief said "phase 2 at 50% HP".
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _maybe_trigger_mordaine_recalibrate")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "enemy.current_hp * 2 > enemy.max_hp",
		"HP gate must express 50% threshold via integer math (current_hp * 2 vs max_hp) — avoids float rounding surprises")


func test_recalibrate_latches_to_prevent_re_fire() -> void:
	# One-shot per battle. Meta latch so a spike of small hits across
	# the 50% threshold doesn't oscillate the weaknesses back and
	# forth.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _maybe_trigger_mordaine_recalibrate")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "has_meta(\"_calibrant_recalibrated\")",
		"latch must exist — otherwise oscillation would re-swap the weaknesses on every action after 50%")
	assert_string_contains(body, "set_meta(\"_calibrant_recalibrated\", true)",
		"latch set on the same key it checks")


## ── (4) Hook fires from action-execute dispatch ───────────────────────

func test_recalibrate_called_from_execute_next_action() -> void:
	# The hook site: _execute_next_action, right before action_
	# executed.emit. Runs once per action — cheap enough to poll
	# every enemy for the trigger without a signal-based observer.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Search for the call site in the action-executed emit region.
	# There are 3 action_executed.emit sites in BM; the primary
	# _execute_next_action path is the one we hook.
	var call_idx: int = src.find("_maybe_trigger_mordaine_recalibrate()")
	assert_gt(call_idx, -1, "call site must exist somewhere in BM")
	# Ratchet: call should sit right before an action_executed emit
	# so a fresh 50% cross gets caught on the very next action.
	var next_emit: int = src.find("action_executed.emit", call_idx)
	assert_gt(next_emit, -1, "call must precede an action_executed emit — timing pin")


## ── (5) Log emit shape names the mechanic + the counterplay ───────────

func test_recalibrate_emits_telegraph_log_line() -> void:
	# The mechanic is meaningless if the player doesn't SEE the
	# swap. Log line names the mechanic + BOTH elements changed +
	# what the player should do next.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _maybe_trigger_mordaine_recalibrate")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "RECALIBRATES the field",
		"log line must name the mechanic — the meta-aware identity is the whole point")
	assert_string_contains(body, "is now RESISTED",
		"log line must call out the element being lost as a weakness")
	assert_string_contains(body, "is the exposed thread",
		"log line must call out the element being gained as a weakness")
	assert_string_contains(body, "Adapt",
		"log line must name the counterplay verb — struktured's design brief was ADAPTATION under pressure")
