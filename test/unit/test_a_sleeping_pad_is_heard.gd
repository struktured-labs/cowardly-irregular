extends GutTest

## A pad connecting or the last one dropping showed only a corner toast a player mid-fight never looks at; each now has its own cue, under the toast's last-pad rule.
## The decision is driven through InputProfileManager.pad_change_cue; the announcer bails headless, so its call is pinned in source after that bail.

const IPM := preload("res://src/input/InputProfileManager.gd")
const GdSrc := preload("res://test/unit/helpers/gd_source.gd")


func _file(key: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(key, {}) as Dictionary).get("file", ""))


func test_both_cues_are_authored_and_are_three_different_sounds() -> void:
	var on := _file(IPM.PAD_CONNECTED_SFX)
	var off := _file(IPM.PAD_DISCONNECTED_SFX)
	for f in [on, off]:
		assert_ne(f, "", "a pad cue is not registered in sfx_manifest.json")
		var stream = load("res://" + f)
		assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.2,
			"%s does not load as a real stream" % f)
	assert_ne(on, off, "connecting and losing the pad must not sound the same")
	assert_ne(off, _file("menu_error"), "losing the pad is not a refused press; it must not reuse menu_error")


func test_the_cue_follows_the_toasts_last_pad_rule() -> void:
	var later := IPM.PAD_BOOT_GRACE_MS + 60000
	assert_eq(IPM.pad_change_cue(true, 1, later), IPM.PAD_CONNECTED_SFX, "a pad connecting was not heard")
	assert_eq(IPM.pad_change_cue(false, 0, later), IPM.PAD_DISCONNECTED_SFX, "the LAST pad leaving was not heard")
	assert_eq(IPM.pad_change_cue(false, 1, later), "", "unplugging one of two pads is not losing control and must stay quiet")


func test_a_pad_already_plugged_in_at_launch_does_not_chime() -> void:
	assert_gt(IPM.PAD_BOOT_GRACE_MS, 0, "CONTROL: there is a boot grace window")
	assert_eq(IPM.pad_change_cue(true, 1, 0), "", "the launch-time enumeration of a plugged-in pad chimed on the title screen")
	assert_eq(IPM.pad_change_cue(true, 2, IPM.PAD_BOOT_GRACE_MS - 1), "", "a second pad enumerated at launch chimed")
	assert_eq(IPM.pad_change_cue(true, 1, IPM.PAD_BOOT_GRACE_MS), IPM.PAD_CONNECTED_SFX, "a pad connecting right after the grace was not heard")


## A WIRING PIN: the announcer returns early headless, so no test run can reach its play call.
func test_wiring_the_announcer_plays_the_cue_after_its_headless_bail() -> void:
	var code: String = GdSrc.code_of("res://src/input/InputProfileManager.gd")
	var at := code.find("func _announce_pad_change(")
	assert_gt(at, -1, "CONTROL: the announcer must exist")
	var stop := code.find("\nfunc ", at + 1)
	var body := code.substr(at, (stop - at) if stop > at else -1)
	var bail := body.find("\"headless\"")
	var plays := body.find("SoundManager.play_ui(cue)")
	var decides := body.find("pad_change_cue(connected, Input.get_connected_joypads().size(), Time.get_ticks_msec())")
	assert_gt(bail, -1, "CONTROL: the headless bail is still there")
	assert_true(decides > bail and plays > decides,
		"the announcer must decide with pad_change_cue from the pads still connected and the real clock, then play it, after the headless bail")
