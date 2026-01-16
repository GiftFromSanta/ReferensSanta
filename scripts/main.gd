extends Node3D

@onready var score_label = $CanvasLayer/UI/ScoreLabel
@onready var level_label = $CanvasLayer/UI/LevelLabel  # Добавим метку уровня
@onready var shovel_label = $CanvasLayer/UI/ShovelLabel  # Метка лопат
@onready var coins_label = $CanvasLayer/UI/CoinsLabel  # Метка монет
@onready var super_portal_button = $CanvasLayer/UI/SuperPortalButton  # Кнопка супер портала
@onready var mass_clear_button = $CanvasLayer/UI/MassClearButton  # Кнопка массовой очистки
@onready var speed_reset_button = $CanvasLayer/UI/SpeedResetButton  # Кнопка сброса скорости
@onready var pause_button = $CanvasLayer/UI/PauseButton
@onready var restart_button = $CanvasLayer/UI/RestartButton
@onready var canvas_layer = $CanvasLayer

var score = 0
var game_paused = false
var level = 1  # Текущий уровень (начинается с 1)
var snowdrift_count = 3  # Начальное количество сугробов (будет равно level)
var shovels = 5  # Глобальный ресурс лопат (можно копить, минтить как NFT для TON)
var super_portals = 1  # Количество супер порталов (мгновенная победа)
var mass_clears = 1  # Количество массовых очисток (глобальный ресурс)
var speed_resets = 1  # Количество сбросов скорости до базовой (глобальный ресурс)
var super_portal_mode = false  # Режим размещения супер портала
var cell_highlight = null  # Объект для подсветки клеток
var portals = []  # Список активных порталов
var wall_cells_base: Array = []  # Все клеточные позиции стен (Vector2i)
var wall_cells_free: Dictionary = {}  # Свободные клетки стен (ключ Vector2i)
var snowdrift_cells: Dictionary = {}  # Ключ: Vector2i(x,z) клетки, значение: узел сугроба
var trigger_objects: Dictionary = {}  # позиционные триггеры: santa, super_portal, etc.
var portal_attempts = 2  # Количество порталов для размещения (вход + выход)
var placed_portals = 0  # Количество размещенных порталов (0, 1, или 2)
var entrance_portal = null  # Ссылка на портал входа
var exit_portal = null      # Ссылка на портал выхода
@export var gift_scene: PackedScene = preload("res://scenes/gift.tscn")
var gift: Node3D = null
var gift_start_pos: Vector3 = Vector3.ZERO
var initial_gift_start_pos: Vector3 = Vector3.ZERO
var gift_start_initialized: bool = false
var gift_base_speed: float = 2.0
var gift_speed_multiplier: float = 1.0
var santa_start_pos: Vector3 = Vector3(0, 1, 5)
var debug_timer := 0.0
var next_level_score_requirement: int = 100
var prev_gift_position: Vector3 = Vector3.ZERO
var coins: int = 0                 # Глобальные монеты (персистентность позже)
var coins_run_gain: int = 0        # Заработок монет за текущий забег
var game_over_panel: Control = null

func flash_mesh(node: Node, duration := 1.0, flash_color := Color(1, 1, 1, 1.0)):
	# Анимация отключена по запросу — заглушка
	return

func _ready():
	# print("Game starting...")
	# print("Initializing portals...")
	$CanvasLayer.process_mode = Node.PROCESS_MODE_ALWAYS  # UI всегда обрабатывается при паузе
	var camera = $Camera3D
	if camera:
		# print("Camera position: ", camera.position)
		# Гарантируем, что камера смотрит на центр арены
		camera.look_at(Vector3.ZERO, Vector3.UP)

	init_actor_positions()
	$"santa".position = santa_start_pos

	create_walls()
	create_grid_overlay()
	create_snowdrifts(level)  # Количество сугробов = уровню
	setup_ui()
	setup_portal_signals()
	create_cell_highlight()
	initialize_portal_positions() # Инициализируем возможные позиции порталов
	reset_portals() # Размещаем начальные порталы

	spawn_gift()
	create_game_over_ui()

func create_cell_highlight():
	# Создаем объект для подсветки клеток
	cell_highlight = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2, 3, 0.1)  # Вертикальная плоскость для стен (изначально)
	cell_highlight.mesh = box_mesh

	# Создаем яркий желтый материал без прозрачности
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 0, 1.0)  # Яркий непрозрачный желтый
	material.emission_enabled = true
	material.emission = Color(1, 1, 0, 1.0)  # Яркое свечение
	material.emission_energy_multiplier = 1.0
	material.unshaded = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	cell_highlight.material_override = material

	# Изначально скрываем
	cell_highlight.visible = false
	add_child(cell_highlight)

# Рисуем сетку 2x2 по арене (20x20) линиями
func create_grid_overlay():
	# Используем MultiMesh с тонкими боксами, приподнятыми над полом
	var line_mesh = BoxMesh.new()
	line_mesh.size = Vector3(0.06, 0.04, 20.0)  # вертикальные линии (вдоль Z)

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 1, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_unshaded = true
	material.flags_do_not_receive_shadows = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS

	# Всего линий: 12 по X (от -10 до 10 с шагом 2) + 12 по Z
	var total_lines = 24
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = line_mesh
	multimesh.instance_count = total_lines

	var idx = 0
	var y_offset = 0.55  # выше половины высоты пола (0.5), чтобы не утопала

	# Линии по X (вертикальные, вдоль Z)
	for x in range(-10, 12, 2):
		var xform = Transform3D()
		xform.origin = Vector3(x, y_offset, 0)
		multimesh.set_instance_transform(idx, xform)
		idx += 1

	# Линии по Z (горизонтальные, вдоль X) — поворачиваем на 90° и задаём длину по X
	for z in range(-10, 12, 2):
		var xform = Transform3D()
		xform.basis = Basis(Vector3(0, 1, 0), deg_to_rad(90))  # повернуть, чтобы длина шла по X
		xform.origin = Vector3(0, y_offset, z)
		multimesh.set_instance_transform(idx, xform)
		idx += 1

	var mm_instance = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	mm_instance.material_override = material
	add_child(mm_instance)

