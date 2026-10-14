extends GutTest

## Raising Text Size did not reach any surface built ONCE and kept. `SettingsMenu.settings_changed`
## has 20 emits and ZERO `.connect(` anywhere in src/ (cowir-story, 2026-10-14), so nothing listened;
## a persistent HUD stayed exactly as it was. The player raises the setting BECAUSE they cannot read
## something, closes the menu, and nothing changed.
##
## Menus, overlays and cutscenes need none of this -- they are built per open and read the live
## scale. The mechanism is for the kept ones.
##
## ⛔ THE LOAD-BEARING CASE IS A HIDDEN NODE, not a visible one. In exploration, Settings is only
## reachable through the overworld menu, and `GameLoop._set_field_hud_hidden(true)` hides the field
## HUD while that menu is open -- so EVERY adopter is hidden at the moment the change lands
## (cowir-story, measured). A re-apply that silently skips hidden nodes would fix nothing at all.
##
## ⚠️ FONTS ONLY, and the guard says so rather than leaving it implied: re-scaling text is not
## re-scaling a LAYOUT. A surface whose boxes come from a literal still owns its own geometry -- my
## own battle log needed a derived reserve alongside the font, or the panel hid itself.

const GS_PATH := "res://src/meta/GameState.gd"

var _saved_scale: float = 1.0
## ⛔ EVERY CONNECTION THIS FILE MAKES IS TO AN AUTOLOAD SIGNAL AND MUST COME BACK OFF. A lambda
## left connected outlives the test: the next file to change the scale fires it, against locals this
## one captured. TextScale.apply guards with is_instance_valid so it would not crash — but an
## accumulating connection list IS autoload state left dirty, which is exactly the class that got
## this stack dropped from .691, one signal over from current_state.
var _conns: Array[Callable] = []


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	for c in _conns:
		if GameState.text_size_scale_changed.is_connected(c):
			GameState.text_size_scale_changed.disconnect(c)
	_conns.clear()
	GameState.text_size_scale = _saved_scale


## Connect through here so after_each can take it back off. A bare `.connect(func(…))` cannot be
## disconnected later: nothing holds the Callable.
func _watch(c: Callable) -> void:
	_conns.append(c)
	GameState.text_size_scale_changed.connect(c)


func _label(px: int) -> Label:
	var l := Label.new()
	add_child_autofree(l)
	l.add_theme_font_size_override(&"font_size", px)
	return l


## FLOOR: a rename reds with the symbol named, instead of an arm aborting mid-frame and passing.
func test_the_mechanism_symbols_exist() -> void:
	assert_true(GameState.has_method("set_text_size_scale"),
		"FLOOR: set_text_size_scale is the single writer every caller must go through")
	assert_true(GameState.has_signal("text_size_scale_changed"),
		"FLOOR: the signal is the whole point — settings_changed has no listeners")
	var probe := _label(20)
	assert_true(probe.has_meta(&"font_size") == false,
		"FLOOR: a fresh label carries no capture yet, so the capture arms below start clean")


## ARM 1 — idempotence. get_theme_font_size() returns the OVERRIDE once one is set, so a helper that
## re-reads the node COMPOUNDS. Measured on BattleScene's first version: 32 -> 128 after two extra
## applications. This is what makes the helper safe to call from a signal that can fire repeatedly.
func test_reapplying_never_compounds() -> void:
	GameState.text_size_scale = 2.0
	var l := _label(16)
	TextScale.apply(l)
	var once: int = l.get_theme_font_size(&"font_size")
	assert_eq(once, 32, "a 16px base at 200%% must be 32, not %d" % once)
	for _i in range(4):
		TextScale.apply(l)
	assert_eq(l.get_theme_font_size(&"font_size"), once,
		("five applications must equal one. A helper that re-reads the node instead of its captured "
		+ "base reaches 512 here (16 -> 32 -> 64 -> 128 -> 256 -> 512), and a change signal would grow the font on every settings visit.")
		)


## ARM 2 — THE DEFECT. A node built BEFORE the change must pick the change up.
func test_a_live_change_reaches_a_node_built_before_it() -> void:
	GameState.text_size_scale = 1.0
	var l := _label(16)
	TextScale.apply(l)
	assert_eq(l.get_theme_font_size(&"font_size"), 16, "built at 100%, so 16 to begin with")
	var seen: Array = []
	_watch(func(s): TextScale.apply(l); seen.append(s))
	GameState.set_text_size_scale(2.0)
	assert_eq(seen.size(), 1,
		"the setter must emit exactly once for a real change, or an adopter is never told")
	assert_eq(l.get_theme_font_size(&"font_size"), 32,
		("a node built at 100%% must read 32 after a live change to 200%% — this is the whole defect: "
		+ "without it the player closes Settings and the HUD is exactly as it was. Got %d.")
		% l.get_theme_font_size(&"font_size"))


