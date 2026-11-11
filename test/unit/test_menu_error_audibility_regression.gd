extends GutTest

## menu_error's level lives in ONE place. Until 2026-11-07 its asset was rendered -12 dB and a +6.6 trim in
## SoundManager's UI table made up the difference. struktured asked for it louder ("the noise is fine, just
## louder"), so cowir-sfx removed the attenuation from the ASSET (+11.6 dB) and the trim had to go with it:
## asset and trim together would double-boost it into the loudest UI cue by ~17 dB over menu_select.
##
## The hazard this pins is unchanged: the trim and the asset are one decision and must move together.

const SM := "res://src/audio/SoundManager.gd"
const ASSET := "res://assets/audio/sfx/menu_error.ogg"
## sha256 of the asset whose gain was measured with NO trim (cowir-sfx, sfx_manifest's menu_error prompt).
const ASSET_SHA := "de7d8dd3a5295f84d9a5524552a1b63aa4ab6fc65dfa8ca7a6949cf23156a6c7"


func test_menu_error_has_no_trim_because_its_asset_carries_the_gain() -> void:
	var src := FileAccess.get_file_as_string(SM)
	assert_ne(src, "", "SoundManager unreadable — every check below would be vacuous")
	assert_true('"menu_select": -2.5' in src, "CONTROL: the UI trim table is not in the shape this test reads — re-point it")
	assert_false('"menu_error":' in src,
		"menu_error is back in the trim table while its asset already carries the gain: that double-boosts it into the loudest UI cue")


func test_the_asset_is_the_one_measured_without_a_trim() -> void:
	assert_true(FileAccess.file_exists(ASSET), "menu_error.ogg missing")
	assert_gt(FileAccess.get_file_as_bytes(ASSET).size(), 0, "asset read as empty — the hash below would be of nothing")
	assert_eq(FileAccess.get_sha256(ASSET), ASSET_SHA,
		"menu_error.ogg changed. Its level was measured with no trim; re-measure against menu_select and menu_cancel before adding one.")
