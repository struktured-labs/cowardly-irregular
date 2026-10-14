extends GutTest

## ⛔ A LISTED PROFILE CAN RESOLVE TO STANDARD AND SAY NOTHING ABOUT IT, AND THE FAILURE IS INVISIBLE
## FROM BOTH SIDES. `get_profile_bindings`' `_:` arm returns PROFILE_STANDARD, so a name added to
## PROFILE_NAMES without a `match` arm becomes a profile the player can pick from ControlsMenu that
## changes nothing at all — the picker shows the name, and the bindings it hands back are a valid
## profile. Nothing is null, nothing throws, and no existing arm reds.
##
## 🔑 Today all three static profiles ARE byte-identical to Standard across all 8 remappable actions
## (measured 2026-10-14, and the reason `ab5d04c4d` removed the v2 migration's "L/R inversion"
## claim). That is a decision — ControllerMappings made the 8BitDo shoulder swap wrong rather than
## right — so this file does not forbid the sameness. It requires the sameness to be DECLARED, in
## `PROFILE_ALIASES`, with the reason the entry still exists.
##
## ✅ Explain-it-green, per CLAUDE.md: there is no suppression flag here. An entry is a sentence, so
## it cannot become muscle memory the way an `"_alias_ok": true` would by the second profile.
##
## 📌 The ratchet is BIDIRECTIONAL. A declared alias whose profile has since DIVERGED is a stale
## note claiming a sameness that is gone — that reds too, because the next reader would trust it.

const SRC := "res://src/input/InputProfileManager.gd"

## "Custom" is excluded by name — see `test_custom_is_excluded_for_a_measured_reason` for why that
## is necessary rather than lazy.
const LIVE_STATE_PROFILE := "Custom"

## A floor on EFFORT, not a check of content: shorter than one clause cannot say why an entry
## exists. Nothing here inspects what the sentence claims, and nothing can satisfy it but prose.
const MIN_REASON_CHARS := 40


func _mgr() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("InputProfileManager")


## FLOOR — every symbol the arms below reach, named from the script's own constant map rather than a
## hand-written list. Without this, a rename makes an arm vacuous instead of red: the dictionary read
## aborts its enclosing function, the helper returns `[]`, and "no undeclared aliases" is what an
## empty array looks like.
func test_the_symbols_these_arms_reach_all_exist() -> void:
	var consts: Dictionary = (load(SRC) as GDScript).get_script_constant_map()
	for name in ["PROFILE_NAMES", "REMAPPABLE_ACTIONS", "PROFILE_ALIASES", "PROFILE_STANDARD"]:
		assert_true(consts.has(name),
			"FLOOR: InputProfileManager must still name %s — a rename makes these arms vacuous"
				% name)
	var mgr: Node = _mgr()
	assert_not_null(mgr, "FLOOR: the InputProfileManager autoload must be reachable")
	if mgr != null:
		assert_true(mgr.has_method("get_profile_bindings"),
			"FLOOR: get_profile_bindings is the CONSUMER's own name->bindings mapping; this file "
			+ "must resolve through it rather than re-deriving the match arms")


## Element-wise, deliberately: whether `Array ==` compares by value or by reference decides this
## file's entire verdict, and under reference semantics every profile would read as "differs" and
## every arm below would pass vacuously. Comparing ints removes the dependency on that fact.
func _same_binding(a, b) -> bool:
	var aa: Array = a if a is Array else []
	var bb: Array = b if b is Array else []
	if aa.size() != bb.size():
		return false
	for i in aa.size():
		if int(aa[i]) != int(bb[i]):
			return false
	return true


## The classifier, shared by the claim and its control. Returns one entry per listed profile that
## resolves to Standard's bindings WITHOUT a PROFILE_ALIASES declaration.
##
## ⚠️ Reached through `get_profile_bindings`, deliberately: re-deriving the name->const mapping here
## would make this file agree with itself and go blind to the `_:` fallback, which is the whole
## defect. A guard that reproduces its subject's logic only ever confirms it.
func _undeclared(names: Array) -> Array:
	var out: Array = []
	var mgr: Node = _mgr()
	if mgr == null:
		return out
	var std: Dictionary = mgr.PROFILE_STANDARD
	var aliases: Dictionary = mgr.PROFILE_ALIASES
	var actions: Array = mgr.REMAPPABLE_ACTIONS
	for raw in names:
		var profile: String = str(raw)
		if profile == "Standard" or profile == LIVE_STATE_PROFILE:
			continue
		var bindings: Dictionary = mgr.get_profile_bindings(profile)
		var differs: bool = false
		for action in actions:
			if not _same_binding(bindings.get(action, null), std.get(action, null)):
				differs = true
				break
		if not differs and not aliases.has(profile):
			out.append(profile)
	return out


## THE CLAIM — every listed profile either binds something differently from Standard, or declares in
## PROFILE_ALIASES why an identical entry still exists.
func test_a_listed_profile_differs_or_declares_itself_an_alias() -> void:
	var mgr: Node = _mgr()
	assert_not_null(mgr, "PRECONDITION: the autoload must exist")
	if mgr == null:
		return
	var undeclared: Array = _undeclared(mgr.PROFILE_NAMES)
	assert_eq(undeclared, [],
		"these listed profiles hand back Standard's bindings and say nothing about it, so picking "
		+ "one from ControlsMenu changes nothing. Either give the profile a real binding difference, "
		+ "or add it to PROFILE_ALIASES with the reason its entry exists. Undeclared: %s"
			% [undeclared])


