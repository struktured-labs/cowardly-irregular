extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left live signal wiring on the autoload.
var _ag_state: Dictionary

## The console is the ONLY listener for `system_collapse`, and closing it disconnects the handler, so
## a catch-up exists to report collapses missed while it was shut. The baseline it diffed against —
## "collapses this console has already told the player about" — lived ON THE CONSOLE, which GameLoop
## FREES on close (:5543) and rebuilds on open (:5477). So the baseline was 0 at every open:
##
##   measured on three consecutive opens with collapse_count = 3, nothing happening in between
##     open 1: catchup=3    open 2: catchup=3    open 3: catchup=3
##
## Every reopen re-announced the whole session's collapses as newly missed — "3 SYSTEM COLLAPSES
## happened while this console was closed" for collapses the player had WATCHED, during a window in
## which nothing happened. A message whose entire job is to tell you what you missed, telling you that
## about things you did not miss.
##
## The baseline now lives on AutogrindSystem (`collapses_announced`), which outlives the console —
## the only place that can hold it. Session-scoped like collapse_count itself: reset in
## start_autogrind, carried in the snapshot so a resume does not re-announce, restored with it.
##
## 🔑 FOUND BY A DISCRIMINATOR, not by the name. A console-side copy is only dangerous when something
## writes the original behind its back. `_is_grinding` and `AutogrindDashboard._battles_completed`
## shadow system fields too and are both FINE, because nothing does. This one is a diff against a
## counter that survives the differ, which is the same shape one layer along.

const UIScript = preload("res://src/ui/autogrind/AutogrindUI.gd")
const SystemScript = preload("res://src/autogrind/AutogrindSystem.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

var _sys


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_sys = AutogrindSystem
	_sys._test_disable_persistence = true
	_sys.collapse_count = 0
	_sys.collapses_announced = 0


func after_each() -> void:
	_sys.stop_autogrind()
	_sys.collapse_count = 0
	_sys.collapses_announced = 0
	_sys._test_disable_persistence = false
	AutogrindState.restore(_ag_state)



## One open: build, connect, read what it owes the player, disconnect. The free is the mechanism, so
## each call really is a separate console.
func _open_console_and_read_catchup() -> int:
	var ui = UIScript.new()
	add_child_autofree(ui)
	ui._connect_autogrind_signals()
	var owed: int = int(ui._pending_collapse_catchup)
	ui._disconnect_autogrind_signals()
	return owed


func test_a_collapse_missed_once_is_announced_once() -> void:
	_sys.collapse_count = 3
	var owed: Array = []
	for _i in 3:
		owed.append(_open_console_and_read_catchup())
	gut.p("    three opens, nothing between: %s" % str(owed))
	assert_eq(int(owed[0]), 3,
		"CONTROL: the first open must still owe the player all three, or the catch-up is broken rather than fixed")
	assert_eq(int(owed[1]), 0,
		"the second open re-announced %s collapses the player had already been told about" % owed[1])
	assert_eq(int(owed[2]), 0, "and the third did it again")


func test_a_collapse_after_the_last_open_is_still_announced() -> void:
	## The catch-up must keep working; a baseline that silences everything passes the arm above.
	_sys.collapse_count = 2
	assert_eq(_open_console_and_read_catchup(), 2, "CONTROL: the first two are owed")
	_sys.collapse_count = 5
	assert_eq(_open_console_and_read_catchup(), 3,
		"three more collapsed while the console was shut and it owed the player nothing")


func test_a_live_collapse_is_not_re_announced_on_the_next_open() -> void:
	## Watched, not missed: the live handler marks it announced, so reopening owes nothing.
	var ui = UIScript.new()
	add_child_autofree(ui)
	ui._connect_autogrind_signals()
	_sys.collapse_count = 1
	ui._on_system_collapse()
	ui._disconnect_autogrind_signals()
	assert_eq(int(_sys.collapses_announced), 1,
		"CONTROL: the live handler must mark it announced, or the arm below passes for the wrong reason")
	assert_eq(_open_console_and_read_catchup(), 0,
		"a collapse the player watched happen was re-announced as missed when the console reopened")


func test_a_fresh_grind_owes_nothing_from_the_last_one() -> void:
	## collapse_count resets at start_autogrind, so the baseline must reset with it or the first
	## collapse of a new session is swallowed by a stale high-water mark.
	_sys.collapse_count = 4
	assert_eq(_open_console_and_read_catchup(), 4, "CONTROL: the old session's collapses are owed first")
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 100, "max_mp": 50, "attack": 20, "defense": 15, "magic": 10, "speed": 12})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	assert_true(_sys.start_autogrind(party, {}), "CONTROL: the probe grind must start")
	assert_eq(int(_sys.collapses_announced), 0, "the announced baseline must reset with collapse_count")
	_sys.collapse_count = 1
	assert_eq(_open_console_and_read_catchup(), 1,
		"the new session's first collapse was swallowed by the previous session's high-water mark")


func test_a_resume_does_not_re_announce_what_was_already_said() -> void:
	## The snapshot half. Without it, restore puts collapse_count back and leaves the baseline at 0,
	## so resuming a paused grind re-announces every collapse of it.
	_sys.collapse_count = 2
	assert_eq(_open_console_and_read_catchup(), 2, "CONTROL: told once before the pause")
	var block: Dictionary = _sys.build_snapshot_system_block(90.0)
	var wire = JSON.parse_string(JSON.stringify(block))
	assert_true(wire is Dictionary, "CONTROL: the snapshot must survive JSON")
	_sys.collapse_count = 0
	_sys.collapses_announced = 0
	_sys.restore_system_from_snapshot(wire)
	assert_eq(int(_sys.collapse_count), 2, "CONTROL: the resume restores the count")
	assert_eq(_open_console_and_read_catchup(), 0,
		"resuming re-announced collapses the player was told about before the pause")


func test_the_baseline_does_not_live_on_the_console() -> void:
	## Structural. Every arm above passes on a console-side copy that happens to be seeded; this is
	## what stops one coming back, and the per-instance copy is precisely the defect.
	var code: String = GdSource.code_of(UI_SRC)
	assert_gt(code.length(), 5000, "CONTROL: the console was actually read")
	assert_true(code.contains("AutogrindSystem.collapses_announced"),
		"CONTROL: the console must read the surviving baseline")
	assert_false(code.contains("_collapses_reported"),
		"the baseline is back on the console, which is freed at every open — it cannot remember anything")
