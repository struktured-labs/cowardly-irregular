extends Control
class_name ShopScene

## FF5-Style Shop System
## Fullscreen overlay with buy/sell menus

signal shop_closed()
## Tick 257: emitted after a successful purchase (gold spent + item
## received). Lets external listeners (quest hooks, achievements,
## VillageShop bridge for the overworld trigger) react without
## reaching into the buy-menu plumbing.
signal item_purchased(item_id: String, cost: int)

enum ShopMode { MAIN, BUY, SELL, QUANTITY, CHAR_SELECT, EQUIP_SELECT }
enum ShopType { ITEM, BLACK_MAGIC, WHITE_MAGIC, BLACKSMITH }

## Keeper-portrait override — pre-registered PNG paths per ShopType.
## When a PNG exists at the mapped path, the description panel loads it via
## TextureRect instead of the CharacterCustomization procedural composite
## (which struktured called "shitty proc gen" — msg 2772, "Chapel of Light
## keeper looks like a serial killer"). Falls through to the procedural
## draw when the PNG is missing so nothing regresses if a file gets
## deleted or a new ShopType is added without art.
const KEEPER_PORTRAIT_PATHS: Dictionary = {
	ShopType.ITEM:        "res://assets/sprites/portraits/keepers/willow.png",
	ShopType.BLACK_MAGIC: "res://assets/sprites/portraits/keepers/mortimer.png",
	ShopType.WHITE_MAGIC: "res://assets/sprites/portraits/keepers/lenora.png",
	ShopType.BLACKSMITH:  "res://assets/sprites/portraits/keepers/brutus.png",
}

## Purchase-feedback tuning (struktured msg 2775). Success flash is a
## deliberately different colour + a scale beat from the red error flash
## so the two outcomes read as opposites at a glance.
const GOLD_FLASH_SUCCESS_COLOR: Color = Color(1.0, 1.0, 0.75)
const GOLD_FLASH_SUCCESS_SEC: float = 0.28
const GOLD_LABEL_COLOR: Color = Color(1.0, 0.9, 0.3)
const GOLD_SPEND_FLASH_COLOR: Color = Color(1.0, 0.25, 0.2)
const GOLD_SPEND_HOLD_SEC: float = 0.65
const BUY_ROW_UNAFFORDABLE_COLOR: Color = Color(0.45, 0.45, 0.5)
const BUY_ROW_OWNED_COLOR: Color = Color(0.55, 0.78, 0.6)
## struktured 2026-08-20: "make the spells in the store green if they're better than what the player has" — saturated, distinct from the soft owned tint; label also carries ▲ so colour-blind mode still reads it
const BUY_ROW_UPGRADE_COLOR: Color = Color(0.35, 0.95, 0.45)
const PURCHASE_TOAST_SEC: float = 1.5
## Description frame. Text starts DESC_TEXT_PAD down; the block is line-height
## plus the theme gap, which already ran past a fixed 120px panel.
const DESC_PANEL_MIN_HEIGHT := 120
const DESC_TEXT_PAD := 16
const DESC_SCREEN_MARGIN := 20

## Shop configuration
var shop_type: ShopType = ShopType.ITEM
var shop_name: String = "Shop"
var shop_inventory: Array[String] = []
var shopkeeper_customization = null  # CharacterCustomization for portrait

## State
var current_mode: ShopMode = ShopMode.MAIN
var selected_item_id: String = ""
var selected_quantity: int = 1
var max_quantity: int = 99
var pending_spell_id: String = ""
var pending_spell_data: Dictionary = {}
var pending_equip_id: String = ""
var pending_equip_data: Dictionary = {}

## UI Components
var background: ColorRect
var gold_label: Label
var _gold_flash_tween: Tween = null
var description_panel: Control
var description_label: Label
var current_menu: Win98Menu = null

## Last item id whose description we painted, so we only refresh the
## description panel when the menu cursor actually moves to a new row.
## Win98Menu emits no cursor-moved signal, so ShopScene polls the menu's
## selected item id each frame and reacts on change (regression: panel was
## frozen on item 0 while navigating the buy/sell list).
var _last_described_item_id: String = ""

## Systems
@onready var game_state = GameState
@onready var equipment_system = EquipmentSystem
@onready var item_system = ItemSystem
@onready var job_system = JobSystem


func _ready() -> void:
	# Make fullscreen overlay
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100  # Render above game world
	# Ensure this processes input
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	_open_main_menu()


func _process(_delta: float) -> void:
	# Win98Menu emits no cursor-moved signal, so poll its selected item id and
	# refresh the description panel when the highlighted buy/sell row changes.
	if current_mode != ShopMode.BUY and current_mode != ShopMode.SELL:
		return
	if not (current_menu and is_instance_valid(current_menu)):
		return
	var item_id: String = current_menu.get_selected_item_id()
	if item_id == _last_described_item_id:
		return
	_last_described_item_id = item_id
	if item_id.is_empty() or item_id == "none":
		return
	_update_description_for_item(item_id)


func setup(type: ShopType, name: String, inventory: Array, keeper_custom = null) -> void:
	"""Configure shop before opening"""
	shop_type = type
	shop_name = name
	shop_inventory.clear()
	for item in inventory:
		shop_inventory.append(item)
	shopkeeper_customization = keeper_custom
	# Tick 250/254: ratchet "Magic as Merchandise" via centralized helper.
	if (type == ShopType.BLACK_MAGIC or type == ShopType.WHITE_MAGIC) \
			and PartyChatSystem:
		PartyChatSystem.fire_event_flag("event_flag_first_magic_shop_visited")


func _setup_ui() -> void:
	"""Create the shop UI layout"""
	# Fullscreen background
	background = ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.85)
	background.size = get_viewport().get_visible_rect().size
	background.position = Vector2.ZERO
	add_child(background)

	# Gold display (top-right)
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.position = Vector2(get_viewport().get_visible_rect().size.x - 200, 20)
	gold_label.size = Vector2(180, 30)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", TextScale.scaled(16))
	gold_label.add_theme_color_override("font_color", GOLD_LABEL_COLOR)
	add_child(gold_label)
	_update_gold_display()

	# Description panel (bottom)
	description_panel = _create_description_panel()
	add_child(description_panel)


