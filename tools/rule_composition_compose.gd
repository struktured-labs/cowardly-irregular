extends SceneTree

## Score captured model replies by driving the REAL RuleComposer.compose_async.
##
## tools/rule_composition_validate.gd re-implements the pipeline: it calls the
## guard, the validator and the repair functions itself, in an order it has to
## keep in step with compose_async by hand. That has drifted twice, and both
## times it published a confident wrong number before anyone noticed.
##
## This asks the shipping code instead. A composition counts as reaching the
## player exactly when compose_async says source == "llm"; there is no second
## opinion to keep synchronised.
##
##   XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy \
##     --script tools/rule_composition_compose.gd -- <arm> <character_id>
##
## The sandbox prefix is not optional and this tool has no wrapper to supply it: a bare
## godot resolves user:// to the real profile and rotates the player's crash logs away.
##
## Reads tmp/replies_<arm>/*.txt, writes tmp/composebench_<arm>.txt.

const ReplayBackend := preload("res://tools/replay_backend.gd")


func _init() -> void:
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var arm: String = args[0] if args.size() > 0 else "live"
	var character_id: String = args[1] if args.size() > 1 else ""
	var lines: PackedStringArray = PackedStringArray()

	var svc = root.get_node_or_null("LLMService")
	var rc = root.get_node_or_null("RuleComposer")
	if svc == null or rc == null:
		lines.append("FATAL: LLMService=%s RuleComposer=%s" % [svc, rc])
		_write(arm, lines)
		quit(2)
		return

	var dir_path: String = "res://tmp/replies_%s" % arm
	var d := DirAccess.open(dir_path)
	if d == null:
		lines.append("FATAL: no such dir %s" % dir_path)
		_write(arm, lines)
		quit(2)
		return

	## A capture is only interpretable against the job it was composed FOR. Replaying a fighter
	## capture as a mage reports a plausible, specific, WRONG fallback rate — 15 of 48, every
	## message naming a real fighter ability "not in mage's level-1 kit". The number reads as a
	## composer defect and is an argument error. If the capture recorded its job, honour it.
	var recorded: String = ""
	if FileAccess.file_exists(dir_path + "/_job.txt"):
		recorded = FileAccess.get_file_as_string(dir_path + "/_job.txt").strip_edges()
	if recorded != "":
		if character_id == "":
			character_id = recorded
		elif character_id != recorded:
			lines.append("FATAL: %s was captured for '%s', not '%s' — every 'not in kit' reason below would be about the wrong character" % [arm, recorded, character_id])
			_write(arm, lines)
			quit(2)
			return

	# Install the replay backend exactly as the live-path tests do.
	var backend := ReplayBackend.new()
	backend.name = "ReplayBE"
	svc.add_child(backend)
	svc.llm_enabled = true
	svc._backends.clear()
	svc._backends.append(backend)
	backend.request_finished.connect(svc._on_backend_finished)
	svc._active_backend = backend

	var names: Array = []
	for f in d.get_files():
		## `_`-prefixed files are capture METADATA, not replies. Without this, _job.txt is replayed
		## as a reply, fails to parse, and counts as a fallback — the guard above would have
		## inflated the very number it exists to protect.
		if f.ends_with(".txt") and not f.begins_with("_"):
			names.append(f)
	names.sort()

	var reached := 0
	var fallback := 0
	var unreadable: PackedStringArray = PackedStringArray()
	var err_tally: Dictionary = {}
	for f in names:
		## An unreadable capture reads as "" and ReplayBackend emits it as a SUCCESSFUL empty
		## reply, so it fails to parse and lands in `fallback` — inflating the exact number this
		## tool exists to measure, one file at a time, with nothing on screen saying so. Same
		## mechanism the `_`-prefix filter above already guards for metadata; a file that goes
		## unreadable reaches it by a different route and must leave the SCORED population.
		var captured: String = FileAccess.get_file_as_string("%s/%s" % [dir_path, f])
		if captured == "":
			unreadable.append(f)
			lines.append("%-10s UNREADABLE — not scored (empty read, err=%d)"
				% [f, FileAccess.get_open_error()])
			continue
		backend.next_text = captured
		var res: Dictionary = await rc.compose_async(
			rc.DOMAIN_AUTOBATTLE, "replayed capture", character_id, [])
		var src: String = str(res.get("source", "?"))
		var errs: Array = res.get("errors", [])
		var notes: Array = res.get("notes", []) if res.has("notes") else []
		if src == "llm":
			reached += 1
			lines.append("%-10s REACHES THE PLAYER  rules=%d  adjusted=%d"
				% [f, (res.get("rules", []) as Array).size(), notes.size()])
		else:
			fallback += 1
			for e in errs:
				err_tally[str(e)] = int(err_tally.get(str(e), 0)) + 1
			lines.append("%-10s fallback (%s)  %s" % [f, src, ", ".join(errs).left(110)])

	lines.append("")
	var scored: int = reached + fallback
	## The rates are over what was SCORED, never over what was on disk — a denominator counting
	## files nobody could read reports a plausible, specific, wrong fallback rate.
	lines.append("arm=%s  character=%s  files=%d  scored=%d  unreadable=%d"
		% [arm, character_id, names.size(), scored, unreadable.size()])
	if unreadable.size() > 0:
		lines.append("  UNREADABLE (excluded)  %s" % ", ".join(unreadable))
	lines.append("  REACHES THE PLAYER   %d/%d   <- compose_async's own verdict" % [reached, scored])
	lines.append("  fallback             %d/%d" % [fallback, scored])
	for e in err_tally.keys():
		lines.append("    x%d  %s" % [err_tally[e], e])
	## FLOOR: a corpus that went entirely dark scores 0/0 and every rate reads as a clean 100%.
	## Refuse rather than publish a number derived from nothing.
	if scored == 0 and names.size() > 0:
		lines.append("FATAL: %d capture(s) present, NONE readable — no rate can be derived" % names.size())
		_write(arm, lines)
		quit(2)
		return
	_write(arm, lines)
	quit(0)


func _write(arm: String, lines: PackedStringArray) -> void:
	var out := FileAccess.open("res://tmp/composebench_%s.txt" % arm, FileAccess.WRITE)
	if out != null:
		out.store_string("\n".join(lines) + "\n")
		out.close()
