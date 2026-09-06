class_name Enemy
extends Node3D
## 追逐玩家的方块动物 AI。
## 采用纯逻辑移动（不参与物理碰撞），因此根节点用 Node3D 即可，
## 致死判定用的 Area3D 与模型平级挂在它下面。
##
## 行为：
##  1. 目标车道跟随玩家（含反应延迟 + 少量判断失误，让 AI 不至于完美）；
##  2. 前视 ENEMY_LOOK_AHEAD 米检测障碍，被挡则切到最近的空闲车道；
##  3. 橡皮筋调速：落后太多会加速追击，贴身时略微减速，给玩家甩开的机会；
##  4. 落后超过 ENEMY_DESPAWN_BEHIND 米或被玩家远远甩开则回收进对象池。

var speed: float = 0.0
var lane: int = 2
var active: bool = false
## 行为原型索引（GameConfig.ENEMY_KINDS）
var kind_index: int = 0

var _world: World
var _pivot: Node3D
var _model: Node3D
var _hazard: Area3D
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _legs: Array[Node3D] = []
var _leg_rest_rot: Array[Vector3] = []

var _think_timer := 0.0
var _bob_time := 0.0
var _lean := 0.0
var _animal_file: String = ""

# --- 原型参数（spawn 时从 ENEMY_KINDS 展开，避免每帧查字典）---
var _k_speed := 1.0
var _k_lane_switch := 1.0
var _k_think := 1.0
var _k_miss := 0.2
var _k_burst := 0.0
var _k_can_jump := false
var _k_lock_lane := false

# --- 冲刺 / 跳跃状态 ---
var _burst_timer := 0.0
var _burst_left := 0.0
var _jump_vy := 0.0
var _jump_y := 0.0


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "ModelPivot"
	add_child(_pivot)

	_build_hazard()
	_build_marker()

	set_physics_process(false)
	visible = false


## 头顶的原型标记（发光小方块）
func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = "KindMarker"
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.34, 0.34)
	_marker.mesh = box
	_marker.position.y = GameConfig.ENEMY_HEIGHT + 0.45
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.emission_enabled = true
	_marker_mat.emission_energy = 1.5
	_marker_mat.roughness = 0.4
	_marker.material_override = _marker_mat
	_marker.visible = false
	add_child(_marker)


func _build_hazard() -> void:
	_hazard = Area3D.new()
	_hazard.name = "Hazard"
	_hazard.collision_layer = GameConfig.LAYER_HAZARD
	_hazard.collision_mask = GameConfig.LAYER_PLAYER
	_hazard.monitoring = false
	_hazard.monitorable = false

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.4, 1.2)
	col.shape = box
	col.position.y = 0.7
	_hazard.add_child(col)

	add_child(_hazard)
	_hazard.body_entered.connect(_on_hazard_body_entered)


## 撞上玩家：扣 1 点生命，并把追兵弹开，避免连续掉血
func _on_hazard_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return
	var p := body as Player
	if p.take_hit():
		position.z += GameConfig.ENEMY_KNOCKBACK
		speed *= 0.7


# ---------------------------------------------------------------- 对象池
func spawn(world: World, spawn_lane: int, z: float, spawn_speed: float, animal_file: String,
		kind: int = 0) -> void:
	_world = world
	lane = GameConfig.clamp_lane(spawn_lane)
	speed = spawn_speed
	active = true
	_think_timer = 0.0
	_lean = 0.0

	# 展开原型参数
	kind_index = kind
	var k := GameConfig.enemy_kind(kind)
	_k_speed = float(k["speed"])
	_k_lane_switch = float(k["lane_switch"])
	_k_think = float(k["think"])
	_k_miss = float(k["miss"])
	_k_burst = float(k["burst"])
	_k_can_jump = bool(k["can_jump"])
	_k_lock_lane = bool(k["lock_lane"])

	_burst_left = 0.0
	_burst_timer = randf_range(GameConfig.ENEMY_BURST_MIN, GameConfig.ENEMY_BURST_MAX)
	_jump_vy = 0.0
	_jump_y = 0.0

	position = Vector3(GameConfig.lane_x(lane), 0.0, z)
	_set_animal(animal_file)
	# 头顶发光标记：从俯视视角一眼就能分辨是哪种追兵
	_marker_mat.albedo_color = k["tint"]
	_marker_mat.emission = k["tint"]
	_marker.visible = kind != 0  # 普通追猎者不加标记，避免画面太吵

	visible = true
	_hazard.monitoring = true
	set_physics_process(true)


