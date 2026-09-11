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
##   godot --headless --script tools/rule_composition_compose.gd -- <arm> <character_id>
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
		if f.ends_with(".txt"):
			names.append(f)
	names.sort()

	var reached := 0
	var fallback := 0
	var err_tally: Dictionary = {}
	for f in names:
		backend.next_text = FileAccess.get_file_as_string("%s/%s" % [dir_path, f])
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
	lines.append("arm=%s  character=%s  samples=%d" % [arm, character_id, names.size()])
	lines.append("  REACHES THE PLAYER   %d/%d   <- compose_async's own verdict" % [reached, names.size()])
	lines.append("  fallback             %d/%d" % [fallback, names.size()])
	for e in err_tally.keys():
		lines.append("    x%d  %s" % [err_tally[e], e])
	_write(arm, lines)
	quit(0)


func _write(arm: String, lines: PackedStringArray) -> void:
	var out := FileAccess.open("res://tmp/composebench_%s.txt" % arm, FileAccess.WRITE)
	if out != null:
		out.store_string("\n".join(lines) + "\n")
		out.close()
