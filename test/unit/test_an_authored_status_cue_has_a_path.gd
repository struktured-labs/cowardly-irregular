extends GutTest

## A composed status cue that nothing can reach is audio nobody hears, and tonight four lanes fixed
## four of them in four different ways — a name mismatch resolved by an alias (memory_leak_status ->
## status_memory_leak), a name mismatch resolved at the executor (cleanse -> status_cured), statuses
## applied where no cue call existed (mind_swap/controlled/permakilled), and bespoke cues swallowed
## by the generic debuff arm (festered/pacify).
##
## 🔑 This guard does NOT model the reason. It asks only whether SOME path can reach each authored
## cue, so it reds on all four shapes without knowing which. That is why it is the right guard: the
## reasons were not predictable in advance, and a fifth shape will not be either.
##
## Every side is DERIVED from source or data — the arm lists, the alias map, the weapon-proc table,
## the item map — because a hand-listed copy of any of them goes stale in the edit that moves it.

const SFX_MANIFEST := "res://data/sfx_manifest.json"
const ABILITIES := "res://data/abilities.json"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
## The docstring delimiter, as a const so it never appears inline and confuses a reader or a scanner.
## EVERY arm and EVERY control reads source through HERE, never GdSource.code_of directly. An arm
## scoped to the helper cannot see its caller stop using it: cowir-battle, cowir-deploy and
## cowir-autogrind each shipped that defect tonight in guards written to be careful about prose.
## Mutating this one function therefore tests all five arms at once.
static func _code(path: String) -> String:
	return GdSource.code_of(path)


const QUOTES := '"""'

## A cue may be authored ahead of its path ONLY with a reason. Not a suppression flag: the entry has
## to say why, and it EXPIRES — an exempted cue that becomes reachable reds, so the list cannot
## outlive the decision it records.
## ⚠️ `festered` and `pacify` were listed here and the expiry arm DELETED THEM BY NAME when
## cowir-sfx's 70ea3c923 landed in .666 — their effects left the generic debuff arm, so both now
## fall through to the `_:` arm and reach their own cues (festered via the amplify_poison alias).
## That is this guard's whole point working on its own author, inside an hour of being written.
const AUTHORED_AHEAD := {
	"paralyze":
		"Deliberately unwired (cowir-story + cowir-main, 2026-10-12): the mechanic a paralyze status"
		+ " would express — a combatant that cannot take its turn — already exists TWICE as `stun` and"
		+ " `cannot_act`, each with its own cue, so wiring a third name for one behaviour is redundant"
		+ " rather than missing. 0 abilities author the effect, 0 add_status literals, 0 STATUS_ALIASES"
		+ " entries. Whether to retire status_paralyze.ogg is struktured's call; the cue is harmless"
		+ " where it is, and if paralyze is ever wired this entry must go.",
}


