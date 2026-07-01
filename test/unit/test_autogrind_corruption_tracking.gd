extends GutTest

## Regression coverage for autogrind corruption tracking:
## - Threshold-band signal fires once per band per session (never spams)
## - session-scoped dedup dict clears on start_autogrind
## - save-corruption baseline captures + delta bubbles into stats
## - stats-strip label formats current/max
## - summary formatter shows the delta only when it's positive

const SummaryScript = preload("res://src/ui/autogrind/AutogrindSummary.gd")

var _system: Node
var _received: Array = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system.corruption_threshold_crossed.connect(_capture_band)
	_received.clear()

	_system.is_grinding = false
	_system.meta_corruption_level = 0.0
	_system._corruption_bands_crossed.clear()


func _capture_band(band: String, level: float) -> void:
	_received.append({"band": band, "level": level})


func test_no_band_fires_below_warning_threshold() -> void:
	_system.meta_corruption_level = _system.CORRUPTION_BAND_WARNING - 0.5
	_system._maybe_emit_corruption_band()
	assert_eq(_received.size(), 0,
		"Below warning band no signal should fire")


func test_warning_band_fires_at_threshold() -> void:
	_system.meta_corruption_level = _system.CORRUPTION_BAND_WARNING
	_system._maybe_emit_corruption_band()
	assert_eq(_received.size(), 1)
	assert_eq(_received[0]["band"], "warning")


func test_crossing_all_three_bands_fires_all_three() -> void:
	# Simulate the corruption climbing past all three bands during a grind.
	_system.meta_corruption_level = _system.CORRUPTION_BAND_WARNING + 0.01
	_system._maybe_emit_corruption_band()
	_system.meta_corruption_level = _system.CORRUPTION_BAND_DANGER + 0.01
	_system._maybe_emit_corruption_band()
	_system.meta_corruption_level = _system.CORRUPTION_BAND_CRITICAL + 0.01
	_system._maybe_emit_corruption_band()
	assert_eq(_received.size(), 3,
		"Each band should fire exactly once when the level rises past it")
	var bands := []
	for e in _received:
		bands.append(e["band"])
	assert_true("warning" in bands, "Warning band should have fired")
	assert_true("danger" in bands, "Danger band should have fired")
	assert_true("critical" in bands, "Critical band should have fired")


func test_band_dedup_prevents_repeat_spam() -> void:
	# CRITICAL contract: bumping the check while the value stays in-band should
	# never re-fire. Otherwise a bumpy corruption graph would flood the toast.
	_system.meta_corruption_level = _system.CORRUPTION_BAND_WARNING + 0.5
	_system._maybe_emit_corruption_band()
	_system._maybe_emit_corruption_band()
	_system._maybe_emit_corruption_band()
	assert_eq(_received.size(), 1,
		"Repeated checks while stably above warning must emit only once — otherwise the toast spams every _increase_efficiency tick")


func test_starting_high_fires_multiple_bands_at_once() -> void:
	# If a grind starts corruption already above the danger band (edge case:
	# resume-from-snapshot path), the first _maybe_emit call should fire both
	# warning and danger together, not just the highest.
	_system.meta_corruption_level = _system.CORRUPTION_BAND_DANGER + 0.1
	_system._maybe_emit_corruption_band()
	var bands := []
	for e in _received:
		bands.append(e["band"])
	assert_true("warning" in bands and "danger" in bands,
		"A single call at danger level must fire both warning + danger bands so the player isn't silently past the warning band")


func test_get_grind_stats_exposes_save_corruption_fields() -> void:
	# Even without a live GameState autoload, get_grind_stats must return the
	# three new keys so the summary/dashboard don't render blanks.
	var stats: Dictionary = _system.get_grind_stats()
	for k in ["corruption_threshold", "save_corruption", "save_corruption_delta"]:
		assert_true(stats.has(k),
			"get_grind_stats must expose '%s' — otherwise the summary silently shows a blank" % k)


func test_get_grind_stats_corruption_threshold_matches_field() -> void:
	# The stats-strip label reads corruption_threshold to format "X / Y".
	# If this drifts from AutogrindSystem.corruption_threshold, the "/ Y" side of
	# the display would misrepresent proximity to collapse.
	var stats: Dictionary = _system.get_grind_stats()
	assert_almost_eq(float(stats.get("corruption_threshold", 0.0)),
		_system.corruption_threshold, 0.001,
		"stats['corruption_threshold'] must equal AutogrindSystem.corruption_threshold")


func test_summary_formatter_hides_delta_when_zero() -> void:
	# The summary line reads "0.000" when the player took no save-corruption hit —
	# no dangling "(+0.000 this session)" noise.
	var stats := {"save_corruption": 0.05, "save_corruption_delta": 0.0}
	var summary = SummaryScript.new()
	autofree(summary)
	var formatted := summary._format_save_corruption(stats)
	assert_false("this session" in formatted,
		"When delta is zero the '(+X this session)' suffix must not appear: %s" % formatted)


func test_summary_formatter_shows_delta_when_positive() -> void:
	var stats := {"save_corruption": 0.15, "save_corruption_delta": 0.03}
	var summary = SummaryScript.new()
	autofree(summary)
	var formatted := summary._format_save_corruption(stats)
	assert_true("+0.030" in formatted,
		"When delta is positive the '(+delta this session)' must show — that's the whole point of tracking session accumulation: %s" % formatted)


func test_summary_save_corruption_color_bands() -> void:
	# 0.6+ is red, 0.3-0.6 yellow, below 0.3 green (VALUE_COLOR). Reads at a glance.
	var summary = SummaryScript.new()
	autofree(summary)
	var green := summary._save_corruption_color({"save_corruption": 0.1})
	var yellow := summary._save_corruption_color({"save_corruption": 0.4})
	var red := summary._save_corruption_color({"save_corruption": 0.8})
	assert_eq(green, SummaryScript.VALUE_COLOR,
		"Below 0.3 save-corruption should render green (VALUE_COLOR)")
	assert_ne(yellow, SummaryScript.VALUE_COLOR,
		"0.3-0.6 save-corruption must not render green — that's the mid-risk band")
	assert_eq(red, SummaryScript.BAD_COLOR,
		"Above 0.6 save-corruption should render BAD_COLOR (red)")
