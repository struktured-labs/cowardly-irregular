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


func test_the_scan_can_actually_fire() -> void:
	# Control: "0 offenders" and "the scan matched nothing" are the same green.
	var total := 0
	for path in SOURCES:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "CONTROL: could not read %s — its verdict below would be vacuous" % path)
		total += _write_opens(src).size()
	assert_gt(total, 0, "derived ZERO WRITE opens across three known writers — the scan is broken")


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
