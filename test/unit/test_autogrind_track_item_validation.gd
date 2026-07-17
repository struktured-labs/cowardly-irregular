extends GutTest

## Cadence #21 — track_item_consumed is the public API used by GameLoop
## between-battle healing. Pre-fix: zero input validation — empty string
## created a phantom items_consumed[""] entry that leaked into
## get_items_consumed_summary. Unknown ids were tracked silently, so a
## typo like "hi_potin" vs "hi_potion" left no drift signal.

const AutogrindSystemScript := preload("res://src/autogrind/AutogrindSystem.gd")


var _system: Node


func before_each() -> void:
	_system = AutogrindSystemScript.new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func test_empty_item_id_refused_no_phantom_entry() -> void:
	# The bug this cadence fixed: empty string used to create items_consumed[""] = 1.
	_system.track_item_consumed("")
	assert_false(_system.items_consumed.has(""),
		"empty string item_id must not create a phantom entry — else the summary displays ' x1' garbage (cadence #21)")
	assert_true(_system.items_consumed.is_empty(),
		"empty-id call must produce zero mutation")


func test_valid_item_id_tracks_normally() -> void:
	# Baseline: a real item_id still tracks. "potion" is in items.json.
	_system.track_item_consumed("potion")
	assert_eq(_system.items_consumed.get("potion", 0), 1,
		"valid id must still track after cadence #21 hardening (contract preserved)")


func test_valid_item_id_repeat_increments() -> void:
	# Contract: repeated calls increment (dict-value += 1 semantics).
	_system.track_item_consumed("potion")
	_system.track_item_consumed("potion")
	_system.track_item_consumed("potion")
	assert_eq(_system.items_consumed.get("potion", 0), 3,
		"repeated tracking must increment — cadence #21 must not have accidentally reset")


func test_unknown_item_id_tracks_with_warning() -> void:
	# Unknown ids still track (so drift is visible in the summary and downstream
	# telemetry) but push_warning surfaces the drift in the editor warnings panel
	# + CI. Test just asserts the tracking-side contract; the warning side is
	# covered by the source ratchet below.
	_system.track_item_consumed("__definitely_not_a_real_item_xyz")
	assert_eq(_system.items_consumed.get("__definitely_not_a_real_item_xyz", 0), 1,
		"unknown id must still track — drift signal in summary; warning happens alongside via push_warning")


func test_source_ratchet_empty_id_guard_pushes_warning() -> void:
	# The empty-id guard must push_warning + return before mutation. Source
	# inspection because we can't easily assert warning contents in-test.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func _track_item_consumed")
	assert_true(fn_start >= 0)
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("item_id.is_empty()"),
		"_track_item_consumed must guard is_empty() BEFORE mutation — else caller-typo creates phantom items_consumed[''] entry (cadence #21)")
	# The guard's push_warning + return must both appear before items_consumed writes.
	var items_write: int = body.find("items_consumed[item_id]")
	assert_true(items_write > 0, "setup: items_consumed write must exist")
	var pre_write: String = body.substr(0, items_write)
	assert_true(pre_write.contains("push_warning"),
		"empty-id guard's push_warning must fire BEFORE the items_consumed write — order matters for the atomic refuse-and-warn contract")
	assert_true(pre_write.contains("return"),
		"empty-id guard must return BEFORE the write — else the guard is inert")


func test_source_ratchet_unknown_id_warns_but_tracks() -> void:
	# The unknown-id branch must warn AND still fall through to tracking
	# (drift signal in summary). Source ratchet on both properties.
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func _track_item_consumed")
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("rec.is_empty()"),
		"unknown-id branch must query ItemSystem.get_item(id) and check rec.is_empty() (cadence #21)")
	assert_true(body.contains("data drift"),
		"unknown-id warning must name 'data drift' as one of the possible causes — helps the reader triage the warning vs a genuine new-id")


func test_public_wrapper_delegates_to_private() -> void:
	# track_item_consumed is the public API; must delegate to _track_item_consumed
	# so the guards apply to external callers (GameLoop between-battle healing).
	var src: String = load("res://src/autogrind/AutogrindSystem.gd").source_code
	var fn_start: int = src.find("func track_item_consumed(")
	assert_true(fn_start >= 0)
	var fn_end: int = src.find("\nfunc ", fn_start + 20)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	assert_true(body.contains("_track_item_consumed(item_id)"),
		"public track_item_consumed must delegate to _track_item_consumed so external callers get the cadence #21 guards — else GameLoop's typo'd items still create phantom entries")


func test_summary_after_empty_id_refusal_stays_clean() -> void:
	# End-to-end: the summary display was the user-visible symptom of the
	# phantom entry. After cadence #21, calling with empty leaves summary "None".
	_system.track_item_consumed("")
	assert_eq(_system.get_items_consumed_summary(), "None",
		"summary must remain 'None' after an empty-id call — the whole point of cadence #21 is preventing the phantom ' x1' garbage from reaching this display")