func update_cell_highlight():
	if not cell_highlight:
		return

	# Получаем камеру
	var camera = $Camera3D
	if not camera:
		cell_highlight.visible = false
		return

	# Получаем позицию мыши
	var mouse_pos = get_viewport().get_mouse_position()

	# Создаем raycast
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)

	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = ray_origin
	ray_params.to = ray_origin + ray_direction * 1000
	ray_params.collide_with_areas = true
	ray_params.collide_with_bodies = true

	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(ray_params)

	# Убрал все print для raycast, оставляем только для подарка
	if result:
		# Определяем клетку под курсором
		var hit_point = result.position

		# Привязка к сетке 2x2 с центрами в нечётных координатах (-9..9)
		var cell_x = floor(hit_point.x / 2.0) * 2.0 + 1.0
		var cell_z = floor(hit_point.z / 2.0) * 2.0 + 1.0

		if result.collider.name.begins_with("wall"):
			if cell_highlight.mesh == null:
				cell_highlight.mesh = BoxMesh.new()

			if abs(hit_point.x) > abs(hit_point.z):  # Западная или восточная стена (X = ±11)
				(cell_highlight.mesh as BoxMesh).size = Vector3(2.1, 3.1, 2.1)
				cell_highlight.rotation = Vector3(0, 0, 0)
				var wall_x = sign(hit_point.x) * 11
				cell_highlight.position = Vector3(wall_x, 1.5, cell_z)
			else:  # Северная или южная стена (Z = ±11)
				(cell_highlight.mesh as BoxMesh).size = Vector3(2.1, 3.1, 2.1)
				cell_highlight.rotation = Vector3(0, 0, 0)
				var wall_z = sign(hit_point.z) * 11
				cell_highlight.position = Vector3(cell_x, 1.5, wall_z)

			cell_highlight.visible = true
		elif result.collider.name == "floor":
			# Попали на пол - подсвечиваем для супер порталов и лопат
			if abs(cell_x) <= 10 and abs(cell_z) <= 10:  # Внутри арены
				var highlight_pos = Vector3(cell_x, 0.4, cell_z)  # Чуть выше над полом, чтобы не сливаться

				# Сбрасываем вращение и меняем размер подсветки на горизонтальную плоскость
				cell_highlight.rotation = Vector3(0, 0, 0)
				if cell_highlight.mesh:
					cell_highlight.mesh.size = Vector3(2.1, 0.35, 2.1)  # Немного толще и шире клетки
				cell_highlight.position = highlight_pos
				cell_highlight.visible = true
			else:
				cell_highlight.visible = false
	else:
		cell_highlight.visible = false


func _physics_process(delta):
	update_cell_highlight()
	debug_timer += delta
	if debug_timer >= 1.0:
		debug_timer = 0.0
		if gift:
			print("[GIFT SPEED] pos=", gift.position, " vel=", gift.velocity, " speed=", gift.velocity.length(), " start_speed=", gift.start_speed, " mult=", gift_speed_multiplier)
	var portal_used = check_portal_hit()
	if not portal_used:
		check_wall_hit()
		check_snowdrift_hit()
		check_trigger_objects()
	if gift:
		prev_gift_position = gift.position

