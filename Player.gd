extends CharacterBody2D

# ================== ПАРАМЕТРЫ ==================
@export var speed: float = 200.0
@export var max_hp: int = 100
@export var base_attack_damage: int = 20
@export var attack_cooldown: float = 0.4
@export var base_attack_range: float = 32.0  # 📏 базовый радиус атаки

# ================== КОМПОНЕНТЫ ==================
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var inventory_ui: CanvasLayer = $InventoryUI
@onready var item_label: Label = $InventoryUI/Control/Panel/Label
@onready var detector: Area2D = $Detector
@onready var grid: GridContainer = $InventoryUI/Control/Panel/GridContainer
@onready var health_node: Node = $Health
@onready var death_ui: Node = $DeathUI
@onready var hp_bar: TextureProgressBar = $HealthBar
@onready var active_item_ui: TextureRect = $ActiveItemUI/Icon
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

# ================== ПЕРЕМЕННЫЕ ==================
var damage_label_scene: PackedScene = preload("res://Scene/DamageLabel.tscn")
var hp: int
var last_direction: String = "down"
var nearby_items: Array = []
var inventory: Array = []
var inventory_open: bool = false
var selected_index: int = -1
var active_item: Dictionary = {}
var is_dead: bool = false
var is_attacking: bool = false
var can_attack: bool = true

# ================== READY ==================
func _ready() -> void:
	hp = max_hp
	anim.play("idle_down")
	inventory_ui.visible = false
	item_label.text = ""
	death_ui.visible = false
	active_item_ui.texture = null

	if detector:
		detector.connect("area_entered", Callable(self, "_on_area_entered"))
		detector.connect("area_exited", Callable(self, "_on_area_exited"))

	if health_node and health_node.has_signal("died"):
		health_node.connect("died", Callable(self, "_on_player_died"))

	if attack_hitbox:
		attack_hitbox.connect("body_entered", Callable(self, "_on_attack_hitbox_body_entered"))
		attack_hitbox.monitoring = false

# ================== UPDATE ==================
func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		if anim.animation != "death":
			anim.play("death")
		return

	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()

	# 🎯 Хитбокс всегда смотрит туда, куда игрок
	_update_attack_hitbox_position()

	if is_attacking:
		return

	if input_vector == Vector2.ZERO:
		play_idle()
	else:
		play_run(input_vector)

	if Input.is_action_just_pressed("interact") and not is_dead:
		for item in nearby_items:
			if item.hovered:
				_pick_up_item(item)
				break

	if Input.is_action_just_pressed("inventory") and not is_dead:
		inventory_open = !inventory_open
		inventory_ui.visible = inventory_open

	if Input.is_action_just_pressed("drop") and selected_index != -1 and not is_dead:
		_drop_selected_item()

	if Input.is_action_just_pressed("use_item") and selected_index != -1 and not is_dead:
		_use_selected_item()

# ================== ВВОД ==================
func _input(event):
	if event.is_action_pressed("attack") and not is_dead:
		if active_item.size() > 0:
			_attack()

# ================== АНИМАЦИИ ==================
func play_run(input_vector: Vector2) -> void:
	if abs(input_vector.x) > abs(input_vector.y):
		if input_vector.x > 0:
			anim.play("run_right"); anim.flip_h = false; last_direction = "right"
		else:
			anim.play("run_right"); anim.flip_h = true; last_direction = "left"
	else:
		if input_vector.y < 0:
			anim.play("run_up"); last_direction = "up"
		else:
			anim.play("run_down"); last_direction = "down"

func play_idle() -> void:
	match last_direction:
		"right": anim.play("idle_right"); anim.flip_h = false
		"left": anim.play("idle_right"); anim.flip_h = true
		"up": anim.play("idle_up")
		"down": anim.play("idle_down")

# ================== ХИТБОКС ПОВОРОТА ==================
func _update_attack_hitbox_position():
	var current_range = base_attack_range
	if active_item.has("attack_range"):
		current_range = active_item["attack_range"]

	match last_direction:
		"up":
			attack_hitbox.position = Vector2(0, -current_range)
		"down":
			attack_hitbox.position = Vector2(0, current_range)
		"left":
			attack_hitbox.position = Vector2(-current_range, 0)
		"right":
			attack_hitbox.position = Vector2(current_range, 0)

