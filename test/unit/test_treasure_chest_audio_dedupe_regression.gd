extends GutTest

## UX regression: TreasureChest._open_chest() must not play "chest_open"
## twice per opening, and the second-cue slot must be content-aware
## (gold pickup chime for gold-type chests; silent for item/equipment
## because the on-screen text + the opening sound at line 331 already
## communicate the reward).
##
## Bug shape:
##   • Line 331 fires SoundManager.play_ui("chest_open") at the start
##     of _open_chest — the actual opening cue.
##   • Line 388 (pre-fix) ALSO fired SoundManager.play_ui("chest_open")
##     AFTER the content match block ran. Same sound, played twice
##     per chest. The comment hinted that this slot was intended as a
##     content-specific reward chime ("Play item found as a UI sound,
##     not a music stinger — avoids music loop bug" — i.e. it must
##     stay play_ui, not play_music) but the actual call used the
##     same chest_open id.
##   • The second call also lacked the `if SoundManager:` guard the
##     first one had — if SoundManager were null mid-scene, it'd
##     crash here.
##
## Fix: replace the duplicate with a content-aware match. Gold
## chests play the canonical "gold_pickup" chime (matches
## BattleResultsDisplay's gold count-up SFX); item / equipment
## chests get no second cue — the opening sound + on-screen text
## already speak for the reward.
##
## Tests:
##   • Source pin: a second bare `play_ui("chest_open")` after
##     `chest_opened.emit(` is GONE
##   • Source pin: the new content-aware match plays "gold_pickup"
##     on the gold branch
##   • Source pin: the second-cue site is wrapped in `if SoundManager:`
##     (matches the first call's null guard)

const TREASURE_CHEST_PATH := "res://src/exploration/TreasureChest.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_no_duplicate_chest_open_after_emit() -> void:
	# Scope: the slice of _open_chest AFTER chest_opened.emit(). Pre-fix this
	# slice contained `SoundManager.play_ui("chest_open")` — the duplicate.
	var text := _read(TREASURE_CHEST_PATH)
	var idx := text.find("func _open_chest")
	assert_gt(idx, -1, "_open_chest must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Find the emit line; everything after it is the tail where the duplicate
	# used to live.
	var emit_idx := body.find("chest_opened.emit(")
	assert_gt(emit_idx, -1, "chest_opened.emit must still be called")
	var tail := body.substr(emit_idx)
	# Strip comment lines so the teaching doc that cites the legacy shape
	# doesn't trip its own lint.
	var lines := tail.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		code_only.append(ln)
	var code := "\n".join(code_only)
	assert_false(code.contains("SoundManager.play_ui(\"chest_open\")"),
		"_open_chest's tail (after chest_opened.emit) must NOT call play_ui(\"chest_open\") — the opening sound already fired earlier")


func test_gold_branch_plays_gold_pickup() -> void:
	var text := _read(TREASURE_CHEST_PATH)
	var idx := text.find("func _open_chest")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var emit_idx := body.find("chest_opened.emit(")
	var tail := body.substr(emit_idx)
	assert_true(tail.contains("\"gold_pickup\""),
		"the gold branch of the post-emit match must play \"gold_pickup\" (the canonical gold chime)")


func test_post_emit_sound_block_guards_sound_manager() -> void:
	# The first sound call at line ~331 wraps in `if SoundManager:`. The
	# second-cue site must do the same to prevent a null-deref crash if
	# SoundManager hasn't initialised.
	var text := _read(TREASURE_CHEST_PATH)
	var idx := text.find("func _open_chest")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var emit_idx := body.find("chest_opened.emit(")
	var tail := body.substr(emit_idx)
	assert_true(tail.contains("if SoundManager:"),
		"the post-emit sound block must be guarded with `if SoundManager:`")
