extends GutTest

## tick 125 regression: _spawn_quip_bubble's text Label must enable
## word-wrap with a max width. Pre-fix, the Label had no autowrap
## configured, so long lines (cleric/mage/bard trigger_voices
## average 80-108 chars after tick 122 wired them into the bubble
## surface) extended horizontally off-screen.
##
## A 100-char line at font-size 13 is roughly 600px wide unwrapped.
## With sprite position 40px left of bubble + bubble extending right,
## that easily clips past the 1280px viewport edge for any sprite
## right of x=600. Wrapping at 260px caps bubble width at a
## reasonable read width regardless of speaker position.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _spawn_bubble_body() -> String:
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _spawn_quip_bubble")
	assert_gt(idx, -1, "_spawn_quip_bubble must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_label_has_autowrap_word_mode() -> void:
	# Pin the AUTOWRAP_WORD enum value specifically — WORD wrapping
	# (vs ARBITRARY) keeps line breaks at word boundaries, which
	# reads better than mid-word splits.
	var body := _spawn_bubble_body()
	assert_true(body.contains("label.autowrap_mode = TextServer.AUTOWRAP_WORD"),
		"_spawn_quip_bubble's text Label must set autowrap_mode = TextServer.AUTOWRAP_WORD")


func test_label_has_max_width_via_custom_minimum_size() -> void:
	# Pin: custom_minimum_size sets the MAX width for wrapping —
	# Label autowrap requires a minimum width to know when to break.
	# 260px chosen as a reasonable read column without overflowing
	# the typical sprite position bracket.
	var body := _spawn_bubble_body()
	assert_true(body.contains("label.custom_minimum_size = Vector2(260, 0)"),
		"_spawn_quip_bubble must set label.custom_minimum_size = Vector2(260, 0) — caps the wrap width")


func test_wrapping_applied_only_to_quote_label_not_name_label() -> void:
	# Pin: name_label (the speaker name header) does NOT need wrapping.
	# Speaker names are short — wrapping them would add no value and
	# might split a multi-word name awkwardly across lines.
	var body := _spawn_bubble_body()
	# Find the name_label declaration and check its config block doesn't
	# include autowrap.
	var name_idx: int = body.find("var name_label = Label.new()")
	var quote_idx: int = body.find("# Quote text")
	assert_gt(name_idx, -1, "name_label must exist")
	assert_gt(quote_idx, -1, "quote text marker must exist")
	var name_block: String = body.substr(name_idx, quote_idx - name_idx)
	assert_false(name_block.contains("autowrap_mode"),
		"name_label should NOT have autowrap — speaker names are short, no need")


func test_existing_bubble_layout_paths_preserved() -> void:
	# Don't regress the existing bubble layout:
	# - PanelContainer wrapper with border
	# - VBoxContainer holding name + quote labels
	# - Polygon2D pointer triangle
	# - Tween fade-in / float-up / fade-out
	var body := _spawn_bubble_body()
	assert_true(body.contains("var bubble = PanelContainer.new()"),
		"PanelContainer wrapper preserved")
	assert_true(body.contains("var vbox = VBoxContainer.new()"),
		"VBoxContainer layout preserved")
	assert_true(body.contains("var pointer = Polygon2D.new()"),
		"pointer triangle preserved")
	assert_true(body.contains("tween.tween_property(container, \"modulate:a\", 1.0, 0.15)"),
		"fade-in tween preserved")


func test_turbo_and_speed_suppression_preserved() -> void:
	# Don't regress the autogrind/turbo/4x suppression — those checks
	# protect the bubble from spamming during fast-mode play.
	var body := _spawn_bubble_body()
	assert_true(body.contains("if turbo_mode or Engine.time_scale >= 2.0:"),
		"turbo + speed suppression preserved")
	assert_true(body.contains("if autogrind_console_mode:"),
		"autogrind suppression preserved")
