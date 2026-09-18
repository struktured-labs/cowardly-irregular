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
## ⛔ SEPARATE, because a static is NOT in get_property_list(). Reflection sees instance members
## only, so a subject with `static var`s reports CLEAN for every one of them — silently. Measured
## 2026-09-18: 3 of 30 autoloads declare statics, and SoundManager (6) is the one this file's own
## usage block advertises. A tool that names an example it cannot actually cover is worse than one
## that covers nothing.
var _static_baseline: Dictionary = {}
var _script: Variant = null
var _armed: bool = false
var _scripts_seen: int = 0      ## incremented on start_script
var _scripts_measured: int = 0  ## incremented on end_script — the one that proves a READING happened
var _dirty_files: int = 0


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
	## ⛔ BASELINE FROM THE LIVE AUTOLOAD AT ARM TIME, NOT FROM A FRESH INSTANCE. A pre-run hook runs
	## before any test script, so arm time IS the clean between-files state — which is the thing this
	## tool compares against. A `script.new()` baseline instead measures "differs from the DECLARED
	## default", and for any subject whose _ready() populates fields that is permanently non-zero:
	## measured on SoundManager, 16 AudioStreamPlayers and 3 dictionaries built in _ready() reported
	## as dirty on every single file, burying the one real finding in the same line. BattleManager
	## does not populate in _ready(), so the two agree there and the noise never showed up in my own
	## lane — which is exactly why a tool wants a second subject before it ships.
	## The property NAMES still come from reflection, so nothing is hand-listed.
	for prop in node.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = str(prop["name"])
		var v: Variant = node.get(n)
		_baseline[n] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	_script = script
	_arm_statics(script_path, script)
	if _baseline.is_empty() and _static_baseline.is_empty():
		print("LEAKPROBE FATAL: %s exposes no script variables — nothing to measure" % _autoload)
		return
	## ⛔ CONNECT BEFORE ANNOUNCING. This printed ARMED and then wired itself, so a renamed or removed
	## GUT signal left a reassuring banner above a hook that never fires — the probe would report a
	## CLEAN suite while measuring nothing. That is the exact failure this file exists to catch, in
	## the file itself. A banner is a claim about state; print it after the state is true.
	for sig in ["start_script", "end_script"]:
		if not gut.has_signal(sig):
			print("LEAKPROBE FATAL: GutMain has no signal `%s` — this hook cannot fire, and a silent "
					% sig + "pass here would read as a clean suite. Check the GUT version.")
			return
	gut.start_script.connect(_on_start)
	gut.end_script.connect(_on_end)
	## ⛔ ANCHOR THE NULL. This tool's PRODUCT is an absence — "no LEAK lines" is the answer a reader
	## acts on. Without a denominator, a run where end_script never fired prints ARMED and nothing
	## else, which is byte-identical to a clean suite. cowir-sfx, 2026-09-18, on a tool whose whole
	## output is a null: "a 0 from a blind instrument is indistinguishable from health."
	if gut.has_signal("end_run"):
		gut.end_run.connect(_on_end_run)
	if not gut.start_script.is_connected(_on_start) or not gut.end_script.is_connected(_on_end):
		print("LEAKPROBE FATAL: signals exist but the connection did not take — measuring nothing")
		return
	_armed = true
	print("LEAKPROBE ARMED %s fields=%d statics=%d" % [_autoload, _baseline.size(), _static_baseline.size()])


## Static names come from the SOURCE, because no reflection API lists them. Their value is then
## read off the SCRIPT object — `script.get(name)` works for statics (verified against
## SoundManager._sfx_manifest). The baseline is whatever they hold at arm time, not a pristine
## default: a static is process-wide, so there is no "fresh" state to compare against once the
## engine has booted. That makes this half a CONDUIT and the instance half a barrier, deliberately.
func _arm_statics(script_path: String, script: Variant) -> void:
	var src: String = FileAccess.get_file_as_string(script_path)
	if src == "":
		print("LEAKPROBE WARNING: could not read %s to enumerate statics — any `static var` on this subject is UNMEASURED" % script_path)
		return
	var re := RegEx.create_from_string("(?m)^static var ([A-Za-z_][A-Za-z0-9_]*)")
	for m in re.search_all(src):
		var n: String = m.get_string(1)
		var v: Variant = script.get(n)
		_static_baseline[n] = v.duplicate(true) if (v is Array or v is Dictionary) else v


