class_name Player
extends CharacterBody3D
## 玩家：方块动物。
## 自动向前奔跑（World 每帧写入 forward_speed），玩家负责 换道 / 跳跃 / 滑铲 / 快速下落。
## 其中「下」键按所处状态分流：地面滑铲（B4）、空中快速下落。
## 支持键盘（A/D、←/→、空格、W/S）与触屏滑动（←/→ 换道、↑ 跳、↓ 滑铲 / 快落）。
##
## 受击：撞到障碍或被追兵碰到扣 1 点生命，随后进入无敌（可穿过障碍）并短暂减速；
## 生命归零或掉出地面则本局结束。死亡判定由外部 Hazard 区域触发，另有兜底卡死检测。

signal died
signal hp_changed(hp: int, max_hp: int)
signal hit_taken
signal shield_blocked

## 横向加速度上限。traction = 1.0 时几乎瞬时响应，低抓地力下才会明显打滑
const LANE_ACCEL := 240.0
## 滑出赛道边缘的余量（不允许直接滑进虚空）
const EDGE_MARGIN := 0.45
## 长按连续变道：按下立即换一次道，继续按住经过起始间隔后按固定节奏连续变道。
## 起始间隔略长，避免想单次变道时误触连换。
const LANE_HOLD_DELAY := 0.26
const LANE_HOLD_REPEAT := 0.16
## 低于此高度即认定「正在坠入坑洞」，用于播放坠落音
const FALLING_Y := -1.5
## 站立 / 滑铲两套碰撞盒。
## 站立时顶端约 1.55 m，会撞上横杆（下沿 1.15 m）；滑铲时压到约 0.93 m，可以从下方穿过。
const STAND_HEIGHT := 1.5
const STAND_Y := 0.8
const SLIDE_HEIGHT := 0.95
const SLIDE_Y := 0.45

## 是否处于滑铲低姿（B4）。压低碰撞盒后可穿过横杆下方
var sliding: bool = false

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
## 护盾（B2）：抵挡一次伤害后消失，视觉上是身周的半透明能量壳
var shielded: bool = false
## 冲刺穿透（B2）：期间免疫伤害并可穿过障碍物
var phase_through: bool = false

var _speed_mul: float = 1.0
var _jump_mul: float = 1.0
var _lane_mul: float = 1.0

var _model_pivot: Node3D
var _model: Node3D
var _shield_shell: MeshInstance3D
## 第一人称模式下隐藏模型与护盾壳（相机就在头里，留着只会穿模）
var _model_hidden: bool = false
var _legs: Array[Node3D] = []
var _leg_rest_rot: Array[Vector3] = []
## 碰撞胶囊与它的形状：滑铲时要压低高度才能穿过横杆
var _col: CollisionShape3D
var _capsule: CapsuleShape3D

# --- 滑铲状态（B4）---
var _slide_left := 0.0
var _slide_cd := 0.0
var _slide_buffer := 0.0
var _slide_pose := 0.0        # 0 站立 / 1 完全伏低，用于平滑过渡

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

# 长按连续变道：当前按住的方向与下次触发倒计时
var _hold_dir: int = 0
var _hold_cd: float = 0.0


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PLAYER
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_OBSTACLE

	_build_collision()

	_model_pivot = Node3D.new()
	_model_pivot.name = "ModelPivot"
	add_child(_model_pivot)

	# 先套用默认角色，保证任何时刻都有可见模型；开局时会被 setup() 覆盖
	setup(GameConfig.character(0), 3)
	_build_shield_shell()
	reset()


# ---------------------------------------------------------------- 构建
func _build_collision() -> void:
	_col = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.42
	_capsule.height = STAND_HEIGHT
	_col.shape = _capsule
	_col.position.y = STAND_Y
	add_child(_col)


## 切换站立 / 低姿碰撞盒
func _set_crouch(on: bool) -> void:
	if _capsule == null:
		return
	_capsule.height = SLIDE_HEIGHT if on else STAND_HEIGHT
	_col.position.y = SLIDE_Y if on else STAND_Y


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