func _create_description_panel() -> Control:
	"""Create the description panel at bottom of screen"""
	var panel = Control.new()
	panel.name = "DescriptionPanel"
	var panel_height = DESC_PANEL_MIN_HEIGHT
	panel.position = Vector2(20, get_viewport().get_visible_rect().size.y - panel_height - DESC_SCREEN_MARGIN)
	panel.size = Vector2(get_viewport().get_visible_rect().size.x - 40, panel_height)

	# Background with Win98 style border
	var bg = ColorRect.new()
	bg.name = "DescriptionFill"
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.position = Vector2(4, 4)
	bg.size = Vector2(panel.size.x - 8, panel.size.y - 8)
	panel.add_child(bg)

	# Borders
	var border_color = Color(0.6, 0.6, 0.7)
	var border_dark = Color(0.3, 0.3, 0.4)

	# Top border
	var top = ColorRect.new()
	top.name = "DescriptionBorderTop"
	top.color = border_color
	top.position = Vector2(4, 0)
	top.size = Vector2(panel.size.x - 8, 4)
	panel.add_child(top)

	# Bottom border
	var bottom = ColorRect.new()
	bottom.name = "DescriptionBorderBottom"
	bottom.color = border_dark
	bottom.position = Vector2(4, panel.size.y - 4)
	bottom.size = Vector2(panel.size.x - 8, 4)
	panel.add_child(bottom)

	# Left border
	var left = ColorRect.new()
	left.color = border_color
	left.name = "DescriptionBorderLeft"
	left.position = Vector2(0, 4)
	left.size = Vector2(4, panel.size.y - 8)
	panel.add_child(left)

	# Right border
	var right = ColorRect.new()
	right.name = "DescriptionBorderRight"
	right.color = border_dark
	right.position = Vector2(panel.size.x - 4, 4)
	right.size = Vector2(4, panel.size.y - 8)
	panel.add_child(right)

	# Shopkeeper portrait (left side of panel) — prefer a bespoke PNG at
	# KEEPER_PORTRAIT_PATHS[shop_type]; fall through to procedural if absent.
	var text_x = 16
	var keeper_png_path: String = KEEPER_PORTRAIT_PATHS.get(shop_type, "")
	if keeper_png_path != "" and ResourceLoader.exists(keeper_png_path):
		var keeper_tex: Texture2D = load(keeper_png_path)
		if keeper_tex:
			var texrect = TextureRect.new()
			texrect.texture = keeper_tex
			## expand_mode BEFORE size: while it is still the default, minimum size is the
			## texture's 256x256 and the 64 is clamped straight back up to it.
			texrect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texrect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texrect.custom_minimum_size = Vector2.ZERO
			texrect.position = Vector2(16, 16)
			texrect.size = Vector2(64, 64)
			panel.add_child(texrect)
			text_x = 16 + 64 + 12
	elif shopkeeper_customization:
		var CharacterPortraitScript = load("res://src/ui/CharacterPortrait.gd")
		var portrait = CharacterPortraitScript.new(shopkeeper_customization, "shopkeeper", CharacterPortraitScript.PortraitSize.LARGE)
		portrait.position = Vector2(16, 16)
		panel.add_child(portrait)
		text_x = 16 + 64 + 12  # After portrait with gap

	# Description text
	description_label = Label.new()
	description_label.position = Vector2(text_x, DESC_TEXT_PAD)
	description_label.size = Vector2(panel.size.x - text_x - DESC_TEXT_PAD, panel.size.y - DESC_TEXT_PAD * 2)
	description_label.add_theme_font_size_override("font_size", TextScale.scaled(12))
	description_label.add_theme_color_override("font_color", Color.WHITE)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(description_label)

	return panel


func _update_gold_display() -> void:
	"""Update the gold label"""
	if gold_label and game_state:
		gold_label.text = "%d G" % game_state.get_gold()


func _open_main_menu() -> void:
	"""Open the main shop menu (Buy/Sell/Exit)"""
	current_mode = ShopMode.MAIN
	_close_current_menu()

	var items = [
		{"id": "buy", "label": "Buy"},
	]
	# Magic shops don't have sell (can't un-learn a spell)
	if not _is_magic_shop():
		items.append({"id": "sell", "label": "Sell"})
	items.append({"id": "exit", "label": "Exit"})

	if description_label:
		description_label.remove_theme_constant_override("line_spacing")
	_set_description_panel_height(DESC_PANEL_MIN_HEIGHT)
	_show_menu("Shop", items, Vector2(100, 100))
	description_label.text = "Welcome to %s!\nWhat would you like to do?" % shop_name


## Buy-menu suffix flagging the gold shortfall for an item. Empty when the
## player can already afford it, so affordable rows stay unadorned and only the
## out-of-reach items call out exactly how much more gold they need.
func _affordability_suffix(cost: int, gold: int) -> String:
	if cost > gold:
		return " (need %dg)" % (cost - gold)
	return ""


func _open_buy_menu() -> void:
	"""Open the buy menu with shop inventory"""
	current_mode = ShopMode.BUY
	_close_current_menu()

	var items: Array = []

	for item_id in shop_inventory:
		var item_data = _get_item_data(item_id)
		if item_data:
			var cost = item_data.get("cost", 0)
			var owned = _get_owned_count(item_id)
			## Tick 187: fallback through ItemNameResolver instead of
			## sentinel "???". Surfaces a meaningful name for items
			## where the shop's _get_item_data found the entry but it
			## lacks a "name" field (Scriptweaver custom items / save-
			## format drift / authoring error). Player sees "Iron
			## Sword" instead of "???" for unknown-name items.
			var label = "%s - %dG" % [item_data.get("name", ItemNameResolver.resolve(item_id)), cost]
			if _is_magic_shop() and owned > 0:
				label += " [%d learned]" % owned
			elif owned > 0:
				label += " (%d)" % owned
			# Equipped gear lives on combatants, not inventory — owned-count misses it and players re-buy what they're wearing
			var wearers := _equipped_by(item_id)
			if wearers != "":
				label += " [on %s]" % wearers

			# struktured 2026-08-15: the "(need Xg)" suffix truncated row labels.
			# Shortfall lives in the description panel now; the ROW communicates by
			# colour - grey = cannot afford, green tint = already have (magic learned /
			# gear someone is wearing). Rows stay SELECTABLE (unlike disabled) so they can be inspected.
			var row := {
				"id": item_id,
				"label": label,
				"data": item_data,
				"icon_id": item_id,
			}
			var already_owned: bool = (_is_magic_shop() and owned > 0) or wearers != ""
			if already_owned:
				row["text_color"] = BUY_ROW_OWNED_COLOR
			elif _is_magic_shop() and _is_spell_upgrade(item_data):
				row["label"] = "▲ " + row["label"]
				row["text_color"] = BUY_ROW_UPGRADE_COLOR
			elif game_state and int(cost) > game_state.get_gold():
				row["text_color"] = BUY_ROW_UNAFFORDABLE_COLOR
			items.append(row)

	if items.is_empty():
		items.append({"id": "none", "label": "(No items available)", "disabled": true})

	_present_item_list("Buy", items, shop_inventory)
	# Sync the poll tracker to the menu's actual first row so the description
	# stays correct as the cursor moves (and isn't double-painted on open).
	_last_described_item_id = current_menu.get_selected_item_id()
	_update_description_for_item(shop_inventory[0] if shop_inventory.size() > 0 else "")


