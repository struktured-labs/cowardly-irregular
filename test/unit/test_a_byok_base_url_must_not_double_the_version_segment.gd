extends GutTest

## A base_url ending in `/v1` produces `/v1/v1/chat/completions` — a 404 that
## reads to the player as "my API key is bad".
##
## `HTTPBackend` appends the version segment itself:
##     base_url.rstrip("/") + "/v1/chat/completions"      (:279)
##     base_url.rstrip("/") + "/v1/models"                (:114, the probe)
## `rstrip("/")` removes trailing SLASHES, not a trailing path segment, so
## "https://api.openai.com/v1" survives intact and the version doubles.
##
## ⛔ AND THE PANEL TELLS THE PLAYER TO TYPE EXACTLY THAT. BYOKConfigPanel:122
## placeholders the base_url field with "https://api.openai.com/v1" — which is
## also the string every provider's own docs call "the base URL", so a player
## reaches it by following either source. HTTPBackend's own header (:12) uses
## the other convention, "http://localhost:11434", with no version segment.
##
## Both endpoints are affected, which is why the failure is so confusing: the
## probe 404s too, so `Test Connection` fails and names nothing.

const PanelScript := preload("res://src/ui/BYOKConfigPanel.gd")
const BackendScript := preload("res://src/llm/HTTPBackend.gd")

## Each provider's own docs call the left column "the base URL", so it is what a
## player pastes. The right column is where the request must actually land.
const EXPECTED_CHAT := [
	["https://api.openai.com/v1", "https://api.openai.com/v1/chat/completions"],
	["https://api.openai.com", "https://api.openai.com/v1/chat/completions"],
	["https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1/chat/completions"],
	["https://api.groq.com/openai/v1", "https://api.groq.com/openai/v1/chat/completions"],
	["https://api.openai.com/v1/", "https://api.openai.com/v1/chat/completions"],
]
const PROVIDER_BASE_URLS := [
	"https://api.openai.com/v1",
	"https://openrouter.ai/api/v1",
	"https://api.groq.com/openai/v1",
]


func _backend(base: String, fmt: String) -> Node:
	var b: Node = BackendScript.new()
	b.base_url = base
	b.api_format = fmt
	return b


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_reachable() -> void:
	var b: Node = _backend("http://x", "openai")
	assert_true(b.has_method("_endpoint_url"),
		"HTTPBackend._endpoint_url is gone — the endpoint builder this file is about")
	assert_true(b.has_method("_probe_url"),
		"HTTPBackend._probe_url is gone — the probe endpoint this file is about")
	assert_true("base_url" in b and "api_format" in b,
		"HTTPBackend no longer exposes base_url/api_format")
	b.free()


func test_the_backend_really_does_append_the_version_itself() -> void:
	## PINS THE ASSUMPTION. If the backend ever stops appending /v1, every arm
	## below is about a problem that no longer exists and this file should go.
	var b: Node = _backend("https://api.example.com", "openai")
	assert_eq(b._endpoint_url(false), "https://api.example.com/v1/chat/completions",
		"the backend no longer appends /v1 to a bare host — re-read this file's header")
	b.free()


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_pasted_provider_base_url_does_not_double_the_version() -> void:
	## ⚠️ ASSERT THE WHOLE URL, NOT A COUNT. `"…/v1/v1/models".count("/v1/")` is
	## **1**, not 2 — the two matches share the middle slash and count() is
	## non-overlapping, so the obvious instrument scores the defect as clean.
	for row in EXPECTED_CHAT:
		var b: Node = _backend(row[0], "openai")
		var url: String = b._endpoint_url(false)
		b.free()
		assert_false(url.contains("/v1/v1/"),
			("base_url %s produced %s — the version segment is doubled. HTTPBackend "
			+ "appends /v1 and rstrip(\"/\") cannot remove a path segment, so a player "
			+ "who pastes the URL their provider's docs call 'the base URL' gets a 404 "
			+ "that reads as a bad API key.") % [row[0], url])
		assert_eq(url, row[1],
			"base_url %s should reach %s, got %s" % [row[0], row[1], url])


