extends GutTest

## `FileAccess.open(path, WRITE)` TRUNCATES ON OPEN. `_write_save_file` opened the player's slot
## directly and only then ran `JSON.stringify` over the whole game state, so for the duration of
## serializing party + quests + inventory + bestiary + injuries + corruption the save on disk was
## 0 bytes. A crash in that window did not corrupt the save, it erased it.
##
## ⛔ THE WINDOW WAS NOT A RACE AGAINST ANOTHER WRITER — it is a race against your own process
## dying, which is why no lock or latch could have covered it (@cowir-controller's framing, found
## on the same shape in the input-mapping writer).
##
## 🔑 AND THE CAUSE WAS ALREADY DIAGNOSED IN THIS FILE: `load_settings`' own docstring says
## "Common cause: game crashed mid-write, leaving an empty / truncated settings.json" — somebody
## saw the truncated file, named the mechanism, and hardened the READER. The writer that creates
## the truncated file was left alone (@cowir-main).
##
## Repair: serialize first, write to `<slot>.new`, rename into place. The previous save is intact
## until the new one is complete on disk, and a failed rename reports false rather than lying.

const SLOT := 94
## The functions in this file that persist player data. The one hand-list in an otherwise derived
## arm, and it is deliberate: a derived corpus shrinks silently, a named one reds.
const PERSISTERS := ["_write_save_file", "save_settings"]
const SENTINEL := '{"sentinel":"PREVIOUS","keep":true}'


func _save_system() -> Node:
	return get_node_or_null("/root/SaveSystem")


func _path() -> String:
	var ss := _save_system()
	return ss._get_save_path(SLOT) if ss else ""