func check_portal_hit() -> bool:
	if not gift or entrance_portal == null:
		return false

	var from_pos = prev_gift_position if prev_gift_position != Vector3.ZERO else gift.position
	var to_pos = gift.position
	var p = entrance_portal.position
	var ab = Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
	var ab_len_sq = ab.length_squared()

	# Определяем плоскость стены по доминирующей координате портала
	var hit := false
	if abs(p.z) > abs(p.x):
		# Стена по Z (север/юг), плоскость Z = p.z
		if (from_pos.z - p.z) * (to_pos.z - p.z) <= 0.0 and to_pos.z != from_pos.z:
			var t = clamp((p.z - from_pos.z) / (to_pos.z - from_pos.z), 0.0, 1.0)
			var x_at = from_pos.x + (to_pos.x - from_pos.x) * t
			if int(round(x_at)) == int(round(p.x)) and abs(to_pos.y - p.y) <= 0.75:
				hit = true
	else:
		# Стена по X (запад/восток), плоскость X = p.x
		if (from_pos.x - p.x) * (to_pos.x - p.x) <= 0.0 and to_pos.x != from_pos.x:
			var t = clamp((p.x - from_pos.x) / (to_pos.x - from_pos.x), 0.0, 1.0)
			var z_at = from_pos.z + (to_pos.z - from_pos.z) * t
			if int(round(z_at)) == int(round(p.z)) and abs(to_pos.y - p.y) <= 0.75:
				hit = true

	if hit:
		if exit_portal:
			_on_gift_hit_portal(entrance_portal)
		else:
			subtract_score(30)
			reset_portals()
			respawn_gift()
		return true

	# Fallback: радиусная проверка по сегменту, если не зацепили плоскость (мелкий шаг/дрожание)
	var portal_radius = 2.0
	var ac = Vector2(p.x - from_pos.x, p.z - from_pos.z)
	var t2 = 0.0
	if ab_len_sq > 0.0:
		t2 = clamp(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest = Vector2(from_pos.x, from_pos.z) + ab * t2
	var dist_sq = (Vector2(p.x, p.z) - closest).length_squared()
	if dist_sq <= portal_radius * portal_radius:
		if exit_portal:
			_on_gift_hit_portal(entrance_portal)
		else:
			subtract_score(30)
			reset_portals()
			respawn_gift()
		return true

	return false

func check_wall_hit():
	if not gift:
		return

	var from_pos = prev_gift_position if prev_gift_position != Vector3.ZERO else gift.position
	var to_pos = gift.position

	# Внутренняя граница арены: стены стоят центром на ±11, толщина 2 => внутренняя грань около 10.
	# Учитываем половину размера подарка (~0.6), чтобы ловить касание центра на 9.4.
	var half_gift = 0.6
	var inner_limit = 10.0 - half_gift

	var crossed = false
	# Проверка по X
	if abs(from_pos.x) <= inner_limit and abs(to_pos.x) > inner_limit:
		var wall_x = sign(to_pos.x) * 11
		var wall_z = snap_to_grid(to_pos.z)
		var key = Vector2i(int(round(wall_x)), int(round(wall_z)))
		if not wall_cells_free.has(key):
			# Здесь стоит портал — пропускаем стеновой хит
			return
		crossed = true
	# Проверка по Z
	if not crossed and abs(from_pos.z) <= inner_limit and abs(to_pos.z) > inner_limit:
		var wall_z2 = sign(to_pos.z) * 11
		var wall_x2 = snap_to_grid(to_pos.x)
		var key2 = Vector2i(int(round(wall_x2)), int(round(wall_z2)))
		if not wall_cells_free.has(key2):
			return
		crossed = true
	# Если уже за границей
	if not crossed and (abs(to_pos.x) > inner_limit or abs(to_pos.z) > inner_limit):
		crossed = true

	if crossed:
		if gift.has_method("update_velocity"):
			gift.velocity = Vector3.ZERO
			gift.is_moving = false
		_on_gift_hit_wall()
		return

func check_snowdrift_hit():
	if not gift:
		return

	# Отслеживаем отрезок движения за кадр
	var from_pos = prev_gift_position if prev_gift_position != Vector3.ZERO else gift.position
	var to_pos = gift.position

	# Вектор движения в плоскости XZ
	var ab = Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
	var ab_len_sq = ab.length_squared()

	# Совмещаем радиусы подарка (0.6) и сугроба; чуть меньше, чтобы не ловить ранние ложные срабатывания у стен/портала
	var combined_radius = 1.4  # подарок ~0.6 + сугроб-сфера ~0.8
	var combined_radius_sq = combined_radius * combined_radius

	for cell_key in snowdrift_cells.keys():
		var snowdrift = snowdrift_cells[cell_key]
		if not is_instance_valid(snowdrift):
			continue
		var c = snowdrift.position
		var ac = Vector2(c.x - from_pos.x, c.z - from_pos.z)
		var t = 0.0
		if ab_len_sq > 0.0:
			t = clamp(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
		var closest = Vector2(from_pos.x, from_pos.z) + ab * t
		var dist_sq = (Vector2(c.x, c.z) - closest).length_squared()
		if dist_sq <= combined_radius_sq:
			if gift.has_method("update_velocity"):
				gift.velocity = Vector3.ZERO
				gift.is_moving = false
			flash_mesh(gift)
			flash_mesh(snowdrift)
			_on_gift_hit_snowdrift()
			break

func check_trigger_objects():
	if not gift:
		return
	if trigger_objects.is_empty():
		return

	var from_pos = prev_gift_position if prev_gift_position != Vector3.ZERO else gift.position
	var to_pos = gift.position

	for key in trigger_objects.keys():
		var data = trigger_objects[key]
		if not data.has("pos"):
			continue
		var p: Vector3 = data["pos"]
		var radius: float = data.get("radius", 1.0)
		var y_tol: float = data.get("y_tol", 1.0)
		var kind: String = data.get("kind", "")

		# Проверка по Y
		if abs(to_pos.y - p.y) > y_tol and abs(from_pos.y - p.y) > y_tol:
			continue

		# Проверка пересечения сегмента с диском радиуса radius
		var ab = Vector2(to_pos.x - from_pos.x, to_pos.z - from_pos.z)
		var ab_len_sq = ab.length_squared()
		var ac = Vector2(p.x - from_pos.x, p.z - from_pos.z)
		var t = 0.0
		if ab_len_sq > 0.0:
			t = clamp(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
		var closest = Vector2(from_pos.x, from_pos.z) + ab * t
		var dist_sq = (Vector2(p.x, p.z) - closest).length_squared()

		if dist_sq <= radius * radius:
			if kind == "santa":
				_on_gift_hit_santa()
			elif kind == "super_portal":
				_on_gift_hit_super_portal(null)
			# После срабатывания выходим, чтобы не цеплять остальные
			return


func check_portal_teleportation():
	return
	if gift == null:
		return

	var gift_bottom_center = gift.position + Vector3(0, -0.6, 0)  # Центр нижней грани подарка

	# Сначала проверяем супер портал (мгновенная победа)
	var super_portal = get_node_or_null("super_portal")
	if super_portal:
		var super_portal_bottom_y = super_portal.position.y - 1.0
		if abs(gift_bottom_center.y - super_portal_bottom_y) < 0.5:
			var super_portal_center_xz = Vector2(super_portal.position.x, super_portal.position.z)
			var gift_center_xz = Vector2(gift_bottom_center.x, gift_bottom_center.z)

			if super_portal_center_xz.distance_to(gift_center_xz) < 0.8:
				# Супер портал! Мгновенная победа!
				add_score(50)
				reset_portals()
				respawn_gift()
				super_portal.queue_free()  # Удаляем использованный супер портал
				# print("СУПЕР ПОРТАЛ! Мгновенная победа! +50 очков")
				return  # Выходим, чтобы не проверять обычные порталы

	# Затем проверяем обычную телепортацию
	if entrance_portal and exit_portal:
		var portal_bottom_y = entrance_portal.position.y - 1.0  # Нижняя грань портала

		# Проверяем совпадение Y координат (увеличенная погрешность для высокой скорости)
		if abs(gift_bottom_center.y - portal_bottom_y) < 0.5:  # Увеличил с 0.1 до 0.5
			# Проверяем совпадение X и Z координат центров
			var portal_center_xz = Vector2(entrance_portal.position.x, entrance_portal.position.z)
			var gift_center_xz = Vector2(gift_bottom_center.x, gift_bottom_center.z)

			if portal_center_xz.distance_to(gift_center_xz) < 0.8:  # Увеличил погрешность с 0.3 до 0.8
				# Телепортация к порталу выхода!
				# Чуть выше пола, но с привязкой к высоте портала (старая формула)
				var exit_y = exit_portal.position.y
				gift.position = Vector3(exit_portal.position.x, max(1.05, exit_y - 0.3), exit_portal.position.z)
				# Задаем направление от стены выхода к центру поля
				var exit_dir = Vector3.ZERO
				if abs(exit_portal.position.z) > abs(exit_portal.position.x):  # север/юг
					exit_dir = Vector3(0, 0, -sign(exit_portal.position.z))
				else:  # запад/восток
					exit_dir = Vector3(-sign(exit_portal.position.x), 0, 0)
				gift.direction = exit_dir
				gift.update_velocity()
				# print("Телепортация через совпадение центров нижних граней!")
	elif entrance_portal and not exit_portal:
		# Подарок вошел в первый портал, но второго нет - АСТРАЛ!
		if abs(gift_bottom_center.y - (entrance_portal.position.y - 1.0)) < 0.5:
			var portal_center_xz = Vector2(entrance_portal.position.x, entrance_portal.position.z)
			var gift_center_xz = Vector2(gift_bottom_center.x, gift_bottom_center.z)
			if portal_center_xz.distance_to(gift_center_xz) < 0.8:
				subtract_score(30)  # -30 очков за "астрал"
				reset_portals()
				respawn_gift()
				# print("Астрал! Выходной портал не размещен! -30 очков")

func setup_collision_signals():
	if gift:
		gift.connect("hit_wall", Callable(self, "_on_gift_hit_wall"), CONNECT_DEFERRED)
		gift.connect("hit_snowdrift", Callable(self, "_on_gift_hit_snowdrift"), CONNECT_DEFERRED)
		gift.connect("hit_santa", Callable(self, "_on_gift_hit_santa"), CONNECT_DEFERRED)
		gift.connect("hit_portal", Callable(self, "_on_gift_hit_portal"), CONNECT_DEFERRED)
		gift.connect("hit_super_portal", Callable(self, "_on_gift_hit_super_portal"), CONNECT_DEFERRED)

func _on_gift_hit_santa():
	# Успешная доставка!
	flash_mesh(gift)
	flash_mesh($"santa")
	add_score(50)  # +50 очков за доставку
	reset_portals()  # Сбрасываем порталы для нового раунда
	# Сначала респавним подарок, затем Санту с отступом >=3 клеток и разным X, только в пустую клетку
	respawn_gift()
	respawn_santa()
	# print("Доставка успешна! +50 очков. Новые порталы!")

func _on_gift_hit_wall():
	# Обычное столкновение со стеной — штраф
	flash_mesh(gift)
	print("[HIT WALL] gift=", gift.position, " entrance=", entrance_portal.position if entrance_portal else null, " exit=", exit_portal.position if exit_portal else null)
	subtract_score(20)  # -20 очков
	reset_portals()  # Сбрасываем порталы
	respawn_gift()
	# print("Краш со стеной! -20 очков")

func _on_gift_hit_snowdrift():
	# Столкновение с сугробом - штраф
	flash_mesh(gift)
	subtract_score(15)  # -15 очков
	reset_portals()  # Сбрасываем порталы
	respawn_gift()
	# print("Краш с сугробом! -15 очков")

func _on_gift_hit_portal(collider):
	# Обрабатываем только входной портал
	if collider == entrance_portal:
		print("[HIT PORTAL] gift=", gift.position, " entrance=", entrance_portal.position if entrance_portal else null, " exit=", exit_portal.position if exit_portal else null)
		if exit_portal:
			await handle_portal_entry()
		else:
			# Астрал: вход без выхода
			subtract_score(30)
			reset_portals()
			respawn_gift()

func _on_gift_hit_super_portal(collider):
	add_score(75)
	reset_portals()
	respawn_gift()
	var sp = get_node_or_null("super_portal")
	if sp and is_instance_valid(sp):
		sp.queue_free()
	trigger_objects.erase("super_portal")

func setup_portal_signals():
	# Сигналы порталов подключаются в create_portal()
	pass


func reset_portals():
	# Удаляем оба портала
	if entrance_portal and is_instance_valid(entrance_portal):
		entrance_portal.queue_free()
	if exit_portal and is_instance_valid(exit_portal):
		exit_portal.queue_free()
	# Удаляем супер портал, если есть
	var sp = get_node_or_null("super_portal")
	if sp and is_instance_valid(sp):
		sp.queue_free()
	trigger_objects.erase("super_portal")

	# Сбрасываем переменные
	placed_portals = 0
	entrance_portal = null
	exit_portal = null

	# Сбрасываем использованные позиции порталов
	for portal in portals:
		portal.used = false
	wall_cells_free.clear()
	for key in wall_cells_base:
		wall_cells_free[key] = true

	# print("Порталы сброшены. Можно размещать новые!")
	initialize_portal_positions()

func spawn_gift():
	# Удаляем старый экземпляр, если есть
	if gift and is_instance_valid(gift):
		gift.queue_free()
	gift = null

	# Стартовая клетка подарка: берем выбранную для текущего уровня, при необходимости ищем ближайшую свободную
	var desired_pos = gift_start_pos
	var chosen_pos = desired_pos

	if not is_cell_free(desired_pos) or desired_pos.distance_to(santa_start_pos) < 6.0 or desired_pos.x == santa_start_pos.x:
		var candidate_cells: Array = []
		for x in range(-7, 8, 2):
			var pos = Vector3(x, 1.0, -7)
			if pos.distance_to(santa_start_pos) >= 6.0 and pos.x != santa_start_pos.x and is_cell_free(pos):
				candidate_cells.append(pos)
		if candidate_cells.size() > 0:
			chosen_pos = candidate_cells.pick_random()

	# Обновляем текущую стартовую позицию (фиксируем на уровне)
	gift_start_pos = chosen_pos

	# Создаем новый экземпляр
	if gift_scene:
		gift = gift_scene.instantiate()
		gift.name = "gift"
		gift.position = Vector3(gift_start_pos.x, gift_start_pos.y, gift_start_pos.z)  # старт по сетке (центр на уровне пола)
		# Применяем текущий глобальный множитель скорости
		gift.start_speed = gift_base_speed * gift_speed_multiplier
		gift.update_velocity()
		add_child(gift)
		setup_collision_signals()
		prev_gift_position = gift.position

func _input(event):
	# Левая кнопка мыши - для бонусов (лопаты, супер порталы)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not game_paused:
			if super_portal_mode and super_portals > 0:
				# Размещаем супер портал
				try_place_super_portal_at_mouse_position()
			elif shovels > 0:
				# Убираем сугроб
				try_remove_snowdrift_at_mouse_position()

	# Правая кнопка мыши - для обычных порталов
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if not game_paused:
			try_place_portal_at_mouse_position()

func create_walls():
	# Создаем 4 стены для квадратной арены 24x24 с клетками 2x2
	# Внутри: 10x10 клеток (24 - 2*2 = 20, 20/2 = 10)
	create_wall("wall_1", Vector3(0, 1.5, 11), Vector3(22, 3, 2), Color(0.8, 0.8, 0.8))  # Северная (Z=11)
	create_wall("wall_2", Vector3(0, 1.5, -11), Vector3(22, 3, 2), Color(0.7, 0.7, 0.7)) # Южная (Z=-11)
	create_wall("wall_3", Vector3(-11, 1.5, 0), Vector3(2, 3, 22), Color(0.6, 0.6, 0.6)) # Западная (X=-11)
	create_wall("wall_4", Vector3(11, 1.5, 0), Vector3(2, 3, 22), Color(0.5, 0.5, 0.5))  # Восточная (X=11)

func create_snowdrifts(count: int):
	# Арена 24x24, внутри 20x20 (за вычетом стен толщиной 2)
	# Сетка 10x10 клеток (20/2 = 10)
	snowdrift_cells.clear()
	var max_snowdrifts = 85  # защитный предел с учётом выреза вокруг старта подарка и Санты
	var target_count = min(count, max_snowdrifts)
	var available_positions = []

	for x in range(-9, 10, 2):  # От -9 до 9 с шагом 2 (10 клеток по X)
		for z in range(-9, 10, 2):  # От -9 до 9 с шагом 2 (10 клеток по Z)
			var pos = Vector3(x, 0.0, z)  # центр на уровне пола, сугроб утоплен на радиус
			# Проверяем, что позиция не слишком близка к стартовой точке подарка
			if pos.distance_to(gift_start_pos) > 4.0 \
				and pos.distance_to(santa_start_pos) > 1.0: # не ставим на Деда
				available_positions.append(pos)

	# Перемешиваем позиции для случайности
	available_positions.shuffle()

	# Создаем сугробы в первых count позициях
	for i in range(min(target_count, available_positions.size())):
		var pos = available_positions[i]
		create_snowdrift("snowdrift_" + str(i), pos)

func create_wall(wall_name: String, position: Vector3, size: Vector3, color: Color):
	# Создаем StaticBody3D
	var wall = StaticBody3D.new()
	wall.name = wall_name
	wall.position = position
	# Переводим стены в "рейкастовый" слой: только для наведения/подсветки
	wall.collision_layer = 8
	wall.collision_mask = 0
	add_child(wall)

	# Создаем MeshInstance3D с BoxMesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh

	# Создаем материал
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	# Делаем южную стену (Z=-11) полупрозрачной, чтобы видеть объекты за ней
	if wall_name == "wall_2":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.15
	mesh_instance.material_override = material

	wall.add_child(mesh_instance)

	# Создаем CollisionShape3D с BoxShape
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	# Утопим коллизию внутрь: уменьшаем толщину и сдвигаем shape внутрь стены
	var collision_size = size
	var offset = Vector3.ZERO
	if size.x > size.z:
		# Толщина по Z, двигаем внутрь по Z
		collision_size.z = max(0.1, size.z * 0.4)  # тоньше во столько раз
		offset.z = -sign(position.z) * (size.z - collision_size.z) * 0.5
	else:
		# Толщина по X
		collision_size.x = max(0.1, size.x * 0.4)
		offset.x = -sign(position.x) * (size.x - collision_size.x) * 0.5
	box_shape.size = collision_size
	collision_shape.shape = box_shape
	collision_shape.position = offset

	wall.add_child(collision_shape)

func try_place_super_portal_at_mouse_position():
	# Получаем камеру
	var camera = $Camera3D
	if not camera:
		return

	# Получаем позицию мыши на экране
	var mouse_pos = get_viewport().get_mouse_position()

	# Создаем raycast от камеры через позицию мыши
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)

	# Создаем PhysicsRayQueryParameters3D для raycast
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = ray_origin
	ray_params.to = ray_origin + ray_direction * 1000  # Дальность raycast
	ray_params.collide_with_areas = true
	ray_params.collide_with_bodies = true

	# Выполняем raycast
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(ray_params)

	# Проверяем, попали ли в пол (арену)
	if result and result.collider and result.collider.name == "floor":
		var hit_point = result.position
		# Снап к клетке 2x2 (центры в нечётных координатах) внутри арены
		var cell_x = snap_to_grid(hit_point.x)
		var cell_z = snap_to_grid(hit_point.z)
		if abs(cell_x) <= 9 and abs(cell_z) <= 9:
			var portal_pos = Vector3(cell_x, 1.2, cell_z) # ставим чуть выше пола
			if is_cell_free(portal_pos):
				create_super_portal("super_portal", portal_pos)
				trigger_objects["super_portal"] = {"pos": portal_pos, "radius": 1.5, "y_tol": 1.5, "kind": "super_portal"}
				super_portals -= 1
				super_portal_mode = false
				super_portal_button.text = "Супер портал"
				update_score_display()

func create_portal(portal_name: String, position: Vector3, is_exit: bool = false):
	# Статический объект, чтобы ловить коллизию подарка
	var portal = StaticBody3D.new()
	portal.name = portal_name
	portal.position = position
	# Порталы больше не участвуют в физколлизиях подарка, только рейкаст/позиционные проверки
	portal.collision_layer = 0
	portal.collision_mask = 0
	add_child(portal)

	# Создаем MeshInstance3D с BoxMesh (2x2x2) для визуала
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2.2, 2.0, 2.2)  # чуть больше клетки, чтобы выступал из стены
	mesh_instance.mesh = box_mesh

	# Создаем материал портала: вход белый, выход черный
	var material = StandardMaterial3D.new()
	if is_exit:
		material.albedo_color = Color(0, 0, 0, 1)  # Черный выход
		material.emission_enabled = true
		material.emission = Color(0.05, 0.05, 0.05, 1)
		material.emission_energy_multiplier = 0.4
	else:
		material.albedo_color = Color(1, 1, 1, 1)  # Белый вход
		material.emission_enabled = true
		material.emission = Color(0.8, 0.8, 0.8, 1)
		material.emission_energy_multiplier = 0.6
	mesh_instance.material_override = material

	portal.add_child(mesh_instance)

	# Коллизия портала: чуть больше клетки, вынесена от стены по нормали
	var normal = get_portal_normal(position)
	var collision_shape = CollisionShape3D.new()
	var collision_box = BoxShape3D.new()
	collision_box.size = Vector3(2.6, 2.0, 2.6)
	collision_shape.shape = collision_box
	collision_shape.position = normal * 1.0
	portal.add_child(collision_shape)

	return portal

func create_super_portal(portal_name: String, position: Vector3):
	# Статический объект, чтобы ловить коллизию подарка
	var portal = StaticBody3D.new()
	portal.name = portal_name
	portal.position = position
	portal.collision_layer = 0
	portal.collision_mask = 0
	add_child(portal)

	# Создаем MeshInstance3D с BoxMesh (2x2x2) для визуала
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2.2, 3.0, 2.2)  # выше и чуть шире клетки
	mesh_instance.mesh = box_mesh

	# Создаем оранжевый светящийся материал супер портала
	var super_portal_material = StandardMaterial3D.new()
	super_portal_material.albedo_color = Color(1.0, 0.55, 0.1, 1)  # Оранжевый
	super_portal_material.emission_enabled = true
	super_portal_material.emission = Color(1.0, 0.35, 0.05, 1)  # Оранжевая эмиссия
	super_portal_material.emission_energy_multiplier = 1.0
	mesh_instance.material_override = super_portal_material

	portal.add_child(mesh_instance)

	# Коллизия супер портала
	var collision_shape = CollisionShape3D.new()
	var collision_box = BoxShape3D.new()
	collision_box.size = Vector3(2.6, 3.0, 2.6)
	collision_shape.shape = collision_box
	portal.add_child(collision_shape)
	return portal