## 护盾的视觉：身周一圈半透明能量壳（球体），平时隐藏
func _build_shield_shell() -> void:
	_shield_shell = MeshInstance3D.new()
	_shield_shell.name = "ShieldShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.15
	sphere.height = 2.3
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color8(0x7f, 0xe3, 0xe0, 90)
	mat.emission_enabled = true
	mat.emission = Color8(0x7f, 0xe3, 0xe0)
	mat.emission_energy = 0.5
	mat.roughness = 0.2
	_shield_shell.mesh = sphere
	_shield_shell.material_override = mat
	_shield_shell.position.y = 0.85
	_shield_shell.visible = false
	add_child(_shield_shell)


# ---------------------------------------------------------------- 生命周期
func reset() -> void:
	lane = GameConfig.LANE_COUNT / 2
	target_lane = lane
	alive = true
	running = false
	hp = max_hp
	shielded = false
	phase_through = false
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
	_hold_dir = 0
	_hold_cd = 0.0
	sliding = false
	_slide_left = 0.0
	_slide_cd = 0.0
	_slide_buffer = 0.0
	_slide_pose = 0.0

	_update_collision_mask()
	_set_crouch(false)
	position = Vector3(GameConfig.lane_x(lane), 0.05, GameConfig.PLAYER_START_Z)
	_model_pivot.rotation = Vector3.ZERO
	_model_pivot.position = Vector3.ZERO
	_model_pivot.scale = Vector3.ONE
	if _model != null:
		_model.visible = true
	if _model_pivot != null:
		_model_pivot.visible = true
	_model_hidden = false
	if _shield_shell != null:
		_shield_shell.visible = false


func die() -> void:
	if not alive:
		return
	alive = false
	running = false
	hp = 0
	velocity = Vector3.ZERO
	emit_signal("hp_changed", hp, max_hp)
	Sfx.play("death")

	_end_slide()
	_update_collision_mask()
	_set_crouch(false)

	# 倒地动画
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_model_pivot, "rotation_degrees:z", -85.0, 0.35)
	tween.tween_property(_model_pivot, "position:y", 0.25, 0.35)

	emit_signal("died")


## 复活（C4）：原地满血起身，并附带一段无敌时间，避免刚站起来又被撞。
## [param at_z] 由 World 挑选的安全落点（掉进坑洞时要挪回实地）。
func revive(at_z: float) -> void:
	alive = true
	running = true
	hp = max_hp
	velocity = Vector3.ZERO
	target_lane = GameConfig.clamp_lane(target_lane)
	lane = target_lane
	position = Vector3(GameConfig.lane_x(lane), 0.05, at_z)
	_invincible = GameConfig.REVIVE_INVINCIBLE
	_hit_slow = 0.0
	_stuck_frames = 0
	_falling = false
	_fast_fall = false
	_jump_buffer = 0.0
	_hold_dir = 0
	_hold_cd = 0.0
	sliding = false
	_slide_left = 0.0
	_slide_cd = 0.0
	_slide_buffer = 0.0
	_slide_pose = 0.0
	_was_on_floor = true

	_set_crouch(false)
	_update_collision_mask()
	if _model_pivot != null:
		_model_pivot.rotation = Vector3.ZERO
		_model_pivot.position = Vector3.ZERO
		_model_pivot.scale = Vector3.ONE
	if _model != null:
		_model.visible = true
	if _shield_shell != null:
		_shield_shell.visible = shielded

	emit_signal("hp_changed", hp, max_hp)
	Sfx.play("revive")


# ---------------------------------------------------------------- 滑铲（B4）
## 按下「下 / S」：地面进入滑铲，空中则是快速下落。
## 落地前提早按下也会缓存下来，落地当帧自动接上滑铲。
func request_down() -> void:
	_slide_buffer = GameConfig.SLIDE_BUFFER
	if not is_on_floor():
		_fast_fall = true


