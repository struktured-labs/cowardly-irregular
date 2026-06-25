extends GutTest

## tick 171 regression: ItemSystem.use_item branches must emit
## battle_log_message. Pre-fix NO item-use path emitted to the
## battle log — every effect used print() only (debug console,
## invisible to the player).
##
## Worst silent cases:
##   - antidote curing poison: NO popup (cure_status emits
##     nothing), NO log line. Only the status icon disappearing
##     gave any signal, easy to miss when multiple effects fire
##     simultaneously.
##   - power_drink/speed_tonic etc.: stat buff applied silently.
##     The buff icon appears on the portrait but no log line
##     telling the player which stat boosted by how much.
##
## Heal items DID emit healing_done (so green popup fired) but
## STILL had no log line — players relying on the log to track
## what just happened were missing item events entirely.

const ITEM_SYSTEM := "res://src/items/ItemSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Heal branches ──────────────────────────────────────────────────────

func test_heal_hp_emits_log() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("%s[/color] recovers [color=lime]%d[/color] HP!"),
		"heal_hp branch must emit a battle_log_message — pre-fix only healing_done + print")


func test_heal_hp_percent_emits_log_with_pct() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("recovers [color=lime]%d[/color] HP! (%d%%)"),
		"heal_hp_percent must surface the percentage in the log")


func test_heal_mp_emits_log() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("recovers [color=cyan]%d MP[/color]!"),
		"heal_mp must emit a log line with cyan MP color")


func test_heal_mp_percent_emits_log_with_pct() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("[color=cyan]%d MP[/color]! (%d%%)"),
		"heal_mp_percent must surface the percentage in the log")


# ── Revive branches ────────────────────────────────────────────────────

func test_revive_with_remaining_heal_emits_log() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("was revived with [color=lime]%d[/color] HP!"),
		"revive (with heal_hp also present) must emit the HP-specific log")


func test_revive_without_heal_emits_log() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("[color=lime]%s[/color] was revived!"),
		"revive (without heal_hp) must emit the simple-revive log")


# ── Cure branches ──────────────────────────────────────────────────────

func test_cure_status_emits_log() -> void:
	# Most invisible pre-fix: no popup at all + only print.
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("is cured of [color=cyan]%s[/color]!"),
		"cure_status must emit a log line — pre-fix this was the most invisible effect")


func test_cure_all_status_emits_log() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("is cured of [color=cyan]all status effects[/color]!"),
		"cure_all_status must emit a log line")


# ── Buff branch ────────────────────────────────────────────────────────

func test_add_buff_emits_log_with_magnitude() -> void:
	var src := _read(ITEM_SYSTEM)
	# Pin the full format including stat magnitude + duration.
	assert_true(src.contains("gains [color=cyan]%s[/color]! (%s +%d%% for %d turns)"),
		"add_buff must emit a log line surfacing effect name + stat + magnitude + duration")


# ── Damage branch ──────────────────────────────────────────────────────

func test_damage_item_emits_log() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("takes [color=yellow]%d[/color] %s damage!"),
		"damage items (bomb_fragment etc.) must emit a log line with element type")


# ── Cross-pins: existing emits preserved ───────────────────────────────

func test_existing_healing_done_emits_preserved() -> void:
	# Non-regression: don't accidentally drop the healing_done /
	# damage_dealt emits while adding battle_log_message.
	var src := _read(ITEM_SYSTEM)
	# Count healing_done emit sites — was 5 pre-fix (revive +
	# heal_hp + heal_hp_pct + heal_mp + heal_mp_pct).
	var count: int = 0
	var cursor: int = 0
	while true:
		var idx: int = src.find("BattleManager.healing_done.emit", cursor)
		if idx < 0:
			break
		count += 1
		cursor = idx + 1
	assert_gte(count, 5,
		"healing_done emits must remain in all 5 heal sites — drove the green popup pre-tick-171")


func test_existing_damage_dealt_emit_preserved() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("BattleManager.damage_dealt.emit(target, actual_damage, false, element, multiplier)"),
		"damage_dealt emit preserved — drives the damage popup for damage items")


# ── Defensive guards ───────────────────────────────────────────────────

func test_battle_log_emits_guarded_by_battlemanager_null_check() -> void:
	# Every new emit must be inside `if ... and BattleManager:` or
	# `if BattleManager:` because ItemSystem is used in test contexts
	# without BattleManager autoload (e.g. headless ItemSystem unit
	# tests). Sample-pin by checking the cure_status branch has the
	# guard.
	var src := _read(ITEM_SYSTEM)
	# Find the cure_status block and look for the guard pattern
	# preceding the emit.
	var cure_idx: int = src.find("if effects.has(\"cure_status\"):")
	assert_gt(cure_idx, -1, "cure_status branch must exist")
	# Walk forward ~600 chars looking for the BattleManager guard.
	var window: String = src.substr(cure_idx, 800)
	assert_true(window.contains("if BattleManager:"),
		"cure_status battle_log emit must be guarded by `if BattleManager:` — defensive for tests")