## THE POSITIVE CONTROL — the arm above reports an absence, and an absence has no loud direction of
## its own: a broken classifier and a clean roster are the same empty array. This feeds the SAME
## helper a name that is NOT in `get_profile_bindings`' match arms, so the real `_:` fallback hands
## back Standard, and asserts the classifier says NO.
##
## 🔑 It is also what catches an abort inside `_undeclared`: the helper's `Array` default is `[]`,
## which reads as a PASS above and fails HERE. The two arms disagree under abort, which is the
## property that makes the pair load-bearing rather than decorative.
func test_the_classifier_flags_a_name_that_falls_through_to_standard() -> void:
	var mgr: Node = _mgr()
	assert_not_null(mgr, "PRECONDITION: the autoload must exist")
	if mgr == null:
		return
	var synthetic := "Synthetic Pad That Has No Match Arm"
	assert_false(mgr.PROFILE_NAMES.has(synthetic),
		"PRECONDITION: the probe name must not be a real profile")
	assert_false(mgr.PROFILE_ALIASES.has(synthetic),
		"PRECONDITION: the probe name must not be a declared alias")
	var flagged: Array = _undeclared([synthetic])
	assert_eq(flagged, [synthetic],
		"the classifier must FLAG a listed name with no match arm — this is the only proof it can "
		+ "say NO, and without it the claim arm's empty array is unfalsifiable. Got %s" % [flagged])


## THE REVERSE RATCHET — a declared alias whose profile has DIVERGED is a note asserting a sameness
## that is gone, and the next reader trusts it. Delete the entry when the profile earns its name.
func test_no_alias_declaration_outlives_the_sameness_it_claims() -> void:
	var mgr: Node = _mgr()
	assert_not_null(mgr, "PRECONDITION: the autoload must exist")
	if mgr == null:
		return
	var std: Dictionary = mgr.PROFILE_STANDARD
	var actions: Array = mgr.REMAPPABLE_ACTIONS
	var stale: Array = []
	for profile in mgr.PROFILE_ALIASES.keys():
		var bindings: Dictionary = mgr.get_profile_bindings(str(profile))
		for action in actions:
			if not _same_binding(bindings.get(action, null), std.get(action, null)):
				stale.append("%s now differs on %s" % [profile, action])
				break
	assert_eq(stale, [],
		"these PROFILE_ALIASES entries claim a sameness the profile no longer has — remove them: %s"
			% [stale])


## An alias entry for a name nobody can select is dead weight that would hide its own removal.
func test_every_declared_alias_names_a_listed_profile() -> void:
	var mgr: Node = _mgr()
	assert_not_null(mgr, "PRECONDITION: the autoload must exist")
	if mgr == null:
		return
	var orphans: Array = []
	for profile in mgr.PROFILE_ALIASES.keys():
		if not mgr.PROFILE_NAMES.has(profile):
			orphans.append(profile)
	assert_eq(orphans, [],
		"these PROFILE_ALIASES entries name profiles that are not in PROFILE_NAMES, so nothing can "
		+ "select them and the entry explains nothing: %s" % [orphans])


## A reason must be prose. This is the half that cannot be satisfied by a flag.
func test_every_alias_reason_is_a_sentence_not_a_flag() -> void:
	var mgr: Node = _mgr()
	assert_not_null(mgr, "PRECONDITION: the autoload must exist")
	if mgr == null:
		return
	var thin: Array = []
	for profile in mgr.PROFILE_ALIASES.keys():
		var reason: String = str(mgr.PROFILE_ALIASES[profile])
		if reason.strip_edges().length() < MIN_REASON_CHARS:
			thin.append("%s: %d chars" % [profile, reason.strip_edges().length()])
	assert_eq(thin, [],
		"a PROFILE_ALIASES value must say WHY the entry exists, in at least %d characters: %s"
			% [MIN_REASON_CHARS, thin])


## WHY "Custom" IS EXCLUDED, pinned rather than asserted in a comment. `_init` seeds
## `custom_bindings = PROFILE_STANDARD.duplicate(true)`, so on a fresh install Custom EQUALS Standard
## by value while being live mutable state the player owns. Including it would red every clean boot
## and the only available cure would be an alias entry that is simply false.
func test_custom_is_excluded_for_a_measured_reason() -> void:
	var mgr: Node = _mgr()
	assert_not_null(mgr, "PRECONDITION: the autoload must exist")
	if mgr == null:
		return
	assert_true(mgr.PROFILE_NAMES.has(LIVE_STATE_PROFILE),
		"PRECONDITION: Custom must still be a listed profile for this exclusion to be about anything")
	assert_true("custom_bindings" in mgr,
		"Custom resolves to the live `custom_bindings` member — if that member is renamed, this "
		+ "exclusion stops being about live state and must be re-justified")
	assert_false(mgr.PROFILE_ALIASES.has(LIVE_STATE_PROFILE),
		"Custom must NOT be declared an alias: it is live state that merely STARTS equal to "
		+ "Standard, and an entry here would assert a permanence it does not have")
