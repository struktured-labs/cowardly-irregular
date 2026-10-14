extends GutTest

## Rivet Row's freight elevator played `armor_clank`, whose own prompt is "Medieval plate armor
## clanking together, metal gauntlet striking breastplate in SALUTE, military honor gesture". Its
## only other consumer is data/cutscenes/world1_warden_intro.json step 8 — a WORLD 1 medieval
## warden. Rivet Row is WORLD 4, a workers' settlement on factory outskirts built by
## IndustrialTileGenerator, reachable from TeleportMenu. A plate-armour salute played for a pallet
## lift: wrong world, wrong event, and the only consumer of that cue in `src/` was the wrong one.
##
## 🔑 FOUND BY AUDITING play_ui's VARIABLE-KEY CALL SITES, which is why the ledger below is a SET.
## `play_ui` takes a free string and SILENTLY RETURNS for a key in neither the manifest nor SOUNDS
## — six sites pass a key no literal grep can see (two Rebalance panels, CutsceneDirector's
## play_sfx step, VillageElevator, play_pickup's fallback, and play_ui's own recursion). I expected
## to find a silent cue. All six resolve, and all 95 authored cutscene cues resolve. The defect was
## not a cue that fails to play but a cue that plays and is the wrong one — which no resolution
## check of any kind can see, only reading what each site means.
##
## ⚠️ WHAT THIS GUARD CANNOT DO, stated rather than implied: GUT cannot measure audio, so no arm
## here asserts a dB or a spectrum. Those live in the manifest prompt and in
## tools/sfx_envelope_accent.py / tools/sfx_band_share.py, and the asset's own derivation is
## tools/gen_freight_lift.sh — committed, and reproducible because `sox -R` fixes the seed its four
## whitenoise layers would otherwise draw per run. Measured on the installed file: 0.408s, peak
## -3.2 dBFS, loudest-250ms -15.1 against a UI world-event median of -16.6 across 22 cues, arrival
## accent at 0.300s and +3.2 dB over the motor body, 250Hz-1k at 71.6% (the one band in that
## neighbourhood holding only plate_engage). What IS pinned here is the mechanism: which cue each elevator passes, that every
## one resolves, and that no elevator cue outlasts its own ride without a reason that still holds.

const ELEVATOR := "res://src/exploration/VillageElevator.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const VILLAGE_DIR := "res://src/maps/villages"
const WARDEN_CUTSCENE := "res://data/cutscenes/world1_warden_intro.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const SALUTE := "armor_clank"
const LIFT_CUE := "freight_lift"

## ⛔ EVERY SOURCE THAT BUILDS AN ELEVATOR, WITH THE CUE IT PASSES AND AN UNRELATED NEEDLE. A cue
## key is a GLOBAL name, so a ledger over one file is a scope bug by construction — that is how
## door_open's fifth instance sat in a sibling file while its one-file ledger read zero, and why
## chest_open's third site turned out not to be a chest.
##
## Each needle is a token in the same file that has NOTHING to do with elevators, so a needle
## failing means "the file moved or the comment strip ate it", never "the subject under test
## changed". I coupled a needle to its own subject twice in one session before writing this.
const ELEVATOR_SITES := {
	## RivetRow is W4 industrial, Brasston W3 steampunk, NodePrime W5 futuristic. The world is in
	## this comment rather than a field: no arm reads it, and a const field nothing consumes is the
	## same dead data as a cue nothing plays.
	"res://src/maps/villages/RivetRowVillage.gd": {
		"cue": "freight_lift", "needle": "\"rivet_row_union_hall\"", "elevators": 1,
	},
	"res://src/maps/villages/BrasstonVillage.gd": {
		"cue": "steam_hiss", "needle": "\"brasston_clockwork_loft\"", "elevators": 1,
	},
	"res://src/maps/villages/NodePrimeVillage.gd": {
		"cue": "portal_activate", "needle": "\"node_prime_daemon_lounge\"", "elevators": 1,
	},
}

## ⛔ THE TWO CUES THAT OUTLAST THE RIDE, DECLARED WITH THE FACT THAT MAKES IT ACCEPTABLE — not a
## suppression flag. A guard you can silence green is not a guard; this one you can only EXPLAIN
## green, and the explanation is itself asserted below. Both are shared with cutscenes, so
## shortening either would edit scenes this change has no business touching. If a cue stops being
## shared, its exemption's premise is gone and the arm reds, which is the moment to author a
## ride-length cue for that elevator.
const LONG_CUE_EXEMPTIONS := {
	"steam_hiss": {"min_cutscenes": 4, "why": "4 W3 cutscenes (chapters 2-3, warden intro/defeat)"},
	"portal_activate": {"min_cutscenes": 9, "why": "9 cutscenes (world transitions and epilogues)"},
}

