extends GutTest

## tick 159 regression: RebalanceDaemon.from_dict must enforce
## PENDING_CAP / APPLIED_CAP on load. Pre-fix the load appended
## without re-checking the ring caps. Not currently triggerable
## because to_dict serializes the already-capped state, but
## becomes a silent bug if a future version REDUCES the cap (e.g.,
## APPLIED_CAP 50→25): old saves propagate 40+ entries unbounded,
## and future writes don't kick anything out until the live size
## hits the new cap.
##
## Also: timestamp negative-coerce. last_consideration_ts > now
## (corrupted future timestamp) would make consider's throttle
## arithmetic (now - past) negative, satisfying the
## "interval has passed" check trivially or with weird sign.
##
## ALLOWED_CONSTANTS validation audit confirmed clean:
## try_auto_apply (line ~280) and force_apply (line ~345) both
## reject unlisted constants. Defense in depth.

const REBALANCE_DAEMON := "res://src/llm/RebalanceDaemon.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_from_dict_enforces_pending_cap() -> void:
	var src := _read(REBALANCE_DAEMON)
	# Pin: the cap-enforcement loop runs after the append loop.
	assert_true(src.contains("while pending.size() > PENDING_CAP:"),
		"from_dict must enforce PENDING_CAP via while-pop_front loop")
	# Find the from_dict body and verify enforcement is INSIDE it.
	var idx: int = src.find("func from_dict")
	assert_gt(idx, -1, "from_dict must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("while pending.size() > PENDING_CAP:"),
		"PENDING_CAP enforcement must be in from_dict, not somewhere else")


func test_from_dict_enforces_applied_cap() -> void:
	var src := _read(REBALANCE_DAEMON)
	var idx: int = src.find("func from_dict")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("while applied.size() > APPLIED_CAP:"),
		"from_dict must enforce APPLIED_CAP via while-pop_front loop")


func test_from_dict_normalizes_negative_timestamp() -> void:
	var src := _read(REBALANCE_DAEMON)
	var idx: int = src.find("func from_dict")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("var raw_ts: int = int(data.get(\"last_consideration_ts\", 0))"),
		"from_dict must int() coerce the timestamp from save")
	assert_true(body.contains("_last_consideration_ts = max(0, raw_ts)"),
		"from_dict must floor negative timestamps at 0 — defensive against corrupted future-timestamp saves")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_oversized_pending_load_caps_to_pending_cap() -> void:
	# Simulate a save written by an older version with a higher cap.
	# Build 30 entries (current PENDING_CAP=20). Load must drop to 20.
	var DaemonScript = load(REBALANCE_DAEMON)
	var daemon = DaemonScript.new()
	var oversized_pending: Array = []
	for i in 30:
		oversized_pending.append({"trigger": "test", "idx": i})
	daemon.from_dict({"pending": oversized_pending})
	# Read PENDING_CAP off the script class so the test stays
	# correct if the cap changes.
	var cap: int = DaemonScript.PENDING_CAP
	assert_eq(daemon.pending.size(), cap,
		"oversized pending load must cap to PENDING_CAP — was unbounded pre-tick-159")
	# Drop OLDEST first: pending[0] should be the 11th entry of
	# the input (idx=10), not idx=0.
	# Skip checking specific entries if cap is 0 or 1 (defensive).
	if cap >= 1:
		var first_idx: int = int(daemon.pending[0].get("idx", -1))
		var expected_first: int = 30 - cap
		assert_eq(first_idx, expected_first,
			"oldest entries must be dropped (ring semantics) — first surviving entry should be idx=%d" % expected_first)


func test_runtime_oversized_applied_load_caps_to_applied_cap() -> void:
	var DaemonScript = load(REBALANCE_DAEMON)
	var daemon = DaemonScript.new()
	# Build APPLIED_CAP + 20 entries to make the overflow visible.
	var cap: int = DaemonScript.APPLIED_CAP
	var oversized: Array = []
	for i in (cap + 20):
		oversized.append({"trigger": "test", "idx": i})
	daemon.from_dict({"applied": oversized})
	assert_eq(daemon.applied.size(), cap,
		"oversized applied load must cap to APPLIED_CAP")


func test_runtime_negative_timestamp_floors_at_zero() -> void:
	var DaemonScript = load(REBALANCE_DAEMON)
	var daemon = DaemonScript.new()
	daemon.from_dict({"last_consideration_ts": -1000})
	assert_eq(daemon._last_consideration_ts, 0,
		"negative timestamp must floor at 0 — prevents throttle arithmetic going inverted")


# ── Non-regression ──────────────────────────────────────────────────────

func test_runtime_in_range_load_passes_through() -> void:
	var DaemonScript = load(REBALANCE_DAEMON)
	var daemon = DaemonScript.new()
	var normal_pending: Array = [
		{"trigger": "test_a", "idx": 1},
		{"trigger": "test_b", "idx": 2},
	]
	var normal_applied: Array = [
		{"trigger": "applied_a", "idx": 1},
	]
	daemon.from_dict({
		"pending": normal_pending,
		"applied": normal_applied,
		"last_consideration_ts": 12345,
	})
	assert_eq(daemon.pending.size(), 2, "small pending list passes through")
	assert_eq(daemon.applied.size(), 1, "small applied list passes through")
	assert_eq(daemon._last_consideration_ts, 12345,
		"positive timestamp passes through unchanged")


# ── ALLOWED_CONSTANTS validation (audit pin) ────────────────────────────

func test_apply_path_rejects_constants_outside_allowlist() -> void:
	# Sanity pin: both apply paths (try_auto_apply, force_apply)
	# still validate constant_name against ALLOWED_CONSTANTS.
	# Audit confirmed both are clean; this test prevents a future
	# refactor from removing the gate.
	var src := _read(REBALANCE_DAEMON)
	# Count the `not in ALLOWED_CONSTANTS` rejection points.
	var count: int = 0
	var cursor: int = 0
	while true:
		var found: int = src.find("not in ALLOWED_CONSTANTS:", cursor)
		if found < 0:
			break
		count += 1
		cursor = found + 1
	assert_gte(count, 2,
		"at least 2 sites (try_auto_apply, force_apply) must reject unlisted constants — defense in depth")