# ================== АТАКА ==================
func _attack():
	if is_attacking or not can_attack:
		return
	if active_item.size() == 0:
		return

	is_attacking = true
	can_attack = false
	velocity = Vector2.ZERO
	attack_hitbox.monitoring = true

	var weapon_type = active_item.get("type", "knife")

	match last_direction:
		"up": anim.play("attack_up_" + weapon_type)
		"down": anim.play("attack_down_" + weapon_type)
		"left":
			anim.play("attack_side_" + weapon_type)
			anim.flip_h = true
		"right":
			anim.play("attack_side_" + weapon_type)
			anim.flip_h = false

	anim.animation_finished.connect(Callable(self, "_on_attack_animation_finished"), CONNECT_ONE_SHOT)

	get_tree().create_timer(attack_cooldown).timeout.connect(func():
		can_attack = true
	)

func _on_attack_animation_finished():
	is_attacking = false
	attack_hitbox.monitoring = false
	play_idle()

# ================== ХИТБОКС ==================
func _on_attack_hitbox_body_entered(body):
	if body.is_in_group("Enemy") and is_attacking and active_item.size() > 0:
		var attack_damage = active_item.get("damage", base_attack_damage)
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, global_position)
		show_enemy_damage(attack_damage, body.global_position)

# ================== СИГНАЛЫ ДЕТЕКТОРА ==================
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

# ================== ПОДБОР ПРЕДМЕТА ==================
func _pick_up_item(item):
	if item == null:
		return
	inventory.append({
		"name": item.item_name,
		"icon": item.item_icon,
		"scene_path": item.scene_path,
		"damage": item.damage,
		"attack_range": item.attack_range
	})
	item.queue_free()
	nearby_items.erase(item)
	item_label.text = ""
	_update_inventory_ui()

# ================== DROP ==================
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
	dropped.damage = dropped_data["damage"]
	dropped.attack_range = dropped_data["attack_range"]

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

	selected_index = -1
	_update_inventory_ui()

func _is_item_at_position(pos: Vector2) -> bool:
	for child in get_parent().get_children():
		if child.is_in_group("Item") and child.position.distance_to(pos) < 16:
			return true
	return false

# ================== ИСПОЛЬЗОВАНИЕ ПРЕДМЕТА ==================
func _use_selected_item():
	if selected_index < 0 or selected_index >= inventory.size():
		return

	active_item = inventory[selected_index]
	print("Используется предмет:", active_item["name"])

	if not active_item.has("type"):
		if "knife" in active_item["name"].to_lower():
			active_item["type"] = "knife"
		elif "axe" in active_item["name"].to_lower():
			active_item["type"] = "axe"
		else:
			active_item["type"] = "knife"

	if active_item.has("icon") and active_item["icon"]:
		active_item_ui.texture = active_item["icon"]
	else:
		active_item_ui.texture = null

	_update_inventory_ui()

# ================== UI ==================
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
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)

		button.set_pressed(i == selected_index or inventory[i] == active_item)
		button.pressed.connect(func(idx=i):
			selected_index = idx
			_update_inventory_ui()
		)

		grid.add_child(button)

# ================== УРОН ==================
func take_damage(amount: int):
	if is_dead:
		return

	hp -= amount
	hp = clamp(hp, 0, max_hp)
	hp_bar.set_hp(hp)
	print("Игрок получил урон:", amount)

	if has_node("AnimationPlayer"):
		$AnimationPlayer.play("hit")

	show_damage(amount, global_position)

	if hp <= 0:
		die()

func die():
	if is_dead:
		return
	is_dead = true
	inventory_open = false
	inventory_ui.visible = false
	death_ui.visible = true
	velocity = Vector2.ZERO
	anim.play("death")
	if $CollisionShape2D:
		$CollisionShape2D.disabled = true

# ================== DAMAGE LABEL ==================
func show_damage(amount: int, pos: Vector2):
	if damage_label_scene == null:
		return
	var label = damage_label_scene.instantiate()
	label.text = str(amount)
	label.global_position = pos
	get_tree().current_scene.add_child(label)

func show_enemy_damage(amount: int, pos: Vector2):
	if damage_label_scene == null:
		return
	var label = damage_label_scene.instantiate()
	label.text = str(amount)
	label.global_position = pos
	get_tree().current_scene.add_child(label)
