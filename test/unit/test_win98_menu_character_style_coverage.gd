extends GutTest

## tick 293: Win98Menu.CHARACTER_STYLES now covers all 14 jobs.
##
## Pre-fix only the 5 starter jobs (fighter / cleric / mage / rogue
## / bard) had styles. Advanced (4) and meta (5) jobs fell through
## to fighter's blue scheme via the line-436 fallback (CHARACTER
## _STYLES.get(class) else CHARACTER_STYLES["fighter"]).
##
## Same visual-voice gap as tick 124's JOB_QUIP_COLORS fix. A
## Necromancer's battle command menu looked indistinguishable from a
## Fighter's even though their JOB_QUIP_COLORS bubble was violet.
##
## Each new scheme anchors on the JOB_QUIP_COLORS base color and
## modulates for the menu palette (dark bg, bright border, accent
## highlight). Color rationale documented per-entry in source.

const WIN98_MENU := "res://src/ui/Win98Menu.gd"

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


# ── Each job has a style entry ────────────────────────────────────

func test_every_job_has_character_style() -> void:
	var src := _read(WIN98_MENU)
	var start: int = src.find("const CHARACTER_STYLES = {")
	assert_gt(start, -1, "CHARACTER_STYLES const must exist")
	var end: int = src.find("\n}", start)
	var body: String = src.substr(start, end - start + 2)
	var missing: Array[String] = []
	for jid in ALL_JOB_IDS:
		if not body.contains("\"%s\":" % jid):
			missing.append(jid)
	assert_eq(missing.size(), 0,
		"CHARACTER_STYLES must cover every job: %s" % str(missing))


# ── Each style has all 7 required keys ───────────────────────────

func test_each_style_has_required_keys() -> void:
	# bg / border / border_shadow / text / highlight_bg /
	# highlight_text / cursor. Catches a partial-copy regression where
	# a new style block missed a key.
	var script: GDScript = load(WIN98_MENU)
	var styles: Dictionary = script.CHARACTER_STYLES
	const REQUIRED_KEYS := ["bg", "border", "border_shadow", "text",
		"highlight_bg", "highlight_text", "cursor"]
	var partial: Array[String] = []
	for jid in ALL_JOB_IDS:
		var s: Dictionary = styles.get(jid, {})
		for k in REQUIRED_KEYS:
			if not s.has(k):
				partial.append("%s missing %s" % [jid, k])
	assert_eq(partial.size(), 0,
		"each style must have all 7 required keys: %s" % str(partial))


# ── Styles are not identical to fighter (visual distinctness) ────

func test_advanced_and_meta_styles_differ_from_fighter() -> void:
	# Catches the bug class where someone copy-pastes the fighter
	# style into a new job entry and forgets to recolor it.
	var script: GDScript = load(WIN98_MENU)
	var styles: Dictionary = script.CHARACTER_STYLES
	var fighter: Dictionary = styles["fighter"]
	var clones: Array[String] = []
	for jid in ALL_JOB_IDS:
		if jid == "fighter":
			continue
		var s: Dictionary = styles[jid]
		# If border AND bg AND highlight_text all match fighter, it's
		# a copy-paste. Single-key matches are fine (purposeful sharing).
		if s["border"] == fighter["border"] and s["bg"] == fighter["bg"] \
				and s["highlight_text"] == fighter["highlight_text"]:
			clones.append(jid)
	assert_eq(clones.size(), 0,
		"non-fighter styles must visually differ from fighter (catches copy-paste): %s" % str(clones))


# ── Fighter still the fallback in source ─────────────────────────

func test_fallback_still_fighter() -> void:
	# Source pin: the .has() fallback path still routes to fighter
	# for unknown/modded job ids. Catches an accidental fallback
	# change that would make custom jobs render as e.g. necromancer.
	var src := _read(WIN98_MENU)
	assert_true(src.contains("style = CHARACTER_STYLES[\"fighter\"]"),
		"unknown-class fallback must still be CHARACTER_STYLES[\"fighter\"]")


# ── Cross-pin: JOB_QUIP_COLORS still has all 14 (tick 124) ──────

func test_job_quip_colors_still_has_all_14() -> void:
	var bs: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	for jid in ALL_JOB_IDS:
		assert_true(bs.contains("\"%s\": Color(" % jid),
			"JOB_QUIP_COLORS must still have %s entry (tick 124 fix preserved)" % jid)