func create_snowdrift(snowdrift_name: String, position: Vector3):
	# Декорация без коллайдера; физику обрабатываем вручную через словарь клеток
	var snowdrift = Node3D.new()
	snowdrift.name = snowdrift_name
	# Сфера радиусом 1.0, центр на Y=0.5 — частично утоплена в пол (верх пола Y=0.5)
	snowdrift.position = Vector3(position.x, 0.5, position.z)
	snowdrift.add_to_group("snowdrifts")  # Добавляем в группу для управления
	add_child(snowdrift)

	# Mesh — сфера радиусом 1.0
	var mesh_instance = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0
	mesh_instance.mesh = sphere_mesh

	# Создаем материал снега
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.9, 1.0, 1)  # Белый с голубым оттенком
	mesh_instance.material_override = material

	snowdrift.add_child(mesh_instance)

	# Запоминаем клетку в словаре
	var cell_key = Vector2i(int(round(position.x)), int(round(position.z)))
	snowdrift_cells[cell_key] = snowdrift

func setup_ui():
	update_score_display()  # Обновит и очки, и уровень
	if pause_button:
		pause_button.process_mode = Node.PROCESS_MODE_ALWAYS  # Кнопка работает даже при паузе
		pause_button.connect("pressed", Callable(self, "_on_pause_pressed"))
	if restart_button:
		restart_button.connect("pressed", Callable(self, "_on_restart_pressed"))
	if super_portal_button:
		super_portal_button.connect("pressed", Callable(self, "_on_super_portal_pressed"))
	if mass_clear_button:
		mass_clear_button.connect("pressed", Callable(self, "_on_mass_clear_pressed"))
	if speed_reset_button:
		speed_reset_button.connect("pressed", Callable(self, "_on_speed_reset_pressed"))

