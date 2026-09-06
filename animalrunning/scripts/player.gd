class_name Player
extends CharacterBody3D
## 玩家：方块动物。
## 自动向前奔跑（World 每帧写入 forward_speed），玩家负责换道 / 跳跃 / 快速下落。
## 支持键盘（A/D、←/→、空格、W/S）与触屏滑动（←/→ 换道、↑ 跳、↓ 快落）。
##
## 受击：撞到障碍或被追兵碰到扣 1 点生命，随后进入无敌（可穿过障碍）并短暂减速；
## 生命归零或掉出地面则本局结束。死亡判定由外部 Hazard 区域触发，另有兜底卡死检测。

signal died
signal hp_changed(hp: int, max_hp: int)
signal hit_taken

## 横向加速度上限。traction = 1.0 时几乎瞬时响应，低抓地力下才会明显打滑
const LANE_ACCEL := 240.0
## 滑出赛道边缘的余量（不允许直接滑进虚空）
const EDGE_MARGIN := 0.45
## 低于此高度即认定「正在坠入坑洞」，用于播放坠落音
const FALLING_Y := -1.5

## 由 World 每帧写入的基础前进速度（未计入角色倍率）
var forward_speed: float = 0.0
## 地面抓地力（由关卡主题决定）。1.0 为正常；越低则换道越飘、会滑过头
var traction: float = 1.0
var lane: int = 2
var target_lane: int = 2
var alive: bool = false
var running: bool = false

var max_hp: int = 3
var hp: int = 3

var _speed_mul: float = 1.0
var _jump_mul: float = 1.0
var _lane_mul: float = 1.0

var _model_pivot: Node3D
var _model: Node3D
var _legs: Array[Node3D] = []
var _leg_rest_rot: Array[Vector3] = []

var _jump_buffer := 0.0
var _fast_fall := false
var _bob_time := 0.0
var _lean := 0.0
var _stuck_frames := 0
var _invincible := 0.0
var _hit_slow := 0.0

# 音效用：落地检测与脚步节奏
var _was_on_floor := true
var _last_step := 0
var _falling := false

var _swipe_start := Vector2.ZERO
var _swipe_used := false


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PLAYER
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_OBSTACLE

	_build_collision()

	_model_pivot = Node3D.new()
	_model_pivot.name = "ModelPivot"
	add_child(_model_pivot)

	# 先套用默认角色，保证任何时刻都有可见模型；开局时会被 setup() 覆盖
	setup(GameConfig.character(0), 3)
	reset()


# ---------------------------------------------------------------- 构建
func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.5
	col.shape = capsule
	col.position.y = 0.8
	add_child(col)


## 应用角色配置（外观 + 属性倍率），并设定本局生命上限
func setup(character: Dictionary, hp_value: int) -> void:
	_speed_mul = float(character.get("speed", 1.0))
	_jump_mul = float(character.get("jump", 1.0))
	_lane_mul = float(character.get("lane", 1.0))
	max_hp = maxi(1, hp_value)
	hp = max_hp
	_rebuild_model(String(character.get("file", "animal-panda.glb")))
	emit_signal("hp_changed", hp, max_hp)


func _rebuild_model(file_name: String) -> void:
	if _model != null:
		_model_pivot.remove_child(_model)
		_model.queue_free()

	_model = AnimalModel.create(file_name, GameConfig.PLAYER_HEIGHT, 180.0)
	_model_pivot.add_child(_model)

	_legs.clear()
	_leg_rest_rot.clear()
	AnimalModel.collect_parts(_model, "leg", _legs)
	for leg in _legs:
		_leg_rest_rot.append(leg.rotation)


# ---------------------------------------------------------------- 生命周期
func reset() -> void:
	lane = GameConfig.LANE_COUNT / 2
	target_lane = lane
	alive = true
	running = false
	hp = max_hp
	velocity = Vector3.ZERO
	_bob_time = 0.0
	_lean = 0.0
	_jump_buffer = 0.0
	_fast_fall = false
	_stuck_frames = 0
	_invincible = 0.0
	_hit_slow = 0.0
	_was_on_floor = true
	_last_step = 0
	_falling = false

	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_OBSTACLE
	position = Vector3(GameConfig.lane_x(lane), 0.05, GameConfig.PLAYER_START_Z)
	_model_pivot.rotation = Vector3.ZERO
	_model_pivot.position = Vector3.ZERO
	if _model != null:
		_model.visible = true


