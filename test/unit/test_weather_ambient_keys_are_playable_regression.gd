extends GutTest

## WeatherSystem names each weather's ambient TWICE: once as WEATHER_TYPES[x]["ambient"] and once
## as a literal branch in the play_ambient match. A value present in the first and missing from the
## second falls to `_: stop_ambient()` — the weather plays SILENCE, which is indistinguishable from
## a quiet bed and never errors. Adding weather_storm_bed created exactly that seam.

const WEATHER := "res://src/exploration/WeatherSystem.gd"
const MANIFEST := "res://data/sfx_manifest.json"


func _src() -> String:
	var s := FileAccess.get_file_as_string(WEATHER)
	assert_ne(s, "", "WeatherSystem.gd unreadable — every check below would pass vacuously")
	return s


func test_every_declared_ambient_has_a_play_branch() -> void:
	var src := _src()
	var declared := RegEx.new()
	declared.compile('"ambient"\\s*:\\s*"([a-z_0-9]+)"')
	var names: Array = []
	for m in declared.search_all(src):
		var n := m.get_string(1)
		if not names.has(n):
			names.append(n)
	assert_true(names.has("weather_rain"), "did not find weather_rain among declared ambients — the scrape is broken, so a clean result below means nothing")
	assert_gt(names.size(), 2, "fewer than 3 distinct ambients declared — the scrape is reading almost nothing")

	var unplayable: Array = []
	for n in names:
		if not ('"%s": sm.play_ambient("%s")' % [n, n]) in src:
			unplayable.append(n)
	if not unplayable.is_empty():
		fail_test("these weathers declare an ambient with NO matching play branch — they fall through to stop_ambient() and play silence: %s" % [unplayable])


func test_every_played_ambient_resolves_in_the_manifest() -> void:
	var src := _src()
	var played := RegEx.new()
	played.compile('sm\\.play_ambient\\("([a-z_0-9]+)"\\)')
	var keys: Array = []
	for m in played.search_all(src):
		var k := m.get_string(1)
		if not keys.has(k):
			keys.append(k)
	assert_gt(keys.size(), 2, "found almost no play_ambient calls — the scrape is broken")

	var raw := FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("weather_rain"), "manifest lacks weather_rain — a known-present member, so this check is not reading the file")

	var missing: Array = []
	for k in keys:
		if not sfx.has(k):
			missing.append(k)
	if not missing.is_empty():
		fail_test("WeatherSystem plays ambient keys absent from the manifest — silence at runtime: %s" % [missing])
