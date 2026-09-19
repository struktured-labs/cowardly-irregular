extends GutTest

## EventLog declares "Never stores LLM output" and nothing enforced it.
##
## The invariant is load-bearing, not hygiene. EventLog rides the save path via
## GameState.to_dict()/from_dict(), so an entry PERSISTS TO DISK — and
## DynamicConversation feeds `recent_varied()` into prompt context at five call
## sites. Model text entering the log would be written into the player's save and
## re-fed to the model on every later conversation: a loop that survives reloads
## and that no single playthrough makes visible.
##
## ⚠️ NO CURRENT DEFECT. Measured across src/:
##     event_log.record() call sites          6
##     whose first arg is an EventLog.TYPE_*  6
##     writers using TYPE_CUSTOM              0   the free-text hatch, unused
##     writers inside src/llm/                0
##
## A static check cannot decide whether a String came from a model — that is
## dataflow. What it CAN hold is the structural separation the invariant implies:
## the log is written by deterministic game systems, and the subsystem that holds
## model text is not one of them. That is the property pinned below.
##
## Every scan reads GdSource.split()["code"] — a `#` comment naming record() must
## neither satisfy an arm nor trip one.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## The call the invariant is about, and the lane that holds model text. Both are
## read by the arms rather than restated inside them.
const WRITE_CALL := "event_log.record("
const MODEL_LANE := "res://src/llm/"
const WALK_ROOT := "res://src"


func _code_lines(src: String) -> PackedStringArray:
	return (GdSource.split(src)["code"] as String).split("\n")


## Every .gd under WALK_ROOT, by recursive walk — a new subsystem enters by itself.
func _all_gd() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [WALK_ROOT]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name: String = d.get_next()
		while name != "":
			var full: String = dir_path.path_join(name)
			if d.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd"):
				out.append(full)
			name = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


## [[path, line_no, first_argument], …] for every write to the log.
func _record_sites() -> Array:
	var out: Array = []
	for path in _all_gd():
		var lines: PackedStringArray = _code_lines(FileAccess.get_file_as_string(path))
		for i in lines.size():
			var line: String = lines[i]
			if line.find(WRITE_CALL) == -1:
				continue
			## The first argument may sit on the NEXT line — all six live sites wrap.
			var tail: String = line.split(WRITE_CALL)[1].strip_edges()
			var j: int = i
			while tail == "" and j + 1 < lines.size():
				j += 1
				tail = lines[j].strip_edges()
			out.append([path, i + 1, tail.trim_suffix(",")])
	return out


func test_every_write_names_a_declared_event_type() -> void:
	## A declared TYPE_* is a fact the schema knows about. Free text arriving as an
	## ad-hoc string is the shape model output would take.
	var offenders: Array[String] = []
	for site in _record_sites():
		if not str(site[2]).begins_with("EventLog.TYPE_"):
			offenders.append("%s:%d passes %s" % [str(site[0]).get_file(), int(site[1]), site[2]])
	assert_eq(offenders, ([] as Array[String]),
		("these event-log writes do not name a declared EventLog.TYPE_* constant: %s. The log "
		+ "persists to the save and feeds prompt context — record a fact, not a sentence.")
			% ", ".join(offenders))


func test_the_subsystem_holding_model_text_never_writes_the_log() -> void:
	## THE INVARIANT, as the only thing about it a static check can hold. src/llm is
	## where a model reply exists as a String; keeping it out of the writer set is what
	## makes "never stores LLM output" true by construction rather than by review.
	var offenders: Array[String] = []
	for site in _record_sites():
		if str(site[0]).begins_with(MODEL_LANE):
			offenders.append("%s:%d" % [str(site[0]).get_file(), int(site[1])])
	assert_eq(offenders, ([] as Array[String]),
		("%s writes the event log: %s. EventLog persists to the save AND feeds prompt context, "
		+ "so a model-derived entry loops back into every later conversation. Record the "
		+ "deterministic fact from the caller instead.") % [MODEL_LANE, ", ".join(offenders)])


# ── controls: each zero above needs the same scan saying YES somewhere ────────

func test_the_write_scan_can_find_a_write() -> void:
	## FLOOR. An empty scan makes both arms above vacuous while they read as thorough.
	## Pinned by MEMBERSHIP as well as count — a count floor is satisfied by a survivor.
	var sites: Array = _record_sites()
	assert_gt(sites.size(), 3,
		"the write scan found %d sites — the scan is broken, and both arms above are vacuous"
			% sites.size())
	var files: Array[String] = []
	for site in sites:
		var f: String = str(site[0])
		if not files.has(f):
			files.append(f)
	for must in ["res://src/GameLoop.gd", "res://src/battle/BattleManager.gd"]:
		assert_true(files.has(must),
			"%s writes the event log and the scan does not reach it — got %s" % [must, files])


func test_the_lane_the_second_arm_names_is_actually_walked() -> void:
	## FLOOR on the SCOPE. The second arm reports zero offenders in src/llm; that zero is
	## worth nothing if the walk never enters src/llm. Reference is LITERAL and deliberately
	## not MODEL_LANE — deriving the check from the const it checks lets one edit move both
	## sides and keep the arm green.
	var in_lane: int = 0
	for p in _all_gd():
		if p.begins_with("res://src/llm/"):
			in_lane += 1
	assert_gt(in_lane, 5,
		"the walk reached %d files under res://src/llm — the second arm's zero is vacuous"
			% in_lane)
	assert_eq(MODEL_LANE, "res://src/llm/",
		"MODEL_LANE no longer names the lane this floor walks")


func test_the_log_really_does_reach_a_prompt() -> void:
	## WHY THIS FILE EXISTS. If nothing fed the log into a prompt, a model-derived entry
	## would be a cosmetic wart rather than a persisted feedback loop, and the arms above
	## would be defending nothing. Pinned so the STAKES cannot quietly go away.
	var dc: String = FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	assert_ne(dc, "", "DynamicConversation.gd is unreadable — the stakes claim is unverified")
	var reads: int = 0
	for line in _code_lines(dc):
		if line.find("_event_log.recent") != -1:
			reads += 1
	assert_gt(reads, 0,
		"nothing in DynamicConversation reads the event log any more — if the log no longer "
		+ "reaches a prompt, re-derive what this file is defending before deleting it")


func test_a_comment_naming_the_write_is_not_a_write() -> void:
	## The defect one lane over tonight: a token pin satisfied by the author's own comment.
	## Both scans read stripped code, so prose can neither satisfy nor trip them.
	var probe: String = ("# GameState.event_log.record(EventLog.TYPE_CUSTOM, reply, {})\n"
		+ "func f() -> void:\n\tpass\n")
	assert_eq((GdSource.split(probe)["code"] as String).find(WRITE_CALL), -1,
		"a commented-out write survives the strip — every arm in this file can be satisfied "
		+ "or tripped by prose")
