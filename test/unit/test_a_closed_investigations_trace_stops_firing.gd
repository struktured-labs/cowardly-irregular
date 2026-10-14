extends GutTest

## ⛔ A CLOSED INVESTIGATION'S TRACE WAS STILL FIRING, ON THE HEALTHY PATH, IN SHIPPED BUILDS.
## The [MENU-NULL] / [MENU-HIDE] lines pinned the menu lifecycle for struktured's "two win98 menus
## at once" report. Diagnostics landed 2026-07-12 (ba65bb692), the ROOT FIX 2026-07-13
## (b2f2d0283) — so the trace had no reader for three months. Measured in his 2026-10-13 session
## (godot.log, 1101 lines, the 988-key build):
##
##   menu_closed_signal 29 · close_win98_menu 22 · defer_requested 12 · actions_submitted 5
##   go_back_requested 2   = 70 lines, 6.4% of the log, plus 12 stray_sweep which are REAL
##
## It fires on an ordinary close — close then signal ~1ms apart, closing == active. A detector
## aimed at the healthy state cannot report illness, and five lanes mine these logs daily; I
## cleared 12 of these myself as "the sweep working" before measuring the rest.
##
## ⚠️ GATED, NEVER DELETED (cowir-main): a recurrence must still be traceable on demand.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
## The two files that carry the trace. Derived over both, because the sites are split across them
## and a guard scoped to one would report full coverage of the half it looked at.
const TRACE_FILES: Array = [
	"res://src/battle/BattleCommandMenu.gd",
	"res://src/battle/BattleScene.gd",
]

var _saved_flag: bool = false


func before_each() -> void:
	_saved_flag = bool(GameState.debug_log_enabled)


func after_each() -> void:
	GameState.debug_log_enabled = _saved_flag


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## One scan, shared, so the figures below are commensurable and the coverage claim can be an
## IDENTITY rather than a round number. Returns every trace line in these files classified.
func _scan() -> Dictionary:
	var found: int = 0
	var routed: int = 0
	var direct: int = 0
	var offenders: Array[String] = []
	for path in TRACE_FILES:
		var text: String = _source(str(path))
		if text == "":
			offenders.append("UNREADABLE: %s" % str(path))
			continue
		for raw in text.split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("#"):
				continue
			if not ("[MENU-NULL]" in line or "[MENU-HIDE]" in line):
				continue
			found += 1
			if "trace_menu(" in line:
				routed += 1
			elif line.begins_with("print(") and "stray_sweep" in line:
				direct += 1
			else:
				offenders.append("%s: %s" % [str(path), line])
	return {"found": found, "routed": routed, "direct": direct, "offenders": offenders}


## FLOOR: a rename reds naming the symbol. Both are reached as STATICS through a class_name, so a
## missing one is a parse error and run_tests.sh exits 3 — louder than any floor — but the
## predicate is also read by arms below through the preload, so pin it.
func test_the_symbols_this_file_drives_exist() -> void:
	assert_true(MenuScript.has_method("trace_menu"),
		"FLOOR: trace_menu is the single gate every trace site routes through")
	assert_true(MenuScript.has_method("tracing_menu_lifecycle"),
		"FLOOR: the gate's decision must be observable, or a guard can only pin spelling")
	assert_true("debug_log_enabled" in GameState,
		"FLOOR: the flag the gate reads")


## THE GATE, as behaviour rather than as a token. Its only input is the flag.
func test_the_trace_follows_the_flag_in_both_directions() -> void:
	GameState.debug_log_enabled = false
	assert_false(MenuScript.tracing_menu_lifecycle(),
		("with the debug log off the trace must NOT fire — this is the whole item: his settings "
		+ "carry false and his log still held 70 of these lines"))
	GameState.debug_log_enabled = true
	assert_true(MenuScript.tracing_menu_lifecycle(),
		("and with it ON the trace must still be available — gated, not deleted, so a recurrence "
		+ "of the two-menus bug is traceable on demand"))


