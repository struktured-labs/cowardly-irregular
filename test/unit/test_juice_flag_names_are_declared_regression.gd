extends GutTest

## `BattleJuice.flag()` returns TRUE for any name it has never heard of:
##
##     return bool(flags.get(feature, true))
##
## So a typo is INDISTINGUISHABLE from a deliberate enable. `flag("rumbel")` reads true, the feature
## runs, and the correctly-named Settings row silently governs nothing. That is @cowir-sfx's
## discriminator — CAN THE FALLBACK'S OUTPUT BE MISTAKEN FOR THE REAL THING? — answered yes, so the
## default is load-bearing rather than a design decision, and it needs a guard rather than a comment.
##
## The same defaulting hid three features with no Settings row at all: `audio_crit_thud`,
## `audio_kill_duck` (both closed by cowir-sfx) and `full_render_on_autobattle`, whose own source
## comment promises it "turns it off for anyone who disagrees" — a player-facing escape hatch no
## player could reach. Rows added; the exemption list below is EMPTY and should stay that way.
##
## ⚠️ BOTH DIRECTIONS, because they are different defects: a flag with no row cannot be turned off,
## and a row with no consumer is a toggle that governs nothing. Neither is visible from the other.

const SETTINGS := "res://src/ui/SettingsMenu.gd"

## flag -> why it legitimately has no Settings row. EMPTY BY DESIGN. An entry here is a claim that
## players must never control this feature; it is checked for staleness below so it cannot rot.
const NO_ROW_NEEDED := {}


## Every `BattleJuice.flag("x")` name anywhere under src/, plus the bare `flag("x")` calls inside
## BattleJuice itself. Walks the tree rather than trusting a hardcoded file list.
func _consulted_flags() -> Array[String]:
	var out: Array[String] = []
	var qualified := RegEx.create_from_string("BattleJuice\\.flag\\(\"([a-z_]+)\"\\)")
	var bare := RegEx.create_from_string("(?:^|[^.\\w])flag\\(\"([a-z_]+)\"\\)")
	var stack: Array[String] = ["res://src"]
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
				if not name.begins_with("."):
					stack.append(full)
			elif name.ends_with(".gd"):
				var src := FileAccess.get_file_as_string(full)
				var re := bare if full.ends_with("BattleJuice.gd") else qualified
				for m in re.search_all(src):
					var f := m.get_string(1)
					if not out.has(f):
						out.append(f)
			name = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


## Flags the player can actually toggle, read from the Settings list itself.
func _toggleable_flags() -> Array[String]:
	var src := FileAccess.get_file_as_string(SETTINGS)
	var at := src.find("BATTLE_FX_FLAGS := [")
	assert_gt(at, -1, "the fx toggle list must exist")
	# Bound at the LIST's end, not the first "]" — every row is itself an array.
	var stop := src.find("\n]", at)
	assert_gt(stop, at, "the fx list must terminate")
	var body := src.substr(at, stop - at)
	var out: Array[String] = []
	for m in RegEx.create_from_string("\\[\"(\\w+)\"").search_all(body):
		out.append(m.get_string(1))
	out.sort()
	return out


## CONTROL FIRST, because a scanner that returns nothing makes every arm below vacuously green —
## cowir-sfx published a 0-of-19 negative tonight from a probe whose corpus string was empty.
func test_the_scanners_actually_find_things() -> void:
	var consulted := _consulted_flags()
	var toggleable := _toggleable_flags()
	assert_gt(consulted.size(), 10, "PRECONDITION: the src scan must find real flag names")
	assert_gt(toggleable.size(), 10, "PRECONDITION: the Settings list must yield real rows")
	assert_true(consulted.has("rumble"), "CONTROL present: rumble is consulted in BattleJuice")
	assert_false(consulted.has("zzq_not_a_flag"), "CONTROL absent: the scan can report a name missing")
	assert_true(toggleable.has("camera_zoom"), "CONTROL present: camera_zoom has a Settings row")
	assert_false(toggleable.has("zzq_not_a_row"), "CONTROL absent: the row scan can report missing")


## A flag with no row CANNOT BE TURNED OFF, and the true-by-default makes that state identical to
## "deliberately always on". Three features were in exactly that position.
func test_every_consulted_flag_can_be_turned_off() -> void:
	var toggleable := _toggleable_flags()
	var missing: Array[String] = []
	for f in _consulted_flags():
		if toggleable.has(f) or NO_ROW_NEEDED.has(f):
			continue
		missing.append(f)
	assert_eq(missing, [] as Array[String],
		"a juice feature is consulted but has no Settings row, so a player cannot switch it off " +
		"and nothing distinguishes that from a deliberate always-on: %s" % [", ".join(missing)])


## THE MIRROR: a row whose flag nothing reads is a toggle that governs nothing — the player flips it
## and the game ignores them. Invisible from the arm above.
func test_every_toggle_governs_something() -> void:
	var consulted := _consulted_flags()
	var dead: Array[String] = []
	for f in _toggleable_flags():
		if not consulted.has(f):
			dead.append(f)
	assert_eq(dead, [] as Array[String],
		"a Settings row has no flag() consumer — flipping it does nothing: %s" % [", ".join(dead)])


## CONTROL: no exemption may be inert. The list is empty today; an entry that names a flag nothing
## consults is a suppression for a case that cannot arise, and it makes the list read as coverage.
func test_no_exemption_is_stale() -> void:
	var consulted := _consulted_flags()
	var inert: Array[String] = []
	for f in NO_ROW_NEEDED:
		if not consulted.has(f):
			inert.append(f)
	assert_eq(inert, [] as Array[String],
		"an exemption names a flag nothing consults — delete it: %s" % [", ".join(inert)])