## CONTROL for ARM 2 — a node built AFTER the change already has the new size, so arm 2 cannot be
## satisfied by construction order rather than by the signal.
func test_a_node_built_after_the_change_needs_no_signal() -> void:
	GameState.set_text_size_scale(2.0)
	var l := _label(16)
	TextScale.apply(l)
	assert_eq(l.get_theme_font_size(&"font_size"), 32,
		"CONTROL: construction already reads the live scale, which is why menus need no adoption")


## ARM 3 — THE ONLY PATH THAT EXISTS. Every field-HUD adopter is HIDDEN when the change lands,
## because the menu that reaches Settings hides them. A re-apply gated on visibility fixes nothing.
func test_the_change_reaches_a_HIDDEN_node() -> void:
	GameState.text_size_scale = 1.0
	var l := _label(16)
	TextScale.apply(l)
	l.visible = false
	_watch(func(_s): TextScale.apply(l))
	GameState.set_text_size_scale(2.0)
	assert_eq(l.get_theme_font_size(&"font_size"), 32,
		("a HIDDEN node must take the change: in exploration Settings is only reachable through the "
		+ "menu that hides the field HUD, so hidden IS the case, not an edge of it"))
	l.visible = true
	assert_eq(l.get_theme_font_size(&"font_size"), 32,
		"and it must still hold after being shown again")


## A no-op write must NOT emit. An adopter re-applying to a whole subtree on every spurious emit is
## how a cheap signal becomes a per-frame cost.
func test_setting_the_same_value_does_not_emit() -> void:
	GameState.set_text_size_scale(1.5)
	var fired: Array = []
	_watch(func(s): fired.append(s))
	GameState.set_text_size_scale(1.5)
	assert_eq(fired.size(), 0, "an unchanged value must not emit; got %d emission(s)" % fired.size())
	GameState.set_text_size_scale(0.8)
	assert_eq(fired.size(), 1, "but a real change must: got %d" % fired.size())


## The setter absorbed a clampf that used to sit in SaveSystem, so a corrupt save cannot drive the
## scale out of range through the new path.
func test_the_setter_clamps_like_the_line_it_replaced() -> void:
	GameState.set_text_size_scale(99.0)
	assert_eq(GameState.text_size_scale, 2.0, "above the range must clamp to 2.0")
	GameState.set_text_size_scale(-5.0)
	assert_eq(GameState.text_size_scale, 0.8, "below it must clamp to 0.8")


## RATCHET: a bare assignment still compiles, and a silent assignment is exactly the defect. Derived
## from source so a new writer has to come through the setter or explain itself here.
##
## ⚠️ IT CATCHES TWO SPELLINGS, NOT ONE, because a ratchet keyed to a single spelling is the hole
## cowir-sfx and cowir-story each found in their own guards today: `GameState.text_size_scale = …`
## AND `GameState.set("text_size_scale", …)`, which reaches the same field and reads nothing like it.
## 📌 THE KNOWN BLIND SPOT, measured rather than left implicit: src/ holds exactly ONE dynamic write,
## LiveVoicePanel:228 `GameState.set(f, _opened_with[f])`, whose keys are the hardcoded list
## ["tts_live_enabled", "tts_server_url", "tts_model"] at :39, so the scale is UNREACHABLE through it
## today. A variable key cannot be read from source, so adding "text_size_scale" to a list like that
## is the one write this ratchet cannot see — named here rather than pretended away.
func test_no_caller_assigns_the_scale_behind_the_setters_back() -> void:
	var offenders: Array[String] = []
	var dirs: Array[String] = ["res://src"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			dirs.append("%s/%s" % [d, sub])
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = "%s/%s" % [d, f]
			if path == GS_PATH:
				continue  ## the setter's own file assigns it, by definition
			var text: String = FileAccess.get_file_as_string(path)
			for raw in text.split("\n"):
				var line: String = raw.strip_edges()
				if line.begins_with("#") or line.begins_with("##"):
					continue
				if 'GameState.set("text_size_scale"' in line:
					offenders.append("%s: %s" % [path, line])
					continue
				if "GameState.text_size_scale" in line and "=" in line \
						and not "==" in line and not "set_text_size_scale" in line \
						and not line.contains("GameState.text_size_scale)") :
					if line.split("=")[0].strip_edges().ends_with("GameState.text_size_scale"):
						offenders.append("%s: %s" % [path, line])
	assert_eq(offenders, [] as Array[String],
		("a bare `GameState.text_size_scale = …` skips the signal, so a kept HUD is never told — "
		+ "which is the defect this mechanism exists to fix. Use set_text_size_scale(). Found: %s")
		% str(offenders))
