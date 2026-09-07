extends GutTest

## tick 164 regression: EventLog.restore must enforce RING_CAP on
## load + int() coerce timestamps + floor negatives at 0.
##
## Three gaps in the pre-fix restore:
##   1. No RING_CAP enforcement. record() caps at line 63-64
##      (pop_front when oversized) but restore() appended without
##      checking — a save from a build with looser cap, or a
##      corrupted save with bogus padding, propagates unbounded.
##      Same class as the tick 159 RebalanceDaemon fix.
##   2. No int() coerce on t / pt timestamps. JSON.parse returns
##      numerics as float; downstream "now - entry.t" arithmetic
##      treats the result as int.
##   3. No negative-timestamp floor. A corrupted save with
##      t: -100 would poison time-since-event UI rendering.

const EVENT_LOG := "res://src/llm/EventLog.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_restore_enforces_ring_cap() -> void:
	var src := _read(EVENT_LOG)
	# Pin: the while-loop trim runs after the typed-array build.
	assert_true(src.contains("while typed.size() > RING_CAP:"),
		"restore() must enforce RING_CAP via while-trim loop")
	assert_true(src.contains("typed.pop_front()"),
		"trim must pop_front — matches record()'s ring semantics (oldest dropped)")


func test_restore_coerces_timestamps_to_int() -> void:
	var src := _read(EVENT_LOG)
	# Pin: both timestamp fields get int() coerce.
	assert_true(src.contains("copied[\"t\"] = max(0, int(copied[\"t\"]))"),
		"restore() must int() coerce + floor t timestamp")
	assert_true(src.contains("copied[\"pt\"] = max(0, int(copied[\"pt\"]))"),
		"restore() must int() coerce + floor pt timestamp")


func test_restore_guards_timestamp_presence() -> void:
	# Pin: the coercion is conditional on the key being present.
	# Otherwise a corrupted entry lacking the field would push
	# Variant null through int() and surface as 0 silently.
	var src := _read(EVENT_LOG)
	# Look for has("t") guard before the t coercion.
	var idx: int = src.find("if copied.has(\"t\"):")
	assert_gt(idx, -1, "t coercion must be guarded by has('t')")
	assert_true(src.contains("if copied.has(\"pt\"):"),
		"pt coercion must be guarded by has('pt')")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_oversized_restore_caps_at_ring_cap() -> void:
	# RING_CAP = 50. Build 70 entries, restore should cap to 50.
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	var oversized: Array = []
	for i in 70:
		oversized.append({
			"t": 1000 + i,
			"pt": 50 * i,
			"type": "test",
			"summary": "entry %d" % i,
			"data": {},
		})
	log.restore(oversized)
	var cap: int = EventLogScript.RING_CAP
	assert_eq(log.size(), cap,
		"oversized restore must cap at RING_CAP=%d" % cap)
	# Drop OLDEST: surviving first entry should have idx=70-50=20.
	# Read via recent() so we get the array.
	var entries: Array = log.recent()
	var first_summary: String = str(entries[0].get("summary", ""))
	var expected_first: String = "entry %d" % (70 - cap)
	assert_eq(first_summary, expected_first,
		"oldest entries dropped — first surviving entry should be 'entry %d'" % (70 - cap))


func test_runtime_negative_timestamp_floors_at_zero() -> void:
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	log.restore([{
		"t": -1000,
		"pt": -500,
		"type": "test",
		"summary": "corrupted",
		"data": {},
	}])
	var entries: Array = log.recent()
	assert_eq(entries.size(), 1, "entry must survive")
	assert_eq(int(entries[0].get("t", -1)), 0,
		"negative t must floor at 0")
	assert_eq(int(entries[0].get("pt", -1)), 0,
		"negative pt must floor at 0")


func test_runtime_json_float_timestamp_coerces_to_int() -> void:
	# JSON.parse returns numerics as float. Verify via real
	# JSON roundtrip.
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	var json := JSON.new()
	json.parse(JSON.stringify([{
		"t": 12345,
		"pt": 67890,
		"type": "test",
		"summary": "via json",
		"data": {},
	}]))
	log.restore(json.data)
	var entries: Array = log.recent()
	var t_val = entries[0].get("t")
	assert_eq(typeof(t_val), TYPE_INT,
		"t must arrive as TYPE_INT after restore (verifies explicit coerce, not auto-truncate accident)")
	assert_eq(int(t_val), 12345,
		"positive t value preserved through JSON roundtrip + coerce")


func test_runtime_missing_timestamp_field_not_polluted() -> void:
	# Defensive: an entry missing the t key shouldn't gain a phantom
	# t=0. The has() guard ensures we don't create the field.
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	log.restore([{
		"type": "test",
		"summary": "no_timestamp",
		"data": {},
	}])
	var entries: Array = log.recent()
	assert_eq(entries.size(), 1)
	assert_false(entries[0].has("t"),
		"missing t field must NOT be created with phantom 0 — preserve absence")
	assert_false(entries[0].has("pt"),
		"missing pt field must NOT be created with phantom 0")


# ── Non-regression ──────────────────────────────────────────────────────

func test_runtime_normal_entries_pass_through_unchanged() -> void:
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	log.restore([
		{"t": 100, "pt": 50, "type": "boss_defeat", "summary": "fight", "data": {}},
		{"t": 200, "pt": 75, "type": "level_up", "summary": "gained", "data": {}},
	])
	assert_eq(log.size(), 2, "normal small restore passes through")


func test_runtime_non_dict_entries_filtered() -> void:
	# Pre-existing filter (line 160 `if item is Dictionary`)
	# must still drop non-Dict entries.
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	log.restore([
		"not_a_dict",
		{"t": 100, "type": "test", "summary": "valid"},
		42,
		null,
	])
	assert_eq(log.size(), 1,
		"only the valid Dictionary entry survives the filter")


func test_runtime_null_input_clears() -> void:
	# Pre-existing null guard (line 153) must still clear entries.
	var EventLogScript = load(EVENT_LOG)
	var log = EventLogScript.new()
	log.restore([{"t": 100, "type": "test", "summary": "pre"}])
	assert_eq(log.size(), 1, "sanity: entry loaded")
	log.restore(null)
	assert_eq(log.size(), 0, "null restore must clear entries")