func _open_sell_menu() -> void:
	"""Open the sell menu with party inventory"""
	current_mode = ShopMode.SELL
	_close_current_menu()

	var items: Array = []
	var sellable_items = _get_sellable_inventory()

	for item_entry in sellable_items:
		var item_id = item_entry["id"]
		var quantity = item_entry["quantity"]
		var item_data = _get_item_data(item_id)

		if item_data:
			var cost = item_data.get("cost", 0)
			var sell_price = int(cost * 0.5)  # 50% sell price
			## Tick 187: same ItemNameResolver fallback as the Buy
			## path. Avoids "???" sentinel for missing-name items.
			var label = "%s - %dG (x%d)" % [item_data.get("name", ItemNameResolver.resolve(item_id)), sell_price, quantity]

			items.append({
				"id": item_id,
				"label": label,
				"data": item_data,
				"icon_id": item_id,
			})

	if items.is_empty():
		items.append({"id": "none", "label": "(No items to sell)", "disabled": true})

	var sell_ids: Array = []
	for entry in sellable_items:
		sell_ids.append(entry.get("id", ""))
	_present_item_list("Sell", items, sell_ids)
	# Sync the poll tracker to the menu's actual first row so the description
	# stays correct as the cursor moves (and isn't double-painted on open).
	_last_described_item_id = current_menu.get_selected_item_id()
	if sellable_items.size() > 0:
		_update_description_for_item(sellable_items[0]["id"])


## Height of the description block the way the Label lays it out: each line is
## get_line_height, and the theme line_spacing sits between lines.
func _description_block_height() -> float:
	if description_label == null:
		return 0.0
	var lines := description_label.get_line_count()
	if lines <= 0:
		return 0.0
	var line_h := float(description_label.get_line_height())
	var gap := float(description_label.get_theme_constant("line_spacing"))
	return line_h * float(lines) + gap * float(lines - 1)


## Show the shelf, growing the description frame to the tallest row. If that
## frame would cover the list, pull line spacing in until the list sits above it.
func _present_item_list(title: String, items: Array, item_ids: Array) -> void:
	if description_label:
		description_label.remove_theme_constant_override("line_spacing")
	_fit_description_panel(item_ids)
	for _attempt in 8:
		_show_menu(title, items, Vector2(100, 100))
		if current_menu == null or description_panel == null:
			return
		if current_menu.position.y + current_menu.size.y <= description_panel.position.y:
			return
		var gap_now := int(description_label.get_theme_constant("line_spacing"))
		if gap_now - 1 < _min_description_line_gap():
			return
		description_label.add_theme_constant_override("line_spacing", gap_now - 1)
		_fit_description_panel(item_ids)
	_show_menu(title, items, Vector2(100, 100))


func _min_description_line_gap() -> int:
	if description_label == null:
		return 0
	var font := description_label.get_theme_font("font")
	if font == null:
		return 0
	var drawn := font.get_string_size("Ag", HORIZONTAL_ALIGNMENT_LEFT, -1, description_label.get_theme_font_size("font_size")).y
	return int(floor(drawn - float(description_label.get_line_height())))


## Grow the frame so the tallest shelf description, including the gold shortfall
## and a blacksmith comparison, ends inside it. The buy list reads this position.
func _fit_description_panel(item_ids: Array) -> void:
	if description_label == null or description_panel == null:
		return
	var tallest := 0.0
	for raw_id in item_ids:
		var item_id := str(raw_id)
		if item_id.is_empty() or _get_item_data(item_id).is_empty():
			continue
		_update_description_for_item(item_id)
		tallest = maxf(tallest, _description_block_height())
	var needed := int(ceili(float(DESC_TEXT_PAD) + tallest + float(DESC_TEXT_PAD)))
	_set_description_panel_height(maxi(DESC_PANEL_MIN_HEIGHT, needed))


func _set_description_panel_height(panel_height: int) -> void:
	if description_panel == null:
		return
	var vp_h := get_viewport().get_visible_rect().size.y
	description_panel.size.y = panel_height
	description_panel.position.y = vp_h - float(panel_height) - float(DESC_SCREEN_MARGIN)
	var fill: ColorRect = description_panel.get_node_or_null("DescriptionFill")
	if fill:
		fill.size.y = panel_height - 8
	var border_bottom: ColorRect = description_panel.get_node_or_null("DescriptionBorderBottom")
	if border_bottom:
		border_bottom.position.y = panel_height - 4
	for side_name in ["DescriptionBorderLeft", "DescriptionBorderRight"]:
		var side: ColorRect = description_panel.get_node_or_null(side_name)
		if side:
			side.size.y = panel_height - 8
	if description_label:
		description_label.size.y = panel_height - DESC_TEXT_PAD * 2


## Pixels of the viewport bottom the shelf must leave clear so it stops above the description panel.
func _menu_bottom_clearance() -> int:
	if description_panel == null or not is_instance_valid(description_panel):
		return 0
	var vp_h := get_viewport().get_visible_rect().size.y
	return int(ceili(vp_h - description_panel.position.y + 8.0))


func _show_menu(title: String, items: Array, pos: Vector2) -> void:
	"""Show a Win98Menu"""
	_close_current_menu()

	current_menu = Win98Menu.new()
	current_menu.battle_mode = false  # No AP display in shops
	current_menu.is_root_menu = true
	current_menu.expand_left = true
	current_menu.expand_up = false
	current_menu.bottom_clearance = _menu_bottom_clearance()
	add_child(current_menu)
	current_menu.setup(title, items, pos, "fighter")

	current_menu.item_selected.connect(_on_menu_item_selected)
	current_menu.menu_closed.connect(_on_menu_closed)

	# Ensure menu has focus for input
	current_menu.grab_focus()


func _close_current_menu() -> void:
	"""Close the current menu"""
	if current_menu and is_instance_valid(current_menu):
		# Disconnect signals before freeing to prevent callbacks on freed objects
		if current_menu.item_selected.is_connected(_on_menu_item_selected):
			current_menu.item_selected.disconnect(_on_menu_item_selected)
		if current_menu.menu_closed.is_connected(_on_menu_closed):
			current_menu.menu_closed.disconnect(_on_menu_closed)
		current_menu.queue_free()
		current_menu = null


func _on_menu_item_selected(item_id: String, item_data: Variant) -> void:
	"""Handle menu selection"""
	match current_mode:
		ShopMode.MAIN:
			match item_id:
				"buy":
					_open_buy_menu()
				"sell":
					_open_sell_menu()
				"exit":
					_close_shop()

		ShopMode.BUY:
			if item_id != "none":
				if _is_magic_shop():
					var spell_data = item_data if item_data is Dictionary else _get_item_data(item_id)
					_open_character_select(item_id, spell_data)
				else:
					_attempt_purchase(item_id, item_data)

		ShopMode.SELL:
			if item_id != "none":
				_attempt_sell(item_id, item_data)

		ShopMode.CHAR_SELECT:
			if item_id != "none":
				_attempt_magic_purchase(item_id)

		ShopMode.EQUIP_SELECT:
			if item_id != "none":
				_attempt_equip(item_id)


