extends GutTest

## AbilityFacts is the zoom's "what does it do" (struktured, main 23219/23225): one source for the field and battle panels.
## An empty box was the defect, and so is a mechanic that is authored but never shown, so every abilities.json key is
## either rendered by some ability's row or declared NON_FACT with a reason, derived from the JSON, never a hand list.

func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return (parsed as Dictionary).get("abilities", parsed)


func test_every_ability_has_type_target_and_no_raw_text() -> void:
	var all := _abilities()
	assert_gt(all.size(), 250, "CONTROL: the whole kit is read (%d)" % all.size())
	var bad: Array = []
	for id in all:
		var rows: Array = AbilityFacts.rows(str(id))
		if rows.size() < 2:
			bad.append("%s has %d rows" % [id, rows.size()])
			continue
		if str(rows[0]["label"]) != "Type" or str(rows[1]["label"]) != "Target":
			bad.append("%s starts %s/%s" % [id, rows[0]["label"], rows[1]["label"]])
		for r in rows:
			var text := "%s %s" % [r["label"], r["value"]]
			if str(r["value"]).strip_edges() == "" or "_" in text:
				bad.append("%s: '%s'" % [id, text])
	assert_eq(bad, [], "a zoomed ability must say what it does in words, with Type and Target always first")


func test_every_authored_key_is_shown_or_declared() -> void:
	var all := _abilities()
	var authored := {}
	for id in all:
		if all[id] is Dictionary:
			for k in all[id]:
				authored[str(k)] = true
	var shown := {}
	for id in all:
		for r in AbilityFacts.rows(str(id)):
			for k in r["keys"]:
				shown[str(k)] = true
	var dropped: Array = []
	for k in authored:
		if not shown.has(k) and not AbilityFacts.NON_FACT.has(k):
			dropped.append(k)
	dropped.sort()
	assert_eq(dropped, [], "an authored mechanic reaches no row and has no declared reason, so the panel silently drops it")
	var stale: Array = []
	for k in AbilityFacts.NON_FACT:
		if not authored.has(k):
			stale.append(k)
	assert_eq(stale, [], "a NON_FACT entry names a key abilities.json no longer has")


func test_a_caster_sees_the_cost_and_heal_the_game_charges() -> void:
	var cleric := Combatant.new()
	autofree(cleric)
	cleric.combatant_name = "Cleric"
	cleric.job = JobSystem.get_job("cleric")
	cleric.magic = 40
	cleric.max_mp = 99
	cleric.current_mp = 99
	# A real discount (mp_efficiency ×0.75), so the charged cost differs from the raw mp_cost and the row has to know which.
	var worn: Array[String] = ["mp_efficiency"]
	cleric.equipped_passives = worn
	assert_ne(JobSystem.get_ability_mp_cost(cleric, "cure"), int(JobSystem.get_ability("cure").get("mp_cost", 0)),
		"CONTROL: mp_efficiency changes what cure costs this caster")
	var rows: Array = AbilityFacts.rows("cure", cleric)
	var by_label := {}
	for r in rows:
		by_label[str(r["label"])] = str(r["value"])
	assert_eq(by_label.get("MP", ""), str(JobSystem.get_ability_mp_cost(cleric, "cure")), "the MP row is the cost the game charges this caster")
	var healed: int = BattleManager.heal_cast_amount(cleric, JobSystem.get_ability("cure"))
	assert_gt(healed, 0, "CONTROL: cure heals this caster for something")
	assert_eq(by_label.get("Heals", ""), "~%d HP" % healed, "the heal row is BattleManager's own estimate")


func test_a_row_never_promises_what_the_engine_does_not_do() -> void:
	var unread: Dictionary = load("res://test/unit/test_ability_effect_keys_reach_the_engine_regression.gd").get_script_constant_map().get("UNREAD_EFFECT_KEYS", {})
	var unbuilt: Array = []
	for k in unread:
		if str(unread[k]).begins_with("DEFERRED") or str(unread[k]).begins_with("MISSING"):
			unbuilt.append(str(k))
	assert_true(unbuilt.has("bp_gain"), "CONTROL: the engine guard still lists the unbuilt BP bank (%s)" % str(unbuilt))
	var all := _abilities()
	var promised: Array = []
	for id in all:
		for r in AbilityFacts.rows(str(id)):
			for k in r["keys"]:
				if unbuilt.has(str(k)):
					promised.append("%s: %s %s" % [id, r["label"], r["value"]])
	assert_eq(promised, [], "a zoom row describes a mechanic the engine does not perform (controller 23290)")
