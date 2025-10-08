extends CharacterBody2D

@export var speed: float = 200.0
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var inventory_ui: CanvasLayer = $InventoryUI
@onready var item_label: Label = $InventoryUI/Control/Panel/Label
@onready var detector: Area2D = $Detector
@onready var grid: GridContainer = $InventoryUI/Control/Panel/GridContainer

var last_direction: String = "down"
var nearby_items: Array = []  # список предметов в зоне триггера
var inventory: Array = []     # каждый предмет — словарь: {name, icon, scene_path}
var inventory_open: bool = false
var selected_index: int = -1

func _ready() -> void:
	anim.play("idle_down")
	inventory_ui.visible = false
	item_label.text = ""

	detector.area_entered.connect(_on_area_entered)
	detector.area_exited.connect(_on_area_exited)

func _physics_process(delta: float) -> void:
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	input_vector = input_vector.normalized()

	# Движение игрока
	velocity = input_vector * speed
	move_and_slide()

	if input_vector == Vector2.ZERO:
		play_idle()
	else:
		play_run(input_vector)

	# Подбор предмета — только если курсор наведён
	if Input.is_action_just_pressed("interact"):
		for item in nearby_items:
			if item.hovered:
				pick_up_item(item)
				break  # берём только один предмет

	# Открытие/закрытие инвентаря
	if Input.is_action_just_pressed("inventory"):
		inventory_open = !inventory_open
		inventory_ui.visible = inventory_open

	# Drop предмета
	if Input.is_action_just_pressed("drop") and selected_index != -1:
		drop_selected_item()

# ===================== АНИМАЦИИ ======================
func play_run(input_vector: Vector2) -> void:
	if abs(input_vector.x) > abs(input_vector.y):
		if input_vector.x > 0:
			anim.play("run_right")
			anim.flip_h = false
			last_direction = "right"
		else:
			anim.play("run_right")
			anim.flip_h = true
			last_direction = "left"
	else:
		if input_vector.y < 0:
			anim.play("run_up")
			anim.flip_h = false
			last_direction = "up"
		else:
			anim.play("run_down")
			anim.flip_h = false
			last_direction = "down"

func play_idle() -> void:
	match last_direction:
		"right": anim.play("idle_right")
		"left": anim.play("idle_right"); anim.flip_h = true
		"up": anim.play("idle_up")
		"down": anim.play("idle_down")

# ===================== СИГНАЛЫ ======================
func _on_area_entered(area):
	if area.is_in_group("Item") and not nearby_items.has(area):
		nearby_items.append(area)
		item_label.text = "Наведи курсор и нажми E, чтобы подобрать"

func _on_area_exited(area):
	if area.is_in_group("Item"):
		nearby_items.erase(area)
		if nearby_items.size() == 0:
			item_label.text = ""

# ===================== ПОДБОР ======================
func pick_up_item(item):
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
	update_inventory_ui()

# ===================== DROP ======================
func drop_selected_item():
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

	# Определяем направление броска
	var offset = Vector2.ZERO
	match last_direction:
		"up": offset = Vector2(0, -32)
		"down": offset = Vector2(0, 32)
		"left": offset = Vector2(-32, 0)
		"right": offset = Vector2(32, 0)

	var final_pos = position + offset
	if is_item_at_position(final_pos):
		final_pos += Vector2(randf_range(-24, 24), randf_range(-24, 24))

	dropped.position = final_pos
	get_parent().add_child(dropped)

	selected_index = -1
	update_inventory_ui()

func is_item_at_position(pos: Vector2) -> bool:
	for child in get_parent().get_children():
		if child.is_in_group("Item") and child.position.distance_to(pos) < 16:
			return true
	return false

# ===================== UI ======================
func update_inventory_ui():
	for child in grid.get_children():
		child.queue_free()

	for i in range(inventory.size()):
		var item_data = inventory[i]
		var button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(48, 48)

		# TextureRect для иконки по центру кнопки
		var icon = TextureRect.new()
		icon.texture = item_data["icon"]
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = button.custom_minimum_size
		icon.position = Vector2.ZERO
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)

		# Подсветка выбранного предмета
		button.set_pressed(i == selected_index)

		button.pressed.connect(func():
			selected_index = i
			update_inventory_ui()
		)

		grid.add_child(button)
