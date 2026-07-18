extends GutTest

## Cycle 17 (cowir-sfx msg 2796) — weapon-proc status sound.
##
## Cross-check found: BS._on_action_executed at line ~3712 wraps its
## SoundManager.play_status(effect) call in `if action_type ==
## "ability":`. That gate captures spell-caused status only. Weapon
## procs (poison_dagger, sleep_dagger — driven by
## BattleManager._apply_equipment_on_hit_status against
## equipment.json special_effects.<status>_chance) fire on the
## BASIC-attack path. That path never enters _on_action_executed's
## ability branch, so the proc lands with an add_status + battle-
## log line, but NO sound.
##
## Same silent-failure class the project's CLAUDE.md flags as worst-
## case. This cycle fires SoundManager.play_status(status_name)
## right where the proc lands, matching the shape cowir-sfx
## expected on their cross-check (msg 2796).
##
## Not this cycle: cowir-sfx's cycle-9b methods
## (play_weakness_flash, play_strike_element) aren't on main yet
## (branch feature/sfx-weapon-strike-identity @ 0621d5a4 fold-
## pinged msg 2795). The weakness-flash + strike-element layering
## into cycle-16's visuals path lands after that folds.

const BM_PATH: String = "res://src/battle/BattleManager.gd"


## ── (1) The fix landed in _apply_equipment_on_hit_status ──────────────

func test_weapon_proc_fires_play_status() -> void:
	# The whole point. Without this line, poison_dagger's status
	# applies silently, breaking parity with ability-caused statuses
	# that DO fire the sound at BS:3729.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _apply_equipment_on_hit_status(attacker: Combatant")
	assert_gt(idx, -1, "the on-hit status applier must exist")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1500)
	assert_string_contains(body, "SoundManager.play_status(entry[\"status\"])",
		"weapon-proc status must fire SoundManager.play_status — parity with the ability-caused status sound at BS:3729")


func test_weapon_proc_sound_is_null_guarded() -> void:
	# SoundManager IS an autoload — safe under real-run conditions.
	# But headless test doubles and GameLoop-less contexts may lack
	# the autoload; a bare call would crash. Guard for the same
	# safety as every other SoundManager consumer in BM.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _apply_equipment_on_hit_status(attacker: Combatant")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1500)
	assert_string_contains(body, "if SoundManager:",
		"SoundManager call must be null-guarded — headless test contexts drop the autoload")


## ── (2) The sound-emit lands AFTER the status apply + log line ───────

func test_sound_fires_after_add_status_and_log_emit() -> void:
	# Ordering: add_status runs first (the mechanic is authoritative),
	# then the battle-log line (player-facing narrative), then the
	# sound (audio cue). A refactor that hoists the sound above
	# add_status would fire on procs that get resisted-out mid-body
	# by a future gate. Belt-and-suspenders correctness.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _apply_equipment_on_hit_status(attacker: Combatant")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1500)
	var add_idx: int = body.find("target.add_status(entry[\"status\"]")
	var log_idx: int = body.find("battle_log_message.emit(")
	var sfx_idx: int = body.find("SoundManager.play_status(")
	assert_gt(add_idx, -1)
	assert_gt(log_idx, add_idx, "log emit follows add_status")
	assert_gt(sfx_idx, log_idx, "sound emit follows log — audio caps the sequence")


## ── (3) The dispatch mirrors the ability-side call at BS:3729 ─────────

func test_matching_sound_call_shape_at_bs() -> void:
	# Sanity: the ability-side path uses SoundManager.play_status
	# too (see BS:3729). Pin the shape so a future SoundManager API
	# change (rename, arg reorder) breaks BOTH paths symmetrically
	# rather than one silently.
	var bs: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_string_contains(bs, "SoundManager.play_status(effect)",
		"the ability-side call at BS:_on_action_executed must keep the same play_status shape — proc-side and ability-side must stay symmetric")


## ── (4) Every ON_HIT_STATUSES entry has a status_<name> manifest key ──

func test_on_hit_status_entries_have_named_status_sounds() -> void:
	# Weakness-check: today's ON_HIT_STATUSES is [poison, sleep]. If
	# a future confuse_chance / burn_chance / freeze_chance lands
	# (per BM:3999-4001's stated extensibility), SoundManager.play_
	# status(<name>) needs a matching manifest entry, else the sound
	# call falls through to whatever play_status does on unknown key
	# (usually silence).
	#
	# We can't easily read the sfx_manifest here (no import). The
	# soft pin: today's ON_HIT_STATUSES entries have known-good
	# manifest keys (poison, sleep). Failing this test means a new
	# on-hit status was added and the pin should be widened AND
	# cowir-sfx should be pinged to add the matching status_<name>
	# manifest key.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var start: int = src.find("const ON_HIT_STATUSES: Array = [")
	assert_gt(start, -1)
	var end: int = src.find("]", start)
	var block: String = src.substr(start, end - start)
	var known_covered: Array = ["poison", "sleep"]
	var cursor: int = 0
	while true:
		var s_idx: int = block.find("\"status\":", cursor)
		if s_idx < 0:
			break
		var quote_start: int = block.find("\"", s_idx + 10)
		var quote_end: int = block.find("\"", quote_start + 1)
		var status_name: String = block.substr(quote_start + 1, quote_end - quote_start - 1)
		assert_true(status_name in known_covered,
			"new ON_HIT_STATUSES entry '%s' — ping cowir-sfx to add status_%s manifest key + widen this pin" % [status_name, status_name])
		cursor = quote_end + 1