func _gd_files(root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			out += _gd_files(p)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out


func _authored() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	var sfx: Dictionary = (parsed.get("sfx", {}) if parsed is Dictionary else {}) as Dictionary
	var out := {}
	for k in sfx.keys():
		if str(k).begins_with("status_"):
			out[str(k).substr(7)] = true
	return out


## The dispatch's own arm lists, read from its source. An effect named in the buff or debuff arm
## plays play_battle(), never a status cue — so it buys NO reachability for a status_<effect> cue.
## Each dispatch arm paired with the body that belongs to IT, bounded by the next arm rather than by
## a character count. A 160-char window read PAST the last arm into three others and left the two
## generic arms only +142 of margin -- two comment lines from a silent false negative.
func _dispatch_arms() -> Array:
	var src: String = _code(BATTLE_SCENE)
	var i: int = src.find("var effect = ability.get(\"effect\", \"\")")
	if i < 0:
		return []
	var j: int = src.find("\nfunc ", i)
	var lines: Array = src.substr(i, (j - i) if j > i else src.length() - i).split("\n")
	var re := RegEx.create_from_string("^\\t+((?:\"[a-z_]+\",?\\s*)+):\\s*$")
	var out: Array = []
	var k := 0
	while k < lines.size():
		var label: String = str(lines[k])
		var m := re.search(label)
		if m == null:
			k += 1
			continue
		var depth: int = label.length() - label.lstrip("\t").length()
		var body: String = ""
		var n: int = k + 1
		while n < lines.size():
			var l: String = str(lines[n])
			if l.strip_edges() != "" and (l.length() - l.lstrip("\t").length()) <= depth:
				break
			body += l + "\n"
			n += 1
		out.append({"effects": m.get_string(1), "body": body})
		k = n
	return out


## Only the arms whose own body plays a GENERIC cue swallow their effects.
func _swallowed_by_a_generic_arm() -> Dictionary:
	var out := {}
	var eff := RegEx.create_from_string("\"([a-z_]+)\"")
	for arm in _dispatch_arms():
		if not str((arm as Dictionary)["body"]).contains("play_battle("):
			continue
		for n in eff.search_all(str((arm as Dictionary)["effects"])):
			out[n.get_string(1)] = true
	return out


## How many arms playing a GENERIC cue the scan found. Structural control for the subtraction above:
## naming a member breaks when that member is correctly re-routed, as `cleanse` was tonight.
func _generic_arms_read() -> int:
	var n := 0
	for arm in _dispatch_arms():
		if str((arm as Dictionary)["body"]).contains("play_battle("):
			n += 1
	return n


## The item cue map, read as a CONST through the class: scanning the source for its brackets lands
## inside the `Array[Array]` type annotation, which is why this leg read zero for its whole life.
func _cued_from_items() -> Dictionary:
	var out: Dictionary = {}
	var rows: Array = load(SOUND_MANAGER).get_script_constant_map().get("_ITEM_EFFECT_SFX", [])
	for row in rows:
		if not (row is Array) or (row as Array).size() < 2:
			continue
		var cue := str((row as Array)[1])
		if cue.begins_with("status_"):
			out[cue.substr(7)] = true
	return out


## Every way a status cue can actually be reached, derived. See the module docstring.
func _reachable() -> Dictionary:
	var out := {}
	var files: Array = _gd_files("res://src")

	## 1. a literal call site. `_cue_status(` is included because it is the seam the meta arms use —
	## omitting it made this derivation miss mind_swap/controlled/permakilled, which are cued by
	## nothing else (measured: the guard red on its own author's fix).
	var re_lit := RegEx.create_from_string("(?:play_status|_cue_status)\\(\\s*\"([a-z_]+)\"")
	var re_auth := RegEx.create_from_string("play_status_if_authored\\(\\s*\"status_([a-z_]+)\"")
	## 2. the weapon-proc table: these are cued on application, by status NAME.
	var re_proc := RegEx.create_from_string("\"status\"\\s*:\\s*\"([a-z_]+)\"")
	for f in files:
		for l in _code(f).split("\n"):
			for m in re_lit.search_all(l):
				out[m.get_string(1)] = true
			for m in re_auth.search_all(l):
				out[m.get_string(1)] = true
			for m in re_proc.search_all(l):
				out[m.get_string(1)] = true

	## 3. the item cue map, read through the class by _cued_from_items(). ⚠️ A loose scan for any
	## `"status_x"` literal in src counts SoundManager's procedural SOUNDS entries — which are an
	## alternative RENDERER, not a path to the cue — and that invented a path for `paralyze`, whose
	## only appearance in src is `"status_paralyze": {"freq": 800, ...}` at SoundManager:213.
	for s in _cued_from_items().keys():
		out[str(s)] = true

	## 4. an ability effect that reaches the catch-all, which calls play_status(effect).
	var swallowed: Dictionary = _swallowed_by_a_generic_arm()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var ab: Dictionary = (parsed.get("abilities", parsed) if parsed is Dictionary else {}) as Dictionary
	for a in ab.values():
		if not (a is Dictionary):
			continue
		for key in ["effect", "secondary_effect"]:
			var e := str((a as Dictionary).get(key, "")).to_lower()
			if e != "" and not swallowed.has(e):
				out[e] = true

	## 5. an alias whose TARGET is reachable makes the target's cue reachable under the source name.
	for k in Combatant.STATUS_ALIASES.keys():
		var tgt := str(Combatant.STATUS_ALIASES[k])
		if out.has(str(k)):
			out[tgt] = true
	return out


func test_the_derivation_is_not_vacuously_wide_or_narrow() -> void:
	## CONTROLS FIRST: a reachable set that accepted everything could never red, and one that
	## accepted nothing would red on all 23. Both failure modes are checked before the subject arm.
	var r: Dictionary = _reachable()
	assert_gt(r.size(), 30, "CONTROL: derived only %d reachable statuses — the scan is broken and a zero below would prove nothing" % r.size())
	assert_true(r.has("poison"), "CONTROL: poison is applied by 11 abilities and must be reachable")
	assert_true(r.has("stun"), "CONTROL: stun is applied by 17+ abilities and must be reachable")
	assert_false(r.has("qqq_not_a_real_status"), "CONTROL: the set accepts an invented status, so it cannot refuse anything")
	var swallowed: Dictionary = _swallowed_by_a_generic_arm()
	assert_gt(swallowed.size(), 10,
		"CONTROL: derived %d effects as swallowed by a generic arm; the buff and debuff arms hold ~20 between them, so a count this low means the arm scan failed and every swallowed effect is being counted as reachable" % swallowed.size())
	## ⚠️ This control named `cleanse` in its first version — "it sits in the buff arm" — and cowir-sfx's
	## cured fix legitimately MOVES it out, so the control red on a correct change. Coincidental-value
	## ratchet: assert the RELATIONSHIP (both generic arms were read) and never a member's membership.
	assert_gte(_generic_arms_read(), 2,
		"CONTROL: read %d generic-cue arm(s); the dispatch has a buff arm and a debuff arm, so fewer than 2 means the arm scan failed and every swallowed effect is being counted as reachable" % _generic_arms_read())


func test_every_authored_status_cue_has_a_path_to_a_player() -> void:
	var authored: Dictionary = _authored()
	var reachable: Dictionary = _reachable()
	assert_gt(authored.size(), 15, "CONTROL: only %d authored status cues found — the manifest read failed" % authored.size())
	var unreachable: Array = []
	for s in authored.keys():
		if not reachable.has(str(s)) and not AUTHORED_AHEAD.has(str(s)):
			unreachable.append(str(s))
	unreachable.sort()
	assert_eq(unreachable.size(), 0,
		"%d authored status cue(s) no path can reach — composed audio nobody hears: %s. Either wire a path or add an AUTHORED_AHEAD entry saying WHY (an explanation, not a flag)" % [unreachable.size(), str(unreachable)])


func test_an_exemption_expires_when_its_cue_becomes_reachable() -> void:
	## The roster-rot rule: an entry must not outlive the decision it records. If paralyze is ever
	## wired, this reds and names it, rather than the list quietly becoming a list of excuses.
	var reachable: Dictionary = _reachable()
	var stale: Array = []
	for s in AUTHORED_AHEAD.keys():
		if reachable.has(str(s)):
			stale.append(str(s))
	assert_eq(stale.size(), 0,
		"%s now HAS a reachable path, so the AUTHORED_AHEAD entry is stale and must be deleted: %s" % [str(stale), str(stale)])


func test_an_exemption_explains_rather_than_suppresses() -> void:
	## A check whose correct case needs a flag is not a check. The deliverable is the reason.
	var authored: Dictionary = _authored()
	for s in AUTHORED_AHEAD.keys():
		var why := str(AUTHORED_AHEAD[s])
		assert_gt(why.length(), 80,
			"the AUTHORED_AHEAD entry for %s is %d chars — too short to be a reason, which makes it a suppression flag" % [s, why.length()])
		assert_true(authored.has(str(s)),
			"AUTHORED_AHEAD names %s but no status_%s cue is authored — exempt a cue that exists, or drop the entry" % [s, s])

func test_the_prose_this_guard_reads_past_was_really_stripped() -> void:
	## UNDER-STRIP direction, which nothing here covered. The floors above cover OVER-strip and are
	## AGGREGATE counts, so a mutant preserving the one line a must-survive names still fails them
	## (cowir-overworld measured exactly that mutant walking past both of their named controls).
	## The open direction was the opposite: if GdSource stopped stripping, a comment naming a cue
	## call site would INVENT a path and this guard would go QUIETER — the silent direction.
	##
	## ⚠️ Currently unexposed rather than protected: measured 0 comments and 0 docstrings in src/
	## naming a cue call site today. `## e.g. play_status("foo")` is a natural thing to write, so
	## this arm exists for the day someone does.
	##
	## Anchors are DERIVED from the raw file. A hardcoded comment string would be the same
	## coincidental-value pin this file already made once, with `cleanse`.
	var raw: String = FileAccess.get_file_as_string(BATTLE_SCENE)
	var code: String = _code(BATTLE_SCENE)
	assert_gt(raw.length(), code.length(),
		"CONTROL: the stripped source (%d) is not smaller than the raw source (%d), so nothing was stripped at all" % [code.length(), raw.length()])

	var comment_line := ""
	for l in raw.split("\n"):
		var t := str(l).strip_edges()
		if t.begins_with("#") and t.length() > 40:
			comment_line = t
			break
	assert_ne(comment_line, "", "CONTROL: no # comment line over 40 chars found; this input carries 1172, so a miss means the scan is wrong")
	assert_false(code.contains(comment_line),
		"a # comment survived the strip, so prose is INPUT to every scan in this file and a comment naming a cue call site would invent a path: %s" % comment_line.substr(0, 60))

	## And a docstring line — the half a #-only pass misses entirely. These inputs carry 357 regions.
	var doc_body := ""
	var a: int = raw.find(QUOTES)
	if a >= 0:
		var b: int = raw.find(QUOTES, a + 3)
		if b > a + 3:
			for l in raw.substr(a + 3, b - a - 3).split("\n"):
				var t2 := str(l).strip_edges()
				if t2.length() > 40:
					doc_body = t2
					break
	assert_ne(doc_body, "", "CONTROL: no docstring line over 40 chars found; this input carries 116 regions, so a miss means the region scan is wrong")
	assert_false(code.contains(doc_body),
		"a docstring line survived the strip — the REGION half of the stripper is not running, which is also what a #-only pass produces: %s" % doc_body.substr(0, 60))

func test_the_item_cue_map_leg_reads_its_const() -> void:
	var from_items: Dictionary = _cued_from_items()
	assert_true(from_items.has("cured"),
		("CONTENT FLOOR: _ITEM_EFFECT_SFX names status_cured on two rows (cure_all_status, " +
		"cure_status), so this leg must yield `cured`; it yielded %s. This leg read ZERO for its " +
		"whole life because find(\"[\") landed inside the `Array[Array]` annotation.")
		% [from_items.keys()])
	var merged: Dictionary = _reachable()
	for s in from_items.keys():
		assert_true(merged.has(str(s)),
			"item-leg cue `%s` was dropped between the leg and _reachable()" % [str(s)])