func die() -> void:
	if not alive:
		return
	alive = false
	running = false
	hp = 0
	velocity = Vector3.ZERO
	emit_signal("hp_changed", hp, max_hp)
	Sfx.play("death")

	# 倒地动画
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_model_pivot, "rotation_degrees:z", -85.0, 0.35)
	tween.tween_property(_model_pivot, "position:y", 0.25, 0.35)

	emit_signal("died")


## 受到一次伤害，返回是否真的扣血（无敌期间或非对局中返回 false）
func take_hit() -> bool:
	if not alive or not running or _invincible > 0.0:
		return false

	hp -= 1
	_invincible = GameConfig.INVINCIBLE_TIME
	_hit_slow = GameConfig.HIT_RECOVER_TIME
	_stuck_frames = 0
	# 无敌期间可穿过障碍物，避免卡在障碍里连续掉血
	collision_mask = GameConfig.LAYER_WORLD

	emit_signal("hit_taken")
	emit_signal("hp_changed", hp, max_hp)

	if hp <= 0:
		die()
	else:
		# 只剩 1 点生命时音调更高更急，听觉上就能感到危险
		Sfx.play("hit", 1.16 if hp == 1 else 1.0)
	return true


## 回复生命，返回是否真的回上了（满血时返回 false，让计数器不被白白清零）
func heal(amount: int) -> bool:
	if not alive or hp >= max_hp:
		return false
	hp = mini(hp + amount, max_hp)
	emit_signal("hp_changed", hp, max_hp)
	Sfx.play("heal")
	return true


func is_invincible() -> bool:
	return _invincible > 0.0


# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if not alive:
		return

	_update_invincible(delta)

	# --- 前进（含角色速度倍率与受击减速）---
	var speed_now := forward_speed
	if _hit_slow > 0.0:
		_hit_slow -= delta
		var t := clampf(_hit_slow / GameConfig.HIT_RECOVER_TIME, 0.0, 1.0)
		speed_now *= lerpf(1.0, GameConfig.HIT_SPEED_MUL, t)
	speed_now *= _speed_mul

	if running:
		velocity.z = -speed_now
	else:
		velocity.z = move_toward(velocity.z, 0.0, 60.0 * delta)

	# --- 换道（带横向惯性；抓地力越低越容易滑过头）---
	var target_x := GameConfig.lane_x(target_lane)
	var dx := target_x - position.x
	var lane_speed := GameConfig.LANE_SWITCH_SPEED * _lane_mul
	var desired_vx := clampf(dx * 14.0, -lane_speed, lane_speed)
	# 关键：不再直接赋值横向速度，而是以有限加速度逼近。
	# 冰面（traction 低）下加速与刹车都变慢，于是会滑过目标车道再荡回来。
	velocity.x = move_toward(velocity.x, desired_vx, LANE_ACCEL * traction * delta)
	# 必须「停稳」才算完成换道，否则滑行途中会被误判为已到位
	if absf(dx) < 0.06 and absf(velocity.x) < 1.2:
		position.x = target_x
		velocity.x = 0.0
		lane = target_lane

	# --- 垂直运动 / 跳跃 ---
	if not is_on_floor():
		velocity.y += GameConfig.GRAVITY * delta
		if _fast_fall and velocity.y < 0.0:
			velocity.y = maxf(velocity.y, GameConfig.FAST_FALL_VELOCITY)

	if _jump_buffer > 0.0:
		_jump_buffer -= delta
		if is_on_floor():
			velocity.y = GameConfig.JUMP_VELOCITY * _jump_mul
			_jump_buffer = 0.0
			# 跳跃力越强音调越高，不同角色手感有区分
			Sfx.play("jump", randf_range(0.97, 1.05) * _jump_mul)

	var prev_z := position.z
	move_and_slide()

	# 打滑时不允许滑出赛道（撞到边缘则横向速度归零）
	var limit := GameConfig.WORLD_HALF_WIDTH - EDGE_MARGIN
	if absf(position.x) > limit:
		position.x = clampf(position.x, -limit, limit)
		velocity.x = 0.0

	# 落地反馈：从空中回到地面的那一帧
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and running:
		Sfx.play("land", randf_range(0.94, 1.06))
	_was_on_floor = on_floor

	# 兜底：被障碍物挡住（连续多帧几乎无法前进）同样判定为撞毁
	if running:
		var expected := speed_now * delta
		if expected > 0.05 and absf(position.z - prev_z) < expected * 0.35:
			_stuck_frames += 1
			if _stuck_frames >= 6:
				die()
		else:
			_stuck_frames = 0

	_animate(delta)

	# 坠入坑洞：先放坠落音，掉到底再判定死亡
	if position.y < FALLING_Y and not _falling:
		_falling = true
		Sfx.play("fall")
	if position.y < GameConfig.FALL_DEATH_Y:
		hp = 0
		emit_signal("hp_changed", hp, max_hp)
		die()


