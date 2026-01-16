extends CharacterBody3D

signal hit_wall
signal hit_snowdrift
signal hit_santa
signal hit_portal(collider)
signal hit_super_portal(collider)

@export var start_speed: float = 2.0
@export var direction: Vector3 = Vector3.BACK

var is_moving: bool = false

func _ready() -> void:
	# Отключаем гравитацию - подарок должен двигаться только горизонтально
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Подарок начинает движение сразу
	is_moving = true
	velocity = direction.normalized() * start_speed
	# print("gift ready:", " pos=", position, " dir=", direction, " speed=", start_speed)

func _physics_process(delta: float) -> void:
	if is_moving:
		# Устанавливаем скорость
		velocity = direction.normalized() * start_speed
		# Двигаемся
		move_and_slide()
		check_collisions()
	else:
		velocity = Vector3.ZERO

# Функция для обновления скорости и запуска движения
func update_velocity() -> void:
	is_moving = true

func check_collisions():
	# Проверяем столкновения через move_and_slide
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		# print("gift collision with:", collider.name)

		if "super_portal" in collider.name:
			emit_signal("hit_super_portal", collider)
			is_moving = false
			break
		elif "portal" in collider.name:
			# Реагируем только на входной портал, выходной не стопорит
			if collider.name == "entrance_portal":
				emit_signal("hit_portal", collider)
				is_moving = false
				break
			else:
				continue
		elif collider.name == "floor":
			continue
		elif collider.name.begins_with("wall"):
			emit_signal("hit_wall")
			is_moving = false
			break
		elif collider.name.begins_with("snowdrift"):
			emit_signal("hit_snowdrift")
			is_moving = false
			break
		elif collider.name == "santa":
			emit_signal("hit_santa")
			is_moving = false
			break
