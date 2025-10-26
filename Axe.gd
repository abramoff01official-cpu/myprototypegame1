extends Area2D

@export var item_name: String = "Axe"
@export var item_icon: Texture
@export var scene_path: String = "res://Scene/Axe.tscn"
@export var damage: int = 60
@export var attack_range: float = 48.0  # 🪓 дальше, чем нож

@onready var sprite: Sprite2D = $Sprite2D
@onready var highlight: Sprite2D = $Highlight
var hovered: bool = false

func _ready():
	add_to_group("Item")
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if highlight:
		highlight.visible = false

func _on_mouse_entered():
	hovered = true
	if highlight:
		highlight.visible = true

func _on_mouse_exited():
	hovered = false
	if highlight:
		highlight.visible = false