func _update_invincible(delta: float) -> void:
	if _invincible <= 0.0:
		return
	_invincible -= delta
	if _invincible <= 0.0:
		_invincible = 0.0
		collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_OBSTACLE
		_model.visible = true
	else:
		# 闪烁提示无敌状态
		_model.visible = fmod(_invincible * GameConfig.INVINCIBLE_BLINK, 1.0) > 0.5


func _animate(delta: float) -> void:
	# 跑动颠簸
	var rate := 4.0 + forward_speed * 0.42
	_bob_time += delta * rate
	var amp := 0.14 if is_on_floor() else 0.04
	_model_pivot.position.y = absf(sin(_bob_time)) * amp

	# 脚步声跟着摆腿节奏（sin 每过半周期算一步），音量压得很低只当节奏底噪
	var step := int(_bob_time / PI)
	if running and is_on_floor():
		if step != _last_step:
			Sfx.play("step", randf_range(0.9, 1.12), -7.0)
	_last_step = step

	# 摆腿
	var swing := 0.55 if running else 0.0
	for i in _legs.size():
		var phase := _bob_time + (PI if i % 2 == 0 else 0.0)
		_legs[i].rotation.x = _leg_rest_rot[i].x + sin(phase) * swing

	# 换道时侧倾 + 轻微转向，增加体感
	_lean = move_toward(_lean, clampf(-velocity.x * 0.018, -0.32, 0.32), delta * 8.0)
	_model_pivot.rotation.z = _lean
	_model_pivot.rotation.y = clampf(-velocity.x * 0.022, -0.45, 0.45)


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not alive or get_tree().paused:
		return

	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_swipe_start = touch.position
			_swipe_used = false
		else:
			_fast_fall = false
			# 轻点 = 跳跃
			if not _swipe_used and (touch.position - _swipe_start).length() < 24.0:
				_jump_buffer = GameConfig.JUMP_BUFFER_TIME
	elif event is InputEventScreenDrag:
		if _swipe_used:
			return
		var drag := event as InputEventScreenDrag
		var d := drag.position - _swipe_start
		if d.length() < 42.0:
			return
		_swipe_used = true
		if absf(d.x) > absf(d.y):
			_change_lane(1 if d.x > 0.0 else -1)
		elif d.y < 0.0:
			_jump_buffer = GameConfig.JUMP_BUFFER_TIME
		else:
			_fast_fall = true


func _handle_key(event: InputEventKey) -> void:
	var code: int = event.physical_keycode
	if code == KEY_NONE:
		code = event.keycode

	if event.pressed and not event.echo:
		match code:
			KEY_LEFT, KEY_A:
				_change_lane(-1)
			KEY_RIGHT, KEY_D:
				_change_lane(1)
			KEY_SPACE, KEY_UP, KEY_W:
				_jump_buffer = GameConfig.JUMP_BUFFER_TIME
			KEY_DOWN, KEY_S:
				_fast_fall = true
	elif not event.pressed and (code == KEY_DOWN or code == KEY_S):
		_fast_fall = false


func _change_lane(dir: int) -> void:
	var before := target_lane
	target_lane = GameConfig.clamp_lane(target_lane + dir)
	# 撞到赛道边缘时不发声，避免连续按键时的噪音
	if target_lane != before:
		Sfx.play("lane", randf_range(0.94, 1.10))