func _on_pause_pressed():
	game_paused = !game_paused
	get_tree().paused = game_paused
	if pause_button:
		pause_button.text = "Продолжить" if game_paused else "Пауза"

func _on_super_portal_pressed():
	if super_portals > 0 and not super_portal_mode:
		super_portal_mode = true
	elif super_portal_mode:
		super_portal_mode = false
	update_score_display()

func _on_mass_clear_pressed():
	if mass_clears <= 0:
		return
	var cleared_count = snowdrift_cells.size()
	clear_all_snowdrifts()
	mass_clears = max(0, mass_clears - 1)
	add_score(10 * cleared_count)  # динамическая награда: 10 очков за каждый сугроб
	update_score_display()

func _on_speed_reset_pressed():
	if speed_resets <= 0:
		return
	if gift:
		gift_speed_multiplier = 1.0
		gift.start_speed = gift_base_speed * gift_speed_multiplier
		gift.update_velocity()
	speed_resets = max(0, speed_resets - 1)
	add_score(90)  # награда за сброс скорости
	update_score_display()

func _on_restart_pressed():
	finish_run_and_show_game_over()

func add_score(points: int):
	score += points

	# Проверяем повышение уровня с прогрессией требования: старт 100, +50 за уровень
	if score >= next_level_score_requirement:
		level += 1
		next_level_score_requirement += 50
		increase_difficulty()

	update_score_display()

