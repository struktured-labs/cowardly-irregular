extends GutTest

## Regression for the .746 pre-gate red (2026-10-30): the render smoke ran beside struktured's own game,
## found his 8BitDo ("[GamepadFilter] Found controller 0"), and his presses opened the field menu and
## changed the party leader mid-leg, so the roamer touch landed with a menu open and never triggered.
## The suite has hidden host pads since run_tests.sh's PAD_JAIL; the smoke commands never did.
## Derived, not listed: every command under tools/ passing a smoke flag must expand a jail array defined
## in the SAME file with an empty /dev/input. Keyed on the FLAG, not on `godot`: deploy_desktop.sh runs
## the exported binary (and wine), which a godot-keyed predicate passed over (@cowir-adhoc, 20036). And on
## ANY windowed launch: the shot tools (shot_sandbox.sh, sourced by 13) were outside a smoke-flag rule (20273).

const ROOTS := ["res://tools", "res://tools/fold_gate"]
const JAIL := "--tmpfs /dev/input"
var _smoke_re := RegEx.new()
var _array_re := RegEx.new()
var _launch_re := RegEx.new()


func before_all() -> void:
	_smoke_re.compile("--(render|battle)-smoke")
	## A windowed launch of the game: xvfb-run, then godot, the exported $BIN, or wine.
	_launch_re.compile("xvfb-run\\b.*(\\bgodot\\b|\\$BIN\\b|\\bwine\\b)")
	_array_re.compile("\"\\$\\{(\\w+)\\[@\\]\\}\"")


func _smoke_lines() -> Array:
	var out: Array = []
	for root in ROOTS:
		for f in DirAccess.get_files_at(root):
			if not (f.ends_with(".sh") or f.ends_with(".tmpl")):
				continue
			var path: String = root.path_join(f)
			var src := FileAccess.get_file_as_string(path)
			var rows: PackedStringArray = src.split("\n")
			for i in range(rows.size()):
				var t: String = rows[i].strip_edges()
				if t.begins_with("#") or t.begins_with("command -v"):
					continue
				if _smoke_re.search(t) == null and _launch_re.search(_joined(rows, i)) == null:
					continue
				## A launch split over rows is reported once, at the row that runs xvfb-run.
				if _smoke_re.search(t) == null and not t.contains("xvfb-run"):
					continue
				## A command split with `\` is one command: the jail can sit on an earlier row.
				var j: int = i
				while j > 0 and rows[j - 1].strip_edges().ends_with("\\"):
					j -= 1
					t = rows[j].strip_edges() + " " + t
				out.append({"path": path, "line": i + 1, "text": t, "src": src})
	return out


func _joined(rows: PackedStringArray, i: int) -> String:
	var t: String = rows[i].strip_edges()
	var j: int = i
	while j + 1 < rows.size() and rows[j].strip_edges().ends_with("\\"):
		j += 1
		t += " " + rows[j].strip_edges()
	return t


func _jailed(entry: Dictionary) -> bool:
	if entry.text.contains(JAIL):
		return true
	for m in _array_re.search_all(entry.text):
		for def in entry.src.split("\n"):
			if def.contains(m.get_string(1) + "=(") and def.contains(JAIL):
				return true
	return false


func test_the_derivation_finds_the_smoke_commands() -> void:
	## Floor: the fold chain, both deploy smokes and the shared screenshot launcher all launch today.
	var paths := {}
	for e in _smoke_lines():
		paths[e.path] = true
	assert_true(paths.has("res://tools/deploy_web.sh"), "the derivation no longer sees deploy_web.sh's smoke — it would pass by measuring nothing: %s" % str(paths.keys()))
	assert_true(paths.has("res://tools/fold_gate/chain.sh.tmpl"), "the derivation no longer sees the fold chain's smoke: %s" % str(paths.keys()))
	assert_true(paths.has("res://tools/deploy_desktop.sh"), "the derivation no longer sees the desktop battle smoke, which runs the exported binary rather than godot: %s" % str(paths.keys()))
	assert_true(paths.has("res://tools/shot_sandbox.sh"), "the derivation no longer sees the shared screenshot launcher, which 13 shot tools source: %s" % str(paths.keys()))


func test_every_smoke_launch_hides_the_host_pads() -> void:
	var lines := _smoke_lines()
	assert_gt(lines.size(), 7, "fewer windowed launches derived than the eight on main today (4 smoke + 4 shot)")
	for e in lines:
		assert_true(_jailed(e), "%s:%d launches the smoke without an empty /dev/input, so a pad he is holding drives it:\n%s" % [e.path, e.line, e.text])


func test_an_unjailed_launch_is_refused() -> void:
	## Control: the predicate must red the pre-fix form, or the arm above cannot fail.
	var bare := {"path": "x", "line": 1, "src": "", "text": "XDG_DATA_HOME=$S xvfb-run -a timeout 300 godot -- --render-smoke"}
	assert_false(_jailed(bare), "the jail predicate passed the exact .746 command line")
	var wrong := {"path": "x", "line": 1, "src": "SJ=(env FOO=1)\n", "text": "\"${SJ[@]}\" xvfb-run godot -- --render-smoke"}
	assert_true(_launch_re.search("XDG_DATA_HOME=$X xvfb-run -a godot -s tool.gd") != null, "CONTROL: a bare shot launch is not recognised as a launch, so the derivation would skip it")
	assert_false(_jailed(wrong), "an array that is not a jail satisfied the predicate")
