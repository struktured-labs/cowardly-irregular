extends GutTest

## tick 151 regression: Combatant.to_dict and from_dict must
## roundtrip status_durations. Pre-fix only status_effects was
## serialized — the per-status duration counter was lost. Status
## carries across battles only on a Time Mage mid-battle rewind,
## which IS supported (GameState.snapshot_for_rewind /
## rewind_to_previous_save use to_dict/from_dict). Without the
## duration counter, an active poison would survive the snapshot
## with no tick-down — effectively permanent.
##
## Update_status_durations iterates status_durations (line ~474)
## and decrements + removes-on-zero. An empty status_durations
## with non-empty status_effects = silently permanent statuses.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_to_dict_includes_status_durations() -> void:
	var src := _read(COMBATANT)
	# Pin: status_durations key serialized via .duplicate() (shallow
	# is fine — values are ints, not nested objects).
	assert_true(src.contains("\"status_durations\": status_durations.duplicate()"),
		"to_dict must serialize status_durations alongside status_effects")


func test_from_dict_loads_status_durations() -> void:
	var src := _read(COMBATANT)
	# Pin: load branch exists with int coercion (JSON.parse returns
	# numeric values as float; status_durations is treated as int).
	assert_true(src.contains("if data.has(\"status_durations\"):"),
		"from_dict must have a status_durations branch")
	assert_true(src.contains("typed_durations[str(status_key)] = int(raw[status_key])"),
		"from_dict must coerce values to int — JSON.parse returns floats")
	assert_true(src.contains("status_durations = typed_durations"),
		"from_dict must assign the coerced dict back")


# ── Runtime roundtrip ────────────────────────────────────────────────────

func test_runtime_status_durations_roundtrip() -> void:
	# Build a Combatant with a poison status + 4-turn duration,
	# serialize, deserialize into a fresh Combatant, verify the
	# duration counter survived.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Test Poisoned"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	var typed_poison: Array[String] = ["poison"]
	c.status_effects = typed_poison
	c.status_durations = {"poison": 4}

	var snapshot: Dictionary = c.to_dict()

	# Roundtrip through JSON to mimic real save semantics.
	var json := JSON.new()
	var err: int = json.parse(JSON.stringify(snapshot))
	assert_eq(err, OK, "snapshot must round-trip through JSON cleanly")
	var loaded_data: Dictionary = json.data as Dictionary

	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(loaded_data)

	assert_eq(c2.status_effects.size(), 1,
		"status_effects must roundtrip (sanity — pre-fix this also worked)")
	assert_true(c2.status_effects.has("poison"),
		"poison status must survive")
	# The new pin: status_durations carries the 4-turn counter.
	assert_eq(c2.status_durations.get("poison", -1), 4,
		"status_durations['poison'] must roundtrip with value 4 — pre-tick-151 it was lost, leaving the poison effectively permanent")


func test_runtime_empty_status_durations_roundtrips_cleanly() -> void:
	# Defensive: empty status_durations doesn't crash on save/load.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Test Clean"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	# No status effects at all.
	var snapshot: Dictionary = c.to_dict()
	var json := JSON.new()
	json.parse(JSON.stringify(snapshot))
	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)
	assert_eq(c2.status_durations.size(), 0,
		"empty status_durations must remain empty after roundtrip")


func test_runtime_multiple_statuses_with_different_durations() -> void:
	# Pin: multiple statuses with distinct durations all survive.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Stacked"
	c.max_hp = 200
	c.current_hp = 200
	c.is_alive = true
	var typed_stacked: Array[String] = ["poison", "burn", "regen"]
	c.status_effects = typed_stacked
	c.status_durations = {"poison": 3, "burn": 7, "regen": 2}

	var json := JSON.new()
	json.parse(JSON.stringify(c.to_dict()))
	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)

	assert_eq(c2.status_durations.get("poison", -1), 3,
		"poison duration must roundtrip")
	assert_eq(c2.status_durations.get("burn", -1), 7,
		"burn duration must roundtrip")
	assert_eq(c2.status_durations.get("regen", -1), 2,
		"regen duration must roundtrip")


func test_runtime_permanent_status_negative_one_survives() -> void:
	# Pin: -1 sentinel for permanent statuses survives. The
	# update_status_durations loop skips negatives (line ~475:
	# `if status_durations[status] > 0`), so permanent doom et al
	# need to come back as -1, not 0 (which would mean "remove").
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Permanently Doomed"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	var typed_doom: Array[String] = ["doom"]
	c.status_effects = typed_doom
	c.status_durations = {"doom": -1}

	var json := JSON.new()
	json.parse(JSON.stringify(c.to_dict()))
	var c2 = CombatantScript.new()
	add_child_autofree(c2)
	c2.from_dict(json.data as Dictionary)

	assert_eq(c2.status_durations.get("doom", 0), -1,
		"permanent (-1) sentinel must survive roundtrip — was the silent failure pre-tick-151 even with the fix mistakenly clamping to 0")


# ── Negative regression ─────────────────────────────────────────────────

func test_status_effects_serialization_still_works() -> void:
	# Don't regress the existing status_effects roundtrip while
	# adding status_durations.
	var src := _read(COMBATANT)
	assert_true(src.contains("\"status_effects\": status_effects.duplicate()"),
		"to_dict must still serialize status_effects")
	assert_true(src.contains("typed_status: Array[String] = []"),
		"from_dict must still typed-coerce status_effects (tick 105 fix)")
