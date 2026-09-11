extends GutTest

## 2026-07-03: the web pck crept to 226 MB and itch.io's 200 MB
## HTML5-embed limit broke the deployed page (user report). Two causes
## live here as pins:
## 1. Sprite-pipeline intermediates regenerate on disk and gitignore
##    does NOT stop the exporter — the exclude filter is the only wall.
## 2. W4-W6 music (75 MB of deep-endgame audio, graceful procedural
##    fallback when missing) is web-excluded; desktop keeps it all.
## The deploy pipeline additionally hard-fails on pck ≥ 190 MB.

## ⚠️ cutscene_w6* was here until 2026-09-11 and was REMOVED DELIBERATELY.
## Its nine beds ship now: world6_ending stopped its music, requested
## cutscene_w6_epilogue, and got silence for the rest of the campaign's
## closer on web. +7.02 MiB at the shipped 48k tier, 6.3 MiB inside the warn
## band (cowir-deploy, measured on the real pack), and reversible to the byte
## by putting the glob back. cowir-main ruled 2026-09-11.
##
## Anything still listed here must stay out. Removing an entry is a budget
## decision with a measurement behind it, not a cleanup.
const REQUIRED_WEB_EXCLUDES := [
	"*.pre_normalize.png",
	"*.pre_palette.png",
	"assets/audio/music/*futuristic*",
	"assets/audio/music/cutscene_w4*",
	"assets/audio/music/cutscene_w5*",
]


func _web_exclude_filter() -> String:
	var cfg: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var web: int = cfg.find("platform=\"Web\"")
	assert_gt(web, -1, "Web preset must exist")
	## Line-scoped, not a char window: at 1283 chars the filter overran the old substr(web, 600), find("\n") returned -1, and the read truncated mid-list — reporting still-present classes as LOST.
	## Bounded by the PRESET, not by a char count and not unbounded. It was
	## substr(web, 600) — too short, and the filter line outgrew it. Unbounded
	## replaced that with a worse failure: with no exclude_filter in the Web
	## preset, find() returns the NEXT preset's line instead of -1, so the guard
	## would vouch for Android's exclusions while reporting on Web.
	var tail: String = cfg.substr(web)
	var nxt: int = tail.find("platform=", 1)
	var seg: String = tail.substr(0, nxt) if nxt > -1 else tail
	var f: int = seg.find("exclude_filter=")
	assert_gt(f, -1)
	return seg.substr(f, seg.find("\n", f) - f)


func test_web_preset_excludes_all_size_offenders() -> void:
	var filter := _web_exclude_filter()
	for pat in REQUIRED_WEB_EXCLUDES:
		assert_true(filter.contains(pat),
			"web exclude_filter lost '%s' — that class re-bloats the pck past itch's 200 MB embed limit" % pat)


func test_w1_w3_music_is_not_excluded() -> void:
	var filter := _web_exclude_filter()
	for pat in ["medieval", "suburban", "steampunk"]:
		assert_false(filter.contains(pat),
			"reachable-world (W1-W3) music must ship — '%s' found in the web exclude filter" % pat)

## The three W4-W6 world classes used to be pinned as the bare globs
## `*industrial*` / `*digital*` / `*abstract*` in REQUIRED_WEB_EXCLUDES above.
## That pinned the FORM of the exclusion, so un-excluding one file meant
## deleting the guard. This asks the question the guard exists for instead:
## does every W4-W6 world bed still stay out of the pack?
const WEB_RESCUED := ["credits_industrial.ogg", "credits_digital.ogg", "credits_abstract.ogg"]


func test_w4_w6_world_music_stays_out_of_the_pack_except_the_credits_beds() -> void:
	var filter := _web_exclude_filter()
	var globs: PackedStringArray = filter.split('"')[1].split(",")
	var dir := DirAccess.open("res://assets/audio/music")
	assert_not_null(dir, "SCOPE control: the music directory did not open")
	var leaked: Array[String] = []
	var rescued: Array[String] = []
	var walked: int = 0
	for f in dir.get_files():
		var name: String = str(f)
		if not name.ends_with(".ogg"):
			continue
		if not (name.contains("industrial") or name.contains("digital") or name.contains("abstract")):
			continue
		walked += 1
		var path: String = "assets/audio/music/" + name
		var hit: bool = false
		for g in globs:
			if path.match(str(g).strip_edges()):
				hit = true
				break
		if hit:
			continue
		if WEB_RESCUED.has(name):
			rescued.append(name)
		else:
			leaked.append(name)
	assert_gt(walked, 30, "SCOPE control: only %d W4-W6 world beds walked — the name test stopped selecting" % walked)
	assert_eq(leaked.size(), 0,
		"%d W4-W6 world bed(s) now ship on web that did not before: %s — a replacement glob is missing a content prefix, and the pck grows by bytes nobody asked for" % [leaked.size(), leaked])
	assert_eq(rescued.size(), WEB_RESCUED.size(),
		"the credits beds this preset deliberately ships are not all shipping (%d of %d): %s — world6_ending's roll_credits step names credits_abstract and the campaign ending would roll in silence" % [rescued.size(), WEB_RESCUED.size(), rescued])
