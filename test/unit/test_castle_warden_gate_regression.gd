extends GutTest

## struktured 2026-08-22, mid-playtest: "also u shouldnt be able to fight mordain until u take
## out her warden/tempo/whatver, should be lots of bosses before we get tehre. its A JPRG!!!"
##
## The spine gate (bad8511c) covered "lots of bosses" — castle entry needs all five W1 flags.
## This covers the other half: a Warden now bars the F3 stair to the throne floor. Victory
## rides pending_boss_defeat (the scene is freed during the battle transition, so a local
## handler would never fire — the Rat King quest-log regression class).

const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"


func _mons() -> Dictionary:
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


## The two SHARED flags this file writes. `world1_mordaine_defeated` is read by 10 src files and
## 22 other guards; `castle_warden_defeated` by 2 and 1. Both are real keys, so a strand crosses
## files rather than sitting latent (cowir-music's reachability discriminator, 2026-09-18).
const GATED_FLAGS: Array[String] = ["castle_warden_defeated", "world1_mordaine_defeated"]

## PRESENCE and VALUE, separately: `is_story_flag_set()` returns a bool and cannot tell an absent
## key from a false one, so restoring through it would leave a key behind that was never there.
var _pre: Dictionary = {}
var _saved: Dictionary = {}


func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	for k in GATED_FLAGS:
		out[k] = [GameState.story_flags.has(k), GameState.story_flags.get(k, null)]
	return out


func _restore(snap: Dictionary) -> void:
	for k in GATED_FLAGS:
		var rec: Array = snap.get(k, [false, null])
		if bool(rec[0]):
			GameState.story_flags[k] = rec[1]
		else:
			GameState.story_flags.erase(k)


## The baseline for the catcher is taken ONCE, before any arm runs. Taking it in before_each would
## make the catcher compare a value against itself re-read — green under every strand, which is the
## over-determined arm this lane fixed in f35ace44b on the same day.
func before_all() -> void:
	_pre = _snapshot()


func before_each() -> void:
	_saved = _snapshot()


## The restore lives HERE and not at the end of the arm. Measured on this file 2026-09-18: with the
## old inline restore and an abort planted between the last mutation and it, `world1_mordaine_defeated`
## was left SET for the rest of the process — and the six sibling tests still reported PASSING.
func after_each() -> void:
	_restore(_saved)


func test_the_warden_exists_and_every_reference_resolves() -> void:
	var w: Dictionary = _mons().get("castle_warden", {})
	assert_false(w.is_empty(), "castle_warden must exist in monsters.json")
	assert_true(bool(w.get("boss", false)), "the Warden is a boss fight, not a random encounter")
	for aid in w.get("abilities", []):
		assert_true(JobSystem.get_ability(str(aid)).size() > 0, "ability must resolve: %s" % aid)
	for drop in w.get("drop_table", []):
		var item: String = str((drop as Dictionary).get("item", ""))
		assert_true(ItemSystem.get_item(item).size() > 0, "drop must resolve: %s" % item)
	assert_true(int(w.get("level", 0)) > 18 and int(w.get("level", 0)) < 20,
		"the Warden sits between Umbraxis (18) and Mordaine (20), got %s" % str(w.get("level")))


func test_the_warden_has_a_sprite_and_a_bestiary_page() -> void:
	var sm = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var entry: Dictionary = (sm["monster_sheets"] as Dictionary).get("castle_warden", {})
	assert_false(entry.is_empty(), "castle_warden needs a monster_sheets entry — absence means procedural fallback")
	assert_true(ResourceLoader.exists(str(entry.get("path", ""))), "its sheet must exist: %s" % str(entry.get("path", "")))
	var b = JSON.parse_string(FileAccess.get_file_as_string("res://data/bestiary.json"))
	assert_true((b as Dictionary).has("castle_warden"), "bestiary page must exist")


func test_warden_defeated_logic_and_the_mordaine_grandfather() -> void:
	var castle = load(CASTLE).new()
	GameState.story_flags["castle_warden_defeated"] = false
	GameState.story_flags["world1_mordaine_defeated"] = false
	assert_false(castle._warden_defeated(), "neither flag set — the stair must be barred")
	GameState.story_flags["castle_warden_defeated"] = true
	assert_true(castle._warden_defeated(), "warden flag set — the stair opens")
	GameState.story_flags["castle_warden_defeated"] = false
	GameState.story_flags["world1_mordaine_defeated"] = true
	assert_true(castle._warden_defeated(),
		"GRANDFATHER: a save already past Mordaine must never be walled off by a flag added later")
	castle.free()


func test_the_stair_override_gates_the_throne_ascent_specifically() -> void:
	var src := FileAccess.get_file_as_string(CASTLE)
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i: int = src.find("func _on_stairs_up_entered")
	assert_gt(i, -1, "CastleHarmonia must override _on_stairs_up_entered")
	var body: String = src.substr(i, 400)
	assert_true(body.contains("total_floors - 1"),
		"the gate audits the FINAL ascent only — F1/F2 stairs stay free")
	assert_true(body.contains("_warden_defeated()"), "the override must consult the flag logic")
	assert_true(body.contains("super._on_stairs_up_entered"),
		"and fall through to the base handler once the audit passes")


func test_victory_flags_ride_the_central_pending_spec() -> void:
	var src := FileAccess.get_file_as_string(CASTLE)
	var i: int = src.find("func _trigger_warden_battle")
	assert_gt(i, -1, "_trigger_warden_battle must exist")
	var body: String = src.substr(i, 500)
	assert_true(body.contains("pending_boss_defeat"),
		"victory must ride GameState.pending_boss_defeat — the scene is freed mid-transition")
	assert_true(body.contains('"story_flags": [WARDEN_FLAG]'),
		"the story flag is what QuestLog reads; dungeon_flag alone is invisible to it")


func test_quest_log_telegraphs_the_full_spine() -> void:
	# The dragons moved from "optional" — the spine gate made that label a lie.
	var src := FileAccess.get_file_as_string("res://src/ui/QuestLog.gd")
	assert_true(src.contains('"castle_warden_defeated"'), "the Warden objective must be listed")
	var opt: int = src.find('"optional": []')
	assert_gt(opt, -1, "W1's optional list must be empty — all four dragons are now required by the castle gate")
	var main_idx: int = src.find('"fire_dragon_defeated"')
	assert_gt(main_idx, -1, "dragons must still be listed, in the MAIN quest lines")
	assert_lt(main_idx, src.find('"world1_mordaine_defeated"'),
		"and they must appear before the Mordaine objective — the order players read is the order they play")


## Declared LAST because declaration order is run order. An arm that aborts mid-mutation still
## reports PASSING, so "I added a teardown" is an unfalsifiable claim without an arm that can see
## the strand (cowir-music 2026-09-18). Compares against the before_all baseline, never against a
## re-read of the state it is checking.
func test_zz_the_story_flags_were_handed_back() -> void:
	for k in GATED_FLAGS:
		var pre: Array = _pre[k]
		assert_eq(GameState.story_flags.has(k), bool(pre[0]),
			"STRAND: '%s' presence changed — this file writes it and something did not hand it back; 22 other guards read world1_mordaine_defeated" % k)
		if bool(pre[0]):
			assert_eq(GameState.story_flags.get(k, null), pre[1],
				"STRAND: '%s' left as %s, was %s before this file ran" % [k, str(GameState.story_flags.get(k, null)), str(pre[1])])
