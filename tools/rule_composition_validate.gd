extends SceneTree

## Score raw model replies through the REAL RuleComposer pipeline.
##
## Exists because an ad-hoc `json.loads(response)` scores a shape the game never
## sees: the shipped contract is {name, description, rules_json} where rules_json
## is a STRINGIFIED array, and LLMService strips fences and slices braces before
## anything parses. Scoring by hand called a correctly-double-encoded reply a
## parse failure and a fatal grammar error a 9-of-11 pass.
##
## Reads tmp/replies_<arm>/*.txt, writes tmp/rulebench_<arm>.txt.
## The unit is the COMPOSITION, not the rule: RuleComposer discards the whole
## ruleset when any single rule fails grammar, so one bad target loses all of it.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _init() -> void:
	# Autoloads are not attached to /root yet at _init; they arrive on the first frame.
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var arm: String = args[0] if args.size() > 0 else "after"
	var character_id: String = args[1] if args.size() > 1 else ""
	var repair: bool = not args.has("--norepair")
	var dir_path: String = "res://tmp/replies_%s" % arm

	var svc = root.get_node_or_null("LLMService")
	var abs = root.get_node_or_null("AutobattleSystem")
	var lines: PackedStringArray = PackedStringArray()
	if svc == null or abs == null:
		lines.append("FATAL: LLMService=%s AutobattleSystem=%s" % [svc, abs])
		_write(arm, lines)
		quit(2)
		return

	var rc = root.get_node_or_null("RuleComposer")
	if rc == null:
		rc = load("res://src/llm/RuleComposer.gd").new()

	var d := DirAccess.open(dir_path)
	if d == null:
		lines.append("FATAL: no such dir %s" % dir_path)
		_write(arm, lines)
		quit(2)
		return

	var names: Array = []
	for f in d.get_files():
		if f.ends_with(".txt"):
			names.append(f)
	names.sort()

	var n_extract := 0
	var n_schema := 0
	var n_parse := 0
	var n_clean := 0
	var total_rules := 0
	var bad_rules := 0
	var err_tally: Dictionary = {}

	for f in names:
		var raw: String = FileAccess.get_file_as_string("%s/%s" % [dir_path, f])
		var extracted: Variant = svc._extract_json_from_raw(raw.strip_edges())
		if not (extracted is Dictionary):
			lines.append("%-10s EXTRACT-FAIL" % f)
			continue
		n_extract += 1

		var guarded: Variant = svc._guard_json(raw, DP.SCHEMA_RULE_COMPOSITION, null)
		if not (guarded is Dictionary):
			lines.append("%-10s SCHEMA-FAIL  keys=%s" % [f, (extracted as Dictionary).keys()])
			continue
		n_schema += 1

		var v: Dictionary = DP.validate_rule_composition(guarded as Dictionary, "autobattle")
		if not bool(v["parse_ok"]):
			lines.append("%-10s RULES_JSON-UNPARSEABLE" % f)
			continue
		n_parse += 1

		var rules: Array = v["rules"]
		# Apply the SHIPPING repair, not a copy of it.
		if repair and character_id != "" and rc != null and abs.has_method("get_deep_check_kit"):
			rc._supply_missing_mp_guards(rules, abs.get_deep_check_kit(character_id))
		var errs: Array[String] = []
		var bad_here := 0
		for r in rules:
			var re: Array = abs.validate_rule(r, character_id)
			if re.size() > 0:
				bad_here += 1
			for e in re:
				errs.append(str(e))
				err_tally[str(e)] = int(err_tally.get(str(e), 0)) + 1
		total_rules += rules.size()
		bad_rules += bad_here

		# The shipped gate: ANY grammar error discards the WHOLE composition.
		if errs.is_empty() and rules.size() > 0:
			n_clean += 1
			lines.append("%-10s OK           rules=%d  name=%s" % [f, rules.size(), v["name"]])
		else:
			lines.append("%-10s DISCARDED    rules=%d bad=%d  %s"
				% [f, rules.size(), bad_here, ", ".join(errs).left(120)])

	lines.append("")
	lines.append("arm=%s  character=%s  samples=%d" % [arm, character_id if character_id != "" else "(shallow)", names.size()])
	lines.append("  extracted a JSON object      %d/%d" % [n_extract, names.size()])
	lines.append("  matched the schema           %d/%d" % [n_schema, names.size()])
	lines.append("  rules_json parsed            %d/%d" % [n_parse, names.size()])
	lines.append("  COMPOSITION SURVIVES         %d/%d   <- what the player gets" % [n_clean, names.size()])
	lines.append("  rules: %d total, %d rejected" % [total_rules, bad_rules])
	for e in err_tally.keys():
		lines.append("    x%d  %s" % [err_tally[e], e])
	_write(arm, lines)
	quit(0)


func _write(arm: String, lines: PackedStringArray) -> void:
	var out := FileAccess.open("res://tmp/rulebench_%s.txt" % arm, FileAccess.WRITE)
	if out != null:
		out.store_string("\n".join(lines) + "\n")
		out.close()
