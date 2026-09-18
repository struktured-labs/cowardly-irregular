extends GutTest

## The truncate-on-open family, for the three writers outside AutogrindSystem. `open(dest, WRITE)`
## truncates, so serializing after it puts the payload inside a window where a process death leaves
## 0 bytes and no previous copy. All three overwrite something the player owns:
##   AutobattleSystem  user://autobattle/profiles.json — 88 KB on struktured's disk, the largest
##   AutogrindUI       the player's authored custom presets
##   ScriptShareManager  export filenames are FIXED, so a re-export overwrites the previous one
## DERIVED per file rather than per function: a per-function ratchet is what let a second writer sit
## 170 lines below a fixed one with the identical shape (cowir-music, src/save).

const SOURCES := {
	"res://src/autobattle/AutobattleSystem.gd": "the largest player-data file in the game",
	"res://src/ui/autogrind/AutogrindUI.gd": "the player's authored autogrind presets",
	"res://src/autobattle/ScriptShareManager.gd": "an export the player hands to a friend",
}


func _write_opens(src: String) -> Array:
	var out: Array = []
	var n := 0
	for line in src.split("\n"):
		n += 1
		var t: String = line.strip_edges()
		if t.begins_with("#") or t.begins_with("##"):
			continue
		if line.contains("FileAccess.open(") and line.contains("WRITE"):
			out.append([n, t])
	return out


## ⛔ MEMBERSHIP, NOT A COUNT — AND THE AGGREGATE VERSION SHIPPED HERE THIS MORNING.
## A count floor is satisfied by a SURVIVOR (@cowir-controller, 2026-09-18). Measured on this very
## file: removing the staged open from TWO of these three writers left it GREEN at 3 passing, because
## the third still had one and the summed floor never noticed. A count answers "did the scan run at
## all"; only per-source membership answers "is EACH writer still being watched".
func test_every_named_writer_is_still_present() -> void:
	var missing: Array = []
	for path in SOURCES:
		var src: String = FileAccess.get_file_as_string(path)
		if src == "":
			missing.append("%s (unreadable — its verdict below would be vacuous)" % path)
		elif _write_opens(src).is_empty():
			missing.append("%s (no WRITE open at all — %s)" % [path, SOURCES[path]])
	assert_eq(missing, [],
		"a writer this file exists to watch has no WRITE open left — it was moved, renamed or deleted, and the offender scan below is silently no longer about it: %s" % str(missing))


func test_no_writer_opens_its_destination() -> void:
	var offenders: Array = []
	for path in SOURCES:
		var src: String = FileAccess.get_file_as_string(path)
		for entry in _write_opens(src):
			if not str(entry[1]).contains("FileAccess.open(staged,"):
				offenders.append("%s:%d — %s (%s)" % [path, entry[0], entry[1], SOURCES[path]])
	assert_eq(offenders, [],
		"These open a destination with WRITE, truncating it before anything is serialized. Stage a sibling and rename it into place: %s" % str(offenders))


func test_every_writer_verifies_its_bytes_before_renaming() -> void:
	## store_string returns nothing, so a short write is invisible — and staging does NOT cover it:
	## a rename carries a partial file into place just as happily. Checked before the rename.
	var missing: Array = []
	for path in SOURCES:
		var src: String = FileAccess.get_file_as_string(path)
		var i_check: int = src.find("get_length()")
		var i_err: int = src.find("get_error()")
		var i_rename: int = src.find("rename_absolute")
		if i_err < 0 or i_check < 0 or i_rename < 0:
			missing.append("%s (get_error=%d get_length=%d rename=%d)" % [path, i_err, i_check, i_rename])
		elif i_check > i_rename:
			missing.append("%s (byte check runs AFTER the rename)" % path)
	assert_eq(missing, [],
		"each writer must consult get_error() AND read its bytes back BEFORE renaming: %s" % str(missing))


## ⛔ SOURCES IS A HAND-LIST OF THE WRITERS THAT EXIST TODAY, AND A CORPUS SCOPED TO WHERE THE
## SUBJECT IS FOUND TODAY CANNOT SEE IT ARRIVE SOMEWHERE NEW (@cowir-controller, 2026-09-18: their
## ratchet named the one src/ui file that writes, so three siblings were INVISIBLE, not clean).
## The arms above ask "did a known writer stop being watched"; this pair asks "did an unwatched
## writer appear". Derived from the lane's directories, so a new FILE is covered with no edit here.
const LANE_DIRS := ["res://src/autogrind", "res://src/ui/autogrind", "res://src/autobattle"]

## Covered by its own guard (test_a_writer_never_opens_its_destination_regression), NOT exempt —
## a second report here would be noise. Its absence from SOURCES is coverage, not a hole.
const COVERED_ELSEWHERE := "AutogrindSystem.gd"


func _lane_gd_files() -> Array:
	var out: Array = []
	var stack: Array = LANE_DIRS.duplicate()
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out.append("%s/%s" % [d, f])
	out.sort()
	return out


func test_the_lane_scan_can_actually_fire() -> void:
	## Control: a derived-empty file list makes the arm below vacuously green, which is the shape
	## that let a batch go red today — a green over a corpus that could not contain the defect.
	var files := _lane_gd_files()
	assert_gt(files.size(), 5, "derived implausibly few lane files — the directory walk is broken, not the code")
	assert_true("res://src/autobattle/ScriptShareManager.gd" in files,
		"control: a known writer must appear in the walk, else the arm below is scanning the wrong tree")


func test_no_unwatched_writer_has_appeared_in_the_lane() -> void:
	var unwatched: Array = []
	for path in _lane_gd_files():
		if path.ends_with(COVERED_ELSEWHERE) or SOURCES.has(path):
			continue
		var src: String = FileAccess.get_file_as_string(path)
		if src == "":
			continue
		for entry in _write_opens(src):
			unwatched.append("%s:%d — %s" % [path, entry[0], entry[1]])
	assert_eq(unwatched, [],
		"a file in this lane writes to disk and NOTHING watches its shape — add it to SOURCES with what the player loses if it truncates, or route it through a staged writer: %s" % str(unwatched))


## ⛔ THE ARM ABOVE CATCHES A NEW FILE; THIS ONE CATCHES A NEW *FORM*, AND THE SAME MUTATION HABIT
## HIDES BOTH (@cowir-sfx, 2026-09-18). Every arm in this file keys on `FileAccess.open(…, WRITE)`,
## so a write through ResourceSaver, store_var/store_buffer or save_png reaches disk while every
## assertion here stays green — it is not an offender, it is not a missing member, it is invisible.
## Measured today: my lane uses NO such form, and the same patterns DO find the fleet's four
## (GameLoop ×2, BaseTileGenerator, FeedbackBundle), so the zero is over a working instrument.
const OTHER_WRITE_FORMS := [
	"ResourceSaver.", "store_var(", "store_buffer(", "store_line(", "store_csv_line(",
	"save_png(", "save_to_file(",
]


func test_no_write_reaches_disk_by_a_form_this_file_cannot_see() -> void:
	var exotic: Array = []
	for path in _lane_gd_files():
		var src: String = FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var n := 0
		for line in src.split("\n"):
			n += 1
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			for form in OTHER_WRITE_FORMS:
				if line.contains(form):
					exotic.append("%s:%d — %s (%s)" % [path, n, t, form])
					break
	assert_eq(exotic, [],
		"this lane now reaches disk by a form none of the arms above can see, so its truncate-on-open exposure is unaudited — either route it through a staged writer or teach this file the form: %s" % str(exotic))
