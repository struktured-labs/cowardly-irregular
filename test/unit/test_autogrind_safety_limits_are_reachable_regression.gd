extends GutTest

## AutogrindSystem has enforced five interrupt rules since it shipped — hp_threshold, party_death,
## item_depleted, corruption_limit, max_battles — and NO src/ui/ file ever set one. Measured before
## this fix: all five keys occurred only in AutogrindSystem.gd, at their own declaration and at the
## _check_interrupt_conditions read. So "configurable interrupt rules" was true of start_autogrind's
## config dict and false of the player, which is the shape CLAUDE.md's own autogrind section flags.
##
## ⛔ THE ARM THAT MATTERS IS THE END-TO-END ONE. A test that sets console state and reads the
## console's own config dict back proves a dictionary literal works. The question is whether the
## value reaches the SYSTEM through the real merge, so that arm calls start_autogrind and reads
## AutogrindSystem.interrupt_rules — the same field _check_interrupt_conditions reads.
##
## corruption_limit is deliberately NOT exposed: it gates system collapse, and raising it is a
## stakes ruling for struktured. Its survival through a four-key merge is arm 3.

var _ui
var _sys

const DEFAULTS := {"hp_threshold": 20.0, "party_death": true, "item_depleted": true, "max_battles": 100}


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem
	_sys.set_interrupt_rules(DEFAULTS)
	_sys.interrupt_rules["corruption_limit"] = 4.5
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)


func after_each() -> void:
	## ⚠️ HERE, not at the end of the arms that start a grind — AutogrindSystem is an autoload, so a
	## session left grinding makes the next arm's start_autogrind a refused double-start.
	## ⛔ NOT because a failing assert truncates the cleanup: MEASURED, a failed GUT assert records
	## and CONTINUES (no exceptions in GDScript), so an in-body stop_autogrind does still run. I
	## predicted Failing 2 for that cascade and got Failing 1, which is how the wrong reason surfaced.
	## The reasons that hold: a runtime ERROR does abort the enclosing function (the typed-array class
	## in CLAUDE.md), and after_each covers arms added later that start a grind and forget to stop.
	## Early-returns when idle, so it is safe to call unconditionally.
	_sys.stop_autogrind()
	AutogrindSystem._test_disable_persistence = false
	_sys.set_interrupt_rules(DEFAULTS)


## Combatant.new() takes no args — initialize() carries the stats (the idiom in test_autogrind.gd).
func _probe_party() -> Array[Combatant]:
	var c := Combatant.new()
	c.initialize({"name": "Probe", "max_hp": 100, "max_mp": 50, "attack": 20, "defense": 15, "magic": 10, "speed": 12})
	add_child_autofree(c)
	var party: Array[Combatant] = [c]
	return party


## Arm 1: a player cycling the dial moves the value the ENFORCER reads, with no grind in between.
## _cycle_safety applies immediately on purpose — someone who sets a limit and closes the console
## without grinding still expects it to have taken.
func test_cycling_a_safety_dial_moves_what_the_enforcer_reads() -> void:
	var before: float = float(_sys.interrupt_rules["hp_threshold"])
	_ui._cycle_safety("hp")
	var after: float = float(_sys.interrupt_rules["hp_threshold"])
	gut.p("  hp_threshold  %s -> %s" % [before, after])
	assert_ne(after, before,
		"cycling the HP dial left the system's own hp_threshold at %s — the console is not reaching the enforcer" % before)
	assert_true(_ui.SAFETY_HP_LADDER.has(after),
		"hp_threshold became %s, which is not a rung on SAFETY_HP_LADDER %s" % [after, _ui.SAFETY_HP_LADDER])

	var b2: int = int(_sys.interrupt_rules["max_battles"])
	_ui._cycle_safety("battles")
	assert_ne(int(_sys.interrupt_rules["max_battles"]), b2,
		"cycling the battle-cap dial left max_battles at %d" % b2)
	for key in ["death", "items"]:
		var field: String = "party_death" if key == "death" else "item_depleted"
		var was: bool = bool(_sys.interrupt_rules[field])
		_ui._cycle_safety(key)
		assert_eq(bool(_sys.interrupt_rules[field]), not was,
			"toggling '%s' did not flip %s" % [key, field])


