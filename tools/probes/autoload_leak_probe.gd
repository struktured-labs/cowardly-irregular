extends GutHookScript

## PER-FILE autoload-leak probe. A GUT pre-run hook: it diffs a target autoload's script variables
## against an in-process baseline after EVERY test script, names the files that left it dirty, then
## resets so the next file is measured independently.
##
## 🔑 WHY PER-FILE AND NOT AT SUITE END. An end-of-suite zero and a clean corpus print the same zero,
## because a later file that restores masks an earlier file that leaked. Measured 2026-09-18 on
## BattleManager: `is_battle_active()` was false at suite end — the claim I had published — while
## test_bossbinder_control_regression left `current_state = PROCESSING_ACTION` for every file that
## followed it. The aggregate was TRUE and it hid a real offender. Decile probes have the same shape
## one level finer: they are aggregates at nine points.
##
## ⚠️ THE RESET IS A BARRIER, WHICH IS CORRECT HERE AND WRONG IN A SHIPPED TEARDOWN. It isolates each
## file, which is the whole point of the measurement; a teardown that restored declared defaults
## would silence whatever leaked upstream. Do not copy this half into a test — use
## test/unit/helpers/battle_state.gd, which restores the PRIOR value.
##
## ⛔ AND THE RUN'S PASS/FAIL IS NOT THE SUITE'S. Healing state between files can change what a test
## that (wrongly) depends on inherited state does. Read the BMLEAK lines; take Totals from a normal run.
##
## Usage:
##   XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy \
##     -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit \
##     -gpre_run_script=res://tools/probes/autoload_leak_probe.gd > tmp/leaks.log 2>&1
##   command grep -a LEAK tmp/leaks.log
##
## Point it at another autoload with two env vars (defaults are BattleManager):
##   LEAK_PROBE_AUTOLOAD=SoundManager LEAK_PROBE_SCRIPT=res://src/audio/SoundManager.gd

const DEFAULT_AUTOLOAD := "BattleManager"
const DEFAULT_SCRIPT := "res://src/battle/BattleManager.gd"

var _autoload: String = ""
var _cur: String = ""
var _baseline: Dictionary = {}
var _armed: bool = false


func run() -> void:
	_autoload = OS.get_environment("LEAK_PROBE_AUTOLOAD")
	if _autoload == "":
		_autoload = DEFAULT_AUTOLOAD
	var script_path: String = OS.get_environment("LEAK_PROBE_SCRIPT")
	if script_path == "":
		script_path = DEFAULT_SCRIPT
	var node: Node = _target()
	## ⛔ A BROKEN PROBE MUST NOT READ AS A CLEAN TREE. Every line below is a report of ABSENCE, and
	## absence is also what a probe that never armed produces. Say so loudly instead.
	if node == null:
		print("LEAKPROBE FATAL: no /root/%s autoload — every reading below would be a lie" % _autoload)
		return
	var script: Variant = load(script_path)
	if script == null:
		print("LEAKPROBE FATAL: could not load %s for an in-process baseline" % script_path)
		return
	## In-process, never a hand-written default list: a literal baseline drifts from the code the
	## first time someone changes an initializer, and drifts silently in the clean direction.
	var fresh: Node = script.new()
	for prop in fresh.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = str(prop["name"])
		var v: Variant = fresh.get(n)
		_baseline[n] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	fresh.free()
	if _baseline.is_empty():
		print("LEAKPROBE FATAL: %s exposes no script variables — nothing to measure" % _autoload)
		return
	_armed = true
	print("LEAKPROBE ARMED %s fields=%d" % [_autoload, _baseline.size()])
	gut.start_script.connect(_on_start)
	gut.end_script.connect(_on_end)


func _target() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	return loop.root.get_node_or_null("/root/" + _autoload) if loop else null


func _on_start(coll_script) -> void:
	_cur = str(coll_script.path).get_file()


func _on_end() -> void:
	if not _armed:
		return
	var node: Node = _target()
	if node == null:
		print("LEAK %s :: PROBE BROKEN — the autoload vanished mid-run" % _cur)
		return
	var diffs: PackedStringArray = PackedStringArray()
	for n in _baseline:
		var live_v: Variant = node.get(str(n))
		var base_v: Variant = _baseline[n]
		## Objects compare by reference, so only the null/non-null transition is meaningful — and a
		## FREED instance still reads non-null here, which is exactly the case worth naming.
		if typeof(live_v) == TYPE_OBJECT or typeof(base_v) == TYPE_OBJECT:
			if (live_v == null) != (base_v == null):
				diffs.append("%s=%s" % [n, "obj" if live_v != null else "null"])
			continue
		if live_v != base_v:
			var shown: String = str(live_v)
			if shown.length() > 70:
				shown = shown.substr(0, 70) + "..."
			diffs.append("%s=%s" % [n, shown])
	if not diffs.is_empty():
		print("LEAK %s :: %d :: %s" % [_cur, diffs.size(), "; ".join(diffs)])
	_reset(node)


func _reset(node: Node) -> void:
	if node.has_method("_cleanup_battle") and node.get("current_state") != null \
			and int(node.current_state) != 0:
		node._cleanup_battle()
	for n in _baseline:
		var base_v: Variant = _baseline[n]
		## ⛔ TYPED ARRAYS GO BACK THROUGH assign(). Assigning a plain Array to an Array[Combatant]
		## property is a script error that ABORTS this function, after which every later field is
		## silently never restored and the NEXT file inherits the difference and gets blamed for it.
		if base_v is Array:
			var live: Variant = node.get(str(n))
			if live is Array:
				live.assign(base_v)
				continue
		## ⛔ DEEP, NOT SHALLOW. One BattleManager field defaults to {"boost": [], "reduce": []};
		## handing the baseline's own inner Arrays to the live dict would let the next file mutate the
		## BASELINE in place, after which every later file reads clean for that field. A probe that
		## its own subject can silently disarm is worse than no probe.
		if base_v is Dictionary:
			var lived: Variant = node.get(str(n))
			if lived is Dictionary:
				lived.clear()
				for k in base_v:
					var bv: Variant = base_v[k]
					lived[k] = bv.duplicate(true) if (bv is Array or bv is Dictionary) else bv
				continue
		node.set(str(n), base_v)
