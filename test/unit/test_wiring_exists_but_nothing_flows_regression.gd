extends GutTest

## THE WIRING EXISTS AND NOTHING FLOWS THROUGH IT.
##
## 2026-09-09 produced this shape three times in three lanes, twice as a live bug:
##   BestiarySystem   never an autoload; seven get_node_or_null sites returned null forever,
##                    each taking a plausible fallback. Field elites spawned with duplicates
##                    and every monster's level read 1, for two shipped releases.
##   is_mode7()       looked for Mode7Overlay as a DIRECT CHILD OF ROOT; setup() parents it
##                    to the scene. False in every world for ten weeks, and it was itself the
##                    replacement for a detector the 2026-07-18 audit killed for the same
##                    reason. Six consumers used flat geometry under Mode-7 sprites.
##
## Both were CONNECTED. Both looked wired at every call site. Neither errored or logged,
## because a null lookup returning "no" is indistinguishable from a real "no".
##
## This file is mechanical and cross-cutting on purpose: it asks, of the two wiring
## mechanisms a Godot project has, whether the thing being addressed actually exists.
##
##   ARM 1  every /root/Name looked up in src/ is a registered autoload
##   ARM 2  every signal something CONNECTS to has at least one emitter
##
## ⚠️ WHAT IT CANNOT DO, stated so a green run is not over-read: it proves the address
## resolves, never that the VALUE is right. is_mode7() would pass ARM 1 today and did not
## need to — its bug was a correct lookup of a node parented elsewhere, which no name check
## reaches. Address-exists and value-correct are different instruments; this is the cheaper
## one and it is not the important one.

const SRC := "res://src"
const PROJECT := "res://project.godot"

## Signals that are declared and connected but never emitted. Every entry is DEBT.
## interrupt_triggered has a live listener in AutogrindUI (_on_interrupt_triggered, which
## would log "INTERRUPT: <reason>" and stop the grind display) that has never once run.
## NOT player-facing: the stop reason reaches the player through grind_complete instead —
## _play_grind_stop_sfx, _show_grind_stop_notification and _show_autogrind_summary all
## receive it. So this is a redundant path, not a silent failure. It is listed rather than
## deleted because deleting another lane's handler is their call, not mine.
const KNOWN_UNEMITTED_WITH_LISTENERS: Array[String] = [
	"interrupt_triggered",
]


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "could not read %s — arms depending on it would pass vacuously" % path)
	return text


## Every .gd under src/, recursively.
func _src_files() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [SRC]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full := dir_path + "/" + name
			if d.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd"):
				out.append(full)
			name = d.get_next()
		d.list_dir_end()
	return out


func _registered_autoloads() -> Array[String]:
	var out: Array[String] = []
	var in_section := false
	for raw in _read(PROJECT).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			in_section = line == "[autoload]"
			continue
		if not in_section or line == "" or line.begins_with(";"):
			continue
		var eq := line.find("=")
		if eq > 0:
			out.append(line.substr(0, eq).strip_edges())
	return out