## Arm 2: every rung is reachable by repeating ONE input. A ring has no text entry, so a dial that
## does not wrap makes the bottom of its own ladder unreachable.
func test_every_rung_is_reachable_by_repeating_one_input() -> void:
	for spec in [["hp", "hp_threshold", _ui.SAFETY_HP_LADDER], ["battles", "max_battles", _ui.SAFETY_BATTLE_LADDER]]:
		var seen := {}
		for _i in range(spec[2].size() * 2):
			_ui._cycle_safety(spec[0])
			seen[_sys.interrupt_rules[spec[1]]] = true
		gut.p("  %-8s reached %d of %d rungs" % [spec[0], seen.size(), spec[2].size()])
		assert_eq(seen.size(), spec[2].size(),
			"'%s' reached %d of %d rungs in two full passes — the dial does not wrap: %s" % [
				spec[0], seen.size(), spec[2].size(), seen.keys()])


## Arm 3: THE END-TO-END ONE. The console's config must carry the choices through start_autogrind's
## real merge, and corruption_limit — which the console never names — must survive it.
func test_the_config_carries_the_choices_through_the_real_merge() -> void:
	_ui._safety_hp_threshold = 50.0
	_ui._safety_max_battles = 25
	_ui._safety_stop_on_death = false
	_ui._safety_stop_on_item_depleted = false
	_sys.interrupt_rules["corruption_limit"] = 4.5

	var cfg: Dictionary = _ui._get_grind_config()
	assert_true(cfg.has("interrupt_rules"),
		"the console's grind config carries no interrupt_rules key — nothing the player set can reach the system")

	var party := _probe_party()
	assert_true(_sys.start_autogrind(party, {}, cfg), "CONTROL: the probe grind must actually start")
	gut.p("  after merge  %s" % _sys.interrupt_rules)

	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 50.0, "hp_threshold did not survive the merge")
	assert_eq(int(_sys.interrupt_rules["max_battles"]), 25, "max_battles did not survive the merge")
	assert_false(bool(_sys.interrupt_rules["party_death"]), "party_death did not survive the merge")
	assert_false(bool(_sys.interrupt_rules["item_depleted"]), "item_depleted did not survive the merge")
	## The console names FOUR of five. A wholesale assign would drop this one and the collapse gate
	## would stop firing silently, because the read site's .get() fallback is 999.0.
	assert_eq(float(_sys.interrupt_rules["corruption_limit"]), 4.5,
		"corruption_limit was dropped by a four-key merge — the collapse gate now falls back to 999.0 and never fires")


## Arm 4: the clamps. Both bounds exist because an out-of-range write produces a net that never
## fires, which on screen is indistinguishable from a net the player switched off.
func test_the_setter_clamps_rather_than_storing_a_net_that_cannot_fire() -> void:
	_sys.set_interrupt_rules({"max_battles": 0})
	assert_eq(int(_sys.interrupt_rules["max_battles"]), 1,
		"max_battles 0 was stored — battles_completed >= 0 is true before the first battle, so the grind stops instantly and the start button looks broken")
	_sys.set_interrupt_rules({"hp_threshold": 500.0})
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 100.0, "hp_threshold above 100% was stored unclamped")
	_sys.set_interrupt_rules({"hp_threshold": -5.0})
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 0.0, "a negative hp_threshold was stored unclamped")

	## An unknown key must not silently become a rule nothing enforces.
	var before: int = _sys.interrupt_rules.size()
	_sys.set_interrupt_rules({"stop_on_tuesday": true})
	assert_eq(_sys.interrupt_rules.size(), before,
		"an unknown key was added to interrupt_rules — nothing reads it, so it reads as a configured rule that does nothing")


## Arm 5: the readout reports the SYSTEM, not the console's own copy. A label sourced from console
## state agrees with itself even when the two have drifted, so it could never show a drift.
func test_the_readout_reports_the_system_not_the_consoles_own_copy() -> void:
	_ui._safety_hp_threshold = 30.0
	_sys.set_interrupt_rules({"hp_threshold": 10.0})
	assert_eq(_ui._safety_label("hp"), "10%",
		"the label read the console's 30%% while the enforcer holds 10%% — a readout that cannot disagree cannot warn")
	_sys.set_interrupt_rules({"hp_threshold": 0.0})
	assert_eq(_ui._safety_label("hp"), "OFF",
		"hp_threshold 0 is the documented off value (the check is `if hp_threshold > 0`) and must read OFF, not 0%%")