func _start_slide() -> void:
	if sliding:
		return
	sliding = true
	_slide_left = GameConfig.SLIDE_TIME
	_slide_buffer = 0.0
	_set_crouch(true)
	Sfx.play("slide", randf_range(0.95, 1.06))


func _end_slide() -> void:
	if not sliding:
		return
	sliding = false
	_slide_left = 0.0
	_slide_cd = GameConfig.SLIDE_COOLDOWN
	_set_crouch(false)


## 主循环里推进滑铲计时（起跳、离地、时间到都会解除低姿）
func _update_slide(delta: float) -> void:
	if _slide_cd > 0.0:
		_slide_cd -= delta
	if _slide_buffer > 0.0:
		_slide_buffer -= delta
	if sliding:
		_slide_left -= delta
		if _slide_left <= 0.0 or not is_on_floor():
			_end_slide()
	elif _slide_buffer > 0.0 and is_on_floor() and _slide_cd <= 0.0:
		_start_slide()


## 受到一次伤害，返回是否真的扣血（无敌 / 冲刺穿透期间或非对局中返回 false）。
## 有护盾时消耗护盾抵挡本次伤害——不掉血、不减速，也不计入「无伤」统计。
func take_hit() -> bool:
	if not alive or not running or _invincible > 0.0 or phase_through:
		return false

	if shielded:
		set_shield(false)
		_invincible = GameConfig.INVINCIBLE_TIME * 0.6
		_stuck_frames = 0
		Sfx.play("shield_break")
		emit_signal("shield_blocked")
		_update_collision_mask()
		return false

	hp -= 1
	_invincible = GameConfig.INVINCIBLE_TIME
	_hit_slow = GameConfig.HIT_RECOVER_TIME
	_stuck_frames = 0
	_update_collision_mask()

	emit_signal("hit_taken")
	emit_signal("hp_changed", hp, max_hp)

	if hp <= 0:
		die()
	else:
		# 只剩 1 点生命时音调更高更急，听觉上就能感到危险
		Sfx.play("hit", 1.16 if hp == 1 else 1.0)
	return true


## 护盾开关（B2）：true 时显示能量壳（第一人称隐藏模型时同步隐藏）
func set_shield(value: bool) -> void:
	shielded = value
	if _shield_shell != null:
		_shield_shell.visible = value and not _model_hidden


## 第一人称（D8）：切换模型 / 护盾壳的整体显隐
func set_model_visible(value: bool) -> void:
	_model_hidden = not value
	if _model_pivot != null:
		_model_pivot.visible = value
	if _shield_shell != null:
		_shield_shell.visible = value and shielded


## 跑动颠簸的相位：第一人称相机用它做轻微的头部起伏
func bob_phase() -> float:
	return _bob_time


## 冲刺穿透开关（B2）：期间可穿过障碍且免疫伤害
func set_phase_through(value: bool) -> void:
	phase_through = value
	_update_collision_mask()


## 无敌 / 冲刺 / 正常三种状态共用一套碰撞掩码规则：
## 无敌与冲刺期间不与障碍物碰撞（可穿过），否则会被挡住。
func _update_collision_mask() -> void:
	var passable := _invincible > 0.0 or phase_through
	collision_mask = GameConfig.LAYER_WORLD if passable \
		else GameConfig.LAYER_WORLD | GameConfig.LAYER_OBSTACLE


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
	# 长按方向键连续变道：按住期间按固定节奏触发（手感优化）
	if _hold_dir != 0:
		_hold_cd -= delta
		if _hold_cd <= 0.0:
			_change_lane(_hold_dir)
			_hold_cd = LANE_HOLD_REPEAT
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

	# --- 滑铲（B4）：低姿从横杆下方穿过；空中按「下」仍是快速下落 ---
	_update_slide(delta)

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
			_end_slide()  # 起跳解除低姿，避免从下方顶到横杆
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
		_update_collision_mask()
		_model.visible = true
	else:
		# 闪烁提示无敌状态（冲刺穿透期间不闪烁，靠 FOV 与速度表达）
		if not phase_through:
			_model.visible = fmod(_invincible * GameConfig.INVINCIBLE_BLINK, 1.0) > 0.5


