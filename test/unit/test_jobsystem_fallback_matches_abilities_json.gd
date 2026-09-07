extends GutTest

## JobSystem._create_default_abilities() is a SECOND definition of ability data, used when
## abilities.json is missing or unopenable. It is the documented two-sources-one-surface shape:
## the Latin rebrand (2026-08-22) renamed 23 spells in the JSON and this block still held
## "Fire"/"Cure"/"Curia" until it was synced by hand. Nothing warns when they drift, because the
## fallback only runs on a path nobody tests interactively — so the agreement is asserted here.

const FALLBACK_FN := "func _create_default_abilities"


func _json_abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d


## Every "<id>": { ... "name": "<name>" } pair declared inside the fallback function.
func _fallback_pairs() -> Dictionary:
	var src := FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var start := src.find(FALLBACK_FN)
	assert_gt(start, -1, "%s must exist — if it was deleted, delete this test with it" % FALLBACK_FN)
	var end := src.find("\nfunc ", start + 1)
	var body := src.substr(start, (end - start) if end > -1 else src.length() - start)
	var out: Dictionary = {}
	var re := RegEx.create_from_string("\"([a-z_]+)\"\\s*:\\s*\\{\\s*\"id\"\\s*:\\s*\"([a-z_]+)\"\\s*,\\s*\"name\"\\s*:\\s*\"([^\"]+)\"")
	for m in re.search_all(body):
		out[m.get_string(1)] = m.get_string(3)
	return out


## Ids the fallback defines that the live data does not. The fallback is allowed its own
## coherent minimal set — it runs when abilities.json is ABSENT — so this is a ratchet on a
## known divergence, not a subset rule. `sneak_attack` is the fallback's rogue opener; the live
## rogue learns `backstab` instead, and jobs.json has no dangling refs, so the two are simply
## snapshots of different days. New entries here mean fresh drift and should be explained.
const FALLBACK_ONLY := ["sneak_attack"]


func test_the_fallback_parses_and_its_json_orphans_do_not_grow() -> void:
	var fb := _fallback_pairs()
	assert_gt(fb.size(), 5, "parsed %d fallback abilities — a zero here means the regex broke, not that the block is empty" % fb.size())
	var a := _json_abilities()
	var orphans: Array = []
	for id in fb:
		if not a.has(id):
			orphans.append(str(id))
	orphans.sort()
	assert_eq(orphans, FALLBACK_ONLY,
		"fallback ids absent from abilities.json changed — was %s, now %s. A new one means the two copies drifted again." % [str(FALLBACK_ONLY), str(orphans)])


func test_every_fallback_name_matches_the_json_name() -> void:
	# The failure this catches: a rename lands in abilities.json only, and the degraded path
	# silently serves the old branding to anyone whose data file failed to load.
	var fb := _fallback_pairs()
	var a := _json_abilities()
	var drift: Array = []
	for id in fb:
		if not a.has(id):
			continue
		var want := str(a[id]["name"])
		if str(fb[id]) != want:
			drift.append("%s: fallback '%s' vs abilities.json '%s'" % [id, fb[id], want])
	assert_eq(drift.size(), 0, "JobSystem fallback names drifted from abilities.json:\n  %s" % "\n  ".join(drift))


func test_the_latin_rebrand_reached_the_fallback() -> void:
	# Named members, so this cannot pass by parsing nothing (the count assert above guards that too)
	var fb := _fallback_pairs()
	for id in ["fire", "blizzard", "thunder", "cure", "cura", "raise"]:
		assert_true(fb.has(id), "the fallback still declares %s" % id)
	assert_eq(fb.get("fire", ""), "Ignis")
	assert_eq(fb.get("cura", ""), "Sanatio Maior")
