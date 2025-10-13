extends CharacterBody2D

@export var speed: float = 200.0
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var inventory_ui: CanvasLayer = $InventoryUI
@onready var item_label: Label = $InventoryUI/Control/Panel/Label
@onready var detector: Area2D = $Detector
@onready var grid: GridContainer = $InventoryUI/Control/Panel/GridContainer
@onready var health_node: Node = $Health  # узел Health.gd
@onready var active_icon: TextureRect = $InventoryUI/ActiveItemUI/ActiveIcon  # иконка активного предмета

var last_direction: String = "down"
var nearby_items: Array = [] 
var inventory: Array = []     
var inventory_open: bool = false
var selected_index: int = -1
var active_item: Dictionary = {}  # текущий активный предмет
var is_dead: bool = false

func _ready() -> void:
	anim.play("idle_down")
	inventory_ui.visible = false
	active_icon.visible = false
	item_label.text = ""

	detector.area_entered.connect(_on_area_entered)
	detector.area_exited.connect(_on_area_exited)

	# Подписка на сигнал смерти
	if health_node and health_node.has_signal("died"):
		health_node.died.connect(_on_player_died)

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		if anim.animation != "death":
			anim.animation = "death"
			anim.play()
		return

	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()

	if input_vector == Vector2.ZERO:
		play_idle()
	else:
		play_run(input_vector)

	# Подбор предметов
	if Input.is_action_just_pressed("interact") and not is_dead:
		for item in nearby_items:
			if item.hovered:
				_pick_up_item(item)
				break

	# Инвентарь
	if Input.is_action_just_pressed("inventory") and not is_dead:
		inventory_open = !inventory_open
		inventory_ui.visible = inventory_open

	# Drop предметов
	if Input.is_action_just_pressed("drop") and selected_index != -1 and not is_dead:
		_drop_selected_item()

	# Использование предмета
	if Input.is_action_just_pressed("use_item") and selected_index != -1 and not is_dead:
		_use_selected_item()

# ===================== Анимации ======================
func play_run(input_vector: Vector2) -> void:
	if abs(input_vector.x) > abs(input_vector.y):
		if input_vector.x > 0:
			anim.play("run_right"); anim.flip_h = false; last_direction = "right"
		else:
			anim.play("run_right"); anim.flip_h = true; last_direction = "left"
	else:
		if input_vector.y < 0:
			anim.play("run_up"); anim.flip_h = false; last_direction = "up"
		else:
			anim.play("run_down"); anim.flip_h = false; last_direction = "down"

func play_idle() -> void:
	match last_direction:
		"right": anim.play("idle_right")
		"left": anim.play("idle_right"); anim.flip_h = true
		"up": anim.play("idle_up")
		"down": anim.play("idle_down")

# ===================== Сигналы ======================
func _on_area_entered(area):
	if area.is_in_group("Item") and not nearby_items.has(area):
		nearby_items.append(area)
		item_label.text = "Наведи курсор и нажми E, чтобы подобрать"

func _on_area_exited(area):
	if area.is_in_group("Item"):
		nearby_items.erase(area)
		if nearby_items.size() == 0:
			item_label.text = ""

func _on_player_died():
	is_dead = true
	inventory_open = false
	inventory_ui.visible = false

# ===================== Подбор предметов ======================
func _pick_up_item(item):
	if item == null:
		return
	inventory.append({
		"name": item.item_name,
		"icon": item.item_icon,
		"scene_path": item.scene_path
	})
	item.queue_free()
	nearby_items.erase(item)
	item_label.text = ""
	_update_inventory_ui()

# ===================== Drop предметов ======================
func _drop_selected_item():
	if selected_index < 0 or selected_index >= inventory.size():
		return

	var dropped_data = inventory[selected_index]
	inventory.remove_at(selected_index)

	var scene = load(dropped_data["scene_path"])
	if scene == null:
		print("Ошибка: не удалось загрузить сцену для", dropped_data["name"])
		return

	var dropped = scene.instantiate()
	dropped.item_name = dropped_data["name"]
	dropped.item_icon = dropped_data["icon"]

	var offset = Vector2.ZERO
	match last_direction:
		"up": offset = Vector2(0, -32)
		"down": offset = Vector2(0, 32)
		"left": offset = Vector2(-32, 0)
		"right": offset = Vector2(32, 0)

	var final_pos = position + offset
	if _is_item_at_position(final_pos):
		final_pos += Vector2(randf_range(-24, 24), randf_range(-24, 24))

	dropped.position = final_pos
	get_parent().add_child(dropped)

	# Если выброшенный предмет был активным — сбрасываем активный
	if active_item == dropped_data:
		active_item = {}
		active_icon.visible = false

	selected_index = -1
	_update_inventory_ui()

func _is_item_at_position(pos: Vector2) -> bool:
	for child in get_parent().get_children():
		if child.is_in_group("Item") and child.position.distance_to(pos) < 16:
			return true
	return false

# ===================== Использование предмета ======================
func _use_selected_item():
	if selected_index < 0 or selected_index >= inventory.size():
		return

	active_item = inventory[selected_index]
	print("Используется предмет:", active_item["name"])

	# Показываем иконку активного предмета в UI
	if active_item.has("icon") and active_icon:
		active_icon.texture = active_item["icon"]
		active_icon.visible = true

	_update_inventory_ui()

# ===================== UI ======================
func _update_inventory_ui():
	for child in grid.get_children():
		child.queue_free()

	for i in range(inventory.size()):
		var item_data = inventory[i]
		var button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(48, 48)

		var icon = TextureRect.new()
		icon.texture = item_data["icon"]
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = button.custom_minimum_size
		icon.position = Vector2.ZERO
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)

		# Подсвечиваем выбранный и активный предмет
		button.set_pressed(i == selected_index or inventory[i] == active_item)
		button.pressed.connect(func():
			selected_index = i
			_update_inventory_ui()
		)

		grid.add_child(button)