func despawn() -> void:
	active = false
	visible = false
	_hazard.monitoring = false
	set_physics_process(false)
	speed = 0.0


func _set_animal(animal_file: String) -> void:
	if animal_file == _animal_file and _model != null:
		return
	_animal_file = animal_file

	if _model != null:
		_pivot.remove_child(_model)
		_model.queue_free()

	_model = AnimalModel.create(animal_file, GameConfig.ENEMY_HEIGHT, 180.0)
	_pivot.add_child(_model)
	_pivot.rotation = Vector3.ZERO
	_pivot.position = Vector3.ZERO

	_legs.clear()
	_leg_rest_rot.clear()
	AnimalModel.collect_parts(_model, "leg", _legs)
	for leg in _legs:
		_leg_rest_rot.append(leg.rotation)


# ---------------------------------------------------------------- AI
func _physics_process(delta: float) -> void:
	if not active or _world == null or not _world.player.alive or not _world.running:
		return

	var player := _world.player

	# --- 决策（带反应延迟，原型不同则快慢不同）---
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = randf_range(
			GameConfig.ENEMY_THINK_MIN, GameConfig.ENEMY_THINK_MAX) * _k_think
		_decide_lane(player)

	# --- 横向移动 ---
	var target_x := GameConfig.lane_x(lane)
	position.x = move_toward(position.x, target_x,
		GameConfig.ENEMY_LANE_SWITCH * _k_lane_switch * delta)

	# --- 前进（沿 -Z）---
	position.z -= speed * delta

	# --- 坑洞：所有原型都会跳（否则会出现「凌空跑过深渊」的穿帮）---
	if _jump_y <= 0.01 and _jump_vy == 0.0:
		if _world.pit_ahead(position.z, maxf(speed * 0.35, 5.0)):
			_start_jump()

	_update_burst(delta)
	_update_jump(delta)
	_adjust_speed(delta, player)
	_animate(delta, player)

	# --- 回收 ---
	var gap := position.z - player.position.z
	if gap > GameConfig.ENEMY_DESPAWN_BEHIND or gap < -25.0:
		_world.recycle_enemy(self)


## 选一条「既安全又靠近玩家」的车道
func _decide_lane(player: Player) -> void:
	# 按原型概率反应慢半拍，保持原车道（封路者几乎不失误）
	if randf() < _k_miss:
		return

	# 封路者预判玩家的换道方向，抢先一步堵在他要去的车道上
	var desired := player.target_lane
	if _k_lock_lane:
		var drift := player.target_lane - player.lane
		if drift != 0:
			desired = GameConfig.clamp_lane(player.target_lane + signi(drift))

	var cur_blocked := _world.lane_blocked_ahead(position.z, lane, GameConfig.ENEMY_LOOK_AHEAD)

	# 跳跃者遇到矮栏直接起跳，不绕路（威胁性更强）
	if _k_can_jump and cur_blocked and _jump_y <= 0.01:
		_start_jump()
		return

	if cur_blocked or _world.lane_blocked_ahead(position.z, desired, GameConfig.ENEMY_LOOK_AHEAD):
		var free_lane := _world.find_free_lane(position.z, desired, GameConfig.ENEMY_LOOK_AHEAD)
		if free_lane >= 0:
			desired = free_lane
		elif cur_blocked:
			# 找不到完全空闲的车道就先躲开当前这条
			var alt := _world.find_free_lane(position.z, lane, GameConfig.ENEMY_LOOK_AHEAD * 0.5)
			if alt >= 0:
				desired = alt

	if desired != lane:
		lane = GameConfig.clamp_lane(desired)


