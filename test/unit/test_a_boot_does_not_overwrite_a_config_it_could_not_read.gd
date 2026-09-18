extends GutTest

## `load_config` handles every failure loudly (tick 167) and then RETURNS, leaving the in-memory
## fields at their defaults. That is safe for exactly one reason: nothing on the boot path saves.
##
##     _ready:186  custom_bindings = PROFILE_STANDARD.duplicate(true)
##          :188  load_config()                       <- may fail and warn
##          :190  apply_profile(active_profile)   OR
##          :191  _autodetect_and_apply()
##
## ⛔ IF ANY OF THOSE SAVED, A CONFIG THAT MERELY FAILED TO PARSE WOULD BE OVERWRITTEN WITH DEFAULTS
## THE INSTANT THE GAME STARTED — before the player could be told, and destroying the only copy of
## bindings that a text editor could still have rescued. Unreadable is not absent.
##
## 📌 THIS PINS A CLAIM I PUBLISHED IN A COMMIT MESSAGE AND NOWHERE ELSE. The four `save_config()`
## call sites are `set_nintendo_mode`, `set_custom_binding`, `reset_custom_to_preset` and
## `cycle_profile` — all deliberate player actions. That is true today and nothing enforced it, so
## adding a save to `apply_profile` for any good reason would silently convert a warned-about
## failure into permanent data loss.
##
## ⚠️ SCOPE: this walks the call graph INSIDE InputProfileManager.gd from `_ready`, to a fixed depth.
## A boot-path save reached through another autoload is out of scope and this arm does not claim it.

const SUBJECT := "res://src/input/InputProfileManager.gd"
const DEPTH := 3


func _source() -> PackedStringArray:
	var f := FileAccess.open(SUBJECT, FileAccess.READ)
	assert_not_null(f, "CONTROL: the subject must be readable")
	var out: PackedStringArray = f.get_as_text().split("\n")
	f.close()
	return out


## The body of `name`, or "" when the file declares no such function.
func _body(lines: PackedStringArray, fname: String) -> String:
	var start: int = -1
	for i in lines.size():
		if str(lines[i]).begins_with("func %s(" % fname):
			start = i
			break
	if start < 0:
		return ""
	var out: String = ""
	for i in range(start + 1, lines.size()):
		if str(lines[i]).begins_with("func "):
			break
		## ⛔ STRIP COMMENTS, OR A COMMENTED-OUT CALL COUNTS AS A CALL. Measured: commenting the known
		## `save_config()` in `set_nintendo_mode` left the control below GREEN, so the one arm whose
		## job is proving this detector can SEE a save could not tell the difference between seeing
		## one and reading prose about one.
		var code: String = str(lines[i])
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		out += code + "\n"
	return out


## Functions this file calls from `body`, self-calls only — `foo(` at the start of a statement or
## after `await`, which is how this file invokes its own methods.
func _callees(lines: PackedStringArray, body: String) -> Array:
	var declared: Array = []
	for l in lines:
		var s := str(l)
		if s.begins_with("func "):
			declared.append(s.substr(5, s.find("(") - 5))
	var hit: Array = []
	for d in declared:
		if ("%s(" % d) in body:
			hit.append(d)
	return hit


## Everything reachable from `_ready` within DEPTH hops, inside this file.
func _boot_reachable() -> Array:
	var lines: PackedStringArray = _source()
	var seen: Array = ["_ready"]
	var frontier: Array = ["_ready"]
	for _hop in DEPTH:
		var next: Array = []
		for fname in frontier:
			for c in _callees(lines, _body(lines, fname)):
				if not (c in seen):
					seen.append(c)
					next.append(c)
		frontier = next
	return seen


## ⛔ THE CONTROL, and it comes first: if the walk resolves nothing, "no boot function saves" is
## vacuously true. `_ready` must actually reach `load_config` — the function whose failure this
## whole invariant is about.
func test_the_boot_path_resolves() -> void:
	var reach: Array = _boot_reachable()
	assert_true("load_config" in reach,
		"CONTROL: the walk must reach load_config from _ready, got %s" % [reach])
	assert_gt(reach.size(), 3, "CONTROL: _ready reaches several functions, found %d" % reach.size())
	var lines: PackedStringArray = _source()
	assert_true("save_config" in _callees(lines, _body(lines, "set_nintendo_mode")),
		"CONTROL: the detector must SEE a real save — set_nintendo_mode is known to call save_config")


## ⛔ THE INVARIANT.
func test_nothing_on_the_boot_path_writes_the_config() -> void:
	var lines: PackedStringArray = _source()
	var savers: Array = []
	for fname in _boot_reachable():
		if fname == "save_config":
			continue
		if "save_config(" in _body(lines, fname):
			savers.append(fname)
	assert_true(savers.is_empty(),
		"%s run during _ready and call save_config(). `load_config` warns and returns on a corrupt " % [savers]
		+ "file, leaving defaults in memory — so a save on the boot path would overwrite a config "
		+ "that merely failed to PARSE with defaults, before the player ever saw the warning. "
		+ "Unreadable is not absent: those bytes are still the only copy of their bindings.")