func test_the_probe_endpoint_does_not_double_the_version_either() -> void:
	## The probe failing the same way is what makes this invisible: Test
	## Connection reports a failure and names nothing the player can act on.
	for base in PROVIDER_BASE_URLS:
		var b: Node = _backend(base, "openai")
		var url: String = b._probe_url()
		b.free()
		assert_false(url.contains("/v1/v1/"),
			("probe URL for %s is %s — /v1 is doubled, so Test Connection 404s for "
			+ "the same reason the real call does and names nothing.") % [base, url])


func test_the_panel_does_not_instruct_the_player_to_paste_a_version_segment() -> void:
	## The placeholder is the instruction most players follow, so it is part of
	## the defect rather than cosmetic.
	var src: String = FileAccess.get_file_as_string("res://src/ui/BYOKConfigPanel.gd")
	assert_ne(src, "", "could not read BYOKConfigPanel.gd — this arm proved nothing")
	assert_false(src.contains("\"https://api.openai.com/v1\""),
		"BYOKConfigPanel still placeholders the base_url field with a URL ending "
		+ "in /v1, which HTTPBackend then doubles into /v1/v1/chat/completions.")


# ── the presets must reach a real endpoint ────────────────────────────────────

func _make_panel():
	var p = PanelScript.new()
	add_child_autofree(p)
	return p


func test_every_preset_reaches_a_well_formed_endpoint() -> void:
	## THE LOAD-BEARING ARM. A preset exists to spare the player from typing a
	## base_url, so a preset that builds a bad URL is worse than the free-text
	## field it replaces — the player has no reason to doubt it. This ties the
	## table to the backend's own construction rather than to a copy of it.
	var presets: Array = PanelScript.PROVIDER_PRESETS
	assert_gt(presets.size(), 1, "the preset table is empty — nothing below tests anything")
	for i in range(1, presets.size()):
		var preset: Dictionary = presets[i]
		var label: String = str(preset["label"])
		assert_ne(str(preset["base_url"]), "", "preset '%s' has no base_url" % label)
		var models: Array = preset.get("models", [])
		assert_gt(models.size(), 0,
			("preset '%s' offers no models, so its Model dropdown is just Custom… — "
			+ "free text is the last resort, not the default") % label)
		for m in models:
			assert_ne(str(m).strip_edges(), "", "preset '%s' lists an empty model name" % label)
		var b: Node = _backend(str(preset["base_url"]), str(preset["format"]))
		var url: String = b._endpoint_url(false)
		var probe: String = b._probe_url()
		b.free()
		assert_false(url.contains("/v1/v1/"),
			"preset '%s' builds %s — doubled version segment" % [label, url])
		assert_false(url.substr(8).contains("//"),
			"preset '%s' builds %s — doubled slash in the path" % [label, url])
		assert_true(url.begins_with("http"),
			"preset '%s' builds %s — not an http(s) URL" % [label, url])
		assert_true(probe.begins_with("http"),
			"preset '%s' probes %s — not an http(s) URL" % [label, probe])


func test_choosing_a_preset_fills_the_three_fields_it_exists_to_fill() -> void:
	var p = _make_panel()
	var presets: Array = PanelScript.PROVIDER_PRESETS
	for i in range(1, presets.size()):
		p._on_provider_selected(i)
		var preset: Dictionary = presets[i]
		assert_eq(p._base_url_field.text, str(preset["base_url"]),
			"preset '%s' did not fill base_url" % str(preset["label"]))
		assert_eq(p._model_field.text, str(preset["models"][0]),
			"preset '%s' did not fill model with its first listed option" % str(preset["label"]))
		var want_fmt: int = 1 if str(preset["format"]) == "ollama" else 0
		assert_eq(p._format_picker.selected, want_fmt,
			"preset '%s' did not set the api_format picker" % str(preset["label"]))