## Arm 6: the ring must actually offer them, and each id must be dispatched. An entry with no arm is
## a row that highlights, plays the select sound, and does nothing.
func test_the_options_ring_offers_every_safety_dial_and_dispatches_it() -> void:
	var ids: Array = []
	for o in _ui._options_ring_spec()["options"]:
		ids.append(o["id"])
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	var handler: String = src.substr(src.find("func _commit_autogrind_option"), 4000)
	for want in ["safety_hp", "safety_battles", "safety_death", "safety_items"]:
		assert_true(ids.has(want), "the options ring does not offer '%s'" % want)
		assert_true(handler.contains('"%s":' % want),
			"'%s' is offered by the ring but _commit_autogrind_option has no arm for it — the row does nothing" % want)


## Arm 7: a dial must refuse mid-grind rather than change the rules under a running session.
func test_a_dial_refuses_while_grinding() -> void:
	var party := _probe_party()
	assert_true(_sys.start_autogrind(party, {}, {}), "CONTROL: the probe grind must start")
	_ui._is_grinding = true
	var before: float = float(_sys.interrupt_rules["hp_threshold"])
	_ui._cycle_safety("hp")
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), before,
		"a safety dial moved mid-grind — the session's own stop conditions changed underneath it")
	_ui._is_grinding = false

## Arm 8: A RESUMED GRIND MUST KEEP THE LIMITS THE PLAYER SET, and it does so through a path that
## already existed — which is the reason these settings live in the emitted config rather than being
## poked into interrupt_rules directly. AutogrindController.serialize_snapshot stores
## `"config": _config.duplicate(true)`, and GameLoop._resume_autogrind feeds that same config back to
## _start_autogrind, so start_autogrind's merge re-applies them. Nothing was added for this.
##
## ⛔ THE STEP THIS ARM EXISTS FOR IS THE JSON ROUND-TRIP. The snapshot is written to
## user://autogrind_snapshot.json, and JSON.parse returns FLOATS where live state held ints — the
## same class CLAUDE.md documents for typed arrays. max_battles is an int and `battles_completed >=
## 25.0` still works, but the readout would print "25.0 battles" and interrupt_rules would carry a
## float where every other writer puts an int. So this walks the real lossy step, not a duplicate().
func test_the_limits_survive_the_snapshot_json_round_trip() -> void:
	_ui._safety_hp_threshold = 50.0
	_ui._safety_max_battles = 25
	_ui._safety_stop_on_death = false
	var cfg: Dictionary = _ui._get_grind_config()

	## Exactly what save_grind_snapshot + load_grind_snapshot do to it.
	var wire: String = JSON.stringify({"controller": {"config": cfg}})
	var back: Dictionary = JSON.parse_string(wire)
	var resumed: Dictionary = back["controller"]["config"]
	gut.p("  max_battles over the wire: %s (%s)" % [
		resumed["interrupt_rules"]["max_battles"],
		type_string(typeof(resumed["interrupt_rules"]["max_battles"]))])

	## Simulate the fresh session the snapshot exists for: the autoload is back at its defaults.
	_sys.set_interrupt_rules(DEFAULTS)
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 20.0,
		"CONTROL: the fresh-session default must differ from the 50.0 the player set, or this passes vacuously")

	var party := _probe_party()
	assert_true(_sys.start_autogrind(party, {}, resumed), "CONTROL: the resumed grind must start")

	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 50.0,
		"a resumed grind lost the HP limit the player set — it reverted to the shipped default silently")
	assert_false(bool(_sys.interrupt_rules["party_death"]),
		"a resumed grind re-enabled stop-on-death after the player turned it off")
	## The type, not just the value: JSON hands back 25.0, and set_interrupt_rules' int() is what
	## keeps interrupt_rules holding the same type every other writer puts there.
	assert_eq(int(_sys.interrupt_rules["max_battles"]), 25, "a resumed grind lost the battle cap")
	assert_eq(typeof(_sys.interrupt_rules["max_battles"]), TYPE_INT,
		"max_battles came back from JSON as %s — int() in set_interrupt_rules is what normalises it" % type_string(typeof(_sys.interrupt_rules["max_battles"])))
