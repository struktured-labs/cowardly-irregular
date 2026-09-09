extends GutTest

## An ability's AP grant popped RED and played the HP-heal cue.
##
## 062e36e2 ("MP gains pop purple, ability AP grants pop red, HP heals stay green") separated the
## POPUPS for struktured's ruling and, in the same commit, gave the AP grant the heal SOUND. Its
## sibling from that commit does it right — _on_mp_restored plays nothing — which is what makes this
## an oversight rather than a choice. Found by cowir-sfx applying "grep the consumer, not the
## comment" to their own comments; the defect was one line below the claim they were verifying.
##
## Sharper than first reported, and worth pinning: `play_battle("heal")` had exactly ONE caller in
## all of src/, and it was this one. Healing abilities route through SoundManager.play_ability(id),
## so the generic heal cue existed solely to fire on AP grants.
##
## Asserts the RELATIONSHIP — the AP path must not share the HP-heal cue — rather than pinning the
## replacement string, which would go red on a correct re-cue and green on a wrong one.

const SCENE := "res://src/battle/BattleScene.gd"

func _body(fn: String) -> String:
	var src := FileAccess.get_file_as_string(SCENE)
	var i: int = src.find("func %s(" % fn)
	assert_gt(i, -1, "CONTROL: located %s" % fn)
	var j: int = src.find("\nfunc ", i + 10)
	return src.substr(i, j - i) if j > i else src.substr(i)

func test_the_ap_grant_does_not_play_the_hp_heal_cue() -> void:
	assert_false(_body("_on_ap_granted").contains('play_battle("heal")'),
		"a red AP popup must not sound like a green HP heal")

func test_the_ap_grant_still_makes_a_sound() -> void:
	## The other failure mode: deleting the line rather than re-cueing it. An AP grant that arrives
	## silently is a worse bug than one that arrives wrong, because nothing on screen contradicts it.
	assert_string_contains(_body("_on_ap_granted"), "SoundManager.play_battle(",
		"the grant must still be audible")

func test_the_cue_it_uses_is_a_real_registered_one() -> void:
	## Guards the swap against a typo — an unregistered key is silence, indistinguishable from
	## "nobody triggers it", which is exactly how the original defect survived.
	var body := _body("_on_ap_granted")
	var i: int = body.find("play_battle(\"")
	var key: String = body.substr(i + 13, body.find("\"", i + 13) - (i + 13))
	assert_gt(key.length(), 2, "CONTROL: extracted a cue key (%s)" % key)
	assert_string_contains(FileAccess.get_file_as_string("res://src/audio/SoundManager.gd"),
		'"%s"' % key, "the AP cue '%s' must be registered in SoundManager" % key)

func test_the_mp_sibling_stays_silent() -> void:
	## The negative control from the same commit. If a later pass gives MP restore a cue too, this
	## should be revisited deliberately rather than drifting.
	assert_false(_body("_on_mp_restored").contains("SoundManager."),
		"MP restore plays nothing by design — it is the sibling that proves the AP cue was a slip")