## A tail past arrival is correct — machinery settles. 5.7x the ride is not. freight_lift is 1.17x.
##
## ⚠️ ONE-SIDED ON PURPOSE, since a threshold usually needs both bounds. There is no floor because
## the short direction is not a failure: a brief cue over a 0.35s ride is thin at worst, and
## pickup_small is 0.137s and correct. A floor here would be a number with no failure behind it —
## the coincidental-value ratchet, which reds on a correct change.
const MAX_CUE_OVER_RIDE := 1.5


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"VOID: the sfx manifest did not parse, so every arm below is about nothing")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


## play_ui resolves a key against the manifest FIRST and SOUNDS second, then returns silently. This
## models both halves: the manifest from its own JSON, SOUNDS by its declaration in source. The
## second half certifies SPELLING rather than runtime presence, which is the honest limit of a
## source read and is why the manifest half is checked by data.
func _resolves(key: String, man: Dictionary, sm_code: String) -> bool:
	if man.has(key) and str((man[key] as Dictionary).get("file", "")) != "":
		return true
	return sm_code.contains("\"%s\": {" % key)


func _ride_time() -> float:
	var code: String = GdSource.code_of(ELEVATOR)
	assert_true(code.contains("tween_property"),
		"VOID: VillageElevator's code did not survive the comment strip — an over-strip and a correct strip are the same green")
	var m := RegEx.create_from_string("const RIDE_TIME\\s*:?=\\s*([0-9.]+)")
	var e := m.search(code)
	assert_not_null(e, "VOID: could not read RIDE_TIME from VillageElevator")
	return float(e.get_string(1)) if e != null else -1.0


func test_the_freight_lift_has_a_cue_of_its_own() -> void:
	var man := _manifest()
	assert_true(man.has(LIFT_CUE),
		"%s is not registered, so Rivet Row's freight elevator passes a key play_ui cannot resolve — and play_ui returns SILENTLY, with no diagnostic anywhere" % LIFT_CUE)
	if not man.has(LIFT_CUE):
		return
	var path: String = str((man[LIFT_CUE] as Dictionary).get("file", ""))
	assert_ne(path, "", "%s has a manifest entry with no file" % LIFT_CUE)
	assert_true(FileAccess.file_exists("res://" + path),
		"%s names %s, which is not on disk" % [LIFT_CUE, path])


func test_no_elevator_plays_the_wardens_armour() -> void:
	## TWO independent defences, and it is worth saying WHICH does the work, because I first wrote
	## this claiming the wrong one. The predicate matches the QUOTED key, since a cue reaches
	## `create()` as a string literal; the read is ALSO comment-stripped. The fix left a comment in
	## RivetRowVillage.gd naming armor_clank to say why it is gone — and that comment writes the cue
	## UNQUOTED, so today the quoting is what separates prose from a call and the strip is spare
	## capacity. It stops mattering the moment someone quotes a cue inside a comment, which is why
	## both stay. My own simulation control is what caught the overclaim.
	var offenders: Array[String] = []
	for path in ELEVATOR_SITES:
		var code: String = GdSource.code_of(path)
		var needle: String = str((ELEVATOR_SITES[path] as Dictionary)["needle"])
		assert_true(code.contains(needle),
			"%s lost its needle (%s) — the file moved or the comment strip ate it, so this arm is measuring nothing" % [path, needle])
		if code.contains("\"%s\"" % SALUTE):
			offenders.append(path)
	assert_eq(offenders, [],
		"these elevator sites pass %s, a MEDIEVAL PLATE-ARMOUR SALUTE whose other consumer is the World 1 warden intro: %s" % [SALUTE, offenders])


func test_the_wardens_salute_keeps_its_own_consumer() -> void:
	## Repointing an only-consumer orphans the cue. This asserts the OTHER consumer is still there,
	## so `armor_clank` remains a cue something plays rather than an unreferenced asset — which is
	## what test_an_unregistered_cue_says_why_it_is_there would have to explain later.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WARDEN_CUTSCENE))
	assert_true(parsed is Dictionary, "VOID: %s did not parse" % WARDEN_CUTSCENE)
	if not parsed is Dictionary:
		return
	var found := false
	for step in (parsed as Dictionary).get("steps", []):
		if step is Dictionary and str((step as Dictionary).get("sfx", "")) == SALUTE:
			found = true
	assert_true(found,
		"%s no longer plays %s, so that cue has no consumer at all — the salute was moved off the freight lift ON THE PREMISE that the warden still uses it" % [WARDEN_CUTSCENE, SALUTE])