func subtract_score(points: int):
	score -= points
	if score < 0:
		score = 0
	update_score_display()

func increase_difficulty():
	# Сбрасываем порталы при новом уровне
	reset_portals()

	# Сбрасываем очки при переходе на новый уровень (запрос пользователя)
	score = 0
	update_score_display()

	# С вероятностью 5% выдаём случайный бонус (глобальный ресурс)
	grant_random_bonus_on_level_up()

	# Начисляем монеты за достигнутый уровень (прогрессия: 2-й =10, 3-й =11, далее +1 за уровень)
	grant_coins_for_level(level)
	print("[LEVEL UP] level=", level, " coins_run_gain=", coins_run_gain)

	# Выбираем новую стартовую клетку подарка для нового уровня
	select_level_start_position()

	# Увеличиваем скорость подарка (глобальный множитель)
	gift_speed_multiplier *= 1.1  # +10% скорости
	if gift:
		gift.start_speed = gift_base_speed * gift_speed_multiplier
		gift.update_velocity()   # Обновляем текущую скорость подарка

	# Респавним подарок и Санту по текущим правилам, чтобы сохранить дистанцию и свободные клетки
	respawn_gift()
	respawn_santa()

	# Обновляем сугробы (количество = уровню)
	clear_all_snowdrifts()
	create_snowdrifts(level)  # Создаем новые (столько, сколько уровень)

	update_score_display()  # Обновляем UI
	# print("Уровень ", level, " достигнут! Скорость: ", gift.start_speed, ", Сугробов: ", level, ", Лопат: ", shovels)

func grant_coins_for_level(lvl: int):
	if lvl <= 1:
		return
	var reward = 8 + lvl  # lvl2 ->10, lvl3 ->11, lvl4 ->12 ...
	coins_run_gain += reward
	coins += reward
	update_score_display()

func create_game_over_ui():
	# Создаём простой оверлей для итога забега
	var panel = Panel.new()
	panel.name = "GameOverPanel"
	panel.visible = false
	panel.modulate = Color(0, 0, 0, 0.75)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0

	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Гейм-овер"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title)

	var coins_label = Label.new()
	coins_label.name = "CoinsLabel"
	coins_label.text = "Монет за забег: 0"
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_label.add_theme_font_size_override("font_size", 22)
	coins_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(coins_label)

	var total_label = Label.new()
	total_label.name = "TotalCoinsLabel"
	total_label.text = "Всего монет: 0"
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 18)
	total_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(total_label)

	var level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Достигнутый уровень: 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(level_label)

	var restart_btn = Button.new()
	restart_btn.text = "Начать заново"
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	restart_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
	)
	vbox.add_child(restart_btn)

	var close_btn = Button.new()
	close_btn.text = "Закрыть (продолжить)"
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close_btn.pressed.connect(func():
		panel.visible = false
		get_tree().paused = false
	)
	vbox.add_child(close_btn)

	canvas_layer.add_child(panel)
	game_over_panel = panel

func finish_run_and_show_game_over():
	if game_over_panel == null:
		return

	# Финализируем монеты за забег
	var coins_before = coins
	coins += coins_run_gain
	print("[RUN END] level=", level, " coins_run_gain=", coins_run_gain, " coins_before=", coins_before, " coins_after=", coins)
	update_score_display()

	# Обновляем UI панели
	var coins_label: Label = game_over_panel.get_node("CoinsLabel")
	var total_label: Label = game_over_panel.get_node("TotalCoinsLabel")
	var level_label: Label = game_over_panel.get_node("LevelLabel")
	if coins_label:
		coins_label.text = "Монет за забег: %d" % coins_run_gain
	if total_label:
		total_label.text = "Всего монет: %d" % coins
	if level_label:
		level_label.text = "Достигнутый уровень: %d" % level

	# Показываем оверлей и паузим мир (UI продолжает работать)
	get_tree().paused = true
	game_over_panel.visible = true

	# Сбрасываем набранные монеты для следующего забега
	coins_run_gain = 0

func grant_random_bonus_on_level_up():
	var roll = randf()
	if roll <= 0.95:
		var pool = ["shovel", "super_portal", "mass_clear", "speed_reset"]
		pool.shuffle()
		var pick = pool[0]
		match pick:
			"shovel":
				shovels += 1
			"super_portal":
				super_portals += 1
			"mass_clear":
				mass_clears += 1
			"speed_reset":
				speed_resets += 1

func select_level_start_position():
	# Выбираем новую стартовую позицию подарка на ряд Z = -7, чтобы разнообразить уровни
	var candidate_cells: Array = []
	for x in range(-7, 8, 2):
		var pos = Vector3(x, 1.0, -7)  # центр подарка на уровне пола (без коллизий с полом)
		if pos.distance_to(santa_start_pos) >= 6.0 and pos.x != santa_start_pos.x and is_cell_free(pos):
			candidate_cells.append(pos)

	if candidate_cells.size() > 0:
		var chosen = candidate_cells.pick_random()
		gift_start_pos = chosen
		initial_gift_start_pos = chosen

func place_exit_portal():
	# Размещаем портал выхода у Деда Мороза (автоматически)
	var exit_position = Vector3(santa_start_pos.x, 1.5, santa_start_pos.z)  # Позиция Деда Мороза по сетке
	create_portal("exit_portal", exit_position, true)
	# print("Портал выхода размещен у Деда Мороза")