## Names addressed as an autoload, in BOTH syntaxes. The prefixless form is the one that
## matters: BestiarySystem and Mode7Overlay were both written as
## `root.get_node_or_null("Name")`, and a sweep for the literal "/root/Name" finds neither.
func _addressed_names(files: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	var prefixed := RegEx.create_from_string('"/root/([A-Za-z_][A-Za-z_0-9]*)"')
	var bare := RegEx.create_from_string('root\\.get_node(?:_or_null)?\\("([A-Za-z_][A-Za-z_0-9]*)"\\)')
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		for line in text.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for rx in [prefixed, bare]:
				for m in rx.search_all(line):
					var n: String = m.get_string(1)
					if not out.has(n):
						out[n] = path.get_file()
	return out


func test_every_autoload_lookup_addresses_a_registered_autoload() -> void:
	var files := _src_files()
	assert_gt(files.size(), 100,
		"walked only %d .gd files under src/ — the sweep below would be near-vacuous" % files.size())
	var registered := _registered_autoloads()
	assert_gt(registered.size(), 10,
		"parsed only %d autoloads from project.godot — every name would look unregistered" % registered.size())

	var addressed := _addressed_names(files)
	assert_gt(addressed.size(), 10,
		"found only %d addressed names — the regexes are not matching the real call shapes" % addressed.size())

	var unregistered: Array[String] = []
	for n in addressed.keys():
		# GameLoop is the main scene's ROOT NODE (GameLoop.tscn), so /root/GameLoop
		# resolves at runtime without being an autoload. Named, not pattern-matched.
		if str(n) == "GameLoop":
			continue
		if not registered.has(str(n)):
			unregistered.append("%s (in %s)" % [n, addressed[n]])
	unregistered.sort()
	assert_eq(unregistered.size(), 0,
		"addressed as an autoload but not registered in project.godot, so the lookup returns null forever: %s" % ", ".join(unregistered))


## The control that makes the zero above a reading. A fabricated name proves the regex runs;
## it does NOT prove the regex finds what exists. This seeds a name known to be present in
## BOTH sets — the discipline that separated a working sweep from a blind one today.
func test_the_autoload_sweep_can_find_a_known_member() -> void:
	var addressed := _addressed_names(_src_files())
	assert_true(addressed.has("SoundManager"),
		"SoundManager is looked up all over src/ and the sweep did not see it — the address regexes are broken, so any empty offender list above is not a reading")
	assert_true(_registered_autoloads().has("SoundManager"),
		"SoundManager is not in project.godot's [autoload] — the parser is reading the wrong section")
	assert_false(addressed.has("ZzqNotAnAutoloadName"),
		"the sweep matched a name that appears nowhere — the regex is over-broad")


func test_every_connected_signal_has_an_emitter() -> void:
	var files := _src_files()
	# THE CORPUS IS THE ANSWER — @cowir-battle, 2026-09-09, and this guard failed it on the
	# first run. Checking "connected but not emitted in src/" flagged 19 names, every one a
	# BUILT-IN Godot signal: pressed, timeout, body_entered, draw, resized. The engine is
	# their emitter, so it sits outside the corpus BY CONSTRUCTION and they can never look
	# emitted however healthy they are. The DEFINER set has to be project-declared signals;
	# only those have their emitter inside the corpus being searched.
	var declared: Dictionary = {}
	var decl_rx := RegEx.create_from_string('^signal\\s+([a-z_][a-z_0-9]*)')
	for path in files:
		var src_text := FileAccess.get_file_as_string(path)
		if src_text == "":
			continue
		for line in src_text.split("\n"):
			for dm in decl_rx.search_all(line):
				declared[dm.get_string(1)] = true

	var connected: Dictionary = {}
	var emitted: Dictionary = {}
	var conn_rx := RegEx.create_from_string('([a-z_][a-z_0-9]*)\\.connect\\(')
	var emit_rx := RegEx.create_from_string('([a-z_][a-z_0-9]*)\\.emit\\(|emit_signal\\("([a-z_][a-z_0-9]*)"')
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		for line in text.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m in conn_rx.search_all(line):
				connected[m.get_string(1)] = path.get_file()
			for m2 in emit_rx.search_all(line):
				var n: String = m2.get_string(1) if m2.get_string(1) != "" else m2.get_string(2)
				if n != "":
					emitted[n] = true

	assert_gt(declared.size(), 100,
		"found only %d signals DECLARED in src/ — the definer set is broken, so the disjointness this arm depends on does not hold" % declared.size())
	assert_gt(connected.size(), 20,
		"found only %d connected signal names — the connect regex is not matching" % connected.size())
	assert_gt(emitted.size(), 20,
		"found only %d emitted signal names — the emit regex is not matching, so everything would look unemitted" % emitted.size())

	var dead: Array[String] = []
	for n in connected.keys():
		var name := str(n)
		# Project-declared only. An engine signal's emitter is not in this corpus.
		if not declared.has(name):
			continue
		if emitted.has(name) or KNOWN_UNEMITTED_WITH_LISTENERS.has(name):
			continue
		dead.append("%s (connected in %s)" % [name, connected[n]])
	dead.sort()
	assert_eq(dead.size(), 0,
		"a listener is connected to a signal nothing emits — the wiring exists and nothing flows: %s" % ", ".join(dead))

	# Ratchet the other way: a known-dead entry that starts being emitted must leave the
	# list, or this file goes on claiming a path is dead after someone revived it.
	var revived: Array[String] = []
	for n in KNOWN_UNEMITTED_WITH_LISTENERS:
		if emitted.has(n):
			revived.append(n)
	assert_eq(revived.size(), 0,
		"GOOD NEWS, STALE LIST: %s now has an emitter. Remove it from KNOWN_UNEMITTED_WITH_LISTENERS." % ", ".join(revived))