func _target() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	return loop.root.get_node_or_null("/root/" + _autoload) if loop else null


## Printed at end of run so a zero is reportable rather than merely absent. `scripts=0` means the
## hook never fired and EVERY clean reading above it is vacuous — say so rather than leaving the
## reader to infer health from silence.
func _on_end_run() -> void:
	if not _armed:
		return
	## ⛔ COUNT THE MEASUREMENT, NOT THE ARRIVAL. `_scripts_seen` rises in start_script, so it keeps
	## counting even when end_script is dead — my first version reported `scripts=1 dirty=0` under a
	## mutation that measured NOTHING, which is the reassuring reading. The two counters must be
	## compared: a gap means scripts began and were never read.
	if _scripts_measured == 0:
		print("LEAKPROBE DONE %s started=%d MEASURED=0 — THE HOOK NEVER FIRED. This run measured "
				% [_autoload, _scripts_seen] + "nothing; a clean result above is vacuous, not healthy.")
		return
	if _scripts_measured != _scripts_seen:
		print("LEAKPROBE DONE %s started=%d MEASURED=%d dirty=%d — %d script(s) were never read, so "
				% [_autoload, _scripts_seen, _scripts_measured, _dirty_files, _scripts_seen - _scripts_measured]
				+ "this result is PARTIAL.")
		return
	print("LEAKPROBE DONE %s scripts=%d dirty=%d" % [_autoload, _scripts_measured, _dirty_files])


func _on_start(coll_script) -> void:
	_cur = str(coll_script.path).get_file()
	_scripts_seen += 1


func _on_end() -> void:
	if not _armed:
		return
	_scripts_measured += 1
	var node: Node = _target()
	if node == null:
		print("LEAK %s :: PROBE BROKEN — the autoload vanished mid-run" % _cur)
		return
	var diffs: PackedStringArray = PackedStringArray()
	for n in _baseline:
		var live_v: Variant = node.get(str(n))
		var base_v: Variant = _baseline[n]
		## Objects compare by reference, so the null/non-null transition is the only value signal —
		## but a FREED instance also reads non-null, and that is the case worth naming loudest. An
		## Array renders its dead members as `<Freed Object>`; a SCALAR Object field renders as
		## nothing at all, so without this arm a dangling `current_combatant` is invisible while the
		## same dangling instance inside `player_party` is not. Same defect, two spellings.
		if typeof(live_v) == TYPE_OBJECT or typeof(base_v) == TYPE_OBJECT:
			if live_v != null and not is_instance_valid(live_v):
				diffs.append("%s=<Freed Object>" % n)
			elif (live_v == null) != (base_v == null):
				diffs.append("%s=%s" % [n, "obj" if live_v != null else "null"])
			continue
		if live_v != base_v:
			var shown: String = str(live_v)
			if shown.length() > 70:
				shown = shown.substr(0, 70) + "..."
			diffs.append("%s=%s" % [n, shown])
	for n in _static_baseline:
		var live_s: Variant = _script.get(str(n))
		var base_s: Variant = _static_baseline[n]
		if typeof(live_s) == TYPE_OBJECT or typeof(base_s) == TYPE_OBJECT:
			if live_s != null and not is_instance_valid(live_s):
				diffs.append("static %s=<Freed Object>" % n)
			elif (live_s == null) != (base_s == null):
				diffs.append("static %s=%s" % [n, "obj" if live_s != null else "null"])
			continue
		if live_s != base_s:
			var shown_s: String = str(live_s)
			if shown_s.length() > 70:
				shown_s = shown_s.substr(0, 70) + "..."
			diffs.append("static %s=%s" % [n, shown_s])
	if not diffs.is_empty():
		_dirty_files += 1
		print("LEAK %s :: %d :: %s" % [_cur, diffs.size(), "; ".join(diffs)])
	_reset(node)
	_reset_statics()


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


func _reset_statics() -> void:
	for n in _static_baseline:
		var base_v: Variant = _static_baseline[n]
		_script.set(str(n), base_v.duplicate(true) if (base_v is Array or base_v is Dictionary) else base_v)
