extends GutTest

## monsters.json `signature_ability` sits on the 5 spotlight bosses, is read by nothing, and does not mean one thing.

const MONSTERS_PATH := "res://data/monsters.json"
const JOBS_PATH := "res://data/jobs.json"
const ABILITIES_PATH := "res://data/abilities.json"

## The exact quoted literal a reader would have to write; not a substring of "used_signature_ability".
const FIELD_LITERAL := "\"signature_ability\""

## Present in src today, so it proves the scanner reads files at all.
const CONTROL_PRESENT := "\"used_signature_ability\""

## Whether each boss's signature_ability is in its OWN kit. False = the value names a move the boss cannot use.
const SIGNATURE_IN_OWN_KIT := {
	"fighter_skeleton_knight": true,
	"cleric_survive_target": true,
	"rogue_lockward": true,
	"mage_prismatic_construct": true,
	"bard_hostile_courtier": false,
}

var _monsters: Dictionary
var _jobs: Dictionary
var _abilities: Dictionary


func before_all() -> void:
	_monsters = _load(MONSTERS_PATH, "monsters")
	_jobs = _load(JOBS_PATH, "jobs")
	_abilities = _load(ABILITIES_PATH, "abilities")


func _load(path: String, key: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var body: Variant = raw[key] if (raw is Dictionary and raw.has(key)) else raw
	return body if body is Dictionary else {}


## Base abilities plus everything unlocked at or below the duel's level.
func _pc_kit(job_id: String, level: int) -> Array:
	var job: Dictionary = _jobs.get(job_id, {})
	var kit: Array = (job.get("abilities", []) as Array).duplicate()
	for lvl_key in job.get("abilities_at_level", {}):
		if int(str(lvl_key)) <= level:
			kit.append_array(job["abilities_at_level"][lvl_key])
	return kit


func _gd_sources() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var n := dir.get_next()
		while n != "":
			var full := "%s/%s" % [d, n]
			if dir.current_is_dir():
				stack.append(full)
			elif n.ends_with(".gd"):
				out.append(full)
			n = dir.get_next()
		dir.list_dir_end()
	return out


func test_the_source_scan_can_see_anything_at_all() -> void:
	var files := _gd_sources()
	assert_gt(files.size(), 100, "CONTROL: res://src should yield hundreds of .gd files, got %d" % files.size())
	var present := 0
	var fabricated := 0
	for f in files:
		var body := FileAccess.get_file_as_string(f)
		if body.contains(CONTROL_PRESENT):
			present += 1
		if body.contains("\"zzz_not_a_real_field\""):
			fabricated += 1
	assert_gt(present, 0, "CONTROL: %s is known to exist in src and must be found" % CONTROL_PRESENT)
	assert_eq(fabricated, 0, "CONTROL: a fabricated field name must not be found")


func test_exactly_the_five_spotlight_bosses_declare_the_field() -> void:
	var declarers: Array = []
	for mid in _monsters:
		var entry: Variant = _monsters[mid]
		if entry is Dictionary and (entry as Dictionary).has("signature_ability"):
			declarers.append(str(mid))
	declarers.sort()
	var expected: Array = SIGNATURE_IN_OWN_KIT.keys()
	expected.sort()
	assert_eq(declarers, expected,
		("the signature_ability field's membership moved. It is a spotlight-duel field: every declarer "
		+ "must be a spotlight_duel boss, and every spotlight_duel boss must declare one. Found: %s") % str(declarers))


func test_nothing_in_src_reads_the_field_yet() -> void:
	var readers: Array[String] = []
	for f in _gd_sources():
		if FileAccess.get_file_as_string(f).contains(FIELD_LITERAL):
			readers.append(f.replace("res://", ""))
	assert_eq(readers, [] as Array[String],
		("signature_ability just gained its first reader (%s) — READ THIS TEST BEFORE KEEPING IT. "
		+ "Its two sibling fields on these same 5 rows, signature_sfx and victory_sfx, were each authored "
		+ "with no reader and wired later. This is the third. But it does NOT mean one thing across the 5 "
		+ "rows (see test_the_field_does_not_mean_one_thing), so a reader that assumes either meaning is "
		+ "silently wrong on the other rows. Settle the semantics first, then delete this test.") % str(readers))


func test_the_field_does_not_mean_one_thing() -> void:
	var actual: Dictionary = {}
	for mid in SIGNATURE_IN_OWN_KIT:
		var m: Dictionary = _monsters.get(mid, {})
		var sig: String = str(m.get("signature_ability", ""))
		assert_true(_abilities.has(sig), "%s signature_ability '%s' must resolve in abilities.json" % [mid, sig])
		actual[mid] = sig in (m.get("abilities", []) as Array)
	assert_eq(actual, SIGNATURE_IN_OWN_KIT,
		("signature_ability's boss-kit membership changed. Today 4 of 5 name a move in the boss's OWN kit "
		+ "while bard_hostile_courtier names 'lullaby', which only its spotlight PC can cast — so the field "
		+ "is a boss move on some rows and a PC move on others. If you are draining this by editing "
		+ "monsters.json, do NOT simply add the signature to the boss's kit: for the courtier that puts a "
		+ "sleep into a solo 1v1 duel whose win condition requires the PC to keep acting. Found: %s") % str(actual))


func test_the_courtier_signature_is_reachable_by_its_pc_not_its_boss() -> void:
	var m: Dictionary = _monsters.get("bard_hostile_courtier", {})
	var sig: String = str(m.get("signature_ability", ""))
	var pc: String = str(m.get("spotlight_pc", ""))
	var pc_kit := _pc_kit(pc, int(m.get("level", 1)))
	assert_false(sig in (m.get("abilities", []) as Array),
		"the courtier's own kit gained '%s' — see test_the_field_does_not_mean_one_thing before keeping it" % sig)
	assert_true(sig in pc_kit,
		("the courtier's signature '%s' must stay castable by the %s, which is the only reading that makes "
		+ "the field coherent on this row. Its own setup_hint tells the player \"Lullaby lands the truth\". "
		+ "PC kit at level %d: %s") % [sig, pc, int(m.get("level", 1)), str(pc_kit)])
