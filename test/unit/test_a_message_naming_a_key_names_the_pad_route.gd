extends GutTest

## The autobattle grid editor's import picker said "No export files found — press E to export
## first". A pad player cannot press E, and they had reached that picker through More Actions —
## so they were told to use a key their hardware lacks, for the verb sitting one row ABOVE the one
## they had just used.
##
## The pad route already existed. `_open_more_actions` carries its own note: "nine verbs below were
## raw KEY_* only, so a pad could not export, import, share, compose, toggle a row or switch
## profile at all. This is the pad's route to them." Someone fixed the reachability and left this
## one message naming the key — the same shape as the Party Formations hint that said "Press F".
##
## ⚠️ SCANNED AT THE CALL SITE, NOT OVER THE FILE. A whole-file literal scan returns docstrings:
## `"""Cancel autobattle ... (when they press B after selecting Auto)"""` and `"""Create an action
## button setting (press A to activate)"""` both match a key pattern and neither is player-facing.
## Keying on the message FUNCTIONS excludes them by construction — 3 whole-file matches, 1 real.
##
## The exemption is the deliverable: a message may name a key if it ALSO names the route a pad can
## take. It cannot be silenced by deleting the key.

const SURFACES := [
	"res://src/ui/autobattle/AutobattleGridEditor.gd",
	"res://src/ui/autogrind/AutogrindUI.gd",
	"res://src/ui/Toast.gd",
	"res://src/battle/BattleScene.gd",
]

## Functions whose String argument a player reads.
const MESSAGE_CALLS := ["_flash_status(", "Toast.show(", "Toast.show_warning(",
	"Toast.show_success(", "Toast.show_danger("]

## Naming any of these means a pad player has a way in.
const ROUTE_WORDS := ["more actions", "menu", "d-pad", "pad", "row"]


func _literals_passed_to_messages(src: String) -> Array:
	var out: Array = []
	for call in MESSAGE_CALLS:
		var from := 0
		while true:
			var at := src.find(call, from)
			if at == -1:
				break
			from = at + call.length()
			## the first double-quoted literal inside this call's argument list
			var q1 := src.find("\"", at)
			var close := src.find(")", at)
			if q1 == -1 or (close != -1 and q1 > close and src.find("\"", close) == -1):
				continue
			var q2 := src.find("\"", q1 + 1)
			if q2 == -1:
				continue
			out.append(src.substr(q1 + 1, q2 - q1 - 1))
	return out


func _names_a_bare_key(text: String) -> bool:
	var low := text.to_lower()
	for verb in ["press ", "hit ", "hold "]:
		var at := low.find(verb)
		while at != -1:
			var rest := text.substr(at + verb.length())
			## a KEY is a short run of capitals/digits: "E", "F", "Tab", "Shift+E"
			var tok := ""
			for i in rest.length():
				var c := rest[i]
				if c == " " or c == "." or c == "," or c == ")":
					break
				tok += c
			if tok.length() > 0 and tok.length() <= 7 and tok == tok.to_upper() and tok != "":
				var has_letter := false
				for i in tok.length():
					if tok[i] >= "A" and tok[i] <= "Z":
						has_letter = true
				if has_letter:
					return true
			at = low.find(verb, at + 1)
	return false


func _names_a_route(text: String) -> bool:
	var low := text.to_lower()
	for w in ROUTE_WORDS:
		if low.find(w) != -1:
			return true
	## a resolved glyph token (%s from hint_for_action) is a pad route by construction
	return text.find("%s") != -1 or text.find("{") != -1


func test_control_the_detector_fires_on_the_shape_it_is_for() -> void:
	## Without this, a silent zero below would read as a clean corpus.
	assert_true(_names_a_bare_key("No export files found — press E to export first"),
		"CONTROL: the detector must see a bare key")
	assert_false(_names_a_route("No export files found — press E to export first"),
		"CONTROL: and must not count that string as naming a route")
	assert_true(_names_a_route("export one first (E, or More Actions ▸ Export)"),
		"CONTROL: naming More Actions must count as a route")


func test_control_the_surfaces_are_readable_and_carry_messages() -> void:
	var found := 0
	for path in SURFACES:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "CONTROL: %s must be readable" % [path])
		found += _literals_passed_to_messages(src).size()
	assert_gt(found, 10,
		"CONTROL: the scan must find player messages to check, found %d" % [found])


func test_no_player_message_names_a_key_without_a_pad_route() -> void:
	## THE DEFECT. A message may name a key — it must not name ONLY a key.
	##
	## ⚠️ COLLECTED THEN ASSERTED ONCE, deliberately. Asserting inside the loop means that on a
	## clean corpus the arm executes NO assertion at all and GUT scores it Risky, not passing —
	## `run_tests.sh`'s "ran and asserted nothing" check caught exactly that in the first version
	## of this file. A guard whose pass depends on finding something is not a guard.
	var offenders: Array = []
	var scanned := 0
	for path in SURFACES:
		var src: String = FileAccess.get_file_as_string(path)
		for text in _literals_passed_to_messages(src):
			scanned += 1
			if _names_a_bare_key(text) and not _names_a_route(text):
				offenders.append("%s: \"%s\"" % [path.get_file(), text])
	assert_gt(scanned, 10,
		"PRECONDITION: the scan must reach real player messages, reached %d" % [scanned])
	assert_eq(offenders.size(), 0,
		"a player message names a key and no route a pad can take: %s" % [", ".join(offenders)])
