extends GutTest

## Regression: an ability GRANTING AP played the HP heal cue (2026-09-09).
##
## 062e36e2 implemented struktured's 2026-09-07 ruling — "MP gains and ability AP grants get their
## own popups (purple / red) — never healing_done's green" — and in the SAME commit gave the AP
## grant `play_battle("heal")`. The popup was separated; the sound was not, so the audio said
## "you were healed" over a red AP popup.
##
## Its sibling handler from that commit, _on_mp_restored, correctly plays nothing — which is what
## makes this an oversight rather than a choice.

const SCENE := "res://src/battle/BattleScene.gd"


func _src() -> String:
	var t := FileAccess.get_file_as_string(SCENE)
	assert_ne(t, "", "BattleScene.gd unreadable — every assert below would pass vacuously")
	return t


func _handler_body(src: String, fn: String) -> String:
	var i := src.find("func %s(" % fn)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > i else 40)


func test_the_ap_handler_exists() -> void:
	## PREMISE: if the handler is renamed or removed, the body checks below match "" and pass.
	var body := _handler_body(_src(), "_on_ap_granted")
	assert_ne(body, "", "_on_ap_granted not found — this guard is watching nothing")
	assert_true(body.contains("SoundManager.play_battle("),
		"_on_ap_granted plays no cue at all — an AP grant should be audible")


func test_ap_grant_does_not_play_the_heal_cue() -> void:
	var body := _handler_body(_src(), "_on_ap_granted")
	assert_false(body.contains('play_battle("heal")'),
		"an AP grant plays the HP heal cue — struktured separated AP from healing in the popups on 2026-09-07 and the audio must agree")
	assert_true(body.contains('play_battle("round_ap_gain")'),
		"_on_ap_granted should play round_ap_gain, the cue the round's own AP gain already uses")


func test_the_cue_it_uses_is_real() -> void:
	## A mapping to a key the manifest lacks falls through to silence — worse than the wrong cue.
	var raw := FileAccess.get_file_as_string("res://data/sfx_manifest.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("round_ap_gain"), "round_ap_gain missing from the manifest")
	assert_true(sfx.has("heal"), "control: `heal` must still exist, else the assert above proves nothing about the swap")


func test_the_mp_sibling_still_plays_nothing() -> void:
	## NEGATIVE CONTROL, and the reason this was an oversight rather than a choice: _on_mp_restored
	## came from the same commit and correctly stays silent — the cast cue and play_item already
	## cover MP restores, so a cue here would DOUBLE-FIRE on pray and channel.
	var body := _handler_body(_src(), "_on_mp_restored")
	assert_ne(body, "", "control: _on_mp_restored not found — the comparison below is vacuous")
	assert_false(body.contains("SoundManager.play_battle("),
		"_on_mp_restored now plays a cue — that double-fires with play_ability/play_item on pray, channel and every ether")
