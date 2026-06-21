extends GutTest

## Regression test for previously-orphan SFX/music keys (slice 47bf8a49).
##
## Pre-fix:
##   - 30+ menu_error play_ui call sites — SFX manifest had no entry, beeps silent.
##   - 9+ KeyItemPopup item_obtain plays — SFX manifest had no entry.
##   - BattleScene tried to play boss_rat_king music — music manifest had no slot.
##
## Post-fix asserts the manifest entries exist (even as placeholders) so
## audit tooling can see them and SFX synthesis can target them.

const SFX_PATH := "res://data/sfx_manifest.json"
const MUSIC_PATH := "res://data/music_manifest.json"


func _load(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t = f.get_as_text()
	f.close()
	var p = JSON.parse_string(t)
	return p if p is Dictionary else {}


func test_menu_error_sfx_entry_exists() -> void:
	var data = _load(SFX_PATH)
	var sounds = data.get("sfx", {})
	assert_true(sounds.has("menu_error"),
		"sfx_manifest must declare menu_error — 30+ call sites rely on it")


func test_item_obtain_sfx_entry_exists() -> void:
	var data = _load(SFX_PATH)
	var sounds = data.get("sfx", {})
	assert_true(sounds.has("item_obtain"),
		"sfx_manifest must declare item_obtain — KeyItemPopup uses it across 9+ cutscenes")


func test_boss_rat_king_music_slot_exists() -> void:
	var data = _load(MUSIC_PATH)
	var tracks = data.get("tracks", {})
	assert_true(tracks.has("boss_rat_king"),
		"music_manifest must reserve a boss_rat_king slot — BattleScene plays it for W1 tutorial boss")
