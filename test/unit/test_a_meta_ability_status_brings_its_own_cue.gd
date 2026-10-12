extends GutTest

## Bossbinder's mind_swap and control_override, and Necromancer's permakill and
## mutual_destruction, applied a status and played NOTHING — while status_mind_swap.ogg,
## status_controlled.ogg and status_permakilled.ogg sat authored on disk, never once played.
##
## BattleScene's status dispatch keys on `ability.effect`, and those four abilities carry a
## `meta_effect` with NO `effect`, so they land on the `"": pass` arm. `time_stop` is the control:
## it has `effect: stun`, so it cued, which is why the gap never showed. _execute_meta_ability was
## 344 lines with zero SoundManager calls — the status was applied where no cue could see it, the
## same shape as the weapon procs at BM:5228 and the vulnerability window, both fixed before.
##
## ⚠️ The CUE is centralised, not the application. Wrapping `add_status` in a cued applier broke
## two other guards that derive the engine's status set from the `add_status("literal")` shape —
## test_a_status_cue_names_a_status_that_can_happen's RegEx and test_meta_effect_handlers'
## contains() — and made them report status_controlled and status_mind_swap as "silent forever",
## the exact opposite of the truth. Measured: 3 failures in a 599-guard sweep.

const BM_SRC := "res://src/battle/BattleManager.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## Bounded by the function's END, never a character count: a fixed window reds on an unrelated
## insertion and names the wrong file (measured on my own branch earlier today).
func _meta_body() -> String:
	var src: String = GdSource.code_of(BM_SRC)
	var i: int = src.find("func _execute_meta_ability")
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 10)
	return src.substr(i, (j - i) if j > i else src.length() - i)


func _sfx() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	return (parsed.get("sfx", {}) if parsed is Dictionary else {}) as Dictionary


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_the_cue_seam_really_plays_the_cue() -> void:
	## LIVENESS, at runtime. The pairing arm below is textual; without this, a seam moved into a
	## dead function would still read as covered (cowir-ai's condition on relation guards).
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	sm._battle_player.stream = null
	BattleManager._cue_status("mind_swap")
	var st = sm._battle_player.stream
	var got := (str(st.resource_path).get_file() if st != null else "<no stream>")
	assert_eq(got, "status_mind_swap.ogg",
		"the cue seam played %s — Bossbinder's signature ability stays silent while its cue sits on disk" % got)


func test_every_status_these_arms_apply_is_paired_with_a_cue() -> void:
	## DERIVED from the function's own text, BOTH sides, so a fifth meta arm is covered without
	## editing this file — a hand-list cannot see it, because whoever adds the arm adds it to the
	## list in the same edit (@cowir-overworld's point).
	var body: String = _meta_body()
	assert_ne(body, "", "CONTROL: _execute_meta_ability not found, so this arm scanned nothing")
	assert_gt(body.length(), 2000, "CONTROL: body read back %d chars, the bound is wrong" % body.length())
	var applied := {}
	var cued := {}
	var re_app := RegEx.create_from_string("add_status\\(\\s*\"([a-z_]+)\"")
	var re_cue := RegEx.create_from_string("_cue_status\\(\\s*\"([a-z_]+)\"")
	for l in body.split("\n"):
		var t := str(l).strip_edges()
		if t.begins_with("#"):
			continue
		for m in re_app.search_all(t):
			applied[m.get_string(1)] = true
		for m in re_cue.search_all(t):
			cued[m.get_string(1)] = true
	assert_gt(applied.size(), 0, "CONTROL: no applied status derived, so the relation is vacuous")
	var silent: Array = []
	for s in applied.keys():
		if not cued.has(s):
			silent.append(str(s))
	silent.sort()
	assert_eq(silent.size(), 0,
		"%d status(es) applied by a meta arm with no cue beside them, so they land silently: %s" % [silent.size(), str(silent)])


func test_the_scan_refuses_an_application_it_cannot_read() -> void:
	## "I found no status" and "I cannot read this status" must not share an answer — the defect
	## @cowir-deploy measured in a sibling extractor today. A table-driven arm would satisfy the
	## pairing arm vacuously, so every application in scope must be a readable literal.
	var body: String = _meta_body()
	if body == "":
		return
	var unreadable: Array = []
	var seen := 0
	var re_lit := RegEx.create_from_string("add_status\\(\\s*\"[a-z_]+\"")
	for l in body.split("\n"):
		var t := str(l).strip_edges()
		if t.begins_with("#") or not t.contains(".add_status("):
			continue
		seen += 1
		if re_lit.search(t) == null:
			unreadable.append(t.substr(0, 70))
	assert_gt(seen, 0, "CONTROL: no application found, so this refusal checked nothing")
	assert_eq(unreadable.size(), 0,
		"%d application(s) name a status this scan cannot read, so the pairing arm cannot speak for them: %s" % [unreadable.size(), str(unreadable)])


func test_the_cues_these_arms_need_are_authored() -> void:
	## Without this the arms above pass while the player hears the generic descending blip, which
	## struktured ruled "not even close to good".
	var sfx: Dictionary = _sfx()
	assert_gt(sfx.size(), 100, "CONTROL: sfx manifest read back %d" % sfx.size())
	var missing: Array = []
	for s in ["mind_swap", "controlled", "permakilled", "stun"]:
		if not sfx.has("status_" + s):
			missing.append("status_" + s)
	assert_eq(missing.size(), 0,
		"%s unauthored — a meta status would reach the generic blip instead of its own cue" % str(missing))


func test_one_event_stays_one_sound() -> void:
	## time_stop now cues at application AND through the dispatch on the same key. The 80ms
	## per-key cooldown must swallow the second, or the fix trades silence for a double hit.
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	BattleManager._cue_status("stun")
	assert_false(bool(sm._sfx_suppressed_by_cooldown), "CONTROL: the first cue must not be suppressed")
	sm.play_status("stun")
	assert_true(bool(sm._sfx_suppressed_by_cooldown),
		"a second status_stun inside one frame was NOT suppressed — application and dispatch would both sound and time_stop would double-hit")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## DERIVED from this file's own source, scoped to BattleManager, the receiver it names.
	##
	## ⚠️ Lines holding a res:// path are excluded, and that exclusion is STRUCTURAL on purpose.
	## The bare regex extracted `gd` from this file's own BM_SRC const and red on it. Stripping
	## quoted strings with "[^"]*" was WORSE: this file contains escaped quotes, so the pairing
	## shifted, swallowed the floor's own code line, and silently cut the derived set from 3 names
	## to 1 while still passing. A path line has nothing to pair; it is simply not a reach.
	var reached := {}
	var re := RegEx.create_from_string("\\bBattleManager\\.([A-Za-z_][A-Za-z0-9_]*)")
	for l in GdSource.code_of("res://test/unit/test_a_meta_ability_status_brings_its_own_cue.gd").split("\n"):
		var t := str(l).strip_edges()
		if t.begins_with("#") or t.contains("res://"):
			continue
		for m in re.search_all(l):
			reached[m.get_string(1)] = true
	assert_gt(reached.size(), 1,
		"CONTROL: derived only %d BattleManager reach(es); this file drives the cue seam plus the floor's own accessors, so a set this small means the scan narrowed" % reached.size())
	for name in reached.keys():
		assert_true(BattleManager.has_method(str(name)) or BattleManager.get(str(name)) != null,
			"BattleManager has no member `%s`, which this file drives" % [str(name)])
