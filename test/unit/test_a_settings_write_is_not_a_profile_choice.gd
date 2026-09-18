extends GutTest

## `profile_chosen_by_user` decides whether a newly connected pad is AUTODETECTED. It was not
## persisted — `load_config` inferred it from "a profile is saved", and `save_config` saves the
## active profile unconditionally on every settings write.
##
## ⛔ MEASURED BEFORE THE FIX, in-engine against the real config file:
##     autodetect picks "8BitDo SN30"        chosen=false
##     player toggles the face convention    persisted: active_profile=8BitDo SN30, no choice recorded
##     next boot                             chosen=TRUE
##     -> plug in a different pad family     autodetect never runs again
##
## Three of the four `save_config` callers are not profile choices — `set_nintendo_mode`,
## `set_custom_binding`, `reset_custom_to_preset`. Only `cycle_profile` is. So toggling ONE setting
## froze the player on whatever pad they happened to own that day: every later controller gets the
## old profile's bindings and the old family's glyphs, with nothing on screen explaining why.
##
## 📌 The fix is to persist the flag rather than re-derive it, and the legacy default is `true` —
## today's behaviour. A config written before this cannot say whether the choice was real, and
## silently overriding a deliberate Settings choice is the worse of the two errors. Presence of the
## key is the discriminator, so no version bump: absent means pre-fix.

const REAL_PROFILE := "8BitDo SN30"

var _raw: String = ""
var _had: bool = false
var _saved_profile: String = ""
var _saved_nintendo: bool = false
var _saved_chosen: bool = false


## ⛔ SNAPSHOT THE BYTES, NOT THE FIELDS. These arms drive the real writer against the real path, so
## the file itself is fixture state — and eight other files in this lane read it.
func before_all() -> void:
	_had = FileAccess.file_exists(InputProfileManager.CONFIG_PATH)
	if _had:
		_raw = FileAccess.get_file_as_string(InputProfileManager.CONFIG_PATH)
	_saved_profile = InputProfileManager.active_profile
	_saved_nintendo = InputProfileManager.nintendo_mode
	_saved_chosen = InputProfileManager.profile_chosen_by_user


func after_all() -> void:
	if _had:
		var f := FileAccess.open(InputProfileManager.CONFIG_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_raw)
			f.close()
	else:
		DirAccess.remove_absolute(InputProfileManager.CONFIG_PATH)
	InputProfileManager.nintendo_mode = _saved_nintendo
	InputProfileManager.apply_profile(_saved_profile)
	InputProfileManager.profile_chosen_by_user = _saved_chosen


func _config() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(InputProfileManager.CONFIG_PATH))
	return d if d is Dictionary else {}


## Puts the manager in the state autodetect leaves it in: a real profile is active, and the player
## has chosen nothing.
func _as_if_autodetected() -> void:
	InputProfileManager.profile_chosen_by_user = false
	InputProfileManager.apply_profile(REAL_PROFILE)


## ⛔ THE CONTROL, first: if the flag never reaches disk, every arm below is reading a default.
func test_the_choice_is_recorded_on_disk_at_all() -> void:
	_as_if_autodetected()
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)
	var d := _config()
	assert_true(d.has("active_profile"),
		"CONTROL: the config must persist the profile, or there is no defect to have")
	assert_true(d.has("profile_chosen_by_user"),
		"the config must record WHETHER the profile was chosen — inferring it from the profile's "
		+ "presence is what disabled autodetect, and every settings write persists the profile")


## ⛔ THE DEFECT. Toggling a face convention is not choosing a profile.
func test_toggling_the_convention_does_not_claim_a_profile_choice() -> void:
	_as_if_autodetected()
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)

	InputProfileManager.profile_chosen_by_user = true
	InputProfileManager.load_config()

	assert_false(InputProfileManager.profile_chosen_by_user,
		"the player toggled the face convention and never picked a profile, but the next boot read "
		+ "the saved profile as a choice — so a different controller would never be autodetected "
		+ "again, and every caption would name the old family's buttons")


## The other two non-choice writers. A fix wired only to `set_nintendo_mode` covers one of three.
func test_rebinding_a_button_does_not_claim_a_profile_choice() -> void:
	_as_if_autodetected()
	InputProfileManager.set_custom_binding("ui_accept", [JOY_BUTTON_B])

	InputProfileManager.profile_chosen_by_user = true
	InputProfileManager.load_config()

	assert_false(InputProfileManager.profile_chosen_by_user,
		"rebinding one button persisted the active profile, which was then read as a profile choice")


func test_resetting_to_defaults_does_not_claim_a_profile_choice() -> void:
	_as_if_autodetected()
	InputProfileManager.reset_custom_to_preset()

	InputProfileManager.profile_chosen_by_user = true
	InputProfileManager.load_config()

	assert_false(InputProfileManager.profile_chosen_by_user,
		"resetting to defaults persisted the active profile, which was then read as a choice")


## ⛔ THE OPPOSITE DIRECTION, AND WITHOUT IT A FIX THAT ALWAYS WROTE `false` PASSES EVERY ARM ABOVE
## while throwing away the setting the player actually set. `cycle_profile` is the one caller that
## IS a choice.
func test_a_real_profile_choice_survives_a_reload() -> void:
	_as_if_autodetected()
	InputProfileManager.cycle_profile(1)
	var chosen_name: String = InputProfileManager.active_profile

	InputProfileManager.profile_chosen_by_user = false
	InputProfileManager.load_config()

	assert_true(InputProfileManager.profile_chosen_by_user,
		"the player picked a profile in Settings; that must outlive a restart, or autodetect "
		+ "overwrites their choice every time they plug a pad in")
	assert_eq(InputProfileManager.active_profile, chosen_name,
		"…and it must be the profile they picked")


## ⛔ THE UPGRADE PATH. A config written before this fix has no such key, and it cannot say whether
## the choice was real. Defaulting to `false` would silently discard a deliberate Settings choice on
## the first launch after an update — the worse of the two errors, and the same reasoning as the
## unrecognised-profile warning already in `load_config`.
func test_a_config_from_before_this_fix_keeps_its_profile() -> void:
	var legacy := {
		"version": 2,
		"active_profile": REAL_PROFILE,
		"nintendo_mode": false,
		"custom_bindings": {},
	}
	var f := FileAccess.open(InputProfileManager.CONFIG_PATH, FileAccess.WRITE)
	assert_not_null(f, "CONTROL: the fixture config must be writable")
	f.store_string(JSON.stringify(legacy, "\t"))
	f.close()
	assert_false(_config().has("profile_chosen_by_user"),
		"CONTROL: the fixture must be a PRE-FIX config, or this arm tests the new path")

	InputProfileManager.profile_chosen_by_user = false
	InputProfileManager.load_config()

	assert_true(InputProfileManager.profile_chosen_by_user,
		"an old config cannot say whether the profile was chosen, so it must be treated as chosen — "
		+ "re-running autodetect would overwrite a choice the player made before the update")
	assert_eq(InputProfileManager.active_profile, REAL_PROFILE, "…and the saved profile still applies")
