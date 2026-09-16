extends GutTest

## Both sfx orphan audits walk the MANIFEST, so an .ogg on disk with no entry is invisible to both
## — cowir-sprites' point: not a tuning problem, the direction the instrument faces. They found two
## unregistered NPC sheets that every manifest-first guard they built today was blind to.
##
## The motivating instance here is mine, from this morning: w2_/w3_ability_heal.ogg sit on disk
## unnamed because struktured REJECTED them for brightness on 2026-09-10, and I was one commit from
## re-landing them. Nothing in the tree said so except a prompt field on a different key. An
## unregistered file that says why it is there is a decision; one that says nothing is a loose end
## the next lane "fixes".

const SFX_DIR := "res://assets/audio/sfx"

## Files on disk that NO manifest key names, with the reason each is deliberate.
## Both retirement triggers below: gaining a key reds, vanishing from disk reds.
const KNOWN_UNREGISTERED := {
	"heal.ogg": "superseded by heal_v4.ogg, which the `heal` key names; kept as the pre-v4 render",
	"w2_ability_heal.ogg": "struktured rejected it for BRIGHTNESS 2026-09-10 (9735 Hz / 97.6% >4kHz vs ability_heal's 437 Hz); w2_ability_heal points back at the W1 cue. Re-land only when it measures warm",
	"w3_ability_heal.ogg": "same 2026-09-10 rejection (9404 Hz / 94.8%); see the prompt on w3_ability_heal",
}


func _disk_oggs() -> Array:
	var out: Array = []
	var d := DirAccess.open(SFX_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".ogg"):
			out.append(n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _named_by_manifest() -> Dictionary:
	var f := FileAccess.open("res://data/sfx_manifest.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var sfx = parsed.get("sfx", {})
	var named: Dictionary = {}
	if sfx is Dictionary:
		for k in sfx.keys():
			var entry = sfx[k]
			if entry is Dictionary:
				named[str(entry.get("file", "")).get_file()] = str(k)
	return named


func test_every_unregistered_ogg_is_declared() -> void:
	var disk: Array = _disk_oggs()
	assert_gt(disk.size(), 0, "VOID, not clean: the sfx directory read back 0 .ogg files")
	var named: Dictionary = _named_by_manifest()
	assert_gt(named.size(), 0, "VOID, not clean: the manifest named 0 files")
	var undeclared: Array = []
	for f in disk:
		if not named.has(str(f)) and not KNOWN_UNREGISTERED.has(str(f)):
			undeclared.append(str(f))
	assert_eq(undeclared.size(), 0,
		"%d .ogg on disk that no manifest key names and nothing declares — each is unreachable, and an undeclared one reads as a loose end somebody will 'fix': %s" % [undeclared.size(), str(undeclared)])


func test_a_declaration_does_not_outlive_its_fact() -> void:
	## Trigger 1: the file gained a key, so the entry is stale — delete it.
	## Trigger 2: the file left disk, so the entry describes nothing — delete it.
	## A suppression that can only be removed, never silently kept (cowir-music).
	var disk: Array = _disk_oggs()
	var named: Dictionary = _named_by_manifest()
	assert_gt(disk.size(), 0, "VOID, not clean: the sfx directory read back 0 .ogg files")
	var now_named: Array = []
	var vanished: Array = []
	for f in KNOWN_UNREGISTERED.keys():
		if named.has(str(f)):
			now_named.append(str(f))
		elif not disk.has(str(f)):
			vanished.append(str(f))
	assert_eq(now_named.size(), 0,
		"declared-unregistered file(s) that a manifest key NOW names — remove the entry: %s" % str(now_named))
	assert_eq(vanished.size(), 0,
		"declared-unregistered file(s) no longer on disk — remove the entry: %s" % str(vanished))


func test_each_declaration_states_a_reason() -> void:
	## You can explain it green; you cannot silence it green.
	assert_gt(KNOWN_UNREGISTERED.size(), 0, "CONTROL: an empty declaration set makes the arms above vacuous")
	for f in KNOWN_UNREGISTERED.keys():
		assert_gt(str(KNOWN_UNREGISTERED[f]).strip_edges().length(), 25,
			"%s is declared with no usable reason — the deliverable is the explanation, not permission to skip" % str(f))
