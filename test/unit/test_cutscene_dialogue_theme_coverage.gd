extends GutTest

## tick 294: CutsceneDialogue.CHARACTER_THEMES now covers all 14 jobs.
##
## Pre-fix only the 5 starter jobs (fighter / cleric / mage / rogue
## / bard) had theme entries. Any cutscene line tagged with a non-
## starter job as `theme` fell through to "narrator"'s flat gray
## via the line-585 fallback (CHARACTER_THEMES.get(name,
## CHARACTER_THEMES["narrator"])).
##
## Same visual-voice gap as the 5-tick meta-job sweep (289-293):
## per-job theming established in JOB_QUIP_COLORS (tick 124) and
## Win98Menu CHARACTER_STYLES (tick 293) didn't carry into cutscene
## dialogue panels.
##
## Each new scheme anchors on JOB_QUIP_COLORS base color matching
## the registers already documented in Win98Menu's per-job theme.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"

const ALL_JOB_IDS: Array[String] = [
	# Starter
	"fighter", "cleric", "mage", "rogue", "bard",
	# Advanced
	"guardian", "ninja", "summoner", "speculator",
	# Meta
	"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Each job has a theme entry ────────────────────────────────────

func test_every_job_has_character_theme() -> void:
	var src := _read(CUTSCENE_DIALOGUE)
	var start: int = src.find("const CHARACTER_THEMES = {")
	assert_gt(start, -1, "CHARACTER_THEMES const must exist")
	var end: int = src.find("\n}", start)
	var body: String = src.substr(start, end - start + 2)
	var missing: Array[String] = []
	for jid in ALL_JOB_IDS:
		if not body.contains("\"%s\":" % jid):
			missing.append(jid)
	assert_eq(missing.size(), 0,
		"CHARACTER_THEMES must cover every job: %s" % str(missing))


# ── Each theme has all 5 required keys ────────────────────────────

func test_each_theme_has_required_keys() -> void:
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	var themes: Dictionary = script.CHARACTER_THEMES
	const REQUIRED_KEYS := ["bg", "border", "text", "name", "portrait_bg"]
	var partial: Array[String] = []
	for jid in ALL_JOB_IDS:
		var t: Dictionary = themes.get(jid, {})
		for k in REQUIRED_KEYS:
			if not t.has(k):
				partial.append("%s missing %s" % [jid, k])
	assert_eq(partial.size(), 0,
		"each theme must have all 5 required keys: %s" % str(partial))


# ── Advanced/meta themes differ from narrator (visual distinctness) ─

func test_non_starter_themes_differ_from_narrator() -> void:
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	var themes: Dictionary = script.CHARACTER_THEMES
	var narrator: Dictionary = themes["narrator"]
	var clones: Array[String] = []
	for jid in ["guardian", "ninja", "summoner", "speculator",
			"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"]:
		var t: Dictionary = themes[jid]
		# If border AND bg match narrator, it's a copy-paste regression.
		if t["border"] == narrator["border"] and t["bg"] == narrator["bg"]:
			clones.append(jid)
	assert_eq(clones.size(), 0,
		"new themes must visually differ from narrator (catches copy-paste): %s" % str(clones))


# ── Narrator still the fallback ───────────────────────────────────

## Was a source pin on the literal `CHARACTER_THEMES.get(theme_name, …)` call. That went
## RED when the lookup gained an alias step, even though the invariant it names — unknown
## themes fall back to narrator — was fully preserved. Pinning the expression made a
## correct change fail; this drives the resolver and tests the invariant itself.
func test_narrator_still_fallback() -> void:
	var dlg = load(CUTSCENE_DIALOGUE).new()
	add_child_autofree(dlg)
	var themes: Dictionary = load(CUTSCENE_DIALOGUE).get_script_constant_map().get("CHARACTER_THEMES", {})
	assert_true(themes.has("narrator"), "PRECONDITION: the narrator theme must exist")
	assert_eq(dlg.resolve_theme("zzz_unknown_theme"), themes["narrator"],
		"an unrecognised theme must still fall back to CHARACTER_THEMES[\"narrator\"]")
	assert_ne(dlg.resolve_theme("zzz_unknown_theme"), themes["villager"],
		"NEGATIVE CONTROL: an unknown theme must not resolve to a real palette")


# ── Cross-pin: tick 293 Win98Menu coverage preserved ──────────────

func test_win98_menu_character_styles_still_has_all_14() -> void:
	var win98: String = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	for jid in ALL_JOB_IDS:
		assert_true(win98.contains("\"%s\":" % jid),
			"Win98Menu.CHARACTER_STYLES must still have %s entry (tick 293 fix)" % jid)