func _animate(delta: float) -> void:
	# 滑铲姿态：整个人伏低、后仰、略微拉长，一眼能看出「低姿通过」
	_slide_pose = move_toward(_slide_pose, 1.0 if sliding else 0.0, delta * 11.0)
	_model_pivot.scale = Vector3(
		lerpf(1.0, 1.14, _slide_pose),
		lerpf(1.0, 0.56, _slide_pose),
		lerpf(1.0, 1.20, _slide_pose))
	_model_pivot.rotation.x = lerpf(0.0, -0.5, _slide_pose)

	# 跑动颠簸
	var rate := 4.0 + forward_speed * 0.42
	_bob_time += delta * rate
	var amp := 0.14 if is_on_floor() else 0.04
	if sliding:
		amp = 0.0
	_model_pivot.position.y = absf(sin(_bob_time)) * amp

	# 脚步声跟着摆腿节奏（sin 每过半周期算一步），音量压得很低只当节奏底噪
	var step := int(_bob_time / PI)
	if running and is_on_floor():
		if step != _last_step:
			Sfx.play("step", randf_range(0.9, 1.12), -7.0)
	_last_step = step

	# 摆腿（滑铲时双腿收起，不再摆动）
	var swing := 0.0 if sliding else (0.55 if running else 0.0)
	for i in _legs.size():
		var phase := _bob_time + (PI if i % 2 == 0 else 0.0)
		_legs[i].rotation.x = _leg_rest_rot[i].x + sin(phase) * swing

	# 换道时侧倾 + 轻微转向，增加体感
	_lean = move_toward(_lean, clampf(-velocity.x * 0.018, -0.32, 0.32), delta * 8.0)
	_model_pivot.rotation.z = _lean
	_model_pivot.rotation.y = clampf(-velocity.x * 0.022, -0.45, 0.45)


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	# 松开事件任何时候都要处理：暂停 / 死亡期间松键若被拦掉，
	# 按住变道的状态会残留，恢复游戏后角色会自己跑起来
	if event is InputEventKey and not (event as InputEventKey).pressed:
		_handle_key_release(event as InputEventKey)
		return

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
			request_down()


func _handle_key(event: InputEventKey) -> void:
	var code: int = event.physical_keycode
	if code == KEY_NONE:
		code = event.keycode

	if event.pressed and not event.echo:
		match code:
			KEY_LEFT, KEY_A:
				_change_lane(-1)
				_hold_dir = -1
				_hold_cd = LANE_HOLD_DELAY
			KEY_RIGHT, KEY_D:
				_change_lane(1)
				_hold_dir = 1
				_hold_cd = LANE_HOLD_DELAY
			KEY_SPACE, KEY_UP, KEY_W:
				_jump_buffer = GameConfig.JUMP_BUFFER_TIME
			KEY_DOWN, KEY_S:
				# 同一个键：地面滑铲、空中快速下落
				request_down()


## 松开按键：清除按住状态（任何时候都有效，见 _unhandled_input 的说明）
func _handle_key_release(event: InputEventKey) -> void:
	var code: int = event.physical_keycode
	if code == KEY_NONE:
		code = event.keycode
	match code:
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			_hold_dir = 0
		KEY_DOWN, KEY_S:
			_fast_fall = false


func _change_lane(dir: int) -> void:
	var before := target_lane
	target_lane = GameConfig.clamp_lane(target_lane + dir)
	# 撞到赛道边缘时不发声，避免连续按键时的噪音
	if target_lane != before:
		Sfx.play("lane", randf_range(0.94, 1.10))
