extends GutTest

## menu_error's asset is attenuated -12 dB on purpose ("soft negative feedback" — its own
## provenance note). Measured 2026-09-09 that landed it 28.5 dB under the W1 music bed, against
## menu_select's 22.0: soft had become masked, across 23 call sites. Fixed at the CHANNEL
## (+6.6 trim) rather than the asset, so the note stays true.
##
## The hazard this pins: normalising the asset later while the trim stays makes menu_error the
## LOUDEST UI cue. The trim and the asset are one decision and must move together.

const SM := "res://src/audio/SoundManager.gd"
const ASSET := "res://assets/audio/sfx/menu_error.ogg"
## sha256 of the asset the +6.6 was derived against.
const ASSET_SHA := "adbc1b83dd204f97f3b6c6def271dec60625451d43aa68f5863463af7b4e6f6f"


func test_menu_error_carries_its_audibility_trim() -> void:
	var src := FileAccess.get_file_as_string(SM)
	assert_ne(src, "", "SoundManager unreadable — every check below would be vacuous")
	assert_true('"menu_select": -2.5' in src, "the UI trim table is not in the shape this test reads — re-point it")
	assert_true('"menu_error": 6.6' in src,
		"menu_error lost its +6.6 dB trim — it drops to 28.5 dB under the music bed and 23 call sites stop giving the player feedback")


func test_the_asset_has_not_changed_under_the_trim() -> void:
	assert_true(FileAccess.file_exists(ASSET), "menu_error.ogg missing")
	assert_gt(FileAccess.get_file_as_bytes(ASSET).size(), 0, "asset read as empty — the hash below would be of nothing")
	assert_eq(FileAccess.get_sha256(ASSET), ASSET_SHA,
		"menu_error.ogg changed while the +6.6 trim is still applied. If it was normalised, the trim now DOUBLE-boosts it into the loudest UI cue. Re-measure against menu_select and update both, or neither.")


func test_the_trim_is_positive_because_the_asset_is_pre_attenuated() -> void:
	# A negative entry here would be someone reading the table as attenuation-only and "correcting" it.
	var src := FileAccess.get_file_as_string(SM)
	var at := src.find('"menu_error":')
	assert_gt(at, -1, "menu_error absent from the trim table")
	var line := src.substr(at, 40)
	assert_false("-" in line.substr(line.find(":"), 10),
		"menu_error's trim went negative — the asset is ALREADY -12 dB attenuated, so a negative trim compounds it")