func _attempt_purchase(item_id: String, item_data: Dictionary) -> void:
	"""Attempt to buy an item"""
	var cost = item_data.get("cost", 0)
	var current_gold = game_state.get_gold()

	if current_gold < cost:
		# Insufficient funds
		SoundManager.play_ui("menu_error")
		_flash_gold_label()
		description_label.text = "Insufficient gold!\nYou need %d G but only have %d G." % [cost, current_gold]
		return

	# Purchase successful — atomic: if the item can't actually be received
	# (no party member to hold it, save corruption mid-shop, etc.), refund
	# the gold and surface the failure. Pre-fix, _add_item_to_inventory
	# silently no-op'd when player_party was empty — the gold was already
	# spent and the UI showed "Purchased X!" but no item appeared.
	if game_state.spend_gold(cost):
		var added: bool = _add_item_to_inventory(item_id)
		if not added:
			_credit_exact_gold(cost)  # Refund the coins spend_gold took. add_gold would scale them by the drop-rate dial.
			SoundManager.play_ui("menu_error")
			_update_gold_display()
			description_label.text = "No party to receive item — gold refunded."
			return
		# struktured msg 2775: "more obvious that you purchase something...
		# a nice little ka-ching... more visual indication, not just a
		# closing of a menu." Three beats fire together: the dedicated
		# purchase sound, a gold-counter flash, and a floating receipt.
		SoundManager.play_ui("purchase_complete")
		_flash_gold_spend(cost)
		_show_purchase_toast(str(item_data.get("name", "item")), cost)
		# Tick 257: emit only after the gold spend AND the item handoff
		# both succeeded — refund path above returns early so we don't
		# spuriously fire on failed transactions.
		item_purchased.emit(item_id, cost)

		description_label.text = "Purchased %s for %d G!" % [item_data.get("name", "item"), cost]

		# struktured msg 2775: gear you just bought is gear you want on now.
		# Returns false when there's no live party to equip onto (test envs).
		if shop_type == ShopType.BLACKSMITH and _offer_equip(item_id, item_data):
			return

		# Refresh buy menu to show updated owned count
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(self):
			return
		_open_buy_menu()


## Sticker gold. Drops, quest rewards and chests go through add_gold, which multiplies by the drop-rate dial. A shop price is the number already on screen.
func _credit_exact_gold(amount: int) -> void:
	if amount <= 0 or game_state == null or not ("party_gold" in game_state):
		return
	game_state.party_gold += amount


func _attempt_sell(item_id: String, item_data: Dictionary) -> void:
	"""Attempt to sell an item"""
	# Defense-in-depth: even if a META/0-cost row leaks into the menu, refuse the sale (permanent quest-item loss)
	if int(item_data.get("category", -1)) == 4 or int(item_data.get("cost", 0)) <= 0:
		SoundManager.play_ui("menu_error")
		description_label.text = "That item can't be sold."
		return
	var cost = item_data.get("cost", 0)
	var sell_price = int(cost * 0.5)

	# Check if we have the item
	var removed: bool = _remove_from_equipment_pool(item_id) if shop_type == ShopType.BLACKSMITH else _remove_item_from_inventory(item_id)
	if not removed:
		SoundManager.play_ui("menu_error")
		description_label.text = "You don't have that item!"
		return

	# Sell successful. The line on screen is the sticker; add_gold would pay that times gold_multiplier.
	_credit_exact_gold(sell_price)
	SoundManager.play_ui("menu_select")
	_update_gold_display()

	description_label.text = "Sold %s for %d G!" % [item_data.get("name", "item"), sell_price]

	# Refresh sell menu
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(self):
		return
	_open_sell_menu()


func _get_item_data(item_id: String) -> Dictionary:
	"""Get item data from appropriate system"""
	match shop_type:
		ShopType.ITEM:
			return item_system.items.get(item_id, {})
		ShopType.BLACK_MAGIC, ShopType.WHITE_MAGIC:
			return job_system.get_ability(item_id)
		ShopType.BLACKSMITH:
			var weapon = equipment_system.weapons.get(item_id, {})
			if not weapon.is_empty():
				return weapon
			var armor = equipment_system.armors.get(item_id, {})
			if not armor.is_empty():
				return armor
			## The shelf stocks no accessories, but the pool it buys back from holds them.
			return equipment_system.accessories.get(item_id, {})
	return {}


## A spell is an UPGRADE when its data tier outranks the best tier anyone in the party knows in that family (nothing known → tier 1 is an upgrade). Data-driven: family/tier fields, never a name-suffix guess.
func _is_spell_upgrade(spell_data: Dictionary) -> bool:
	if not spell_data.has("family") or not spell_data.has("tier"):
		return false
	return int(spell_data["tier"]) > _best_known_tier(str(spell_data["family"]))


## Highest tier anyone already has in this family. "Already has it" is _member_knows: the snapshot learned list or, when that slot is reachable, live knows_ability.
func _best_known_tier(family: String) -> int:
	var best := 0
	if game_state == null or job_system == null or game_state.player_party.is_empty():
		return best
	var rungs: Array = []
	for aid in job_system.abilities.keys():
		var data: Dictionary = job_system.get_ability(str(aid))
		if str(data.get("family", "")) != family:
			continue
		rungs.append({"id": str(aid), "tier": int(data.get("tier", 0))})
	for i in range(game_state.player_party.size()):
		var learned: Array = _snapshot_learned(game_state.player_party[i])
		for rung in rungs:
			var tier: int = int(rung["tier"])
			if tier <= best:
				continue
			if _member_knows(i, str(rung["id"]), learned):
				best = tier
	return best


## Live inventories when a party is in the tree; otherwise the snapshot dicts. Menu-open and pre-save are the only snapshot writers, and walking into a shop does not save, so a potion used in the field menu or picked up from a chest in this area is on the Combatant only.
func _inventory_sources() -> Array:
	var live: Array = _resolve_live_party()
	var sources: Array = []
	var saw_live := false
	for member in live:
		if member == null or not is_instance_valid(member) or not ("inventory" in member):
			continue
		var inv = member.inventory
		if inv is Dictionary:
			sources.append(inv)
			saw_live = true
	if saw_live or game_state == null:
		return sources
	for member_data in game_state.player_party:
		if member_data is Dictionary:
			var snap: Variant = member_data.get("inventory", {})
			if snap is Dictionary:
				sources.append(snap)
	return sources


func _get_owned_count(item_id: String) -> int:
	"""Get how many of this item the party owns"""
	if shop_type == ShopType.ITEM:
		var sources: Array = _inventory_sources()
		if sources.is_empty():
			return 0
		return int(sources[0].get(item_id, 0))
	elif _is_magic_shop():
		# Members who already have this spell — same rule as character select, not the snapshot list alone.
		if game_state == null:
			return 0
		var count := 0
		for i in range(game_state.player_party.size()):
			var learned: Array = _snapshot_learned(game_state.player_party[i])
			if _member_knows(i, item_id, learned):
				count += 1
		return count
	elif shop_type == ShopType.BLACKSMITH:
		# Spares live in the pool. A worn piece is not one of them; the row names that person separately.
		return _spare_copies_in_pool(item_id)
	return 0


## Unequipped copies across every pool key. A misfiled spare still counts, matching the sell list.
func _spare_copies_in_pool(item_id: String) -> int:
	var pool: Dictionary = _live_equipment_pool()
	var count := 0
	for key in pool:
		var slot: Variant = pool[key]
		if slot is Array:
			count += (slot as Array).count(item_id)
	return count


