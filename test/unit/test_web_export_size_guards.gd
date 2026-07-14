extends GutTest

## 2026-07-03: the web pck crept to 226 MB and itch.io's 200 MB
## HTML5-embed limit broke the deployed page (user report). Two causes
## live here as pins:
## 1. Sprite-pipeline intermediates regenerate on disk and gitignore
##    does NOT stop the exporter — the exclude filter is the only wall.
## 2. W4-W6 music (75 MB of deep-endgame audio, graceful procedural
##    fallback when missing) is web-excluded; desktop keeps it all.
## The deploy pipeline additionally hard-fails on pck ≥ 190 MB.

const REQUIRED_WEB_EXCLUDES := [
	"*.pre_normalize.png",
	"*.pre_palette.png",
	"assets/audio/music/*industrial*",
	"assets/audio/music/*digital*",
	"assets/audio/music/*abstract*",
	"assets/audio/music/*futuristic*",
	"assets/audio/music/cutscene_w4*",
	"assets/audio/music/cutscene_w5*",
	"assets/audio/music/cutscene_w6*",
]


func _web_exclude_filter() -> String:
	var cfg: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var web: int = cfg.find("platform=\"Web\"")
	assert_gt(web, -1, "Web preset must exist")
	# exclude_filter line appears after the platform line within the preset block
	var seg: String = cfg.substr(web, 600)
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
