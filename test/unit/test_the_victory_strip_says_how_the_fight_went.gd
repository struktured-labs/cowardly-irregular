extends GutTest

## The victory grade scales SPECTACLE by the enemy — boss, elite, spotlight — which is what struktured
## asked for ("look more amazing against bosses or OP monsters"). It says nothing about how the fight
## WENT, so a party that was nearly wiped and a party that walked through untouched got the identical
## banner against the same monster.
##
## .740 recorded the dip (`_battle_low_water_pct`) and routed the KO record for the victory QUIP. This
## spends the same two facts on the screen, which matters because the 60 new voice lines are unrecorded
## and play as text: the moment should read even with the voice pack absent entirely.
##
## 🔑 RENDERED THROUGH THE EXISTING CHIP STRIP rather than as a new text node. The overlay has a real
## layout contract — `occupied_rects()`, the title dock, `_fit_card_scale` — and other victory chrome
## reads it to stay clear, so a new Label would owe collision work and its own three Text Size arms.
## A chip inherits the strip's `TextScale.scaled(14)` and everything already guarding it.

const Overlay := preload("res://src/battle/VictoryOverlay.gd")


func _strip(results: Dictionary) -> VictoryOverlay:
	var o: VictoryOverlay = Overlay.new()
	add_child_autofree(o)
	var base: Dictionary = {"char_results": [], "total_gold": 0, "item_drops": [], "injuries": [], "bonuses": []}
	for k in results:
		base[k] = results[k]
	o.build(base, null)
	o.complete_now()
	return o


func _chip_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array[String]) -> void:
	for c in node.get_children():
		if c is Label:
			out.append(str((c as Label).text))
		_walk(c, out)


func test_a_near_wipe_is_called_a_close_call() -> void:
	var got: Dictionary = Overlay.fight_shape_chip(4.0, false)
	assert_eq(str(got.get("text", "")), "CLOSE CALL", "reaching 4%% is the definition of a close call")


func test_a_casualty_outranks_a_close_call() -> void:
	## Both are true in the same fight constantly — somebody who hits 0% also passed through the low
	## band on the way down. Reporting both would print two chips for one event.
	var got: Dictionary = Overlay.fight_shape_chip(0.0, true)
	assert_eq(str(got.get("text", "")), "COSTLY",
		"a member who fell is the bigger fact; a close call is implied by it")


func test_an_ordinary_win_earns_no_chip() -> void:
	## ⛔ THE ANTI-SPAM ARM, and the reason there is no FLAWLESS chip. Most fights in this game end with
	## the party untouched; a chip that prints on nearly every victory is furniture, not information.
	assert_eq(Overlay.fight_shape_chip(100.0, false), {}, "an untouched party gets no chip at all")
	assert_eq(Overlay.fight_shape_chip(80.0, false), {}, "a scratch is not a close call")


func test_the_threshold_is_shared_with_the_voice_tag_not_duplicated() -> void:
	## ⛔ TWO SURFACES, ONE NUMBER. The quip says "Too close" from VoiceLineTags.CLOSE_CALL_PCT; if the
	## chip carried its own literal they would disagree for some fights — the banner calling it close
	## while nobody says so, which reads as a bug in whichever one the player notices second.
	var t: float = VoiceLineTags.CLOSE_CALL_PCT
	assert_gt(t, 1.0, "CONTROL: a threshold at or below 1%% makes the arms below vacuous")
	assert_eq(str(Overlay.fight_shape_chip(t - 0.5, false).get("text", "")), "CLOSE CALL",
		"just inside the shared threshold")
	assert_eq(Overlay.fight_shape_chip(t, false), {},
		"the threshold itself is not a close call, and raising CLOSE_CALL_PCT must move BOTH surfaces")


func test_the_chip_reaches_the_strip() -> void:
	## The helper can be perfect while nothing calls it — the wiring lesson from .740, applied to a
	## second surface. Driven through the real build(), reading the real Labels.
	var texts: Array[String] = _chip_texts(_strip({"low_water_pct": 3.0, "anyone_fell": false}))
	assert_true(texts.has("CLOSE CALL"),
		"the strip was built and must carry the chip; labels found: %s" % str(texts))


func test_a_clean_fight_puts_no_chip_on_the_strip() -> void:
	var texts: Array[String] = _chip_texts(_strip({"low_water_pct": 100.0, "anyone_fell": false, "total_gold": 7}))
	assert_false(texts.has("CLOSE CALL"), "nothing to report about this fight")
	assert_false(texts.has("COSTLY"), "nothing to report about this fight")
	assert_true(texts.has("7 G"), "CONTROL: the strip really did build — without this the arms above pass on an empty strip")


func test_an_old_results_dict_is_read_as_an_ordinary_fight() -> void:
	## A save/replay path or a caller not yet updated supplies neither key. The defaults must describe a
	## clean fight, because the alternative is a COSTLY chip on a battle nobody was hurt in.
	var texts: Array[String] = _chip_texts(_strip({"total_gold": 3}))
	assert_false(texts.has("COSTLY"), "a missing key must not invent a casualty")
	assert_false(texts.has("CLOSE CALL"), "a missing key must not invent a close call")
	assert_true(texts.has("3 G"), "CONTROL: the strip built")


func test_the_injury_chip_still_gets_the_final_word() -> void:
	## The strip's own ordering rule, in a comment at the injury loop: injuries are permanent, so they
	## come last. A shape chip appended after them would silently take that position.
	var o: VictoryOverlay = _strip({
		"low_water_pct": 2.0, "anyone_fell": true,
		"injuries": [{"name": "Brom", "injury": {"penalty": 3, "stat": "speed", "description": "limp"}}],
	})
	var texts: Array[String] = _chip_texts(o)
	var shape_at: int = texts.find("COSTLY")
	var inj_at: int = -1
	for i in texts.size():
		if texts[i].begins_with("⚠"):
			inj_at = i
			break
	assert_gt(shape_at, -1, "the shape chip must be present; labels: %s" % str(texts))
	assert_gt(inj_at, -1, "the injury chip must be present; labels: %s" % str(texts))
	assert_lt(shape_at, inj_at, "the injury keeps the final word, so the shape chip comes before it")


func test_the_engine_actually_publishes_the_two_facts() -> void:
	## The strip reads `low_water_pct` and `anyone_fell` off the results dict; end_battle is what puts
	## them there. Nothing types those two together, so a rename on either side leaves the chip reading
	## its defaults forever — an ordinary-looking win on every close call.
	var code: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_gt(code.length(), 10000, "CONTROL: BattleManager was read")
	assert_true(code.contains('"low_water_pct": _battle_low_water_pct'),
		"end_battle no longer publishes low_water_pct, so the strip can never say CLOSE CALL")
	assert_true(code.contains('"anyone_fell": not _ko_this_battle.is_empty()'),
		"end_battle no longer publishes anyone_fell, so the strip can never say COSTLY")