func init_actor_positions():
	# Допустимые клетки для подарка: ряд Z = -7, X от -7 до 7
	var gift_cells: Array = []
	for x in range(-7, 8, 2):
		gift_cells.append(Vector3(x, 1.0, -7)) # тонкая настройка высоты для избежания коллизий с полом
	gift_cells.shuffle()

	# Старт подарка из списка допустимых
	gift_start_pos = Vector3(0, 1.0, -7) # центр подарка на уровне пола (без коллизий с полом)
	if gift_cells.size() > 0:
		gift_start_pos = gift_cells.pop_front()
	initial_gift_start_pos = gift_start_pos
	gift_start_initialized = true

	# Клетки для Деда Мороза: вся сетка 10x10 (центры в нечётных координатах)
	var santa_cells: Array = []
	for x in range(-9, 10, 2):
		for z in range(-9, 10, 2):
			santa_cells.append(Vector3(x, 1.0, z))

	santa_cells.shuffle()

	# Старт Деда Мороза — минимум 3 клетки (>=6 ед.) от подарка, X не совпадает с подарком
	var min_dist = 6.0
	santa_start_pos = Vector3(0, 1.0, 5)
	for c in santa_cells:
		if c.distance_to(gift_start_pos) >= min_dist and c.x != gift_start_pos.x:
			santa_start_pos = Vector3(c.x, 1.0, c.z)
			break

	# Инициализируем позиционный триггер Санты
	trigger_objects["santa"] = {"pos": santa_start_pos, "radius": 1.0, "y_tol": 1.0, "kind": "santa"}

func initialize_portal_positions():
	# Порталы размещаются ТОЛЬКО на стенах арены!
	# Арена 24x24, стены на расстоянии 12 от центра
	portals.clear() # Очищаем старые позиции
	wall_cells_base.clear()
	wall_cells_free.clear()

	# Северная стена (Z = 12)
	for x in range(-10, 11, 2):  # От -10 до 10 с шагом 2
		var pos = Vector3(x, 1.5, 11)
		if pos.distance_to(gift_start_pos) > 6.0: # Не слишком близко к старту
			portals.append({"position": pos, "used": false})
			var cell_key = Vector2i(int(round(pos.x)), int(round(pos.z)))
			wall_cells_base.append(cell_key)
			wall_cells_free[cell_key] = true

	# Южная стена (Z = -12)
	for x in range(-10, 11, 2):  # От -10 до 10 с шагом 2
		var pos = Vector3(x, 1.5, -11)
		if pos.distance_to(gift_start_pos) > 6.0: # Не слишком близко к старту
			portals.append({"position": pos, "used": false})
			var cell_key = Vector2i(int(round(pos.x)), int(round(pos.z)))
			wall_cells_base.append(cell_key)
			wall_cells_free[cell_key] = true

	# Западная стена (X = -12)
	for z in range(-10, 11, 2):  # От -10 до 10 с шагом 2
		var pos = Vector3(-11, 1.5, z)
		if pos.distance_to(gift_start_pos) > 6.0: # Не слишком близко к старту
			portals.append({"position": pos, "used": false})
			var cell_key = Vector2i(int(round(pos.x)), int(round(pos.z)))
			wall_cells_base.append(cell_key)
			wall_cells_free[cell_key] = true

	# Восточная стена (X = 12)
	for z in range(-10, 11, 2):  # От -10 до 10 с шагом 2
		var pos = Vector3(11, 1.5, z)
		if pos.distance_to(gift_start_pos) > 6.0: # Не слишком близко к старту
			portals.append({"position": pos, "used": false})
			var cell_key = Vector2i(int(round(pos.x)), int(round(pos.z)))
			wall_cells_base.append(cell_key)
			wall_cells_free[cell_key] = true

func try_place_portal_at_mouse_position():
	if placed_portals >= 2:
		return

	# Получаем камеру
	var camera = $Camera3D
	if not camera:
		return

	# Получаем позицию мыши на экране
	var mouse_pos = get_viewport().get_mouse_position()

	# Создаем raycast от камеры через позицию мыши
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)

	# Создаем PhysicsRayQueryParameters3D для raycast
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = ray_origin
	ray_params.to = ray_origin + ray_direction * 1000  # Дальность raycast
	ray_params.collide_with_areas = true
	ray_params.collide_with_bodies = true

	# Выполняем raycast
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(ray_params)

	if result:
		# Проверяем, попали ли в стену
		if result.collider and result.collider.name.begins_with("wall"):
			var hit_point = result.position

			# Привязываем портал к ближайшей клетке на стене
			var portal_pos = snap_portal_to_wall_cell(hit_point)

			if portal_pos:
				if placed_portals == 0:
					# Размещаем портал входа
					entrance_portal = create_portal("entrance_portal", portal_pos, false)
					var key = Vector2i(int(round(portal_pos.x)), int(round(portal_pos.z)))
					wall_cells_free.erase(key)
					placed_portals = 1
				else:
					exit_portal = create_portal("exit_portal", portal_pos, true)
					var key_exit = Vector2i(int(round(portal_pos.x)), int(round(portal_pos.z)))
					wall_cells_free.erase(key_exit)
					placed_portals = 2
					# Теперь порталы размещены - запускаем подарок
					var gift = $gift
					if gift:
						gift.update_velocity()

func find_nearest_portal_cell(hit_point: Vector3) -> Vector3:
	# Находим ближайшую свободную клетку для портала
	var nearest_pos = null
	var min_distance = 9999

	for portal in portals:
		if not portal.used and is_cell_free(portal.position):
			var distance = hit_point.distance_to(portal.position)
			if distance < min_distance:
				min_distance = distance
				nearest_pos = portal.position

	# Помечаем клетку как использованную
	if nearest_pos:
		for portal in portals:
			if portal.position == nearest_pos:
				portal.used = true
				break

	return nearest_pos

# Привязка точки попадания на стену к центру клеточной позиции портала
func snap_portal_to_wall_cell(hit_point: Vector3) -> Vector3:
	var wall_coord = 11.0
	# Клеточные центры по XZ: нечётные координаты от -9 до 9

	if abs(hit_point.x) > abs(hit_point.z):
		# Левая/правая стена, фиксируем X, снапим Z
		var x = sign(hit_point.x) * wall_coord
		var z = snap_to_grid(hit_point.z)
		return Vector3(x, 1.5, z)
	else:
		# Верх/низ, фиксируем Z, снапим X
		var z = sign(hit_point.z) * wall_coord
		var x = snap_to_grid(hit_point.x)
		return Vector3(x, 1.5, z)

# Снап значения к центру клетки 2x2 в пределах [-9..9]
func snap_to_grid(value: float) -> float:
	return clamp(floor(value / 2.0) * 2.0 + 1.0, -9.0, 9.0)