# ---------------------------------------------------------------- 冲刺 / 跳跃
## 冲刺者：周期性爆发提速，制造「突然被逼近」的紧张感
func _update_burst(delta: float) -> void:
	if _k_burst <= 0.0:
		return
	if _burst_left > 0.0:
		_burst_left -= delta
		return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_burst_timer = randf_range(GameConfig.ENEMY_BURST_MIN, GameConfig.ENEMY_BURST_MAX)
		_burst_left = GameConfig.ENEMY_BURST_TIME


## 跳跃者：跨越坑洞与矮栏。纯动画位移，不参与物理
func _start_jump() -> void:
	_jump_vy = GameConfig.ENEMY_JUMP_VELOCITY
	Sfx.play("enemy_jump", randf_range(0.95, 1.08), -8.0)


func _update_jump(delta: float) -> void:
	if _jump_vy == 0.0 and _jump_y <= 0.0:
		return
	_jump_y += _jump_vy * delta
	_jump_vy += GameConfig.GRAVITY * delta
	if _jump_y <= 0.0:
		_jump_y = 0.0
		_jump_vy = 0.0


## 橡皮筋速度：落后追、贴身缓、超车减速
func _adjust_speed(delta: float, player: Player) -> void:
	var gap := position.z - player.position.z  # > 0 表示敌人在玩家后方
	var base := player.forward_speed * _world.enemy_speed_factor() * _k_speed
	var desired: float

	if gap > 30.0:
		desired = base * GameConfig.ENEMY_CHASE_FAR
	elif gap > 12.0:
		desired = base * GameConfig.ENEMY_CHASE_MID
	elif gap > 2.0:
		desired = base * GameConfig.ENEMY_CHASE_NEAR
	else:
		desired = base * GameConfig.ENEMY_CHASE_CONTACT

	# 冲刺爆发期间大幅提速
	if _burst_left > 0.0:
		desired *= 1.0 + _k_burst

	# 爆发时加速度也翻倍，让「窜出来」的感觉更明显
	var accel := GameConfig.ENEMY_ACCEL * (2.2 if _burst_left > 0.0 else 1.0)
	speed = move_toward(speed, desired, accel * delta)
	speed = maxf(speed, GameConfig.BASE_SPEED * 0.5)


func _animate(delta: float, player: Player) -> void:
	_bob_time += delta * (4.0 + speed * 0.42)
	# 起跳期间用抛物线高度替代跑动颠簸
	if _jump_y > 0.0:
		_pivot.position.y = _jump_y
	else:
		_pivot.position.y = absf(sin(_bob_time)) * 0.13
	if _marker.visible:
		_marker.position.y = GameConfig.ENEMY_HEIGHT + 0.45 + _pivot.position.y
		_marker.rotation.y += delta * 2.2

	for i in _legs.size():
		var phase := _bob_time + (PI if i % 2 == 0 else 0.0)
		_legs[i].rotation.x = _leg_rest_rot[i].x + sin(phase) * 0.6

	var dx := GameConfig.lane_x(lane) - position.x
	_lean = move_toward(_lean, clampf(-dx * 0.05, -0.3, 0.3), delta * 8.0)
	_pivot.rotation.z = _lean
	_pivot.rotation.y = clampf(-dx * 0.06, -0.4, 0.4)

	# 距离过近时轻微前倾，制造压迫感
	if absf(position.z - player.position.z) < 6.0:
		_pivot.rotation.x = move_toward(_pivot.rotation.x, -0.18, delta * 4.0)
	else:
		_pivot.rotation.x = move_toward(_pivot.rotation.x, 0.0, delta * 4.0)
