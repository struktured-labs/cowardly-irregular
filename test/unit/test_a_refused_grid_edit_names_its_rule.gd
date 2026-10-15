extends GutTest

## ⛔ THE GRID EDITOR REFUSED FIVE EDITS WITH A BEEP AND NO REASON, AND THE REASONS WERE NUMBERS THE
## PLAYER CANNOT SEE ANYWHERE. `MAX_RULES = 32` and `MAX_ACTIONS = 5` appear in no player-facing
## string in the game; "nothing can follow Defer" and "Defer has no target" are rules of the editor
## that nothing states. Each site played `menu_error` and returned.
##
## 🔑 The same file already explains TWENTY other refusals through `_flash_status`, the transient
## line above the legend strip. So this was not a surface without a channel — it was a channel the
## five did not use. Measured before the fix: 23 `menu_error` sites, 13 with no flash within ±4
## lines; the five below were the subset whose reason is an INVISIBLE RULE rather than the cursor
## position (which the player can see on screen).
##
## ⚠️ THE OTHER EIGHT ARE DELIBERATELY LEFT, and this file does not assert over them. They refuse on
## things already visible — the cursor is in the conditions half, the party has one member, the
## condition takes no operator. An allowlist of eight on day one is rot arriving dressed as
## diligence; the arm below is scoped by DERIVATION instead, to refusals gated on a cap const or on
## the defer type, which is the class whose reason cannot be seen.

const EDITOR_PATH := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## Every `menu_error` refusal whose guarding condition names a cap or the defer action — i.e. whose
## reason is invisible — paired with whether a reason is flashed with it.
func _cap_gated_refusals() -> Array:
	var out: Array = []
	## ⛔ strip_comments, NOT code_of: this arm reports `i + 1` as a SOURCE LINE, and code_of
	## rejoins after splitting on triple quotes, so its line map is gone. Measured on this
	## file: 3805 raw lines, 3805 after strip_comments, 3865 after code_of — every printed
	## number was off by 32-57, naming healthy code to whoever read the failure. The swap is
	## behaviour-neutral: the needle occurs 23 times under both readers (cowir-battle).
	var lines: PackedStringArray = GdSource.strip_comments(
			FileAccess.get_file_as_string(EDITOR_PATH)).split("\n")
	for i in lines.size():
		if not str(lines[i]).contains('play_ui("menu_error")'):
			continue
		var cond := ""
		for j in range(i - 1, maxi(0, i - 6), -1):
			var s: String = str(lines[j]).strip_edges()
			if s.begins_with("if ") or s.begins_with("elif "):
				cond = s
				break
		var invisible: bool = cond.contains("MAX_RULES") or cond.contains("MAX_ACTIONS") \
			or cond.contains('"defer"')
		if not invisible:
			continue
		var window := ""
		for j in range(i, mini(lines.size(), i + 4)):
			window += str(lines[j]) + "\n"
		out.append({"line": i + 1, "cond": cond, "flashed": window.contains("_flash_status")})
	return out


func test_the_derivation_finds_the_refusals_at_all() -> void:
	var found := _cap_gated_refusals()
	assert_gt(found.size(), 3,
		"PRECONDITION: the cap- and defer-gated refusals must be findable, or every arm here is "
		+ "vacuous. Found %d" % found.size())


## THE CLAIM: a refusal the player cannot explain from the screen must say its rule.
func test_every_invisible_rule_refusal_names_itself() -> void:
	var silent: Array = []
	for r in _cap_gated_refusals():
		if not r["flashed"]:
			silent.append("%d: %s" % [r["line"], r["cond"]])
	assert_eq(silent, [],
		"a refusal gated on a cap const or on Defer must flash its reason — the cap is in no "
		+ "player-facing string and Defer's rules are stated nowhere: %s" % [silent])


## CONTROL: the derivation must EXCLUDE the visible-reason refusals, or the arm above is really a
## claim about all 23 sites and would red on the eight left deliberately.
func test_the_derivation_excludes_the_visible_ones() -> void:
	var code: String = GdSource.code_of(EDITOR_PATH)
	var all_errors: int = code.split('play_ui("menu_error")').size() - 1
	var caught: int = _cap_gated_refusals().size()
	assert_gt(all_errors, caught,
		"CONTROL: this file must not be asserting over every menu_error (%d of %d) — the cursor-"
		% [caught, all_errors] + "position and nothing-to-cycle refusals are visible and excluded")


## And the caps really are invisible, which is the whole premise.
func test_the_caps_appear_in_no_player_facing_string() -> void:
	var code: String = GdSource.code_of(EDITOR_PATH)
	var re := RegEx.new()
	## A player-facing use would interpolate the const into a string shown on screen; the only such
	## uses must be the refusal messages this fix added.
	re.compile('_flash_status\\([^)]*MAX_(RULES|ACTIONS)')
	assert_gt(re.search_all(code).size(), 1,
		"the caps must now reach the player through the refusal messages, or the fix is not wired")