func is_cell_free(cell_position: Vector3) -> bool:
	# Проверяем, свободна ли клетка

	# 1. Проверяем расстояние до подарка (клетка занята если подарок в ней)
	if gift and cell_position.distance_to(gift.position) < 1.5:
		return false

	# 2. Проверяем наличие сугробов в клетке по словарю
	var cell_key = Vector2i(int(round(cell_position.x)), int(round(cell_position.z)))
	if snowdrift_cells.has(cell_key):
		return false

	# 3. Проверяем наличие порталов в клетке
	var existing_entrance = get_node_or_null("entrance_portal")
	var existing_exit = get_node_or_null("exit_portal")
	var existing_super = get_node_or_null("super_portal")

	if existing_entrance and cell_position.distance_to(existing_entrance.position) < 1.5:
		return false
	if existing_exit and cell_position.distance_to(existing_exit.position) < 1.5:
		return false
	if existing_super and cell_position.distance_to(existing_super.position) < 1.5:
		return false

	# Клетка свободна
	return true

# Анимация входа/выхода через портал с отключением коллизий
func handle_portal_entry():
	if entrance_portal == null:
		return

	# Сохранить слои коллизий и выключить
	var old_layer = gift.collision_layer
	var old_mask = gift.collision_mask
	gift.collision_layer = 0
	gift.collision_mask = 0

	# Небольшой флеш на входном портале и подарке
	flash_mesh(gift)
	flash_mesh(entrance_portal)

	# Остановить движение
	gift.is_moving = false
	gift.velocity = Vector3.ZERO

	# Мгновенно ставим в центр входного портала
	gift.position = Vector3(entrance_portal.position.x, gift.position.y, entrance_portal.position.z)

	if exit_portal:
		# Телепорт к выходу и выкатывание наружу
		var normal = get_portal_normal(exit_portal.position)
		var new_y = 1.25  # центр подарка чуть выше пола, чтобы не тонуть
		var offset_from_wall = 2.0  # вынос от стены глубже в арену
		var prev_pos = gift.position
		gift.position = Vector3(exit_portal.position.x, new_y, exit_portal.position.z) + normal * offset_from_wall
		prev_gift_position = gift.position
		print("[PORTAL EXIT] prev_pos=", prev_pos, " new_pos=", gift.position, " normal=", normal, " exit_y=", exit_portal.position.y, " new_y=", new_y, " offset=", offset_from_wall)
		# Направление: по нормали стены внутрь арены
		gift.direction = normal
		gift.velocity = normal.normalized() * gift.start_speed
		gift.update_velocity()
		print("[AFTER EXIT MOVE] gift_dir=", gift.direction, " vel=", gift.velocity)
		flash_mesh(gift)
		flash_mesh(exit_portal)

		# Включить движение
		gift.is_moving = true

		# Убираем порталы сразу после выхода, чтобы не было повторных касаний/зацикливаний
		reset_portals()
	else:
		# Астрал: вход есть, выхода нет
		subtract_score(30)
		reset_portals()
		respawn_gift()

	# Вернуть коллизии
	gift.collision_layer = old_layer
	gift.collision_mask = old_mask

func get_portal_normal(pos: Vector3) -> Vector3:
	# Определяем нормаль по доминирующей координате: если |X| > |Z| — стена по X, иначе по Z
	if abs(pos.x) > abs(pos.z):
		return Vector3(-sign(pos.x), 0, 0)  # восточная/западная стены
	else:
		return Vector3(0, 0, -sign(pos.z))  # северная/южная стены

func create_portal_at_position(position: Vector3):
	# Создаем портал в указанной позиции
	create_portal("portal_" + str(portals.size()), position)

func try_remove_snowdrift_at_mouse_position():
	# Получаем камеру
	var camera = $Camera3D
	if not camera:
		return

	# Получаем позицию мыши на экране
	var mouse_pos = get_viewport().get_mouse_position()

	# Создаем raycast от камеры через позицию мыши
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)

	# Создаем PhysicsRayQueryParameters3D для raycast
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = ray_origin
	ray_params.to = ray_origin + ray_direction * 1000  # Дальность raycast
	ray_params.collide_with_areas = true
	ray_params.collide_with_bodies = true

	# Выполняем raycast
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(ray_params)

	# Проверяем попадание в пол или в сугроб (через декорацию)
	if result and result.collider:
		if result.collider.name == "floor" or result.collider.name.begins_with("snowdrift"):
			var hit_point = result.position
			var cell_x = snap_to_grid(hit_point.x)
			var cell_z = snap_to_grid(hit_point.z)
			var cell_key = Vector2i(int(cell_x), int(cell_z))
			if snowdrift_cells.has(cell_key):
				var snowdrift_node = snowdrift_cells[cell_key]
				if is_instance_valid(snowdrift_node):
					snowdrift_node.queue_free()
				snowdrift_cells.erase(cell_key)
				shovels = max(0, shovels - 1)
				add_score(10)  # награда за уборку сугроба
				update_score_display()

func clear_all_snowdrifts():
	for s in snowdrift_cells.values():
		if is_instance_valid(s):
			s.queue_free()
	snowdrift_cells.clear()

func update_score_display():
	if score_label:
		score_label.text = "Очки: " + str(score)
	if level_label:
		level_label.text = "Уровень: " + str(level)
	if coins_label:
		coins_label.text = "Монеты: %d (+%d)" % [coins, coins_run_gain]
	if shovel_label:
		shovel_label.text = "Лопаты: " + str(shovels)
	if super_portal_button:
		var sp_label = "Супер портал: " + str(super_portals)
		if super_portal_mode:
			sp_label = "Отмена (" + str(super_portals) + ")"
		super_portal_button.text = sp_label
	if mass_clear_button:
		mass_clear_button.text = "Массовая очистка: " + str(mass_clears)
	if speed_reset_button:
		speed_reset_button.text = "Сброс скорости: " + str(speed_resets)

# Функция для респавна подарка (будет использоваться позже)
func respawn_gift():
	spawn_gift()

# Респавн Санты: не ближе 3 клеток (6 ед.) к подарку, X не совпадает, клетка свободна
func respawn_santa():
	var santa_cells: Array = []
	for x in range(-9, 10, 2):
		for z in range(-9, 10, 2):
			santa_cells.append(Vector3(x, 1.0, z))
	santa_cells.shuffle()

	var min_dist = 6.0
	var gift_pos = gift.position if gift else gift_start_pos
	for c in santa_cells:
		if c.distance_to(gift_pos) >= min_dist and c.x != gift_pos.x and is_cell_free(c):
			santa_start_pos = Vector3(c.x, 1.0, c.z)
			var santa_node = $"santa"
			if santa_node:
				santa_node.position = santa_start_pos
			trigger_objects["santa"] = {"pos": santa_start_pos, "radius": 1.0, "y_tol": 1.0, "kind": "santa"}
			return
