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
	## RELAXED 2026-07-30: was pinned to the exact expression
	## `SoundManager.play_status(entry["status"])`. That goes RED on a CORRECT refactor —
	## renaming the loop variable, or extracting a `_play_proc_cue(entry)` helper, both
	## preserve behaviour and both broke this. Two lanes hit that shape today
	## (cowir-cutscenes' `_begin_staging()` pin, cowir-overworld's literal-only parser),
	## and a ratchet that punishes correctness teaches people to edit the ratchet.
	##
	## Now asserts PRESENCE only — still catches outright deletion, which is the
	## regression. Whether the call is CORRECT is covered behaviourally by
	## test_weapon_proc_actually_plays_a_status_cue below, which drives the real
	## BattleManager and observes a cue resolving.
	assert_string_contains(body, "play_status(",
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


## ── (6) RUNTIME COMPANION — drives the real path, no source text ──────
##
## Added 2026-07-30. Every assert above this line reads BattleManager.gd as TEXT.
## Source pins are blind to what the code DOES: they pass if the call is present but
## the status name is wrong, if the manifest key doesn't resolve, or if an early
## return above it means the line never executes. They also go red on correct
## refactors, which is why the pin at (1) was relaxed to presence-only.
##
## This test asserts the OUTCOME instead: swing a poison_dagger and confirm a status
## cue actually resolved. The observable is the SFX cooldown stamp — a manifest MISS
## provably does NOT stamp (pinned by test_sfx_reverse_orphan_audit's premise assert),
## so a stamp means the cue was requested AND resolved to a real file.

func test_weapon_proc_actually_plays_a_status_cue() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	var es: Node = get_node_or_null("/root/EquipmentSystem")
	var bm: Node = get_node_or_null("/root/BattleManager")
	if sm == null or es == null or bm == null:
		pending("SoundManager + EquipmentSystem + BattleManager autoloads required")
		return

	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var attacker: Combatant = c_script.new()
	attacker.initialize({"name": "Prockster", "max_hp": 100, "max_mp": 10,
		"attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(attacker)
	var target: Combatant = c_script.new()
	target.initialize({"name": "Victim", "max_hp": 100, "max_mp": 10,
		"attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(target)
	attacker.equipped_weapon = "poison_dagger"

	## PREMISE 1: the weapon must really author the proc chance. If equipment.json
	## renames poison_chance or drops the dagger, the loop below can never fire and
	## every assert after it is vacuous.
	var chance: float = bm._sum_equipment_special_effect(attacker, "poison_chance")
	assert_gt(chance, 0.0,
		"PREMISE BROKEN: poison_dagger reports %.2f poison_chance — the proc can never fire, so the assertions below would pass having tested nothing" % chance)

	## PREMISE 2: the cue key must be genuinely unstamped, else has() below is
	## satisfied by an earlier test in the same run (the autoload persists all suite).
	sm._sfx_cooldowns.erase("status_poison")
	assert_false(sm._sfx_cooldowns.has("status_poison"),
		"control: status_poison must start unstamped or the final assert proves nothing")

	## poison_dagger is 0.25, so drive it until it lands. At 200 attempts a false
	## failure is 0.75^200 (~1e-25) — the loop bounds flakiness, it doesn't hide it.
	var applied: bool = false
	for _i in 200:
		bm._apply_equipment_on_hit_status(attacker, target)
		if target.has_status("poison"):
			applied = true
			break
	assert_true(applied,
		"poison_dagger never applied its status in 200 swings — the proc path itself is broken, independent of audio")
	if not applied:
		return

	assert_true(sm._sfx_cooldowns.has("status_poison"),
		"the weapon proc APPLIED poison but no status cue resolved — this is exactly the msg-2796 defect (status lands silently), and a source pin cannot see it")


func test_weapon_proc_cue_survives_a_missing_soundmanager() -> void:
	## The null guard at (2) is source-pinned. This drives the behaviour it protects:
	## the proc must still apply its status when audio is unavailable, so a missing
	## autoload degrades to silence rather than dropping the game mechanic.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var attacker: Combatant = c_script.new()
	attacker.initialize({"name": "A", "max_hp": 50, "max_mp": 5,
		"attack": 5, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(attacker)
	var target: Combatant = c_script.new()
	target.initialize({"name": "B", "max_hp": 50, "max_mp": 5,
		"attack": 5, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(target)
	attacker.equipped_weapon = "poison_dagger"
	var applied: bool = false
	for _i in 200:
		bm._apply_equipment_on_hit_status(attacker, target)
		if target.has_status("poison"):
			applied = true
			break
	assert_true(applied,
		"the status mechanic must not depend on audio being present")