func _get_sellable_inventory() -> Array:
	"""Get all sellable items from party"""
	var sellable: Array = []
	var counted: Dictionary = {}

	## Gear never enters a party inventory — purchases, chests and drops all land in the pool — so the blacksmith listed nothing to sell.
	if shop_type == ShopType.BLACKSMITH:
		var pool: Dictionary = _live_equipment_pool()
		for key in pool:
			if pool[key] is Array:
				for item_id in pool[key]:
					counted[str(item_id)] = counted.get(str(item_id), 0) + 1
	else:
		# Live stock when the party is in the tree. The snapshot still lists a potion the field menu already used, and it misses a chest drop until the next menu open.
		for inventory in _inventory_sources():
			for item_id in inventory:
				var quantity = int(inventory[item_id])
				if quantity > 0:
					counted[item_id] = counted.get(item_id, 0) + quantity

	# Convert to array, excluding key/quest items and worthless junk.
	for item_id in counted:
		var item_data = _get_item_data(item_id)
		if item_data.is_empty():
			continue
		# category 4 = ItemCategory.META (returned_sword, chapter_three_pages…) — selling these was permanent quest-item loss for 0 gold
		if int(item_data.get("category", -1)) == 4:
			continue
		# 0-cost items sell for 0 gold — no reason to offer them (also the key-item signature)
		if int(item_data.get("cost", 0)) <= 0:
			continue
		sellable.append({
			"id": item_id,
			"quantity": counted[item_id]
		})

	return sellable


## Snapshot learned list for one party slot, copied into an untyped Array. Empty when the slot isn't a dict or the field isn't an array.
func _snapshot_learned(member_data) -> Array:
	var out: Array = []
	if member_data is Dictionary:
		var raw = member_data.get("learned_abilities", [])
		if raw is Array:
			for aid in raw:
				out.append(aid)
	return out


## One predicate for "already has it": the LIVE Combatant's knows_ability (kit ∪ learned ∪ purchased ∪ level ∪ free move) when reachable, else the snapshot's learned list. Character select, the purchase guard, magic owned-counts, and upgrade tiers all use it.
func _member_knows(char_index: int, spell_id: String, snapshot_learned: Array) -> bool:
	if spell_id in snapshot_learned:
		return true
	var live: Array = _resolve_live_party()
	if char_index < live.size() and live[char_index] != null and is_instance_valid(live[char_index]) \
			and live[char_index].has_method("knows_ability"):
		return bool(live[char_index].knows_ability(spell_id))
	return false


func _has_live_equipment_pool() -> bool:
	if not is_inside_tree():
		return false
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	return gl != null and "equipment_pool" in gl


## GameLoop.equipment_pool is the live store of unequipped gear; an empty dict when there is none.
func _live_equipment_pool() -> Dictionary:
	if not _has_live_equipment_pool():
		return {}
	return get_tree().root.get_node("GameLoop").equipment_pool


## weapons / armors / accessories by catalog lookup, "" for an id the catalog does not know.
func _equipment_pool_key(item_id: String) -> String:
	var eq = get_node_or_null("/root/EquipmentSystem")
	if eq == null:
		return ""
	if eq.has_method("get_weapon") and not eq.get_weapon(item_id).is_empty():
		return "weapons"
	if eq.has_method("get_armor") and not eq.get_armor(item_id).is_empty():
		return "armors"
	if eq.has_method("get_accessory") and not eq.get_accessory(item_id).is_empty():
		return "accessories"
	return ""


## Catalog slot first, then any slot: an old save can hold a piece the pre-fix chest heuristic filed under the wrong key, and the sell list counts every key.
func _remove_from_equipment_pool(item_id: String) -> bool:
	var pool: Dictionary = _live_equipment_pool()
	var keys: Array = [_equipment_pool_key(item_id)]
	keys.append_array(pool.keys())
	for key in keys:
		if pool.get(key, null) is Array and (pool[key] as Array).has(item_id):
			(pool[key] as Array).erase(item_id)
			return true
	return false


## Tick 314: resolve the LIVE party (Array[Combatant]) so shop writes
## land on the source-of-truth inventory. Pre-fix shop only mutated
## game_state.player_party (the serialized snapshot dict). On the next
## menu open / pre-save sync, _sync_party_to_game_state copied LIVE
## inventory back over the snapshot, OVERWRITING every shop change.
## Net effect: purchases vanished (gold spent, item gone — refund flow
## couldn't catch this because the dict update technically "succeeded");
## sales were a free-money exploit (gold credited, item kept).
##
## Falls back to null in test envs without a GameLoop in the tree —
## callers handle null by writing only to the snapshot (legacy behavior),
## which keeps the existing unit tests passing.
func _resolve_live_party() -> Array:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return []
	var gl: Node = tree.root.get_node_or_null("GameLoop")
	if gl == null or not ("party" in gl):
		return []
	return gl.party


func _add_item_to_inventory(item_id: String) -> bool:
	"""Add item to party inventory. Returns true if a recipient was found
	and the item was added; false if no party member exists to hold it
	(empty player_party). _attempt_purchase relies on this return value to
	refund the spent gold when no recipient is reachable.

	Tick 314: writes to BOTH the live Combatant.inventory (source of
	truth) AND the snapshot dict (still consumed by other shop code +
	the next _sync_party_to_game_state's seed value). Without the live
	write, the snapshot mutation gets overwritten on the next sync."""
	if shop_type == ShopType.ITEM:
		# Add to first party member's inventory.
		if game_state.player_party.size() == 0:
			return false
		var party_leader = game_state.player_party[0]
		if not party_leader.has("inventory"):
			party_leader["inventory"] = {}
		var inventory = party_leader["inventory"]
		inventory[item_id] = inventory.get(item_id, 0) + 1
		# Tick 314: also write to the LIVE Combatant so the next sync
		# doesn't clobber the purchase.
		var live_party: Array = _resolve_live_party()
		if live_party.size() > 0 and live_party[0] and live_party[0].has_method("add_item"):
			live_party[0].add_item(item_id, 1)
		return true
	elif shop_type == ShopType.BLACKSMITH:
		# Equipment goes to GameLoop.equipment_pool below. The old
		# player_party[0]["equipment_inventory"] write had 0 readers.
		if game_state.player_party.size() == 0:
			return false
		# Tick 314: equipment_pool lives on GameLoop, not the snapshot
		# dict (per the BattleManager._route_drop_to_equipment_pool
		# pattern at line ~4979). Without this the same overwrite class
		# applies to blacksmith purchases.
		var pool: Dictionary = _live_equipment_pool()
		var key: String = _equipment_pool_key(item_id)
		if key != "" and _has_live_equipment_pool():
			if not pool.has(key):
				pool[key] = []
			pool[key].append(item_id)
		return true
	# Magic purchases handled separately in _attempt_magic_purchase. Any
	# other shop_type values reaching here are an authoring error — refuse
	# so the caller refunds the gold rather than silently accepting a
	# half-applied transaction.
	return false


