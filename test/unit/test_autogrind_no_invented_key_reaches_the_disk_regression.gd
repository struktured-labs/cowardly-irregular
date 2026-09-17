extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## @cowir-ai measured a defect worth generalising: an unvalidated string reaches a Dictionary that
## AUTO-CREATES on miss, and the dictionary is persisted — so one composed rule writes a phantom
## entry into the player's save. Their vector was an LLM inventing a character id.
##
## Autogrind has the same shape and is safe for a WEAKER reason than @cowir-sfx's lane, which is the
## point of this file. Theirs refuses the key in the CALLEE (`if not _sfx_manifest.has(key): return`),
## so it holds no matter who calls. Mine holds because the callers happen to be engine-side:
## `update_learned_patterns` and `set_current_region` both auto-create without checking, and the
## first writes `user://autogrind/learned_patterns.json`.
##
## ⛔ A RUNTIME GUARD IS THE WRONG REPAIR HERE AND I CHECKED BEFORE ASSUMING: there is no canonical
## region roster to validate against, so refusing an unknown region_id would silently stop pattern
## learning for a legitimately new map — a worse failure than the one it prevents, and a silent one.
## The property that actually holds is about the CALL GRAPH, so that is what this file pins: the day
## a fourth writer appears, someone has to look at where its string comes from.

const WRITERS := {
	"set_current_region": ["res://src/autogrind/AutogrindController.gd", "res://src/autogrind/AutogrindSystem.gd"],
	"update_learned_patterns": ["res://src/GameLoop.gd"],
}

## Surfaces that author strings a player or a model can influence. None may reach a writer above.
const EXTERNAL_AUTHORS := [
	"res://src/llm/RuleComposer.gd",
	"res://src/autobattle/ScriptShareManager.gd",
]


func _src_files() -> Array:
	var out: Array = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if str(f).ends_with(".gd"):
				out.append("%s/%s" % [d, str(f)])
	return out


func _callers_of(fn: String, files: Array) -> Array:
	var out: Array = []
	for path in files:
		var code: String = GdSource.code_of(str(path))
		if code.contains("%s(" % fn) and not code.contains("func %s(" % fn):
			out.append(str(path))
		elif code.contains("func %s(" % fn):
			## the declaring file may also call it — count it only if it does so outside the `func` line
			var without_decl: String = code.replace("func %s(" % fn, "")
			if without_decl.contains("%s(" % fn):
				out.append(str(path))
	out.sort()
	return out


func test_the_auto_creating_writers_have_exactly_the_callers_we_have_checked() -> void:
	var files: Array = _src_files()
	assert_gt(files.size(), 100, "CONTROL: the src sweep must actually find files, or every set below is empty by accident")
	for fn in WRITERS:
		var expected: Array = (WRITERS[fn] as Array).duplicate()
		expected.sort()
		var actual: Array = _callers_of(str(fn), files)
		gut.p("    %s <- %s" % [fn, str(actual)])
		assert_eq(actual, expected,
			"the caller set of %s changed. It auto-creates a persisted key, so a new caller needs its ARGUMENT traced: if the string is player- or LLM-authored, this is @cowir-ai's phantom-key defect and the key must be validated before the write" % fn)


func test_no_external_author_reaches_a_writer() -> void:
	## The direct question, asked independently of the caller set so a rename cannot dodge both.
	var offenders: Array = []
	for path in EXTERNAL_AUTHORS:
		if not ResourceLoader.exists(path):
			continue
		var code: String = GdSource.code_of(path)
		assert_gt(code.length(), 200, "CONTROL: %s was actually read" % path)
		for fn in WRITERS:
			if code.contains("%s(" % fn):
				offenders.append("%s calls %s" % [path, fn])
	gut.p("    external authors reaching an auto-creating writer: %s" % str(offenders))
	assert_eq(offenders, [],
		"a player- or model-authored string now reaches a dictionary that auto-creates and persists: %s" % str(offenders))


func test_the_composer_still_refuses_a_character_id_for_the_grind() -> void:
	## ⛔ THE REFUSAL @cowir-ai's DEFECT TURNED ON, pinned from this side because it is load-bearing
	## for MY lane too: autogrind rules are party-level, so the composer errors rather than passing an
	## id through. That refusal is why no model-authored id exists here to become a phantom key.
	var rc: String = GdSource.code_of("res://src/llm/RuleComposer.gd")
	assert_gt(rc.length(), 500, "CONTROL: RuleComposer was actually read")
	assert_true(rc.contains("autogrind domain must not receive a character_id"),
		"RuleComposer no longer refuses a character_id on the autogrind domain — a model-authored id can now reach grind state, which is exactly @cowir-ai's vector")


func test_the_persisted_dict_really_does_auto_create() -> void:
	## ⛔ THE PREMISE ARM. Everything above is only worth running while these writers are genuinely
	## unguarded — if someone adds a validation check, this file's framing is stale and should say so
	## rather than keep pinning a call graph that no longer matters.
	##
	## ⛔ IT ASKS FOR THE ABSENCE OF A GUARD, NOT THE PRESENCE OF THE AUTO-CREATE LINE, and the first
	## version asked the wrong one: inserting `if not _is_known_region(region_id): return` ABOVE the
	## auto-create left that line intact, so the arm stayed green while the premise it names had been
	## repaired. An arm that cannot see the thing it exists to notice — mutation caught it, reading
	## did not, second time tonight in this lane. A validating guard has to bail out, so the tell is a
	## `return` between the signature and the auto-create.
	var ags: String = GdSource.code_of("res://src/autogrind/AutogrindSystem.gd")
	var fn_at: int = ags.find("func update_learned_patterns(")
	assert_gt(fn_at, 0, "CONTROL: update_learned_patterns must be locatable")
	var create_at: int = ags.find("if not learned_patterns.has(region_id):", fn_at)
	assert_gt(create_at, fn_at,
		"learned_patterns no longer auto-creates on an unknown region — if it now VALIDATES, this file can relax: the property moved from the call graph into the callee, which is the stronger place for it")
	var preamble: String = ags.substr(fn_at, create_at - fn_at)
	assert_false(preamble.contains("return"),
		"update_learned_patterns now bails out before the auto-create, so it GUARDS the key rather than trusting its callers — the stronger place for this property. Relax this file to the composer arm and delete the call-graph pins")
	assert_true(ags.contains("user://autogrind/learned_patterns.json"),
		"learned_patterns is no longer persisted — without a disk write this whole class is a memory-only curiosity")
