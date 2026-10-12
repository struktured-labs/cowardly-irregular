extends GutTest

## An ability names its EFFECT (memory_leak_status) where the status LANDS under another word
## (memory_leak), and the cue is authored as status_memory_leak. play_status built its key from
## the raw effect, asked for status_memory_leak_status, found nothing, and played the generic
## descending blip over an authored cue on disk. Combatant.resolve_status_alias is the applier's
## own map and nine rule-side call sites already use it — audio was the sibling left behind.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SELF_PATH := "res://test/unit/test_a_status_cue_follows_the_alias_the_applier_uses.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"

const PROCEDURAL := "<the generic blip>"
const NOTHING := "<no stream at all>"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


## The cue a play_status call actually REACHED, by the stream it left on the battle player. The
## procedural blip carries no resource_path, which is what separates it from every authored cue.
func _cue_reached(sm: Node, status_name: String) -> String:
	sm._sfx_cooldowns.clear()
	sm._battle_player.stream = null
	sm.play_status(status_name)
	var st = sm._battle_player.stream
	if st == null:
		return NOTHING
	var p := str(st.resource_path)
	return p.get_file() if p != "" else PROCEDURAL


func _authored() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	return (parsed.get("sfx", {}) if parsed is Dictionary else {}) as Dictionary


func test_the_memory_leak_cue_is_reached_and_not_the_blip() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var sfx: Dictionary = _authored()
	assert_true(sfx.has("status_memory_leak"),
		"CONTROL: status_memory_leak is not authored, so this arm cannot tell a fix from a miss")
	assert_false(sfx.has("status_memory_leak_status"),
		"CONTROL: status_memory_leak_status is now authored too — the alias is no longer what makes this reachable, re-read the arm")
	assert_eq(_cue_reached(sm, "memory_leak_status"), "status_memory_leak.ogg",
		"Memory Leak lands and the player hears the generic descending blip instead of the authored status_memory_leak cue — play_status must resolve the effect name through Combatant.resolve_status_alias")


func test_the_exact_key_still_wins_over_its_alias() -> void:
	## Load-bearing: burn aliases to burning, status_burn IS authored and status_burning is NOT,
	## so resolving before trying the exact key would send every Burn ability to the blip.
	var sm: Node = _sm()
	if sm == null:
		return
	var sfx: Dictionary = _authored()
	assert_true(sfx.has("status_burn"), "CONTROL: status_burn unauthored — this arm measures nothing")
	assert_false(sfx.has("status_burning"),
		"CONTROL: status_burning is now authored, so this arm no longer proves exact-first ordering — pick another alias whose target is unauthored")
	assert_eq(_cue_reached(sm, "burn"), "status_burn.ogg",
		"a Burn ability no longer reaches its own authored cue — the alias is being resolved BEFORE the exact key")


func test_every_alias_the_applier_knows_reaches_an_authored_cue() -> void:
	## DERIVED from Combatant.STATUS_ALIASES, so an alias added later is covered without editing
	## this file. Only pairs where SOME cue exists are judged — an unauthored pair is content.
	var sm: Node = _sm()
	if sm == null:
		return
	var sfx: Dictionary = _authored()
	var aliases: Dictionary = Combatant.STATUS_ALIASES
	assert_gt(aliases.size(), 0, "CONTROL: STATUS_ALIASES is empty — this arm would judge nothing")
	var judged := 0
	var blipped: Array = []
	for effect in aliases.keys():
		var canonical := str(aliases[effect])
		var ke := "status_" + str(effect)
		var kc := "status_" + canonical
		if not sfx.has(ke) and not sfx.has(kc):
			continue
		judged += 1
		var got := _cue_reached(sm, str(effect))
		if got == PROCEDURAL or got == NOTHING:
			blipped.append("%s -> %s (authored: %s)" % [effect, got, kc if sfx.has(kc) else ke])
	assert_gt(judged, 0, "CONTROL: no alias pair has a cue authored on either side — nothing was judged")
	assert_eq(blipped.size(), 0,
		"%d of %d aliased effects play the generic blip while a cue is authored for the status they land as: %s" % [blipped.size(), judged, str(blipped)])


func test_an_unauthored_status_still_gets_the_designed_blip() -> void:
	## The alias path must not swallow the designed fallback for a genuinely unknown status.
	var sm: Node = _sm()
	if sm == null:
		return
	var sfx: Dictionary = _authored()
	assert_false(sfx.has("status_qqq_not_a_real_status"), "CONTROL: the probe key must stay unauthored")
	assert_eq(_cue_reached(sm, "qqq_not_a_real_status"), PROCEDURAL,
		"an unknown status no longer reaches the generic descending blip — play_status's designed fallback is gone")


func test_a_status_named_by_the_engine_is_unchanged() -> void:
	## BattleManager's weapon procs pass the STORED status name; that path must be untouched.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_eq(_cue_reached(sm, "poison"), "status_poison.ogg",
		"an un-aliased status no longer reaches its own cue — the alias branch is interfering with the exact path")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## DERIVED from this file's own source, so it cannot go stale against the reaches below it.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var src: String = GdSource.code_of(SELF_PATH)
	var stripped := ""
	for l in src.split("\n"):
		if not l.strip_edges().begins_with("#"):
			stripped += l + "\n"
	var reached := {}
	var re := RegEx.create_from_string("\\bsm\\.([A-Za-z_][A-Za-z0-9_]*)")
	for m in re.search_all(stripped):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 0, "CONTROL: derived no sm. reaches — the regex or the scan is broken")
	for name in reached.keys():
		var n := str(name)
		assert_true(sm.has_method(n) or sm.get(n) != null,
			"SoundManager has no member `%s`, which this file drives — an arm reaching it aborts and can score green" % [n])
	assert_true(Combatant.STATUS_ALIASES is Dictionary,
		"Combatant.STATUS_ALIASES is no longer a Dictionary — the derived arm reads it directly")