## Live stock is authoritative when a party is in the tree. Selling the snapshot paid gold for a potion the field menu had already used (the live remove's false was ignored) and refused a drop that existed only on the Combatant.
func _remove_item_from_inventory(item_id: String) -> bool:
	var live_party: Array = _resolve_live_party()
	var live_authoritative := false
	for i in range(live_party.size()):
		var member = live_party[i]
		if member == null or not is_instance_valid(member) or not member.has_method("remove_item"):
			continue
		live_authoritative = true
		if not member.remove_item(item_id, 1):
			continue
		_decrement_snapshot_inventory(i, item_id)
		return true
	if live_authoritative or game_state == null:
		return false
	for i in range(game_state.player_party.size()):
		if _decrement_snapshot_inventory(i, item_id):
			return true
	return false


func _decrement_snapshot_inventory(index: int, item_id: String) -> bool:
	if game_state == null or index < 0 or index >= game_state.player_party.size():
		return false
	var member_data: Dictionary = game_state.player_party[index]
	if not member_data.has("inventory") or not (member_data["inventory"] is Dictionary):
		return false
	var inventory: Dictionary = member_data["inventory"]
	if not inventory.has(item_id) or int(inventory[item_id]) <= 0:
		return false
	inventory[item_id] = int(inventory[item_id]) - 1
	if inventory[item_id] == 0:
		inventory.erase(item_id)
	return true


func _update_description_for_item(item_id: String) -> void:
	"""Update description panel for selected item"""
	if item_id.is_empty():
		return

	var item_data = _get_item_data(item_id)
	if item_data.is_empty():
		return

	var desc = ""
	desc += "%s\n" % item_data.get("name", "???")
	desc += "%s\n\n" % item_data.get("description", "No description")

	# Row labels no longer carry the shortfall (it truncated them) - it lives here.
	if game_state and int(item_data.get("cost", 0)) > game_state.get_gold():
		desc += "Not enough gold%s.\n\n" % _affordability_suffix(int(item_data.get("cost", 0)), game_state.get_gold())

	# Show stats + comparison for equipment (blacksmith)
	if shop_type == ShopType.BLACKSMITH:
		var stat_mods = item_data.get("stat_mods", {})
		if not stat_mods.is_empty():
			var comparison := _compare_equipment(item_id, item_data)
			if comparison.is_empty():
				desc += "Stats:\n"
				for stat in stat_mods:
					var value = stat_mods[stat]
					if value != 0:
						# Tick 211: shared StatNames preserves HP/MP acronyms.
						desc += "  %s: %+d\n" % [StatNames.display_name(stat), value]
			else:
				desc += "Stats (vs equipped):\n"
				# Union, not just the new piece: a robe that omits Max HP still drops Iron Armor's +250.
				var shown: Dictionary = {}
				for stat in stat_mods:
					shown[str(stat)] = true
				for stat in comparison:
					shown[str(stat)] = true
				for stat in shown:
					var value: int = int(stat_mods.get(stat, 0))
					var delta: int = int(comparison.get(stat, 0))
					if value == 0 and delta == 0:
						continue
					if delta > 0:
						desc += "  %s: %+d  (+%d)\n" % [StatNames.display_name(stat), value, delta]
					elif delta < 0:
						desc += "  %s: %+d  (%d)\n" % [StatNames.display_name(stat), value, delta]
					elif value != 0:
						desc += "  %s: %+d  (=)\n" % [StatNames.display_name(stat), value]

	# Show MP cost for magic
	if _is_magic_shop():
		var mp_cost = item_data.get("mp_cost", 0)
		desc += "MP Cost: %d\n" % mp_cost

	# Show cost
	var cost = item_data.get("cost", 0)
	if current_mode == ShopMode.BUY:
		desc += "\nCost: %d G" % cost
	elif current_mode == ShopMode.SELL:
		desc += "\nSell: %d G" % int(cost * 0.5)

	description_label.text = desc


## Live equipped slots when a party is in the tree; otherwise the save snapshot. Menu-open and pre-save are the only snapshot writers, and walking into a shop does not save.
func _party_gear_rows() -> Array:
	var live: Array = _resolve_live_party()
	var rows: Array = []
	var saw_live := false
	for member in live:
		if member == null or not is_instance_valid(member):
			continue
		if not ("equipped_weapon" in member) and not ("equipped_armor" in member) and not ("equipped_accessory" in member):
			continue
		var who := "?"
		if "combatant_name" in member and str(member.combatant_name) != "":
			who = str(member.combatant_name)
		rows.append({
			"name": who,
			"equipped_weapon": str(member.equipped_weapon) if "equipped_weapon" in member else "",
			"equipped_armor": str(member.equipped_armor) if "equipped_armor" in member else "",
			"equipped_accessory": str(member.equipped_accessory) if "equipped_accessory" in member else "",
		})
		saw_live = true
	if saw_live or game_state == null:
		return rows
	for member in game_state.player_party:
		if typeof(member) != TYPE_DICTIONARY:
			continue
		rows.append(member)
	return rows


## Names the party members currently wearing item_id ("" if nobody).
func _equipped_by(item_id: String) -> String:
	var wearers: PackedStringArray = []
	for member in _party_gear_rows():
		if typeof(member) != TYPE_DICTIONARY:
			continue
		if str(member.get("equipped_weapon", "")) == item_id \
				or str(member.get("equipped_armor", "")) == item_id \
				or str(member.get("equipped_accessory", "")) == item_id:
			wearers.append(str(member.get("name", "?")))
	return ", ".join(wearers)


func _compare_equipment(item_id: String, item_data: Dictionary) -> Dictionary:
	"""Compare item_data's stat_mods to the party leader's currently equipped
	gear in the same slot (weapon vs weapon, armor vs armor). Returns a dict
	of stat deltas: positive = upgrade, negative = downgrade. Empty if no
	comparison possible."""
	var rows := _party_gear_rows()
	if rows.is_empty() or typeof(rows[0]) != TYPE_DICTIONARY:
		return {}
	var leader: Dictionary = rows[0]
	var new_mods: Dictionary = item_data.get("stat_mods", {})

	# Determine which slot this equipment goes in and what's currently equipped
	var current_id := ""
	if equipment_system.weapons.has(item_id):
		current_id = leader.get("equipped_weapon", "")
	elif equipment_system.armors.has(item_id):
		current_id = leader.get("equipped_armor", "")
	elif equipment_system.accessories.has(item_id):
		current_id = leader.get("equipped_accessory", "")
	else:
		return {}

	# Get current equipment stat mods
	var current_mods: Dictionary = {}
	if current_id != "":
		var current_data: Dictionary = {}
		if equipment_system.weapons.has(current_id):
			current_data = equipment_system.weapons[current_id]
		elif equipment_system.armors.has(current_id):
			current_data = equipment_system.armors[current_id]
		elif equipment_system.accessories.has(current_id):
			current_data = equipment_system.accessories[current_id]
		current_mods = current_data.get("stat_mods", {})

	# Both sides. A stat only the worn piece has is still a change (Iron Armor's HP, its speed penalty).
	var stats: Dictionary = {}
	for stat in new_mods:
		stats[str(stat)] = true
	for stat in current_mods:
		stats[str(stat)] = true
	var delta: Dictionary = {}
	for stat in stats:
		delta[stat] = int(new_mods.get(stat, 0)) - int(current_mods.get(stat, 0))
	return delta


