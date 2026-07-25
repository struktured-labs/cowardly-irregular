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


## Named-canon W1 speakers → their canonical theme. Round 1 (2026-07-16) pinned
## Elder Theron only; round 2 (same day) generalized after finding Bram
## villager-tagged in world1_bram_shield and Phil villager-tagged (with the
## wrong name "Phil") in world1_orrery. Add new principals here as they get
## authored — the ratchet catches any drift.
const NAMED_CANON_THEMES := {
	# W1
	"Elder Theron": "elder",
	"Scholar Milo": "scholar",
	"Bram": "shopkeeper",
	"Phil the Lost": "mysterious",
	# W2-W5 (2026-07-25 sweep). Canon = the character's roster/dedicated file
	# (*_npcs.json, *_guidance_*.json); drift consistently appeared in chapter
	# and orrery scenes where the NPC inherited the scene's dominant tone.
	"Mail Carrier": "elder",          # canon: world2_maple_heights_npcs
	"Union Rep": "elder",             # canon: world4_rivet_row_npcs
	"Firewall Attendant": "system",   # canon: world5_guidance_core
}


func test_named_canon_speakers_use_canonical_theme() -> void:
	var offenders: Array = []
	_iter_dialogue_lines(func(path: String, line: Dictionary):
		var spk: String = str(line.get("speaker", ""))
		if not NAMED_CANON_THEMES.has(spk):
			return
		var expected: String = NAMED_CANON_THEMES[spk]
		var actual: String = str(line.get("theme", ""))
		if actual != expected:
			offenders.append("%s: '%s' theme='%s' (expected '%s')" % [path.get_file(), spk, actual, expected])
	)
	assert_eq(offenders.size(), 0,
		"named-canon speakers must use their canonical theme:\n  %s" % "\n  ".join(offenders))


func test_phil_the_lost_speaker_name_is_canonical() -> void:
	# Author-drift pin: the character's canonical name is "Phil the Lost"
	# (per world1_chapter1 proof scene + HarmoniaVillage NPC registry). One
	# early scene called him just "Phil" — the name inconsistency broke
	# NAMED_CANON theme matching and any future speaker-key lookups.
	var offenders: Array = []
	_iter_dialogue_lines(func(path: String, line: Dictionary):
		if str(line.get("speaker", "")) == "Phil":
			offenders.append(path.get_file())
	)
	assert_eq(offenders.size(), 0,
		"'Phil' is not canonical — use 'Phil the Lost' (matches HARMONIA_NPC_CANON + world1_chapter1):\n  %s" % "\n  ".join(offenders))


## Party jobs legitimately vary their PORTRAIT via EXPRESSION_TINTS suffixes
## ("bard_happy", "cleric_sad") — that's the emotion feature working, not drift.
## Their THEME must still be constant.
const EXPRESSION_SUFFIXES := ["angry", "sad", "happy", "surprised", "worried", "determined", "mysterious"]


func _strip_expression(portrait: String) -> String:
	for e in EXPRESSION_SUFFIXES:
		if portrait.ends_with("_" + e):
			return portrait.substr(0, portrait.length() - e.length() - 1)
	return portrait


func test_no_named_speaker_drifts_theme_across_files() -> void:
	# GENERAL drift catcher — supersedes hand-listing every character in
	# NAMED_CANON_THEMES. Any speaker appearing in 2+ files with 2+ different
	# themes is rendering as a different character depending on the scene.
	#
	# 2026-07-25 sweep found three: Union Rep (mysterious/elder/villager across
	# 4 W4 files), Firewall Attendant (system/mysterious across 2 W5 files),
	# Mail Carrier (mysterious/elder across 2 W2 files). Root pattern: chapter
	# and orrery scenes defaulted the NPC's theme to the scene's dominant tone
	# instead of the character's identity from their roster file.
	var themes_by_speaker: Dictionary = {}   # speaker -> {theme: [files]}
	_iter_dialogue_lines(func(path: String, line: Dictionary):
		var spk: String = str(line.get("speaker", "")).strip_edges()
		if spk == "":
			return
		var theme_name: String = str(line.get("theme", ""))
		if not themes_by_speaker.has(spk):
			themes_by_speaker[spk] = {}
		if not themes_by_speaker[spk].has(theme_name):
			themes_by_speaker[spk][theme_name] = []
		var fname := path.get_file()
		if not themes_by_speaker[spk][theme_name].has(fname):
			themes_by_speaker[spk][theme_name].append(fname)
	)
	var offenders: Array = []
	for spk in themes_by_speaker:
		var by_theme: Dictionary = themes_by_speaker[spk]
		if by_theme.size() < 2:
			continue
		var parts: Array = []
		for t in by_theme:
			parts.append("'%s' in %s" % [t, ", ".join(by_theme[t])])
		offenders.append("%s renders as %d different themes — %s" % [spk, by_theme.size(), " | ".join(parts)])
	assert_eq(offenders.size(), 0,
		"a named speaker must look the same in every scene:\n  %s" % "\n  ".join(offenders))


func test_party_portrait_variation_is_expression_only() -> void:
	# Complement to the theme pin: party members MAY vary portrait via the
	# emotion suffix, but the stripped base must stay constant. Catches a
	# genuine mis-tag (Fighter drawn with the mage portrait) while allowing
	# the intentional "fighter_determined" / "cleric_sad" beats.
	var bases_by_speaker: Dictionary = {}
	_iter_dialogue_lines(func(path: String, line: Dictionary):
		var spk: String = str(line.get("speaker", "")).strip_edges()
		if spk == "":
			return
		var base := _strip_expression(str(line.get("portrait", "")))
		if base == "":
			return
		if not bases_by_speaker.has(spk):
			bases_by_speaker[spk] = {}
		bases_by_speaker[spk][base] = true
	)
	var offenders: Array = []
	for spk in bases_by_speaker:
		var bases: Array = bases_by_speaker[spk].keys()
		if bases.size() > 1:
			offenders.append("%s uses %d different portrait bases: %s" % [spk, bases.size(), str(bases)])
	assert_eq(offenders.size(), 0,
		"a speaker's portrait base must be constant (emotion suffixes excepted):\n  %s" % "\n  ".join(offenders))
