extends GutTest

## Two actions on one key is how today's live bug got in: ui_menu binds ENTER, ui_accept binds ENTER,
## and one press of Confirm opened the autobattle editor mid-fight. Escape had the same collision and
## had already been patched twice, at two separate call sites, each time with a raw-keycode
## special-case — three incidents, one undetected class.
##
## This enumerates every pair of PROJECT-OWNED actions sharing a key or a pad button and requires each
## to be DECLARED with a reason. A new accidental collision fails; an intentional one costs one line.
##
## ⚠️ SCOPE, stated to match the instrument: only actions the project declares in project.godot's
## [input] section — the ones it has taken ownership of. Godot ships ~50 more built-ins (ui_text_*,
## ui_copy…) that overlap constantly and correctly; including them makes this fail toward ALARM,
## which is the shape that got three instruments retired in this fleet today. Bindings come from the
## live InputMap, not from parsing the file, so a runtime rebind is measured rather than assumed.
##
## 🛑 CONSEQUENCE, MEASURED, AND IT WILL FOOL THE NEXT PERSON TO MUTATION-TEST THIS:
## InputProfileManager (autoload) ERASES every InputEventJoypadButton at _ready and re-adds from its
## own profile table. So project.godot's PAD bindings are DEAD at runtime and its KEY bindings are
## live. Planting a pad collision in project.godot therefore changes nothing the game sees, the
## ratchet stays green, and it reads as a hollow guard — it is an inadequate mutation. Mutate a KEY
## binding, or mutate the profile table. Reading the roster from the file and the BINDINGS from the
## live InputMap is deliberate: the roster is what the project owns, the InputMap is what the player
## actually presses.
##
## The DECLARED entries are not suppressions — each names why the two can never both be live, and
## that sentence is the deliverable. You cannot silence this green, only explain it green.

const PROJECT := "res://project.godot"

## key/button signature -> the reason the collision is safe. Keep the reason, not just the pair.
const DECLARED := {
	"battle_defer+party_chat":
		"L / pad 9. party_chat is gated on LoopState.EXPLORATION in GameLoop; battle_defer's " +
		"consumers are battle-only or consume first. Never both live.",
	"ui_accept+ui_menu":
		"ENTER. ui_menu is the START button; Enter is Confirm. GameLoop's BATTLE arm excludes " +
		"KEY_ENTER (2026-09-10) so Confirm cannot open the editor. Exploration keeps Enter on the " +
		"quick-Settings path by a prior ruling — see test_enter_is_confirm_not_start_regression.",
	"ui_cancel+ui_menu":
		"ESCAPE. Same shape, patched earlier at both call sites: 'Escape is BACK, never OPEN' " +
		"(struktured 2026-08-30) and the exploration double-open (web smoke 2026-07-11).",
}


## The actions the PROJECT owns, read from its own [input] section rather than hardcoded here — a
## hardcoded roster goes stale silently the first time someone adds an action.
func _project_actions() -> Array[String]:
	var src := FileAccess.get_file_as_string(PROJECT)
	var start := src.find("[input]")
	assert_gt(start, -1, "project.godot must have an [input] section")
	var stop := src.find("\n[", start + 1)
	var body := src.substr(start, (stop - start) if stop > start else -1)
	var out: Array[String] = []
	var re := RegEx.create_from_string("(?m)^([A-Za-z_][A-Za-z0-9_]*)=\\{")
	for m in re.search_all(body):
		out.append(m.get_string(1))
	return out


## Signature for one event. Modifiers are part of the key's identity — Shift+R and R are different
## bindings, and Godot matching an action with EXTRA modifiers held is a separate hazard.
func _sig(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var mods := ""
		if k.shift_pressed: mods += "S"
		if k.ctrl_pressed: mods += "C"
		if k.alt_pressed: mods += "A"
		if k.meta_pressed: mods += "M"
		return "key:%d%s" % [k.keycode, mods]
	if ev is InputEventJoypadButton:
		return "btn:%d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var j := ev as InputEventJoypadMotion
		return "axis:%d:%s" % [j.axis, ("+" if j.axis_value > 0.0 else "-")]
	return ""


## Every bucket holding more than one project action, as "a+b" keys.
func _collisions() -> Dictionary:
	var buckets := {}
	for action in _project_actions():
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			var s := _sig(ev)
			if s == "":
				continue
			if not buckets.has(s):
				buckets[s] = []
			if not buckets[s].has(action):
				buckets[s].append(action)
	var out := {}
	for s in buckets:
		var names: Array = buckets[s]
		if names.size() < 2:
			continue
		names.sort()
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				var pair: String = "%s+%s" % [names[i], names[j]]
				if not out.has(pair):
					out[pair] = []
				out[pair].append(s)
	return out


## THE RATCHET. A new shared binding must be declared with the reason it is safe.
func test_every_shared_binding_is_declared() -> void:
	var found := _collisions()
	var undeclared: Array[String] = []
	for pair in found:
		if not DECLARED.has(pair):
			undeclared.append("%s (on %s)" % [pair, ", ".join(found[pair])])
	assert_eq(undeclared, [] as Array[String],
		"two project actions share a binding with no declared reason — one press fires both, " +
		"which is how ENTER opened the autobattle editor mid-fight. Declare it or unbind it: %s"
		% [", ".join(undeclared)])


## CONTROL: the enumerator must actually FIND the collisions we know exist. Without this, a broken
## scan reports zero undeclared and reads as health — the wrong-shape zero.
func test_the_scan_finds_the_known_collisions() -> void:
	var found := _collisions()
	assert_true(found.has("battle_defer+party_chat"),
		"CONTROL: L is bound to BOTH battle_defer and party_chat — if the scan cannot see that, " +
		"its zero means nothing")
	assert_true(found.has("ui_accept+ui_menu"),
		"CONTROL: ENTER is bound to both — this is the pair that produced today's fix")


## CONTROL: no DECLARED entry may be INERT. An allowlist line for a collision that no longer exists
## is a suppression nobody will ever revisit, and it makes the list read as bigger coverage than it has.
func test_no_declared_entry_is_stale() -> void:
	var found := _collisions()
	var inert: Array[String] = []
	for pair in DECLARED:
		if not found.has(pair):
			inert.append(pair)
	assert_eq(inert, [] as Array[String],
		"a declared collision no longer exists — delete the entry rather than leaving it: %s"
		% [", ".join(inert)])


## The roster must be read from the file and be non-trivial, or every arm above is vacuously green.
func test_the_project_action_roster_is_real() -> void:
	var actions := _project_actions()
	assert_gt(actions.size(), 5, "PRECONDITION: the [input] section must yield real actions")
	assert_true(actions.has("battle_defer"), "a known project action must be in the roster")
	assert_false(actions.has("zzq_not_an_action"),
		"CONTROL: the roster must be able to report a name as ABSENT")