func _flash_gold_label() -> void:
	"""Flash the gold label red to indicate error"""
	if not is_instance_valid(gold_label):
		return
	var original_color = gold_label.get_theme_color("font_color")
	gold_label.add_theme_color_override("font_color", Color.RED)
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self) or not is_instance_valid(gold_label):
		return
	gold_label.add_theme_color_override("font_color", original_color)


## Spend flash (struktured 2026-08-15): on any purchase the counter turns red
## showing the DELTA ("-1000 G"), pulses, holds long enough to read, then
## settles to the new total in the normal gold colour. Kill-prior so rapid
## repeat-buys restart the flash instead of fighting a stale settle.
func _flash_gold_spend(cost: int) -> void:
	if not is_instance_valid(gold_label):
		return
	if _gold_flash_tween and _gold_flash_tween.is_valid():
		_gold_flash_tween.kill()
	gold_label.text = _gold_spend_flash_text(cost)
	gold_label.add_theme_color_override("font_color", GOLD_SPEND_FLASH_COLOR)
	# Pivot at the label's own centre so the pulse doesn't drift the text.
	gold_label.pivot_offset = gold_label.size * 0.5
	gold_label.scale = Vector2.ONE
	_gold_flash_tween = create_tween()
	_gold_flash_tween.tween_property(gold_label, "scale", Vector2(1.18, 1.18), GOLD_FLASH_SUCCESS_SEC * 0.4)
	_gold_flash_tween.tween_property(gold_label, "scale", Vector2.ONE, GOLD_FLASH_SUCCESS_SEC * 0.6)
	_gold_flash_tween.tween_interval(GOLD_SPEND_HOLD_SEC)
	_gold_flash_tween.tween_callback(_settle_gold_label)


## Pure so the delta format is unit-testable.
func _gold_spend_flash_text(cost: int) -> String:
	return "-%d G" % cost


func _settle_gold_label() -> void:
	if not is_instance_valid(gold_label):
		return
	gold_label.add_theme_color_override("font_color", GOLD_LABEL_COLOR)
	gold_label.scale = Vector2.ONE
	_update_gold_display()


## Floating purchase receipt — item name + gold delta, rising and fading
## just under the gold counter so the eye connects the two. Purely
## presentational: no input capture (MOUSE_FILTER_IGNORE), self-frees, and
## never blocks the menu, so rapid repeat-buys just stack their own toasts.
func _show_purchase_toast(item_name: String, cost: int) -> void:
	if not is_instance_valid(gold_label):
		return
	var toast := Label.new()
	toast.name = "PurchaseToast"
	toast.text = "%s  −%d G" % [item_name, cost]
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toast.add_theme_font_size_override("font_size", TextScale.scaled(13))
	toast.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	toast.add_theme_constant_override("shadow_offset_x", 1)
	toast.add_theme_constant_override("shadow_offset_y", 1)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.position = gold_label.position + Vector2(0, gold_label.size.y + 2)
	toast.size = gold_label.size
	add_child(toast)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(toast, "position:y", toast.position.y + 22.0, PURCHASE_TOAST_SEC)
	tw.tween_property(toast, "modulate:a", 0.0, PURCHASE_TOAST_SEC).set_delay(PURCHASE_TOAST_SEC * 0.45)
	tw.chain().tween_callback(func():
		if is_instance_valid(toast):
			toast.queue_free())


func _is_magic_shop() -> bool:
	"""Check if this is a magic shop"""
	return shop_type in [ShopType.BLACK_MAGIC, ShopType.WHITE_MAGIC]


func _get_eligible_jobs_for_school(school: String) -> Array:
	"""Get job IDs that can learn spells from a magic school"""
	match school:
		"black": return ["mage"]
		"white": return ["cleric"]
	return []


## Primary or secondary job. Live Combatant wins when that slot is in the tree; otherwise snapshot job + secondary_job_id.
func _member_can_learn_school(char_index: int, snapshot: Dictionary, eligible_jobs: Array) -> bool:
	for job_id in _member_job_ids(char_index, snapshot):
		if job_id in eligible_jobs:
			return true
	return false


func _member_job_ids(char_index: int, snapshot: Dictionary) -> Array:
	var live: Array = _resolve_live_party()
	if char_index < live.size() and live[char_index] != null and is_instance_valid(live[char_index]):
		return _job_ids_on_live(live[char_index])
	return _job_ids_on_snapshot(snapshot)


func _job_ids_on_live(member) -> Array:
	var ids: Array = []
	if "job" in member:
		_append_job_id(ids, _job_id_of(member.job))
	if "secondary_job_id" in member:
		_append_job_id(ids, _job_id_of(member.secondary_job_id))
	if "secondary_job" in member:
		_append_job_id(ids, _job_id_of(member.secondary_job))
	return ids


func _job_ids_on_snapshot(snapshot: Dictionary) -> Array:
	var ids: Array = []
	_append_job_id(ids, _job_id_of(snapshot.get("job", "")))
	_append_job_id(ids, _job_id_of(snapshot.get("secondary_job_id", "")))
	return ids


func _append_job_id(ids: Array, job_id: String) -> void:
	if job_id != "" and not ids.has(job_id):
		ids.append(job_id)


func _job_id_of(job_field) -> String:
	if job_field is Dictionary:
		return str(job_field.get("id", ""))
	if job_field is String:
		return job_field
	return ""


func _open_character_select(spell_id: String, spell_data: Dictionary) -> void:
	"""Open character selection for magic spell purchase"""
	current_mode = ShopMode.CHAR_SELECT
	pending_spell_id = spell_id
	pending_spell_data = spell_data
	_close_current_menu()

	var school = spell_data.get("magic_school", "")
	var eligible_jobs = _get_eligible_jobs_for_school(school)

	var items: Array = []
	for i in range(game_state.player_party.size()):
		var member = game_state.player_party[i]
		var member_name = member.get("name", "???")
		var learned = member.get("learned_abilities", [])

		# Primary or secondary, live Combatant first — same reach as _member_knows.
		if not _member_can_learn_school(i, member, eligible_jobs):
			continue

		# Check if already knows the spell — provenance-blind (struktured 2026-09-06: the Mage bought Ignis, which is in his starting KIT, because this only read the snapshot's learned list).
		if _member_knows(i, spell_id, learned):
			items.append({
				"id": str(i),
				"label": "%s - Already known" % member_name,
				"disabled": true
			})
		else:
			items.append({
				"id": str(i),
				"label": member_name
			})

	if items.is_empty():
		items.append({"id": "none", "label": "(No one can learn this!)", "disabled": true})

	_show_menu("Who learns?", items, Vector2(100, 100))
	description_label.text = "Choose who will learn %s." % spell_data.get("name", "???")


## Which equipment slot an id belongs to, or "" when the id is unknown.
func _equip_slot_for_item(item_id: String) -> String:
	if equipment_system.weapons.has(item_id):
		return "weapon"
	if equipment_system.armors.has(item_id):
		return "armor"
	if equipment_system.accessories.has(item_id):
		return "accessory"
	return ""


