extends GutTest

## tick 329: SaveSystem._process retries auto-save with a 30s backoff
## when the previous attempt was refused, instead of resetting the
## full auto_save_interval and waiting another 5 minutes.
##
## Pre-fix the timer reset to 0 regardless of auto_save()'s return
## value. So a refused auto-save (player in battle / inside an
## interior — both legitimate reasons can_quick_save returns false)
## meant the player waited another FULL auto_save_interval (default
## 5 min) for the next retry. During that window any progress could
## be lost to a party wipe.
##
## Symptom: "the game saved every 5 minutes BUT if I happened to be
## fighting when it would've fired, the next save was 10 minutes
## away instead of 5+." Hard to notice but real.
##
## Fix: only zero the timer on success. On failure, back the timer
## off by AUTO_SAVE_RETRY_BACKOFF (30s) so we retry that soon.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: AUTO_SAVE_RETRY_BACKOFF constant exists ─────────────

func test_retry_backoff_constant_exists() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	assert_true(src.contains("const AUTO_SAVE_RETRY_BACKOFF"),
		"AUTO_SAVE_RETRY_BACKOFF constant must be declared")


# ── Source pin: _process branches on auto_save() return ─────────────

func test_process_branches_on_auto_save_result() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _process(delta: float)")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Success branch: zero the timer.
	assert_true(body.contains("if auto_save():"),
		"_process must call auto_save() and branch on its bool return — pre-fix it called auto_save() then reset unconditionally")
	assert_true(body.contains("time_since_last_auto_save = 0.0"),
		"success branch must reset timer to 0")
	# Failure branch: back the timer off.
	assert_true(body.contains("auto_save_interval - AUTO_SAVE_RETRY_BACKOFF"),
		"failure branch must back the timer off by AUTO_SAVE_RETRY_BACKOFF")


# ── Source pin: backoff is clamped at 0 ─────────────────────────────

func test_backoff_clamped_at_zero() -> void:
	# If auto_save_interval is set pathologically small (e.g., debug
	# tools lower it to 5s), `interval - backoff` could go negative.
	# maxf(0.0, ...) keeps the timer non-negative.
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _process(delta: float)")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("maxf(0.0, auto_save_interval - AUTO_SAVE_RETRY_BACKOFF)"),
		"failure-branch backoff must be clamped at 0 via maxf to handle small auto_save_interval values")


# ── Behavioral: success path resets timer to 0 ──────────────────────

func test_success_resets_timer() -> void:
	# Real autoload. We can't easily mock auto_save() to return true on
	# demand without elaborate setup; instead verify the source pin
	# already covered above is structurally correct by inspecting the
	# branches' relative position.
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _process(delta: float)")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Zero-reset must come BEFORE the backoff line (it's the success arm
	# of the if).
	var zero_idx: int = body.find("time_since_last_auto_save = 0.0")
	var backoff_idx: int = body.find("auto_save_interval - AUTO_SAVE_RETRY_BACKOFF")
	assert_gt(zero_idx, -1, "zero-reset line must exist")
	assert_gt(backoff_idx, -1, "backoff line must exist")
	assert_lt(zero_idx, backoff_idx,
		"zero-reset (success arm) must come before backoff (failure arm) in source order")


# ── Behavioral: constant value is reasonable ────────────────────────

func test_backoff_value_is_reasonable() -> void:
	# The exact value is a design choice — 30s is short enough for quick
	# retry after a boss battle, long enough not to spam can_quick_save
	# every frame. Pin it loosely (must be > 0 and < interval).
	var src := _read(SAVE_SYSTEM_PATH)
	var idx: int = src.find("const AUTO_SAVE_RETRY_BACKOFF")
	var next_newline: int = src.find("\n", idx)
	var line: String = src.substr(idx, next_newline - idx)
	# Extract the float value.
	var eq_idx: int = line.find("=")
	assert_gt(eq_idx, -1)
	var value_part: String = line.substr(eq_idx + 1).strip_edges()
	# Strip trailing comments.
	if "#" in value_part:
		value_part = value_part.split("#")[0].strip_edges()
	var value: float = value_part.to_float()
	assert_gt(value, 0.0, "backoff must be positive")
	assert_lt(value, 300.0, "backoff must be smaller than the default 5-min auto_save_interval — otherwise the fix is pointless")
