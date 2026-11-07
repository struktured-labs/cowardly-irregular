extends Node2D
class_name EnemyAdvanceTell

## A monster's Advance, readable at a glance (struktured via main 23349): chosen at selection, it powers up there and
## stays powered up until it acts, so it reads at 64x. An enemy-tinted AdvanceAura sized to the queue, a countable
## "×N" pip over the head, ticked down per sub-action and cleared when the queue is spent or its owner falls.

const AdvanceAuraClass = preload("res://src/battle/AdvanceAura.gd")
const NODE_NAME := "EnemyAdvanceTell"
## A ×1 still has a pending action but is no longer an Advance, so the tell clears at 1, not at 0.
const MIN_SHOWN := 2

var combatant: Combatant = null
var _aura: Node2D = null
var _pip: Label = null
var _count: int = 0


## The tell on `sprite`, built on first use. Counter-scaled so the sheet's draw scale does not shrink it.
static func on(sprite: Node2D) -> EnemyAdvanceTell:
	var t := sprite.get_node_or_null(NODE_NAME) as EnemyAdvanceTell
	if t == null:
		t = EnemyAdvanceTell.new()
		t.name = NODE_NAME
		sprite.add_child(t)
	var sx: float = absf(sprite.scale.x)
	var sy: float = absf(sprite.scale.y)
	t.scale = Vector2(1.0 / sx if sx > 0.001 else 1.0, 1.0 / sy if sy > 0.001 else 1.0)
	return t


func _init() -> void:
	_aura = AdvanceAuraClass.new()
	_aura.name = "Aura"
	add_child(_aura)
	_pip = Label.new()
	_pip.name = "Pip"
	_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pip.add_theme_font_size_override("font_size", TextScale.scaled(22))
	_pip.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	_pip.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.02))
	_pip.add_theme_constant_override("outline_size", 6)
	_pip.z_index = 70
	_pip.visible = false
	add_child(_pip)


func count() -> int:
	return _count


func pip() -> Label:
	return _pip


func aura() -> Node2D:
	return _aura


## Show a queue of `n` (n < 2 is not an Advance and clears). `show_aura` is false at the MINIMAL juice tier; the pip stays.
func show_queue(n: int, for_combatant: Combatant, color: Color, show_aura: bool = true) -> void:
	combatant = for_combatant
	_count = n
	if n < MIN_SHOWN:
		clear()
		return
	var body := get_parent() as AnimatedSprite2D
	if show_aura:
		if body != null:
			_aura.bind_body(body)
		_aura.set_state(n, false, color, "sparks")
	else:
		_aura.clear()
	_pip.text = "×%d" % n
	_pip.reset_size()
	_pip.position = Vector2(-_pip.size.x * 0.5, _head_y() - _pip.size.y)
	_pip.visible = true
	set_process(true)


## One queued action resolved.
func spend() -> void:
	if _count <= 0:
		return
	_count -= 1
	if _count < MIN_SHOWN:
		clear()
		return
	_aura.set_state(_count, false, _aura.color, _aura.shape)
	_pip.text = "×%d" % _count


func clear() -> void:
	_count = 0
	_aura.clear()
	_pip.visible = false
	set_process(false)


func is_showing() -> bool:
	return _count >= MIN_SHOWN and _pip.visible


## The pip sits above the figure's head; without a bound frame it falls back to a fixed lift.
func _head_y() -> float:
	var r: Rect2 = _aura.figure_rect()
	return r.position.y - 6.0 if r.size.y > 0.0 else -90.0


func _process(_delta: float) -> void:
	if combatant != null and (not is_instance_valid(combatant) or not combatant.is_alive):
		clear()