func after_each() -> void:
	## Both the slot and any staging litter, so a failed arm cannot seed the next one.
	var p := _path()
	if p == "":
		return
	for f in [p, p + ".new"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_a_save_round_trips_through_the_staged_write() -> void:
	var ss := _save_system()
	assert_not_null(ss, "SaveSystem autoload unavailable — a skip here reports GREEN having tested nothing")
	if ss == null:
		return
	var ok: bool = ss._write_save_file(SLOT, {"sentinel": "NEW", "n": 7})
	assert_true(ok, "CONTROL: the staged write must report success, or the arms below are about a write that never happened")
	assert_true(FileAccess.file_exists(_path()), "the rename must put the payload at the real slot path")
	var f := FileAccess.open(_path(), FileAccess.READ)
	assert_not_null(f, "the written slot must be readable")
	if f == null:
		return
	var body := f.get_as_text()
	f.close()
	assert_true(body.contains("\"sentinel\""), "the slot must hold the new payload, got: %s" % body.substr(0, 80))
	assert_false(FileAccess.file_exists(_path() + ".new"),
		"the staging file must not survive a successful write — a leftover .new is litter in the player's save dir")


func test_the_previous_save_is_never_truncated_by_starting_a_new_one() -> void:
	## The defect's shape directly: plant a prior save, write over it, and require that at no
	## point is the destination the file being filled. Observable end state — the slot is either
	## the old bytes or the new bytes, never 0.
	var ss := _save_system()
	assert_not_null(ss, "SaveSystem autoload unavailable")
	if ss == null:
		return
	var pre := FileAccess.open(_path(), FileAccess.WRITE)
	assert_not_null(pre, "CONTROL: could not plant a baseline save")
	if pre == null:
		return
	pre.store_string(SENTINEL)
	pre.close()
	assert_eq(FileAccess.get_file_as_string(_path()).length(), SENTINEL.length(),
		"CONTROL: the baseline must be on disk at full length before the overwrite")

	var ok: bool = ss._write_save_file(SLOT, {"sentinel": "NEW"})
	assert_true(ok, "the write must succeed")
	var after := FileAccess.get_file_as_string(_path())
	assert_gt(after.length(), 0,
		"the slot is 0 bytes after a write — this is the erase, not a corruption: the player's save is gone")


func test_the_destination_is_never_opened_for_write() -> void:
	## A SOURCE ratchet, because the defect is the ORDER and the failure cannot be staged: making
	## the process die mid-serialize is not something a test can arrange. Same technique as the
	## jukebox latch guard — pin the two relationships the repair consists of.
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	var start := src.find("func _write_save_file")
	assert_gt(start, -1, "func _write_save_file not found — renamed? this ratchet is now about nothing")
	if start == -1:
		return
	var end := src.find("\nfunc ", start + 1)
	var body := src.substr(start, (end - start) if end > start else -1)

	var opened_dest: bool = body.contains("FileAccess.open(file_path, FileAccess.WRITE)")
	assert_false(opened_dest,
		"_write_save_file opens the DESTINATION with WRITE, which truncates the player's existing save before the replacement exists")

	var i_stringify := body.find("JSON.stringify")
	var i_open := body.find("FileAccess.open")
	assert_gt(i_stringify, -1, "CONTROL: _write_save_file must still serialize, or this ratchet guards nothing")
	assert_gt(i_open, -1, "CONTROL: _write_save_file must still open a file")
	assert_lt(i_stringify, i_open,
		"JSON.stringify runs AFTER the open (stringify at %d, open at %d) — the whole game state is serialized while the target file is already truncated" % [i_stringify, i_open])

	assert_true(body.contains("rename_absolute"),
		"the staged file must be renamed into place — without it the write is not atomic and a dead process leaves no save")


## Derived rather than hand-listed: EVERY writer in this file, so a third one added later is
## covered without anybody remembering to extend this arm. `_write_save_file` was fixed first and
## `save_settings` sat 170 lines below it with the identical shape — a per-function ratchet would
## have passed the whole time.
func test_no_writer_in_this_file_opens_its_destination() -> void:
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()

	var offenders: Array = []
	var staged_writes := 0
	for line in src.split("\n"):
		var t := line.strip_edges()
		if not t.contains("FileAccess.open(") or not t.contains("FileAccess.WRITE"):
			continue
		if t.contains("staged"):
			staged_writes += 1
		else:
			offenders.append(t)

	## ⛔ A COUNT FLOOR IS SATISFIED BY A SURVIVOR. This was `staged_writes > 0`, and it passed with
	## BOTH writers gone: planting the .434 refactor — hoist each open into a shared `_write_staged`
	## helper — left one staged write (the helper's) above the floor, offenders empty, arm GREEN.
	## Every subject had left the derivation and the only thing that red was the per-function arm.
	## So the floor is MEMBERSHIP, by name: each persister must carry its own staged write.
	## (cowir-controller's rule, cowir-sfx's second instance, this is the third.)
	assert_gt(staged_writes, 0,
		"CONTROL: no staged write found in SaveSystem.gd — either the repair is gone or this arm stopped matching it")
	for fn in PERSISTERS:
		var start := src.find("func " + fn)
		assert_gt(start, -1,
			"PERSISTER %s is gone from SaveSystem.gd — if it was renamed, rename it here too; this list exists so a disappearance is LOUD rather than a silently smaller corpus" % fn)
		if start == -1:
			continue
		var end := src.find("\nfunc ", start + 1)
		var body := src.substr(start, (end - start) if end > start else -1)
		## ⛔ NOT `contains("staged")` — MY FIRST ATTEMPT AT THIS FLOOR, AND IT DID NOT FIRE.
		## Hoisting the open into a helper leaves `var staged := path + ".new"` in place, so the
		## token survives while the write leaves. A name satisfied for a reason unrelated to the
		## property, committed inside the fix for exactly that. The arm's corpus is
		## `FileAccess...WRITE` lines, so the floor must assert what the corpus can SEE.
		assert_true(body.contains("FileAccess.WRITE"),
			"%s no longer performs its own write — it may be correct (a helper can stage and rename just as well), but this arm derives its corpus from FileAccess...WRITE lines and can no longer see it, so a file with every writer delegated would report ZERO offenders and a clean bill. Inline it, or extend this arm to follow the delegate." % fn)
	assert_eq(offenders, [],
		"a writer in SaveSystem.gd opens its real destination with WRITE, which truncates the player's file before the replacement exists: %s" % str(offenders))


func test_the_settings_writer_reports_a_failure_it_used_to_swallow() -> void:
	## `save_settings` returns void and had a bare `if file:` with no else, so a settings save
	## that could not open was indistinguishable from one that worked — at all six call sites.
	var f := FileAccess.open("res://src/save/SaveSystem.gd", FileAccess.READ)
	assert_not_null(f, "could not read SaveSystem.gd")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	var start := src.find("func save_settings")
	assert_gt(start, -1, "func save_settings not found — renamed? this ratchet is now about nothing")
	if start == -1:
		return
	var end := src.find("\nfunc ", start + 1)
	var body := src.substr(start, (end - start) if end > start else -1)

	assert_true(body.contains("push_warning"),
		"save_settings can fail to open its file and say nothing — the player keeps playing with settings that were never written")
	assert_true(body.contains("rename_absolute"),
		"save_settings must stage and rename: load_settings' own docstring records a crash mid-write already emptying settings.json in the wild")
	## The cleanup is load-bearing for THIS writer only — settings.json holds the BYOK key, and a
	## player who configures it once may never trigger the next save that would truncate an orphan.
	assert_true(body.contains("push_error"),
		"a failed remove of the staging file leaves the player's API key in plaintext at settings.json.new and says nothing — it needs its own loud branch naming the path")