## Name currently filling `slot` on `member`, or "empty". Reads the slot's
## own catalog rather than _get_item_data, whose BLACKSMITH branch checks
## weapons then armors and never accessories.
func _equipped_name_in_slot(member, slot: String) -> String:
	var current_id: String = ""
	var catalog: Dictionary = {}
	match slot:
		"weapon":
			current_id = member.equipped_weapon
			catalog = equipment_system.weapons
		"armor":
			current_id = member.equipped_armor
			catalog = equipment_system.armors
		"accessory":
			current_id = member.equipped_accessory
			catalog = equipment_system.accessories
	if current_id.is_empty():
		return "empty"
	return str(catalog.get(current_id, {}).get("name", current_id))


## Post-purchase "equip this now?" offer. Returns true when the menu opened,
## so the caller skips its own buy-menu refresh.
func _offer_equip(item_id: String, item_data: Dictionary) -> bool:
	var slot: String = _equip_slot_for_item(item_id)
	if slot.is_empty():
		return false
	# Equipping writes to the LIVE Combatant (tick 314) — without one there
	# is nothing to equip onto, so fall through to the normal refresh.
	var live_party: Array = _resolve_live_party()
	if live_party.is_empty():
		return false

	current_mode = ShopMode.EQUIP_SELECT
	pending_equip_id = item_id
	pending_equip_data = item_data
	_close_current_menu()

	var items: Array = []
	for i in range(live_party.size()):
		var member = live_party[i]
		if member == null or not is_instance_valid(member):
			continue
		items.append({
			"id": str(i),
			"label": "%s (%s)" % [member.combatant_name, _equipped_name_in_slot(member, slot)]
		})
	items.append({"id": "skip", "label": "Not now"})

	_show_menu("Equip %s?" % item_data.get("name", "it"), items, Vector2(100, 100))
	description_label.text = "Equip %s on whom? (current %s shown)" % [
		item_data.get("name", "it"), slot]
	return true


## Equip the just-purchased item, or decline and go back to the shelves.
func _attempt_equip(choice: String) -> void:
	if choice == "skip":
		SoundManager.play_ui("menu_select")
		_open_buy_menu()
		return

	var live_party: Array = _resolve_live_party()
	var char_index: int = int(choice)
	if char_index < 0 or char_index >= live_party.size():
		_open_buy_menu()
		return
	var member = live_party[char_index]
	if member == null or not is_instance_valid(member):
		_open_buy_menu()
		return

	var slot: String = _equip_slot_for_item(pending_equip_id)
	var replaced: String = _equipped_name_in_slot(member, slot)
	## equip_weapon only writes the slot. The purchase is already one pool entry; wearing it that way left the entry in the bag and never returned the piece it replaced.
	var success: bool = false
	var gl: Node = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	if gl != null and gl.has_method("equip_from_pool") and slot != "":
		success = gl.equip_from_pool(member, slot, pending_equip_id)

	if not success:
		SoundManager.play_ui("menu_error")
		description_label.text = "Couldn't equip that."
		_open_buy_menu()
		return

	SoundManager.play_ui("menu_select")
	var equipped_name: String = str(pending_equip_data.get("name", pending_equip_id))
	if replaced == "empty":
		description_label.text = "%s equipped %s." % [member.combatant_name, equipped_name]
	else:
		description_label.text = "%s equipped %s, replacing %s." % [
			member.combatant_name, equipped_name, replaced]
	_open_buy_menu()


func _attempt_magic_purchase(char_index_str: String) -> void:
	"""Purchase a spell for a specific party member"""
	var char_index = int(char_index_str)
	if char_index < 0 or char_index >= game_state.player_party.size():
		return

	var cost = pending_spell_data.get("cost", 0)
	var current_gold = game_state.get_gold()

	if current_gold < cost:
		SoundManager.play_ui("menu_error")
		_flash_gold_label()
		description_label.text = "Insufficient gold!\nYou need %d G but only have %d G." % [cost, current_gold]
		return

	# Guard against double-purchase: the character-select menu disables
	# already-known options, but a stale menu (rebuild race after a job
	# change) or a future direct-call path could still reach here. Spend
	# THEN no-op-append silently consumed the gold for nothing.
	var existing_member: Dictionary = game_state.player_party[char_index]
	var existing_learned: Array = existing_member.get("learned_abilities", [])
	if _member_knows(char_index, pending_spell_id, existing_learned):
		SoundManager.play_ui("menu_error")
		var name_str: String = str(existing_member.get("name", "Character"))
		description_label.text = "%s already knows %s." % [name_str, pending_spell_data.get("name", "this spell")]
		return

	# Silent-failure audit 2026-07-02: verify the LIVE mirror is
	# reachable BEFORE spending — the snapshot-only append gets
	# clobbered by the next _sync_party_to_game_state (tick 315), so
	# spend-then-fail-to-mirror was "paid, confirmed, revoked": the
	# most misleading outcome a shop can produce. No live target →
	# refuse the sale loudly, gold untouched.
	var live_party: Array = _resolve_live_party()
	var live_ok: bool = char_index < live_party.size() and live_party[char_index] != null \
		and live_party[char_index].has_method("learn_ability")
	if not live_ok:
		push_error("ShopScene: no live Combatant for char_index %d — spell sale refused (gold untouched)" % char_index)
		SoundManager.play_ui("menu_error")
		description_label.text = "The spell fizzles — try again outside the shop."
		return

	if game_state.spend_gold(cost):
		var member = game_state.player_party[char_index]
		if not member.has("learned_abilities"):
			member["learned_abilities"] = []
		if pending_spell_id not in member["learned_abilities"]:
			member["learned_abilities"].append(pending_spell_id)

		# Tick 315: mirror to the LIVE Combatant. Same overwrite class as
		# tick 314's potion-purchase fix — pre-fix the snapshot-only
		# append was clobbered on the next _sync_party_to_game_state,
		# silently un-learning the just-purchased spell while keeping
		# the gold spent.
		live_party[char_index].learn_ability(pending_spell_id)
		# Item 18: bought spells are marked so the Dev Full-Kits
		# toggle's OFF-strip never repossesses gold-paid knowledge.
		if "purchased_abilities" in live_party[char_index] and pending_spell_id not in live_party[char_index].purchased_abilities:
			live_party[char_index].purchased_abilities.append(pending_spell_id)

		SoundManager.play_ui("purchase_complete")
		_flash_gold_spend(cost)

		var member_name = member.get("name", "???")
		description_label.text = "%s learned %s!" % [member_name, pending_spell_data.get("name", "spell")]

		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(self):
			return
		_open_buy_menu()


func _close_shop() -> void:
	"""Close the shop and return to exploration"""
	_close_current_menu()
	shop_closed.emit()
	queue_free()


func _on_menu_closed() -> void:
	"""Handle menu closed (B button)"""
	match current_mode:
		ShopMode.MAIN:
			_close_shop()
		ShopMode.BUY, ShopMode.SELL:
			_open_main_menu()
		ShopMode.CHAR_SELECT, ShopMode.EQUIP_SELECT:
			_open_buy_menu()


