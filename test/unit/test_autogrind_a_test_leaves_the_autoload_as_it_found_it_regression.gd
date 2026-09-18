extends GutTest

const State := preload("res://test/unit/helpers/autogrind_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GRIND := "res://src/autogrind/AutogrindSystem.gd"

## AutogrindSystem is an autoload, so its state is per-PROCESS and every GUT file after a leaker
## inherits it. This lane already carries the receipt: test_autogrind_snapshot's after_each says a
## left-behind `battles_completed` "refuses a grind in every later file of the same GUT process
## (measured 2026-09-16 — a healing-item sweep saw a party that could not heal)".
##
## ⛔ WHAT THIS GUARD DEFENDS IS THE DERIVATION, NOT A FIELD LIST. Measured 2026-09-17 with an
## in-process before/after probe over all 55 script variables: the two gold files leak NINE fields
## and name TWO of them. `on_battle_victory()` moves the efficiency ladder, the corruption ladder,
## the win streak, the adaptation level and the battle counter — none of those words occur in the
## file that drives it. A teardown listing what the file ASSIGNS is blind to all of it, which is
## why the repair is a whole-surface snapshot rather than a longer list.

var _snap: Dictionary


func before_each() -> void:
	_snap = State.snapshot_and_isolate()


func after_each() -> void:
	State.restore(_snap)


func _member() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 100, "max_mp": 10,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


## The whole point: a victory moves fields the caller never named, and restore puts them all back.
func test_restore_returns_fields_the_caller_never_named() -> void:
	var inner: Dictionary = State.snapshot()
	AutogrindSystem.grind_party = [] as Array[Combatant]
	AutogrindSystem.current_region_id = ""
	AutogrindSystem.on_battle_victory(10, {"gold": 5})

	## ⛔ THE DETECTOR CONTROL. Without it, "leaked is empty after restore" is also what a broken
	## probe prints. This proves the mutation is real AND that leaked() can see it.
	var during: Array = State.leaked(inner)
	gut.p("    one victory moved %d field(s): %s" % [during.size(), str(during)])
	assert_gt(during.size(), 4,
		"CONTROL: one grind victory must move several autoload fields, or this guard proves nothing")
	var moved_names: String = str(during)
	assert_true(moved_names.contains("efficiency_multiplier") and moved_names.contains("meta_corruption_level"),
		"CONTROL: the ladders a grind advances must be among them — those are the ones no file names")

	State.restore(inner)
	assert_eq(State.leaked(inner), [],
		"restore left the autoload changed — every later file in this GUT process inherits that")


## The list-based teardowns in this lane restore what their author listed; this pins the alternative.
func test_the_snapshot_is_derived_from_the_autoload_not_hand_listed() -> void:
	var src: String = GdSource.code_of(GRIND)
	var declared: Array = []
	for line in src.split("\n"):
		var m := RegEx.create_from_string("^var ([A-Za-z_][A-Za-z_0-9]*)").search(line)
		if m != null:
			declared.append(m.get_string(1))
	assert_gt(declared.size(), 40, "CONTROL: the source scan must find the autoload's fields")

	var snap: Dictionary = State.snapshot()
	var missing: Array = []
	for n in declared:
		if not snap.has(n):
			missing.append(n)
	gut.p("    declared %d · snapshotted %d" % [declared.size(), snap.size()])
	assert_eq(missing, [],
		"the snapshot misses fields the autoload declares, so a teardown built on it leaks them: %s" % str(missing))


## A record without its connection is worse than the leak — the disarm path can no longer find it.
func test_restore_severs_the_signal_wiring_rather_than_dropping_the_record() -> void:
	var clean: Dictionary = State.snapshot()
	var m := _member()
	assert_true(m.has_signal("ability_learned"), "CONTROL: the wiring target signal must exist")

	AutogrindSystem._wire_smart_interrupt_signals([m])
	assert_gt(AutogrindSystem._ability_learned_conns.size(), 0,
		"CONTROL: wiring must actually connect, or the severing claim is vacuous")
	assert_true(m.ability_learned.get_connections().size() > 0,
		"CONTROL: the Combatant must really be connected before restore")

	State.restore(clean)
	assert_eq(AutogrindSystem._ability_learned_conns.size(), 0, "the connection record must be cleared")
	assert_eq(m.ability_learned.get_connections().size(), 0,
		"restore put the record back to empty and left the Combatant CONNECTED — the disarm path can no longer reach it")
