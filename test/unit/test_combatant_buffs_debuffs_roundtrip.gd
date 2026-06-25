extends GutTest

## tick 152 regression: Combatant.to_dict and from_dict must
## roundtrip active_buffs and active_debuffs for Time Mage
## mid-battle rewind. Pre-fix only status_effects was serialized;
## buffs/debuffs were dropped silently. Less catastrophic than the
## tick-151 status_durations gap (buffs disappear on rewind vs DoT
## becoming permanent) but still wrong — a player using rewind
## after pumping their party with buffs would find the buffs gone.
##
## Same typed-array trap as tick 151 — assigning generic Array
## literal to Array[Dictionary] silently throws SCRIPT ERROR and
## leaves the field at default []. Tests build typed locals before
## assignment.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_to_dict_includes_active_buffs_and_debuffs() -> void:
	var src := _read(COMBATANT)
	# Pin: both fields serialized via deep duplicate (nested dicts
	# carry effect/stat/modifier/duration/remaining_turns).
	assert_true(src.contains("\"active_buffs\": active_buffs.duplicate(true)"),
		"to_dict must serialize active_buffs with deep duplicate")
	assert_true(src.contains("\"active_debuffs\": active_debuffs.duplicate(true)"),
		"to_dict must serialize active_debuffs with deep duplicate")


func test_from_dict_loads_buffs_with_int_coercion() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("if data.has(\"active_buffs\"):"),
		"from_dict must have an active_buffs branch")
	assert_true(src.contains("if data.has(\"active_debuffs\"):"),
		"from_dict must have an active_debuffs branch")
	# Both branches must coerce duration + remaining_turns to int.
	# JSON.parse returns numeric values as float; update_buff_durations
	# decrement-by-1 + > 0 check relies on int semantics.
	assert_true(src.contains("entry[\"duration\"] = int(entry[\"duration\"])"),
		"from_dict must coerce duration field to int (JSON gives float)")
	assert_true(src.contains("entry[\"remaining_turns\"] = int(entry[\"remaining_turns\"])"),
		"from_dict must coerce remaining_turns to int")
	# Typed Array[Dictionary] build matches the permanent_injuries
	# pattern from tick 105.
	assert_true(src.contains("var typed_buffs: Array[Dictionary] = []"),
		"from_dict must build a typed Array[Dictionary] for buffs")
	assert_true(src.contains("var typed_debuffs: Array[Dictionary] = []"),
		"from_dict must build a typed Array[Dictionary] for debuffs")


# ── Runtime roundtrip ────────────────────────────────────────────────────

func test_runtime_single_buff_roundtrips() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Buffed Fighter"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	var typed_buffs: Array[Dictionary] = [{
		"effect": "haste",
		"stat": "speed",
		"modifier": 1.5,
		"duration": 5,
		"remaining_turns": 3,
	}]
	c.active_buffs = typed_buffs

	var snapshot: Dictionary = c.to_dict()
	var json := JSON.new()
	var err: int = json.parse(JSON.stringify(snapshot))
	assert_eq(err, OK, "snapshot must JSON-roundtrip cleanly")

	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)

	assert_eq(c2.active_buffs.size(), 1,
		"single buff must survive roundtrip — pre-fix it was dropped")
	var loaded: Dictionary = c2.active_buffs[0]
	assert_eq(str(loaded["effect"]), "haste",
		"buff effect must survive")
	assert_eq(str(loaded["stat"]), "speed",
		"buff stat must survive")
	assert_almost_eq(float(loaded["modifier"]), 1.5, 0.001,
		"buff modifier (float) must survive")
	# Critical: duration counters must be int after roundtrip so
	# the > 0 check + decrement logic in update_buff_durations
	# behaves correctly.
	assert_eq(loaded["duration"], 5,
		"buff duration must roundtrip as int (5), not float (5.0)")
	assert_eq(loaded["remaining_turns"], 3,
		"buff remaining_turns must roundtrip as int (3)")


func test_runtime_single_debuff_roundtrips() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Debuffed Mage"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	var typed_debuffs: Array[Dictionary] = [{
		"effect": "slow",
		"stat": "speed",
		"modifier": 0.5,
		"duration": 4,
		"remaining_turns": 2,
	}]
	c.active_debuffs = typed_debuffs

	var json := JSON.new()
	json.parse(JSON.stringify(c.to_dict()))
	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)

	assert_eq(c2.active_debuffs.size(), 1,
		"debuff must survive roundtrip")
	var loaded: Dictionary = c2.active_debuffs[0]
	assert_eq(str(loaded["effect"]), "slow")
	assert_almost_eq(float(loaded["modifier"]), 0.5, 0.001)
	assert_eq(loaded["remaining_turns"], 2)


func test_runtime_multiple_buffs_and_debuffs_stack() -> void:
	# Pin: more than one of each survives, ordering preserved.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Stacked"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	var typed_buffs: Array[Dictionary] = [
		{"effect": "haste", "stat": "speed", "modifier": 1.5, "duration": 5, "remaining_turns": 5},
		{"effect": "protect", "stat": "defense", "modifier": 1.3, "duration": 8, "remaining_turns": 4},
	]
	var typed_debuffs: Array[Dictionary] = [
		{"effect": "weaken", "stat": "attack", "modifier": 0.7, "duration": 3, "remaining_turns": 3},
	]
	c.active_buffs = typed_buffs
	c.active_debuffs = typed_debuffs

	var json := JSON.new()
	json.parse(JSON.stringify(c.to_dict()))
	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)

	assert_eq(c2.active_buffs.size(), 2,
		"both buffs must survive")
	assert_eq(c2.active_debuffs.size(), 1,
		"debuff must survive")
	# Ordering preserved (haste first, then protect).
	assert_eq(str(c2.active_buffs[0]["effect"]), "haste")
	assert_eq(str(c2.active_buffs[1]["effect"]), "protect")


func test_runtime_empty_buffs_roundtrip_cleanly() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Clean"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true

	var json := JSON.new()
	json.parse(JSON.stringify(c.to_dict()))
	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)

	assert_eq(c2.active_buffs.size(), 0)
	assert_eq(c2.active_debuffs.size(), 0)


func test_status_durations_serialization_still_works() -> void:
	# Don't regress tick 151's status_durations fix while adding
	# buffs/debuffs.
	var src := _read(COMBATANT)
	assert_true(src.contains("\"status_durations\": status_durations.duplicate()"),
		"tick 151 status_durations serialization must remain")
	assert_true(src.contains("typed_durations[str(status_key)] = int(raw[status_key])"),
		"tick 151 status_durations int coercion must remain")