## ⛔ DERIVED FROM SOURCE, because the claim IS about call sites: no trace print may bypass the
## gate. A hand-listed set goes stale the day a tenth site is added, which is the shape this item
## exists to prevent.
func test_no_trace_print_bypasses_the_gate() -> void:
	var r: Dictionary = _scan()
	assert_eq(r["offenders"], [] as Array[String],
		("a [MENU-NULL]/[MENU-HIDE] line neither routes through trace_menu() nor is the kept "
		+ "stray_sweep print, so it fires whatever the flag says. Found: %s") % str(r["offenders"]))


## ⛔ COVERAGE AS AN IDENTITY, NOT A ROUND NUMBER. Every trace line is either routed through the
## gate or is the one stray_sweep print — so `found == routed + direct` is the whole population,
## and adding a tenth site moves both sides together. A pinned figure cannot do that:
## @cowir-adhoc shipped `assert_gt(measured, 500)` against a true 1110, so their arm could have
## skipped 55% of its subject while claiming it measured all of it.
func test_every_trace_line_is_accounted_for() -> void:
	var r: Dictionary = _scan()
	assert_gt(int(r["found"]), 0,
		"FLOOR: the pattern must match something — a scan that finds nothing reports a clean sweep "
		+ "of an empty corpus, which is the false green this whole file is about")
	assert_eq(int(r["found"]), int(r["routed"]) + int(r["direct"]),
		("every trace line must be classified: found %d, routed %d, direct %d. A line in neither "
		+ "bucket is an ungated print, and this identity cannot fall behind a new site the way a "
		+ "pinned count does.") % [int(r["found"]), int(r["routed"]), int(r["direct"])])


## ⛔ THE CONTROL, AND IT GUARDS THE OPPOSITE MISTAKE: the stray_sweep line must stay
## UNCONDITIONAL. It is the only signal that the self-heal actually fired, so routing it through
## the gate would delete that signal exactly when the flag is off — which is his normal state and
## precisely when a leak would matter (cowir-main: "keep the stray-sweep line").
func test_the_self_heal_signal_is_not_gated() -> void:
	var r: Dictionary = _scan()
	assert_eq(int(r["direct"]), 1,
		("CONTROL: the stray_sweep line must remain exactly ONE unconditional print — it is the only "
		+ "evidence the self-heal fired, and his settings carry debug_log_enabled false, so gating it "
		+ "would delete that evidence in the state he actually plays in. Got %d.") % int(r["direct"]))


## The gate must be load-bearing rather than defined and unused: the sites really do call it.
func test_the_gate_is_actually_reached() -> void:
	var r: Dictionary = _scan()
	assert_gt(int(r["routed"]), 7,
		("the nine measured trace sites must route through the gate; %d found. Three sites alone "
		+ "would leave 36 of his 82 lines in place, which is the scope error this arm pins.")
		% int(r["routed"]))


## ⛔ THE ARM THAT CATCHES THE GATE LOSING ITS GUARD, and without it all the others are green
## through that mutation. Delete the `if` inside trace_menu and: the predicate arm still passes (the
## predicate is unchanged), the routing arm still passes (the nine sites still call it), the reached
## arm still passes. Only the ACTION tells you — so trace_menu reports whether it logged, and this
## drives the real function rather than something adjacent to it.
##
## @cowir-sfx hit this exact shape today: an arm named `test_the_quota_is_per_cue_not_global` was
## green on a per-variant quota bug because it drove two unrelated cue names.
func test_the_gate_itself_obeys_the_flag_not_just_its_predicate() -> void:
	GameState.debug_log_enabled = false
	assert_false(MenuScript.trace_menu("[MENU-NULL] guard probe, flag off"),
		("with the flag off trace_menu must NOT log — a predicate that answers correctly while the "
		+ "body ignores it is the whole trace back in his log"))
	GameState.debug_log_enabled = true
	assert_true(MenuScript.trace_menu("[MENU-NULL] guard probe, flag on"),
		("and with it on it must log, or the trace is deleted rather than gated and a recurrence of "
		+ "the two-menus bug is untraceable"))
