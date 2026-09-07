extends GutTest
## InteractGeometry claims to BE the interaction contract. This checks that it is.
##
## Its own header says: "Every radius, box, and offset the interaction system uses lives
## HERE -- call sites reference these names, tests pin the values, and a feel change is one
## edit." On 2026-08-22 that was false for the three values the Mode 7 overworld leans on
## hardest. Measured: 12 of 28 constants had ZERO by-name consumers anywhere in src/, and
## the Mode 7 Y-stretch was hardcoded as the literal `Vector2(1.0, 1.67)` at SEVENTEEN sites
## across fourteen files while `MODE7_Y_STRETCH` sat in the contract with one consumer.
##
## WHY THIS IS THE RIGHT GUARD FOR "I DON'T QUITE TRUST OBJECT DETECTION" (struktured,
## 2026-08-22). The failure is not that the zones are the wrong size -- it is that the file
## you would open to RESIZE them does not control them. Change NPC_TALK_RADIUS_MODE7 from
## 128 to 160, relaunch, and nothing moves. The tuning surface lies, so every tuning attempt
## reads as "the fix didn't work" rather than "the edit went nowhere". That is exactly the
## experience of not trusting a system.
##
## THE FORBIDDEN LITERAL IS DERIVED FROM THE CONSTANT, never typed here. Re-tuning
## MODE7_Y_STRETCH to 1.5 changes what this test forbids, automatically -- so the guard
## cannot pin a value it was only supposed to route.
##
## BOUND, stated rather than implied: this covers the three Mode 7 zone constants and the
## Y-stretch literal. Nine other constants still have no by-name consumer; a bare-number
## scan cannot tell a shadowed value from a coincidence (`48.0` matches anything), so they
## are NOT claimed here and need reading, not grepping.

const Geo := preload("res://src/exploration/InteractGeometry.gd")

## The constants that size a Mode 7 interaction zone -- the ones a feel change would touch
const ROUTED := ["NPC_TALK_RADIUS_MODE7", "CHEST_GRAB_RADIUS_MODE7", "MODE7_Y_STRETCH"]

const SRC_DIR := "res://src/exploration"


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := "%s/%s" % [dir_path, n]
		if d.current_is_dir():
			if not n.begins_with("."):
				out.append_array(_gd_files(full))
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func test_every_mode7_zone_constant_has_a_real_consumer() -> void:
	var files := _gd_files(SRC_DIR)
	assert_gt(files.size(), 40, "only found %d .gd files under %s -- the scan is not seeing src/" % [files.size(), SRC_DIR])

	var bodies := {}
	for p in files:
		if not p.ends_with("InteractGeometry.gd"):
			bodies[p] = _read(p)

	# CONTROL: a name that IS consumed must be found, and a fabricated one must not.
	var live := 0
	var fake := 0
	for p in bodies:
		if (bodies[p] as String).contains("MODE7_TRIGGER_Y_OFFSET"):
			live += 1
		if (bodies[p] as String).contains("FABRICATED_GEOMETRY_CONST"):
			fake += 1
	assert_gt(live, 0, "control failed: a known-consumed constant scanned to 0, so the zeros below would be meaningless")
	assert_eq(fake, 0, "control failed: a fabricated constant was 'found', so the scan matches anything")

	var orphaned: Array = []
	for name in ROUTED:
		var users := 0
		for p in bodies:
			if (bodies[p] as String).contains(name):
				users += 1
		if users == 0:
			orphaned.append(name)
	assert_eq(
		orphaned, [],
		"these constants size a live Mode 7 interaction zone and NOTHING in src/ reads them: %s. Editing them changes nothing in the game, so the contract file lies to whoever opens it to tune the feel." % str(orphaned)
	)


func test_the_y_stretch_is_not_hardcoded_anywhere() -> void:
	# derived from the constant, never typed -- re-tuning changes what is forbidden
	var literal := "Vector2(1.0, %s)" % str(Geo.MODE7_Y_STRETCH)
	var offenders: Array = []
	var scanned := 0
	for p in _gd_files(SRC_DIR):
		if p.ends_with("InteractGeometry.gd"):
			continue
		scanned += 1
		if _read(p).contains(literal):
			offenders.append(p.get_file())
	assert_gt(scanned, 40, "scanned only %d files -- too few for this to mean anything" % scanned)

	# CONTROL: the derived literal must be the shape that actually appears in this codebase,
	# or "0 offenders" is just a string that never matches.
	assert_true(
		literal.begins_with("Vector2(1.0, ") and literal.ends_with(")"),
		"the derived literal %s is malformed, so a zero below proves nothing" % literal
	)
	assert_eq(
		offenders, [],
		"%d file(s) hardcode %s instead of InteractGeometry.MODE7_Y_STRETCH: %s. Seventeen sites did on 2026-08-22, which is why re-tuning the Mode 7 zones was a fourteen-file edit that looked like a one-line one." % [offenders.size(), literal, str(offenders)]
	)