func test_custom_fills_nothing_so_it_cannot_erase_a_hand_typed_config() -> void:
	## Entry 0 must be inert. If it filled blanks, scrolling onto it would wipe
	## a working hand-entered config the player never meant to touch.
	var p = _make_panel()
	p._base_url_field.text = "https://my.proxy.internal"
	p._model_field.text = "my-model"
	p._on_provider_selected(0)
	assert_eq(p._base_url_field.text, "https://my.proxy.internal",
		"selecting Custom erased a hand-typed base_url")
	assert_eq(p._model_field.text, "my-model",
		"selecting Custom erased a hand-typed model")


func test_a_saved_config_reselects_its_preset_including_the_v1_spelling() -> void:
	## Round-trip: a player who saved via a preset should see that preset again,
	## and one who pasted the /v1 form should still be recognised rather than
	## silently shown "Custom".
	var p = _make_panel()
	assert_eq(p._match_preset("https://api.openai.com"), 1, "bare OpenAI base_url did not match")
	assert_eq(p._match_preset("https://api.openai.com/v1"), 1, "the /v1 spelling did not match")
	assert_eq(p._match_preset("https://api.openai.com/v1/"), 1, "the /v1/ spelling did not match")
	assert_eq(p._match_preset("https://something.else"), 0, "an unknown host must fall to Custom")


# ── the model dropdown ────────────────────────────────────────────────────────

func test_every_provider_offers_a_model_list_ending_in_custom() -> void:
	## struktured 2026-09-19: "free text is bad, thats the last resort 'custom',
	## instead off most 10 common options or so". So the dropdown must carry real
	## options AND always keep an escape hatch — a list with no Custom… traps a
	## player whose model is not on it.
	var p = _make_panel()
	for i in range(1, PanelScript.PROVIDER_PRESETS.size()):
		p._on_provider_selected(i)
		var label: String = str(PanelScript.PROVIDER_PRESETS[i]["label"])
		assert_gt(p._model_picker.item_count, 1,
			"provider '%s' shows only Custom… — the dropdown offers nothing" % label)
		assert_eq(p._model_picker.get_item_text(p._model_picker.item_count - 1),
			PanelScript.CUSTOM_MODEL_LABEL,
			"provider '%s' has no Custom… escape hatch as its last entry" % label)


func test_picking_a_listed_model_writes_it_to_the_authoritative_field() -> void:
	## _model_field is what Save and the Test probe read, so a dropdown that does
	## not write through is a control that appears to work and changes nothing.
	var p = _make_panel()
	p._on_provider_selected(1)
	var last_real: int = p._model_picker.item_count - 2
	assert_gt(last_real, 0, "provider 1 has fewer than two listed models — arm proves little")
	p._model_picker.selected = last_real
	p._on_model_selected(last_real)
	assert_eq(p._model_field.text, p._model_picker.get_item_text(last_real),
		"choosing a model from the dropdown did not reach _model_field")


func test_choosing_custom_does_not_overwrite_what_the_player_typed() -> void:
	var p = _make_panel()
	p._on_provider_selected(1)
	p._model_field.text = "my-finetune:v3"
	var custom_idx: int = p._model_picker.item_count - 1
	p._on_model_selected(custom_idx)
	assert_eq(p._model_field.text, "my-finetune:v3",
		"selecting Custom… clobbered the model the player had typed")


func test_typing_an_unlisted_model_moves_the_picker_to_custom() -> void:
	## Otherwise the dropdown keeps naming a model that is not what gets sent.
	var p = _make_panel()
	p._on_provider_selected(1)
	p._model_field.text = "some-unlisted-model"
	p._on_model_text_changed("some-unlisted-model")
	assert_eq(p._model_picker.get_item_text(p._model_picker.selected),
		PanelScript.CUSTOM_MODEL_LABEL,
		"hand-typing an unlisted model left the dropdown naming a different one")


func test_typing_a_listed_model_snaps_the_picker_back_to_it() -> void:
	var p = _make_panel()
	p._on_provider_selected(1)
	var wanted: String = p._model_picker.get_item_text(0)
	p._model_field.text = wanted
	p._on_model_text_changed(wanted)
	assert_eq(p._model_picker.get_item_text(p._model_picker.selected), wanted,
		"typing a model that IS on the list should re-select it, not fall to Custom…")
