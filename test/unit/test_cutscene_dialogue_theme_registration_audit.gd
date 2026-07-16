extends GutTest

## Regression: playtest 2026-07-16 — Elder Theron in
## world1_harmonia_after_cave.json rendered as unstyled generic narrator
## because he was tagged with `theme: "villager"`, which wasn't in
## CutsceneDialogue.CHARACTER_THEMES at all (fell through to narrator via
## line 656's .get(name, THEMES["narrator"]) default).
##
## The scope of the drift was 52 lines across 7 W1-W5 cutscene files, all
## rendering with grey narrator styling.
##
## Two ratchets:
##   (A) every `theme` value referenced in data/cutscenes/*.json must be
##       registered in CHARACTER_THEMES — no more silent narrator
##       fallbacks for content-side typos.
##   (B) Elder Theron dialogue speakers must use theme="elder" — pins him
##       to his signature warm-amber styling. Named-canon character.
##       (The proof scene, world1_chapter1, already does this correctly;
##       this test catches the harmonia_after_cave-style drift for future
##       Theron-featuring scenes.)


const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"


func _load_registered_themes() -> Array:
	# Load themes from the actual script via `const CHARACTER_THEMES = {`
	# rather than a hand-maintained list — always fresh.
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	assert_not_null(script, "CutsceneDialogue script must load")
	var themes: Dictionary = script.CHARACTER_THEMES
	return themes.keys()


func _iter_dialogue_lines(callback: Callable) -> void:
	# Walk every dialogue step in every data/cutscenes/*.json.
	# callback(cutscene_path, line_dict)
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path = "res://data/cutscenes/%s" % f
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "dialogue":
				continue
			for line in step.get("lines", []):
				if line is Dictionary:
					callback.call(path, line)


func test_villager_theme_is_registered() -> void:
	# Direct pin for the fix: villager theme must exist. Without it, the 52
	# villager-tagged lines fall back to narrator's grey styling.
	var registered = _load_registered_themes()
	assert_true("villager" in registered,
		"CHARACTER_THEMES must have a `villager` entry — playtest 2026-07-16 found the after-cave scene rendering all villagers (and Theron mis-tagged as villager) with narrator's grey box")


func test_every_dialogue_theme_referenced_in_json_is_registered() -> void:
	var registered = _load_registered_themes()
	var missing: Dictionary = {}  # theme -> [example_paths]
	_iter_dialogue_lines(func(path: String, line: Dictionary):
		var theme_name: String = str(line.get("theme", ""))
		if theme_name == "" or theme_name in registered:
			return
		if not missing.has(theme_name):
			missing[theme_name] = []
		if missing[theme_name].size() < 3:
			missing[theme_name].append(path.get_file())
	)
	if not missing.is_empty():
		var reports: Array = []
		for t in missing:
			reports.append("'%s' (e.g. in %s)" % [t, ", ".join(missing[t])])
		assert_true(false,
			"cutscene dialogue references themes not in CHARACTER_THEMES (silent narrator fallback):\n  %s" % "\n  ".join(reports))
	else:
		assert_true(true)


func test_elder_theron_speaker_uses_elder_theme() -> void:
	# Named-canon character: Elder Theron always gets his `elder` styling.
	# Content-drift pin — the world1_harmonia_after_cave scene shipped with
	# 7 Theron lines mis-tagged as villager, giving him generic-npc treatment
	# in a scene where his lines are the emotional beat.
	var offenders: Array = []
	_iter_dialogue_lines(func(path: String, line: Dictionary):
		if str(line.get("speaker", "")) != "Elder Theron":
			return
		if str(line.get("theme", "")) != "elder":
			offenders.append("%s: theme='%s'" % [path.get_file(), line.get("theme", "")])
	)
	assert_eq(offenders.size(), 0,
		"Elder Theron speaker lines must use theme='elder' (his named-canon warm-amber styling):\n  %s" % "\n  ".join(offenders))
