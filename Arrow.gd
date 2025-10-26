extends Area2D

@export var speed: float = 600.0
var direction: Vector2 = Vector2.ZERO
var damage: int = 10

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("Arrow")
	connect("body_entered", Callable(self, "_on_body_entered"))

	# 🔄 Поворачиваем спрайт в направлении полёта
	if direction != Vector2.ZERO:
		rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if direction == Vector2.ZERO:
		return

	position += direction * speed * delta

	# Если стрела вышла за пределы экрана — удалить
	if not get_viewport_rect().has_point(global_position):
		queue_free()

func _on_body_entered(body):
	# 💥 Если попала во врага
	if body.is_in_group("Enemy"):
		if body.has_method("take_damage"):
			body.take_damage(damage, global_position)

			# Показываем цифры урона
			var player = get_tree().get_first_node_in_group("Player")
			if player and player.has_method("show_enemy_damage"):
				player.show_enemy_damage(damage, body.global_position)

		queue_free()

	# 🚫 Не взаимодействует с игроком или другими стрелами
	elif body.is_in_group("Player") or body.is_in_group("Arrow"):
		return

	else:
		# Попала в стену или другой объект — уничтожаем
		queue_free()