func test_every_elevator_site_is_in_the_ledger() -> void:
	## A new village elevator must land in the ledger, because the ledger is where someone states
	## which cue it passes and why that cue belongs to that world. An unledgered site is exactly the
	## shape this whole item was: a cue picked for flavour with nothing checking what it means.
	var dir := DirAccess.open(VILLAGE_DIR)
	assert_not_null(dir, "VOID: could not open %s" % VILLAGE_DIR)
	if dir == null:
		return
	var builders: Array[String] = []
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var path: String = "%s/%s" % [VILLAGE_DIR, f]
		if GdSource.code_of(path).contains("VillageElevatorScript.create"):
			builders.append(path)
	builders.sort()
	var ledgered: Array[String] = []
	for k in ELEVATOR_SITES:
		ledgered.append(str(k))
	ledgered.sort()
	assert_eq(builders, ledgered,
		"the villages that build an elevator and the ledger disagree — a new elevator needs a row naming its cue, and a removed one needs its row dropped")
	## ⛔ THE COUNT, NOT ONLY THE FILE SET — and a mutation is the only reason this is here. The arm
	## above compares FILES, so adding a SECOND elevator to an already-ledgered village left it
	## GREEN: the ledger records one cue per file, and a second lift passing a different cue would
	## be invisible to a set comparison. That is a real gap, not just a weak test.
	var miscounted: Array[String] = []
	for path in ELEVATOR_SITES:
		var n: int = GdSource.code_of(path).count("VillageElevatorScript.create")
		var want: int = int((ELEVATOR_SITES[path] as Dictionary)["elevators"])
		if n != want:
			miscounted.append("%s builds %d elevator(s), the ledger records %d" % [path, n, want])
	assert_eq(miscounted, [],
		"a village's elevator COUNT moved — each elevator passes its own cue, so a second one needs its own ledger row: %s" % [miscounted])


func test_every_elevator_cue_resolves() -> void:
	## play_ui SILENTLY RETURNS for an unresolvable key: no push_warning, no print, nothing in a
	## log. An elevator whose cue key is a typo is a ride that makes no sound, and the only way to
	## find it is to look. This includes the @export DEFAULT, which no village uses today — so the
	## first village that forgets to pass a cue inherits whatever that default is.
	var man := _manifest()
	var sm_code: String = GdSource.code_of(SOUND_MANAGER)
	assert_true(sm_code.contains("func play_ui"),
		"VOID: SoundManager's code did not survive the comment strip")
	var unresolvable: Array[String] = []
	for path in ELEVATOR_SITES:
		var cue: String = str((ELEVATOR_SITES[path] as Dictionary)["cue"])
		var code: String = GdSource.code_of(path)
		if not code.contains("\"%s\"" % cue):
			unresolvable.append("%s no longer passes %s" % [path, cue])
		elif not _resolves(cue, man, sm_code):
			unresolvable.append("%s passes %s, which resolves nowhere" % [path, cue])
	var m := RegEx.create_from_string("@export var sfx_key: String = \"([a-z0-9_]+)\"")
	var e := m.search(GdSource.code_of(ELEVATOR))
	assert_not_null(e, "VOID: could not read the sfx_key default from VillageElevator")
	if e != null and not _resolves(e.get_string(1), man, sm_code):
		unresolvable.append("the @export default %s resolves nowhere" % e.get_string(1))
	assert_eq(unresolvable, [], "unresolvable elevator cues (play_ui would return in silence): %s" % [unresolvable])


func test_an_elevator_cue_does_not_outlast_its_own_ride() -> void:
	## THE CROSS-FILE INVARIANT. RIDE_TIME lives in VillageElevator.gd, the durations in the
	## manifest, and the cue plays at ride START with no arrival cue of its own — so a cue much
	## longer than the ride puts its arrival accent where the player is already standing on the dock.
	## Pinned as a RELATIONSHIP between the two sources, not as a number: raise RIDE_TIME and the
	## bound moves with it.
	var man := _manifest()
	var ride: float = _ride_time()
	assert_gt(ride, 0.0, "VOID: RIDE_TIME read as %f" % ride)
	var budget: float = ride * MAX_CUE_OVER_RIDE
	var over: Array[String] = []
	for path in ELEVATOR_SITES:
		var cue: String = str((ELEVATOR_SITES[path] as Dictionary)["cue"])
		if not man.has(cue):
			continue
		var dur: float = float((man[cue] as Dictionary).get("duration_seconds", 0.0))
		if dur <= budget + 0.001:
			continue
		if not LONG_CUE_EXEMPTIONS.has(cue):
			over.append("%s is %.3fs for a %.2fs ride (%.1fx)" % [cue, dur, ride, dur / ride])
			continue
		## The exemption's PREMISE, asserted rather than trusted: it is excused because cutscenes
		## share it. Count them, and if the sharing is gone so is the excuse.
		var ex: Dictionary = LONG_CUE_EXEMPTIONS[cue]
		var shared := 0
		var cdir := DirAccess.open("res://data/cutscenes")
		if cdir != null:
			for f in cdir.get_files():
				if f.ends_with(".json") and FileAccess.get_file_as_string("res://data/cutscenes/%s" % f).contains("\"%s\"" % cue):
					shared += 1
		assert_gte(shared, int(ex["min_cutscenes"]),
			"%s is %.3fs for a %.2fs ride and is excused as \"%s\" — but it is now shared with %d cutscenes, not %d, so the premise of its exemption is gone and that elevator needs a ride-length cue" % [cue, dur, ride, ex["why"], shared, int(ex["min_cutscenes"])])
	assert_eq(over, [],
		"these elevator cues outlast their own ride with no declared reason, so their arrival accent fires after the player has arrived: %s" % [over])
