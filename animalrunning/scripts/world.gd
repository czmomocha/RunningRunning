class_name World
extends Node3D
## 世界：程序化生成无限方块地形、障碍、能量方块（金币），并管理追逐的敌人与难度曲线。
##
## 地形由 CHUNK_COUNT 个「地块」组成环形队列：玩家跑过的地块会立刻被回收、
## 重新装填并放到队列最前方，从而实现无限地形且零内存增长。
## 障碍 / 金币 / 装饰 / 敌人全部使用对象池复用。
##
## 一局的具体参数来自三张配置表：关卡（长度 / 主题 / 密度）、难度（生命 / 速度 / 倍率）、
## 角色（外观 / 速度跳跃换道倍率）。

signal player_died(score: int, coins: int, distance: float)
signal level_completed(score: int, coins: int, distance: float)
## 无限模式：主题段切换时通知 HUD 更新关卡名与路况
signal stage_changed
## 视角切换（D8）：参数为是否处于第一人称
signal view_mode_changed(first_person: bool)

const CAM_LOOK_AHEAD := 8.0
const CAM_FOLLOW_X := 0.45
const RECYCLE_MARGIN := 35.0  # 地块完全落到玩家身后多少米后回收
const APRON_WIDTH := 56.0     # 赛道两侧大地的宽度（刚好托住所有装饰）
const APRON_TOP := -0.75      # 两侧大地的地表高度（比赛道低一档，赛道像抬起的高台）
const ENEMY_WARN_RANGE := 16.0  # 追兵进入这个距离就开始出现警示音
const WIND_PERIOD := 0.9        # 阵风角频率（约 7 秒一个完整周期）

## 敌人使用的动物模型
const ENEMY_ANIMALS: Array[String] = [
	"animal-tiger.glb",
	"animal-lion.glb",
	"animal-fox.glb",
	"animal-dog.glb",
	"animal-polar.glb",
	"animal-hog.glb",
	"animal-deer.glb",
	"animal-koala.glb",
]

# ---------------------------------------------------------------- 运行时状态
var running: bool = false
var speed: float = GameConfig.BASE_SPEED
var distance: float = 0.0
var score: int = 0
var coins: int = 0
var target_distance: float = 1000.0
## 技巧分（B3）：连击追加 + 跳栏 + 擦身 + 飞坑，独立于距离与方块累加
var trick_score: int = 0
## 当前连击数与最高连击（B3）
var combo: int = 0
var max_combo: int = 0
var player: Player
## 当前逆风系数（1.0 表示无风），供 HUD 显示阵风提示
var wind_factor: float = 1.0
## 是否无限模式 / 每日挑战（B1）
var infinite: bool = false
var daily: bool = false
## 是否处于第一人称视角（D8）。相机位置在两种模式间平滑过渡
var first_person: bool = false
## 当前激活的道具及其剩余时间（B2）：id -> 秒
var powerup_timers: Dictionary = {}

## 本局配置
var level_name: String = ""
var level_subtitle: String = ""
var level_theme: String = "grass"
var _level: Dictionary = {}
var _diff: Dictionary = {}
var _theme: Dictionary = {}
var _speed_mul: float = 1.0
var _obstacle_mul: float = 1.0
var _enemy_mul: float = 1.0
var _enemy_speed_mul: float = 1.0

# ---------------------------------------------------------------- 内部
var _camera: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _chunks: Array[Chunk] = []
var _front_z: float = 0.0
var _active_enemies: Array[Enemy] = []
var _enemy_pool: Array[Enemy] = []
var _obstacle_pool: Array[Node3D] = []
var _coin_pool: Array[Node3D] = []
var _deco_pool: Array[Node3D] = []
var _powerup_pool: Array[Area3D] = []
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _enemy_timer: float = 0.0
var _cam_target := Vector3.ZERO
var _coins_since_heal: int = 0
var _warn_timer: float = 0.0
var _wind: float = 0.0
var _gust_audible := false
var _track_width: float = 0.0
# B3：连击倒计时 / 滞空区间（起跳 z）/ 无限模式主题段索引
var _combo_timer: float = 0.0
var _air_z_start: float = NAN
var _infinite_stage: int = -1
# D8：第一人称融合系数（0 = 纯第三人称，1 = 纯第一人称）
var _fp_blend: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_setup_environment()
	_setup_camera()
	_setup_player()
	_setup_chunks()
	_apply_theme(GameConfig.theme("grass"))
	reset_run()


# ================================================================ 场景搭建
func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.85
	_env.fog_enabled = true
	# 远处平滑融进天空色，形成干净的地平线
	_env.fog_density = 0.013
	_env.set("fog_aerial_perspective", 0.45)
	_env.set("fog_sky_affect", 0.2)
	env_node.environment = _env
	add_child(env_node)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-52.0, 32.0, 0.0)
	_sun.light_energy = 1.15
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 120.0
	_sun.shadow_bias = 0.03
	_sun.shadow_blur = 1.0
	add_child(_sun)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 50.0
	_camera.near = 0.5
	_camera.far = 320.0
	add_child(_camera)


func _setup_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.died.connect(_on_player_died)


func _setup_chunks() -> void:
	for i in GameConfig.CHUNK_COUNT:
		var c := Chunk.new()
		c.index = i
		c.root = Node3D.new()
		c.root.name = "Chunk%d" % i
		add_child(c.root)
		_build_chunk_floor(c)
		_chunks.append(c)


func _build_chunk_floor(c: Chunk) -> void:
	var width := GameConfig.WORLD_WIDTH + 1.2
	var length := GameConfig.CHUNK_LENGTH
	_track_width = width

	# 赛道两侧的大地：没有它，树木岩石会悬在天空里，画面很「穿帮」。
	# 必须做成左右两条，中间留出赛道走廊——否则它会从下方糊住坑洞，
	# 坑洞就变成一条浅浅的黑带，看不出是深渊。
	var amat := StandardMaterial3D.new()
	amat.roughness = 1.0
	amat.metallic = 0.0
	c.apron_mat = amat

	var strip := (APRON_WIDTH - width) * 0.5
	for side in [-1.0, 1.0]:
		var apron := MeshInstance3D.new()
		var abox := BoxMesh.new()
		abox.size = Vector3(strip, 2.0, length)
		apron.mesh = abox
		apron.position = Vector3(
			side * (width * 0.5 + strip * 0.5), APRON_TOP - 1.0, -length * 0.5)
		apron.material_override = amat
		c.root.add_child(apron)

	# 地面按「行」切成一段段独立的板块。
	# 这样某一行才能被整块挖空成坑洞（隐藏网格 + 关掉碰撞），且依然零分配、可复用。
	var rows := int(GameConfig.CHUNK_LENGTH / GameConfig.ROW_LENGTH)
	var row_len := GameConfig.ROW_LENGTH
	for r in rows:
		var slab := FloorSlab.new()
		slab.root = Node3D.new()
		slab.root.name = "Slab%d" % r
		slab.root.position.z = -(float(r) + 0.5) * row_len
		c.root.add_child(slab.root)

		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, GameConfig.FLOOR_THICKNESS, row_len)
		mesh.mesh = box
		mesh.position.y = -GameConfig.FLOOR_THICKNESS * 0.5
		var mat := StandardMaterial3D.new()
		mat.roughness = 1.0
		mat.metallic = 0.0
		mesh.material_override = mat
		slab.root.add_child(mesh)
		slab.mesh = mesh
		slab.mat = mat

		# 车道分隔线
		for i in GameConfig.LANE_COUNT - 1:
			var line := MeshInstance3D.new()
			var lbox := BoxMesh.new()
			lbox.size = Vector3(0.12, 0.02, row_len)
			line.mesh = lbox
			line.position = Vector3(
				GameConfig.lane_x(i) + GameConfig.LANE_WIDTH * 0.5, 0.012, 0.0)
			var lmat := StandardMaterial3D.new()
			lmat.roughness = 1.0
			line.material_override = lmat
			slab.root.add_child(line)
			slab.lane_mats.append(lmat)
			slab.lane_lines.append(line)

		# 地面碰撞
		var body := StaticBody3D.new()
		body.collision_layer = GameConfig.LAYER_WORLD
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, GameConfig.FLOOR_THICKNESS, row_len)
		col.shape = shape
		col.position.y = -GameConfig.FLOOR_THICKNESS * 0.5
		body.add_child(col)
		slab.root.add_child(body)
		slab.body = body
		slab.col = col

		# 坑洞前的预警条纹：平时隐藏，坑洞前一行才亮起
		var warn := MeshInstance3D.new()
		var wbox := BoxMesh.new()
		wbox.size = Vector3(width, 0.05, 0.5)
		warn.mesh = wbox
		# 贴在跳台的最远端，也就是悬崖边缘，明确告诉玩家「这里要起跳」
		warn.position = Vector3(0.0, 0.03,
			row_len * 0.5 - GameConfig.PIT_LEDGE + 0.3)
		var wmat := StandardMaterial3D.new()
		wmat.emission_enabled = true
		wmat.roughness = 0.6
		warn.material_override = wmat
		warn.visible = false
		slab.root.add_child(warn)
		slab.warn = warn
		slab.warn_mat = wmat

		# 坑底发光面（熔岩 / 幽蓝深渊）：只在这一行是坑洞时显示
		var glow := MeshInstance3D.new()
		var gbox := BoxMesh.new()
		# 只铺在缺口范围内，并向远端对齐
		gbox.size = Vector3(width, 0.2, GameConfig.PIT_GAP)
		glow.mesh = gbox
		glow.position = Vector3(0.0, -GameConfig.PIT_DEPTH, -GameConfig.PIT_LEDGE * 0.5)
		var gmat := StandardMaterial3D.new()
		gmat.emission_enabled = true
		gmat.emission_energy = 1.6
		glow.material_override = gmat
		glow.visible = false
		slab.root.add_child(glow)
		slab.glow = glow
		slab.glow_mat = gmat

		c.slabs.append(slab)


# ================================================================ 开局 / 重置
## 按当前选中的关卡、难度、角色开始一局。
## level_index 为负数时是无限模式（B1）：-1 普通，-2 每日挑战（按日期定种子）。
func start_run(level_index: int) -> void:
	infinite = GameConfig.is_infinite(level_index)
	daily = level_index == GameConfig.DAILY_LEVEL
	# 每日挑战：种子 = 当天日期，全世界同一天拿到同一张图
	if daily:
		_rng.seed = hash(Time.get_date_string_from_system())
	elif not infinite:
		_rng.randomize()

	if infinite:
		_level = {}
		_diff = GameConfig.difficulty(GameState.difficulty_index)
		level_name = "每日挑战" if daily else "无限模式"
		level_subtitle = "今日种子 · 同图竞速" if daily else "生存到底"
		_speed_mul = float(_diff.get("speed", 1.0))
		_obstacle_mul = float(_diff.get("obstacle", 1.0))
		_enemy_mul = float(_diff.get("enemy", 1.0))
		_enemy_speed_mul = 1.08
		_infinite_stage = -1
		target_distance = INF
		_update_infinite_stage(true)
	else:
		_level = GameConfig.level(level_index)
		_diff = GameConfig.difficulty(GameState.difficulty_index)
		level_name = String(_level.get("name", ""))
		level_subtitle = String(_level.get("subtitle", ""))
		level_theme = String(_level.get("theme", "grass"))
		target_distance = float(_level.get("distance", 1000.0))
		_speed_mul = float(_diff.get("speed", 1.0))
		_obstacle_mul = float(_diff.get("obstacle", 1.0))
		_enemy_mul = float(_diff.get("enemy", 1.0))
		_enemy_speed_mul = float(_level.get("enemy_speed", 1.0))
		_apply_theme(GameConfig.theme(level_theme))

	var ch := GameConfig.character(GameState.character_index)
	player.setup(ch, GameState.final_hp())
	reset_run()
	running = true


## 无限模式：每 INFINITE_STAGE 米切换一次主题（按关卡表顺序循环）。
## 已生成地块会在回收重装填时自然换色，形成一段过渡带。
func _update_infinite_stage(force := false) -> void:
	var stage := int(distance / GameConfig.INFINITE_STAGE)
	if stage == _infinite_stage and not force:
		return
	_infinite_stage = stage
	var idx := stage % GameConfig.LEVELS.size()
	var lv: Dictionary = GameConfig.level(idx)
	var theme_name := String(lv.get("theme", "grass"))
	_apply_theme(GameConfig.theme(theme_name))
	# 关卡名随时告诉玩家当前跑到哪一段
	level_theme = theme_name
	level_name = "第 %d 段 · %s" % [stage + 1, String(lv.get("name", ""))]
	level_subtitle = String(lv.get("subtitle", ""))
	emit_signal("stage_changed")


func _apply_theme(t: Dictionary) -> void:
	_theme = t
	_env.background_color = t["sky"]
	_env.fog_light_color = t["fog"]
	_env.ambient_light_color = t["ambient"]
	_sun.light_color = t["sun"]
	# 把主题的机制参数下发给玩家（抓地力）与本地缓存（逆风）
	_wind = float(t.get("wind", 0.0))
	player.traction = float(t.get("traction", 1.0))


func reset_run() -> void:
	running = false
	speed = GameConfig.BASE_SPEED
	distance = 0.0
	score = 0
	coins = 0
	trick_score = 0
	combo = 0
	max_combo = 0
	_time = 0.0
	_coins_since_heal = 0
	_warn_timer = 1.5
	_enemy_timer = GameConfig.ENEMY_SPAWN_MIN
	_combo_timer = 0.0
	_air_z_start = NAN
	# 道具效果全部清空（护盾也只在单局内有效）
	for type in powerup_timers.keys():
		_end_powerup(String(type))
	powerup_timers.clear()
	player.set_shield(false)
	player.set_phase_through(false)

	# 回收所有敌人
	for e in _active_enemies:
		e.despawn()
		_enemy_pool.append(e)
	_active_enemies.clear()

	# 重新排布地块：第一块覆盖 [+CHUNK_LENGTH, 0]，保证起跑线后方有地面
	var z := GameConfig.CHUNK_LENGTH
	var last := z
	for c in _chunks:
		c.start_z = z
		last = z
		z -= GameConfig.CHUNK_LENGTH
		_populate_chunk(c)
	_front_z = last

	player.reset()
	# 若上一局停留在第一人称，重新开局保持该视角偏好并同步模型显隐（D8）
	player.set_model_visible(not first_person)
	_update_camera(0.0, true)


func _on_player_died() -> void:
	if not running:
		return
	running = false
	player.running = false
	# 第一人称下自动切回第三人称，让玩家看到倒地与追兵围上来的画面（D8）
	set_view_mode(false)
	emit_signal("player_died", score, coins, distance)


## 复活 / 续关（C4）：把玩家放回安全地面、清空追兵，从当前里程继续跑。
## 货币的扣除交给 GameState（调用方先扣再调这里），世界只负责场面复位。
func revive() -> void:
	var z := player.position.z
	if player.position.y < -0.5:
		# 掉进坑洞的情形：必须往前挪到最近的实地，否则人站在深渊里
		for _i in 12:
			if not pit_ahead(z, GameConfig.ROW_LENGTH + 2.0):
				break
			z -= GameConfig.ROW_LENGTH

	# 追兵全部撤走：刚站起来就被贴脸不成立，也给玩家重新找回节奏的时间
	for e in _active_enemies:
		e.despawn()
		_enemy_pool.append(e)
	_active_enemies.clear()
	_enemy_timer = GameConfig.ENEMY_SPAWN_MAX

	player.revive(z)
	player.set_model_visible(not first_person)
	running = true


## 切换第三 / 第一人称（D8）。
## 死亡时由 _on_player_died 自动切回第三人称，方便观看倒地动画与追兵围上来。
func set_view_mode(first: bool) -> void:
	if first_person == first:
		return
	first_person = first
	player.set_model_visible(not first)
	Sfx.play("ui_click", 1.1)
	emit_signal("view_mode_changed", first)


func _finish_level() -> void:
	if not running:
		return
	running = false
	player.running = false
	Sfx.play("win")
	emit_signal("level_completed", score, coins, distance)


# ================================================================ 主循环
func _physics_process(delta: float) -> void:
	if not running:
		return

	_time += delta

	# 难度曲线：时间 + 距离共同驱动，再乘以难度速度倍率
	speed = minf(
		GameConfig.MAX_SPEED,
		(GameConfig.BASE_SPEED
			+ _time * GameConfig.SPEED_PER_SECOND
			+ distance * GameConfig.SPEED_PER_METER) * _speed_mul)

	# 主题逆风：周期性阵风压低前进速度（沙漠 / 极夜），有节奏可预判
	wind_factor = 1.0
	if _wind > 0.0:
		var gust := 0.5 + 0.5 * sin(_time * WIND_PERIOD)
		wind_factor = 1.0 - _wind * gust * gust
		speed *= wind_factor

	# 冲刺道具：直接放大前进速度（B2）
	if powerup_timers.has("sprint"):
		speed = minf(speed * GameConfig.SPRINT_SPEED_MUL, GameConfig.MAX_SPEED * 1.25)

	player.forward_speed = speed
	player.running = true

	distance += speed * delta

	# 计分（B3）：距离 + 方块 + 技巧，双倍分数道具期间整体翻倍
	var base := int(distance * GameConfig.DISTANCE_SCORE) + coins * GameConfig.COIN_SCORE \
		+ trick_score
	score = base * 2 if powerup_timers.has("double") else base

	# 连击窗口倒计时（B3）
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo = 0

	_update_powerups(delta)
	_update_dynamics()
	_update_tricks()
	_recycle_chunks()
	_update_enemies(delta)
	_update_audio(delta)

	# 无限模式：主题段轮换（B1）
	if infinite:
		_update_infinite_stage()

	if distance >= target_distance:
		distance = target_distance
		_finish_level()


## 追兵贴近时循环播放低沉警示音，越近越急促；阵风来临时播放风声
func _update_audio(delta: float) -> void:
	# 阵风：在风力越过阈值的那一刻响一声，避免每帧刷
	if _wind > 0.0:
		var strong := wind_factor < 1.0 - _wind * 0.55
		if strong and not _gust_audible:
			Sfx.play("gust", randf_range(0.94, 1.06), -3.0)
		_gust_audible = strong

	_warn_timer -= delta
	if _warn_timer > 0.0:
		return

	var nearest := INF
	for e in _active_enemies:
		var behind := e.position.z - player.position.z
		if behind > -2.0:
			nearest = minf(nearest, behind)

	if nearest > ENEMY_WARN_RANGE:
		return

	var t := clampf(nearest / ENEMY_WARN_RANGE, 0.0, 1.0)
	Sfx.play("warn", lerpf(1.15, 0.92, t), lerpf(-4.0, -12.0, t))
	_warn_timer = lerpf(0.8, 1.9, t)


func _process(delta: float) -> void:
	_animate_pickups(delta)
	_update_camera(delta, false)
	# FOV：第三人称 50，第一人称更宽；冲刺时在此基础上再拉高一档强化速度感（B2/D8）
	var target_fov := lerpf(50.0, GameConfig.FP_FOV, smoothstep(0.0, 1.0, _fp_blend))
	if powerup_timers.has("sprint"):
		target_fov += lerpf(GameConfig.SPRINT_FOV - 50.0, 8.0, _fp_blend)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-6.0 * delta))


func _update_camera(delta: float, instant: bool) -> void:
	var p := player.position

	# 视角融合系数：切换时在两种机位之间平滑过渡，而不是瞬切（D8）
	var blend_target := 1.0 if first_person else 0.0
	if instant:
		_fp_blend = blend_target
	else:
		_fp_blend = move_toward(_fp_blend, blend_target, delta * 2.6)
	var k := smoothstep(0.0, 1.0, _fp_blend)

	# 第三人称：高位追尾视角
	var tp_pos := Vector3(p.x * CAM_FOLLOW_X, GameConfig.CAM_HEIGHT, p.z + GameConfig.CAM_BACK)
	var tp_look := Vector3(p.x * 0.3, 0.9, p.z - CAM_LOOK_AHEAD)
	# 第一人称：贴在动物头部，随跑动节奏轻微起伏
	var eye := p.y + GameConfig.FP_EYE_HEIGHT \
		+ absf(sin(player.bob_phase())) * GameConfig.FP_BOB
	var fp_pos := Vector3(p.x, eye, p.z + GameConfig.FP_CAM_OFFSET_Z)
	var fp_look := Vector3(p.x, eye - 0.25, p.z - GameConfig.FP_LOOK_AHEAD)

	_cam_target = tp_pos.lerp(fp_pos, k)
	var look := tp_look.lerp(fp_look, k)

	if instant:
		_camera.position = _cam_target
	else:
		_camera.position = _camera.position.lerp(_cam_target, 1.0 - exp(-8.0 * delta))
	_camera.look_at(look, Vector3.UP)


## 供 HUD 小地图使用：所有敌人在赛道上的进度（0~1）
func get_enemy_progress() -> Array[float]:
	var out: Array[float] = []
	var total := maxf(target_distance, 1.0)
	for e in _active_enemies:
		out.append(clampf(-e.position.z / total, 0.0, 1.0))
	return out


func get_progress() -> float:
	# 无限模式没有终点，进度条展示当前主题段内的进程
	if infinite:
		return fmod(distance, GameConfig.INFINITE_STAGE) / GameConfig.INFINITE_STAGE
	return clampf(distance / maxf(target_distance, 1.0), 0.0, 1.0)


## 供 HUD 显示：距离下一次回血还差多少（0~1）
func get_heal_progress() -> float:
	return clampf(float(_coins_since_heal) / float(GameConfig.HP_HEAL_PER_COINS), 0.0, 1.0)


## 还需多少个能量方块才回血
func get_heal_remaining() -> int:
	return maxi(0, GameConfig.HP_HEAL_PER_COINS - _coins_since_heal)


# ================================================================ 地块：回收 + 装填
## 玩家身后的地块搬移到队列最前方。
## 新位置直接取「当前最靠前地块的 start_z - CHUNK_LENGTH」，保证首尾严格相接、不留缝隙。
func _recycle_chunks() -> void:
	for c in _chunks:
		if c.start_z - GameConfig.CHUNK_LENGTH - player.position.z > RECYCLE_MARGIN:
			c.start_z = _min_start_z_except(c) - GameConfig.CHUNK_LENGTH
			_front_z = c.start_z
			_populate_chunk(c)


func _min_start_z_except(skip: Chunk) -> float:
	var m := INF
	for c in _chunks:
		if c != skip:
			m = minf(m, c.start_z)
	return m


func _populate_chunk(c: Chunk) -> void:
	# 归还旧内容
	for o in c.obstacles:
		_release(_obstacle_pool, o)
	c.obstacles.clear()
	c.obs.clear()
	c.dyn.clear()
	for m in c.coins:
		_release(_coin_pool, m)
	c.coins.clear()
	for p in c.powerups:
		_release(_powerup_pool, p)
	c.powerups.clear()
	for d in c.decos:
		_release(_deco_pool, d)
	c.decos.clear()

	c.pits.clear()
	c.root.position.z = c.start_z
	var even := int(absf(c.start_z) / GameConfig.CHUNK_LENGTH) % 2 == 0
	var ground: Color = _theme["ground_a"] if even else _theme["ground_b"]
	# 两侧大地明显更暗，赛道自然而然被「框」出来
	var apron_color: Color = (_theme["ground_b"] as Color).darkened(0.52)
	c.apron_mat.albedo_color = apron_color.lightened(0.06) if even else apron_color

	var safe := c.start_z > -0.5  # 起跑后的前两个地块不生成障碍
	var rows := c.slabs.size()

	# ---------------------------------------------------------- 1) 先决定哪些行是坑洞
	# 关键约束：地块首尾两行永不挖坑。
	# 地块之间是独立装填的，若允许边缘挖坑，就可能出现「上一块的末行 + 下一块的首行」
	# 两坑相连的 12 m 缺口 —— 那是任何速度都跳不过去的必死地形。
	var pit_rows := {}
	var gap_chance := _pit_chance()
	if not safe and gap_chance > 0.0 and rows >= 3:
		var r := 1
		while r <= rows - 2:
			if _rng.randf() < gap_chance:
				pit_rows[r] = true
				# 坑洞之间至少留 2 行（12 m）落地缓冲
				r += 3
			else:
				r += 1

	# ---------------------------------------------------------- 2) 铺地面 / 挖坑 / 亮预警
	for r in rows:
		var slab := c.slabs[r]
		var is_pit: bool = pit_rows.has(r)
		slab.mat.albedo_color = ground
		for lm in slab.lane_mats:
			lm.albedo_color = _theme["lane"]
		slab.set_pit(is_pit, _theme.get("pit_glow", Color.TRANSPARENT), _track_width)
		# 本行是坑 -> 在它自己保留的那段跳台上亮预警条纹（正好在起跳点前）
		slab.set_warn(is_pit, _theme.get("warn", GameConfig.COLOR_ACCENT))

		if is_pit:
			# 缺口的真实 z 范围：跳台之后才是空的
			var z_near := c.start_z - float(r) * GameConfig.ROW_LENGTH - GameConfig.PIT_LEDGE
			c.pits.append({"z0": z_near, "z1": z_near - GameConfig.PIT_GAP})

	# ---------------------------------------------------------- 3) 障碍与金币
	for r in rows:
		var z_world := c.start_z - (float(r) + 0.5) * GameConfig.ROW_LENGTH
		var blocked: Array[int] = []

		# 坑洞行不放障碍；坑洞的落地行也要留空，否则「跳过坑立刻撞墙」无解
		var near_pit: bool = (pit_rows.has(r) or pit_rows.has(r - 1)
			or pit_rows.has(r + 1))

		if not safe and not near_pit and _rng.randf() < _obstacle_chance():
			# 最多堵住 2 条车道，保证任意相邻两行至少有 1 条公共通路
			var max_block := 2 if distance > 250.0 else 1
			var count := _rng.randi_range(1, max_block)
			var candidates := []
			for i in GameConfig.LANE_COUNT:
				candidates.append(i)
			candidates.shuffle()
			for k in mini(count, GameConfig.LANE_COUNT - 3):
				var l: int = candidates[k]
				blocked.append(l)
				# 平移障碍只给「本行唯一且不在边缘车道」的障碍，
				# 避免扫到相邻障碍上、或横移出赛道
				var mover_ok: bool = count == 1 and l > 0 and l < GameConfig.LANE_COUNT - 1
				_spawn_obstacle(c, l, z_world, mover_ok)

		# 坑洞正上方不放金币（拿不到），但落地行可以放，奖励敢跳的玩家
		if not pit_rows.has(r):
			_spawn_coins(c, blocked, z_world)

	# ---------------------------------------------------------- 4) 道具（B2）
	# 每个地块小概率出现一个道具；避开障碍行与坑洞附近，保证一定能吃到
	if not safe and _rng.randf() < GameConfig.POWERUP_CHUNK_CHANCE and rows >= 5:
		var pr := _rng.randi_range(2, rows - 3)
		var near_pit: bool = (pit_rows.has(pr) or pit_rows.has(pr - 1) or pit_rows.has(pr + 1))
		if not near_pit:
			var pz := c.start_z - (float(pr) + 0.5) * GameConfig.ROW_LENGTH
			var blocked_lanes := {}
			for o in c.obs:
				if float(o["z1"]) < pz + 3.0 and float(o["z0"]) > pz - 3.0:
					for l in range(int(o["l0"]), int(o["l1"]) + 1):
						blocked_lanes[l] = true
			var free_lanes := []
			for i in GameConfig.LANE_COUNT:
				if not blocked_lanes.has(i):
					free_lanes.append(i)
			if not free_lanes.is_empty():
				var pl: int = free_lanes[_rng.randi() % free_lanes.size()]
				_place_powerup(c, GameConfig.pick_powerup(_rng),
					GameConfig.lane_x(pl), 1.0, pz)

	_spawn_decorations(c)


func _obstacle_chance() -> float:
	# 无限模式：障碍密度随里程持续爬升（0.5 → 0.8）
	var base: float
	if infinite:
		base = 0.5 + distance * 0.00006
	elif not _level.is_empty():
		base = float(_level.get("obstacle", 0.55))
	else:
		base = 0.55
	return clampf((base + distance * 0.00012) * _obstacle_mul, 0.2, 0.95)


# ================================================================ 动态障碍（B5）
## 左右平移障碍 / 周期开合闸门。
## 两者都由固定的正弦 / 三角波驱动（而非随机），玩家可以数节拍预判，
## 于是「什么时候通过」也成为一个需要判断的维度，而不只是「走哪条道」。
func _update_dynamics() -> void:
	for c in _chunks:
		for d in c.dyn:
			var node: Node3D = d["node"]
			var info: Dictionary = d["o"]
			if d["mode"] == "mover":
				var x: float = float(d["base_x"]) + sin(
					_time * float(d["w"]) + float(d["phase"])) * float(d["amp"])
				node.position.x = x
				# 技巧判定与敌人 AI 都读这份记录，必须跟着一起走
				info["x"] = x
				var l := GameConfig.lane_of_x(x)
				info["l0"] = l
				info["l1"] = l
			else:
				var closed := _gate_curve(
					fmod(_time / GameConfig.GATE_PERIOD + float(d["phase"]), 1.0))
				# 完全打开时整个闸门沉到地面以下，既看不见也不挡路
				var open_y: float = -float(d["h"]) * 0.5 - 0.3
				node.position.y = lerpf(open_y, float(d["base_y"]), closed)
				info["open"] = closed < 0.55


## 闸门的开合曲线：0 = 完全打开（沉入地面），1 = 完全关闭（立起挡路）。
## 升降各占 GATE_TRANS 个周期，用 smoothstep 过渡，观感是「缓缓升起」而非瞬移。
func _gate_curve(t: float) -> float:
	var open_end := GameConfig.GATE_OPEN_RATIO
	var trans := GameConfig.GATE_TRANS
	var v := 1.0
	if t < open_end - trans:
		v = 0.0
	elif t < open_end:
		v = (t - (open_end - trans)) / trans
	elif t < 1.0 - trans:
		v = 1.0
	else:
		v = 1.0 - (t - (1.0 - trans)) / trans
	return smoothstep(0.0, 1.0, clampf(v, 0.0, 1.0))


## 坑洞出现概率：由主题的 gap 决定，并随跑动距离小幅提升
func _pit_chance() -> float:
	var base := float(_theme.get("gap", 0.0))
	if base <= 0.0:
		return 0.0
	return clampf(base + distance * 0.00006, 0.0, 0.45)


# ================================================================ 障碍物
## [param allow_mover] 本行只有这一个障碍、且不在赛道边缘时，才允许它左右平移（B5）
func _spawn_obstacle(c: Chunk, lane: int, z_world: float, allow_mover: bool = false) -> void:
	var difficulty := clampf(distance / 1200.0, 0.0, 1.0)
	var roll := _rng.randf()
	# 横杆（B4）：悬在半空，站着会撞上、跳也跳不过，只能滑铲穿过
	var bar := distance > GameConfig.BAR_MIN_DISTANCE \
		and _rng.randf() < GameConfig.BAR_CHANCE

	var size: Vector3
	var color: Color
	if bar:
		size = Vector3(GameConfig.LANE_WIDTH * 0.92, GameConfig.BAR_HEIGHT, 0.9)
		color = _theme["bar"]
	elif roll < 0.45 - difficulty * 0.15:
		size = Vector3(GameConfig.LANE_WIDTH * 0.80, 0.9, 1.0)   # 矮栏：可以跳过去
		color = _theme["low"]
	elif roll < 0.80:
		size = Vector3(GameConfig.LANE_WIDTH * 0.82, 2.6, 1.1)   # 高墙：必须换道
		color = _theme["high"]
	else:
		size = Vector3(GameConfig.LANE_WIDTH * 0.90, 1.7, 2.2)   # 大方块
		color = _theme["block"]

	# 动态障碍（B5）：高墙变周期开合闸门，独行障碍左右平移
	var dyn := ""
	if not bar and distance > GameConfig.DYNAMIC_MIN_DISTANCE:
		if size.y >= 2.0 and _rng.randf() < GameConfig.GATE_CHANCE:
			dyn = "gate"
		elif allow_mover and _rng.randf() < GameConfig.MOVER_CHANCE:
			dyn = "mover"

	var y_center := size.y * 0.5
	if bar:
		y_center = GameConfig.BAR_BOTTOM + GameConfig.BAR_HEIGHT * 0.5

	var obs := _acquire(_obstacle_pool, _create_obstacle)
	_setup_obstacle(obs, size, color,
		Vector3(GameConfig.lane_x(lane), y_center, z_world - c.start_z), bar)
	c.root.add_child(obs)
	c.obstacles.append(obs)

	# 记录车道占用信息，供敌人 AI 避障查询；
	# x / low 额外供技巧判定（B3）使用，bar 供滑铲判定（B4）
	var info := {
		"l0": lane,
		"l1": lane,
		"z0": z_world + size.z * 0.5,
		"z1": z_world - size.z * 0.5,
		"x": GameConfig.lane_x(lane),
		"low": size.y <= 1.0,
		"bar": bar,
		"open": false,
	}
	c.obs.append(info)

	if dyn != "":
		c.dyn.append({
			"node": obs,
			"o": info,
			"mode": dyn,
			"base_x": GameConfig.lane_x(lane),
			"base_y": y_center,
			"h": size.y,
			"amp": GameConfig.MOVER_AMP,
			"w": _rng.randf_range(GameConfig.MOVER_SPEED_MIN, GameConfig.MOVER_SPEED_MAX),
			"phase": _rng.randf() * TAU,
		})

	# 矮栏上方放奖励金币，鼓励跳跃
	if size.y <= 1.0 and _rng.randf() < 0.4:
		for k in 2:
			_place_coin(c, GameConfig.lane_x(lane), 2.1, z_world - 0.9 + float(k) * 1.8)


## 障碍物结构：Node3D 容器
##   ├─ StaticBody3D（阻挡）
##   └─ Area3D      （致死判定，必须与刚体平级，否则部分物理后端检测不到）
func _create_obstacle() -> Node3D:
	var root := Node3D.new()

	var body := StaticBody3D.new()
	body.collision_layer = GameConfig.LAYER_OBSTACLE
	body.collision_mask = 0
	root.add_child(body)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	mat.metallic = 0.0
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	col.name = "Col"
	col.shape = BoxShape3D.new()
	body.add_child(col)

	# 受伤判定区：直接检测玩家刚体（Area -> Body）
	var hazard := Area3D.new()
	hazard.name = "Hazard"
	hazard.collision_layer = GameConfig.LAYER_HAZARD
	hazard.collision_mask = GameConfig.LAYER_PLAYER
	hazard.monitoring = true
	hazard.monitorable = false
	var hcol := CollisionShape3D.new()
	hcol.shape = BoxShape3D.new()
	hazard.add_child(hcol)
	root.add_child(hazard)
	hazard.body_entered.connect(_on_hazard_body_entered)

	# 横杆的立柱（B4）：纯装饰，不参与碰撞。没有它横杆看起来像浮在半空。
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "PostL" if side < 0.0 else "PostR"
		post.mesh = BoxMesh.new()
		var pmat := StandardMaterial3D.new()
		pmat.roughness = 0.85
		pmat.metallic = 0.15
		post.material_override = pmat
		post.visible = false
		root.add_child(post)

	# 顶部亮色包边（D8）：俯视视角下障碍只剩顶面可见，用顶面语义色区分高度类型——
	# 绿 = 矮栏可跳、红 = 高墙必须换道、金 = 中高方块减速绕行；横杆自带发光不用包边。
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = BoxMesh.new()
	var cmat := StandardMaterial3D.new()
	cmat.roughness = 0.5
	cmat.metallic = 0.0
	cmat.emission_enabled = true
	cmat.emission_energy = 0.65
	cap.material_override = cmat
	cap.visible = false
	root.add_child(cap)

	# 矮栏专属的向上箭头（D8）：绿色发光三棱柱，明确「这条道可以跳过去」
	var arrow := MeshInstance3D.new()
	arrow.name = "Arrow"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.85, 0.5, 0.4)
	arrow.mesh = prism
	var amat := StandardMaterial3D.new()
	amat.roughness = 0.4
	amat.emission_enabled = true
	amat.emission_energy = 0.9
	arrow.material_override = amat
	arrow.visible = false
	root.add_child(arrow)

	root.set_meta("mesh", mesh)
	root.set_meta("col", col)
	root.set_meta("hcol", hcol)
	root.set_meta("cap", cap)
	root.set_meta("arrow", arrow)
	return root


func _setup_obstacle(root: Node3D, size: Vector3, color: Color, pos: Vector3,
		bar: bool = false) -> void:
	root.position = pos
	root.visible = true

	var mesh := root.get_meta("mesh") as MeshInstance3D
	(mesh.mesh as BoxMesh).size = size
	var mat := mesh.material_override as StandardMaterial3D
	mat.albedo_color = color
	# 横杆自带发光，远远就能认出「这条道要滑铲」
	mat.emission_enabled = bar
	mat.emission = color
	mat.emission_energy = 0.42 if bar else 0.0

	var col := root.get_meta("col") as CollisionShape3D
	(col.shape as BoxShape3D).size = size

	var hcol := root.get_meta("hcol") as CollisionShape3D
	# 判定盒在前进方向略大于视觉体积，确保玩家被挡住之前就已触发
	(hcol.shape as BoxShape3D).size = size + Vector3(0.0, 0.0, 0.4)

	# 立柱：从地面顶到杆子下沿
	var bottom := pos.y - size.y * 0.5
	var post_h := maxf(bottom, 0.02)
	for name in ["PostL", "PostR"]:
		if not root.has_node(name):
			continue
		var p := root.get_node(name) as MeshInstance3D
		p.visible = bar
		if not bar:
			continue
		(p.mesh as BoxMesh).size = Vector3(0.16, post_h, 0.16)
		p.position = Vector3(
			(1.0 if name == "PostR" else -1.0) * (size.x * 0.5 - 0.08),
			-(size.y * 0.5 + post_h * 0.5), 0.0)
		(p.material_override as StandardMaterial3D).albedo_color = color.darkened(0.45)

	# 顶部语义色包边 + 矮栏箭头（D8）：高度类型在俯视视角下一眼可辨
	var cap := root.get_meta("cap") as MeshInstance3D
	var arrow := root.get_meta("arrow") as MeshInstance3D
	if bar:
		# 横杆本体已发光（紫），不再叠加包边与箭头
		cap.visible = false
		arrow.visible = false
	else:
		var cap_color: Color
		if size.y <= 1.0:
			cap_color = GameConfig.COLOR_GOOD      # 矮栏：绿 = 可以跳
		elif size.y >= 2.0:
			cap_color = GameConfig.COLOR_BAD       # 高墙：红 = 必须换道
		else:
			cap_color = GameConfig.COLOR_ACCENT    # 大方块：金 = 减速绕行
		(cap.mesh as BoxMesh).size = Vector3(size.x + 0.14, 0.16, size.z + 0.14)
		cap.position = Vector3(0.0, size.y * 0.5 + 0.02, 0.0)
		var cmat := cap.material_override as StandardMaterial3D
		cmat.albedo_color = cap_color
		cmat.emission = cap_color
		cap.visible = true
		arrow.visible = size.y <= 1.0
		if arrow.visible:
			# 箭头坐在顶面包边之上，沿赛道指向前进方向
			arrow.position = Vector3(0.0, size.y * 0.5 + 0.36, 0.0)
			var amat := arrow.material_override as StandardMaterial3D
			amat.albedo_color = GameConfig.COLOR_GOOD
			amat.emission = GameConfig.COLOR_GOOD


func _on_hazard_body_entered(body: Node3D) -> void:
	if body is Player and running:
		(body as Player).take_hit()


# ================================================================ 能量方块（金币）
func _spawn_coins(c: Chunk, blocked: Array, z_world: float) -> void:
	if _rng.randf() > 0.55:
		return

	var free_lanes := []
	for i in GameConfig.LANE_COUNT:
		if not blocked.has(i):
			free_lanes.append(i)
	if free_lanes.is_empty():
		return

	var lane: int = free_lanes[_rng.randi() % free_lanes.size()]
	var count := _rng.randi_range(2, 5)
	for k in count:
		var zz := z_world - float(k) * 2.2
		if zz < c.start_z - GameConfig.CHUNK_LENGTH:
			break
		_place_coin(c, GameConfig.lane_x(lane), 1.0, zz)


func _place_coin(c: Chunk, x: float, y: float, z_world: float) -> void:
	var coin := _acquire(_coin_pool, _create_coin)
	coin.position = Vector3(x, y, z_world - c.start_z)
	coin.visible = true
	coin.monitoring = true
	var mesh := coin.get_node("Mesh") as MeshInstance3D
	mesh.position = Vector3.ZERO
	mesh.rotation = Vector3.ZERO
	c.root.add_child(coin)
	c.coins.append(coin)


func _create_coin() -> Area3D:
	var area := Area3D.new()
	area.collision_layer = GameConfig.LAYER_PICKUP
	area.collision_mask = GameConfig.LAYER_PLAYER
	area.monitoring = true
	area.monitorable = false

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.55, 0.55)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GameConfig.COLOR_ACCENT
	mat.emission_enabled = true
	mat.emission = GameConfig.COLOR_ACCENT
	mat.emission_energy = 0.45
	mat.roughness = 0.35
	mat.metallic = 0.1
	mesh.material_override = mat
	area.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 1.3, 1.3)  # 判定略大，手感更好
	col.shape = shape
	area.add_child(col)

	area.body_entered.connect(_on_coin_picked.bind(area))
	return area


func _on_coin_picked(_body: Node3D, coin: Area3D) -> void:
	if not coin.visible or not running:
		return
	coin.visible = false
	coin.set_deferred("monitoring", false)  # 信号回调中必须延迟修改
	coins += 1

	# 连击（B3）：COMBO_WINDOW 秒内连续拾取则等级 +1，追加奖励分
	if _combo_timer > 0.0:
		combo += 1
	else:
		combo = 1
	_combo_timer = GameConfig.COMBO_WINDOW
	max_combo = maxi(max_combo, combo)
	if combo > 1:
		trick_score += (combo - 1) * GameConfig.COMBO_BONUS_PER_COIN

	_refresh_score()

	# 连续吃到方块时音高逐级上行（每 6 个循环一次），形成「连击」听感
	Sfx.play("coin", 1.0 + float(coins % 6) * 0.06)

	# 收集足够多的能量方块回复 1 点生命。
	# 满血时不清零计数器——攒着的进度留到掉血之后立刻兑现，不再白白浪费。
	_coins_since_heal += 1
	if _coins_since_heal >= GameConfig.HP_HEAL_PER_COINS:
		if player.heal(1):
			_coins_since_heal = 0
		else:
			_coins_since_heal = GameConfig.HP_HEAL_PER_COINS


func _animate_pickups(delta: float) -> void:
	for c in _chunks:
		# 金币：旋转 + 浮动；磁铁生效时朝玩家飞
		for coin in c.coins:
			if not coin.visible:
				continue
			coin.rotate_y(delta * 2.4)
			var mesh := coin.get_node("Mesh") as MeshInstance3D
			mesh.position.y = sin(_time * 3.0 + coin.position.z * 0.5) * 0.12
			if powerup_timers.has("magnet"):
				_magnet_pull(c, coin)
		# 道具：更快的旋转 + 上下浮动，远处靠光柱识别
		for pu in c.powerups:
			if not pu.visible:
				continue
			pu.rotate_y(delta * 3.2)
			var pmesh := pu.get_node("Mesh") as MeshInstance3D
			pmesh.position.y = sin(_time * 2.6 + pu.position.z * 0.5) * 0.18


## 磁铁（B2）：把附近金币往玩家身上拉。金币坐标是 chunk 局部坐标，要换算。
func _magnet_pull(c: Chunk, coin: Area3D) -> void:
	var world_z := coin.position.z + c.start_z
	var dx := player.position.x - coin.position.x
	var dz := player.position.z - world_z
	if absf(dx) > GameConfig.MAGNET_RADIUS or absf(dz) > GameConfig.MAGNET_RADIUS:
		return
	var target := Vector3(player.position.x, 1.0, player.position.z - c.start_z)
	coin.position = coin.position.move_toward(target, 30.0 * get_process_delta_time())


## 即时刷新分数（主循环每帧也会重算，这里保证拾取当帧 HUD 就对）
func _refresh_score() -> void:
	var base := int(distance * GameConfig.DISTANCE_SCORE) + coins * GameConfig.COIN_SCORE \
		+ trick_score
	score = base * 2 if powerup_timers.has("double") else base


# ================================================================ 道具（B2）
## 拾取效果：磁铁 / 双倍 / 冲刺为限时效果，护盾为一次性。
func _apply_powerup(type: String) -> void:
	var info := GameConfig.powerup(type)
	if type == "shield":
		player.set_shield(true)
		Sfx.play("shield_up")
	else:
		powerup_timers[type] = float(info["dur"])
		if type == "sprint":
			player.set_phase_through(true)
	Sfx.play("powerup")


func _update_powerups(delta: float) -> void:
	for type in powerup_timers.keys():
		powerup_timers[type] = float(powerup_timers[type]) - delta
		if float(powerup_timers[type]) <= 0.0:
			powerup_timers.erase(type)
			_end_powerup(String(type))


## 效果到期：只有冲刺需要显式恢复（穿障碍要关掉），其余靠 has() 判定自然失效
func _end_powerup(type: String) -> void:
	match type:
		"sprint":
			player.set_phase_through(false)


func _on_powerup_picked(_body: Node3D, area: Area3D) -> void:
	if not area.visible or not running:
		return
	area.visible = false
	area.set_deferred("monitoring", false)
	_apply_powerup(String(area.get_meta("type", "magnet")))


func _place_powerup(c: Chunk, type: String, x: float, y: float, z_world: float) -> void:
	var area := _acquire(_powerup_pool, _create_powerup)
	var info := GameConfig.powerup(type)
	area.position = Vector3(x, y, z_world - c.start_z)
	area.visible = true
	area.monitoring = true
	area.set_meta("type", type)

	var mesh := area.get_node("Mesh") as MeshInstance3D
	(mesh.mesh as BoxMesh).size = info["size"]
	var mat := mesh.material_override as StandardMaterial3D
	var color: Color = info["color"]
	mat.albedo_color = color
	mat.emission = color
	mesh.position = Vector3.ZERO
	mesh.rotation = Vector3.ZERO

	# 光柱：让远处一眼就能看到这里有个道具
	var beam := area.get_node("Beam") as MeshInstance3D
	var beam_mat := beam.material_override as StandardMaterial3D
	beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.16)
	beam_mat.emission = color

	c.root.add_child(area)
	c.powerups.append(area)


func _create_powerup() -> Area3D:
	var area := Area3D.new()
	area.collision_layer = GameConfig.LAYER_PICKUP
	area.collision_mask = GameConfig.LAYER_PLAYER
	area.monitoring = true
	area.monitorable = false

	# 本体：颜色 + 长宽高区分类型
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission_energy = 0.9
	mat.roughness = 0.3
	mat.metallic = 0.1
	mesh.material_override = mat
	area.add_child(mesh)

	# 判定盒略大于本体，拾取手感更好
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 1.6, 1.6)
	col.shape = shape
	area.add_child(col)

	# 光柱：细高的半透明发光柱，从远处也能定位
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.22, 7.0, 0.22)
	beam.mesh = bbox
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission_energy = 0.35
	bmat.roughness = 0.4
	beam.material_override = bmat
	beam.position = Vector3(0.0, 3.5, 0.0)
	area.add_child(beam)

	area.body_entered.connect(_on_powerup_picked.bind(area))
	return area


# ================================================================ 技巧计分（B3）
## 每物理帧：追踪滞空区间（跳栏 / 飞坑在落地时结算），障碍通过时判定擦身。
func _update_tricks() -> void:
	_score_slide_under()
	if not player.is_on_floor():
		if is_nan(_air_z_start):
			_air_z_start = player.position.z
		return
	if not is_nan(_air_z_start):
		_score_landing_tricks(_air_z_start, player.position.z)
		_air_z_start = NAN
	_score_near_misses()


## 滑铲穿杆（B4）：低姿从横杆正下方通过才计分。
## 逐帧记录「是否曾在杆下保持低姿」，而不是看通过瞬间的姿态——
## 否则玩家在杆下提前起身就白滑了，判定会变得很难触发。
func _score_slide_under() -> void:
	for c in _chunks:
		for o in c.obs:
			if not bool(o.get("bar", false)) or bool(o.get("under_scored", false)):
				continue
			var pz := player.position.z
			if pz <= float(o["z0"]) + 0.6 and pz >= float(o["z1"]) - 0.6:
				if player.sliding and absf(player.position.x - float(o["x"])) < 1.8:
					o["under"] = true
			elif pz < float(o["z1"]) - 0.6:
				o["under_scored"] = true
				if bool(o.get("under", false)):
					_add_trick(GameConfig.TRICK_SLIDE)


## 落地结算：滞空区间 [z_land, z_takeoff] 内越过的矮栏与坑洞
func _score_landing_tricks(z_takeoff: float, z_land: float) -> void:
	for c in _chunks:
		for o in c.obs:
			if not bool(o.get("low", false)) or bool(o.get("jump_scored", false)):
				continue
			var oz := (float(o["z0"]) + float(o["z1"])) * 0.5
			if oz <= z_takeoff + 1.0 and oz >= z_land - 1.0 \
					and absf(player.position.x - float(o["x"])) < 1.6:
				o["jump_scored"] = true
				_add_trick(GameConfig.TRICK_JUMP)
		for p in c.pits:
			if not bool(p.get("scored", false)) \
					and float(p["z0"]) > z_land - 1.0 and float(p["z1"]) < z_takeoff + 1.0:
				p["scored"] = true
				_add_trick(GameConfig.TRICK_PIT)


## 擦身而过：障碍完全落到身后时，横向距离在险区窗口内且人在地面
func _score_near_misses() -> void:
	for c in _chunks:
		for o in c.obs:
			if bool(o.get("passed", false)):
				continue
			if float(o["z1"]) < player.position.z - 0.8:
				o["passed"] = true
				# 闸门沉在地下时不该算「擦身而过」（B5）
				if bool(o.get("open", false)):
					continue
				# 矮栏绕行没有难度，只奖励高墙 / 大方块的擦身
				if player.is_on_floor() and not bool(o.get("low", false)):
					var dx := absf(player.position.x - float(o["x"]))
					if dx > GameConfig.NEAR_MISS_MIN and dx < GameConfig.NEAR_MISS_MAX:
						_add_trick(GameConfig.TRICK_NEAR_MISS)


## 记一笔技巧分：连击越高，单次技巧的奖励越大
func _add_trick(points: int) -> void:
	var bonus := int(round(float(points) * (1.0 + float(combo) * 0.05)))
	trick_score += bonus
	_refresh_score()
	Sfx.play("trick", 1.0 + float(combo % 8) * 0.05, -2.0)


# ================================================================ 装饰（树木 / 岩石 / 路缘石）
func _spawn_decorations(c: Chunk) -> void:
	# 路缘石：勾出跑道边界
	var curb_count := int(GameConfig.CHUNK_LENGTH / 6.0)
	for i in curb_count:
		var z := -(float(i) + 0.5) * 6.0
		for s in [-1.0, 1.0]:
			_add_deco(c,
				Vector3(0.8, 0.55, 4.4),
				_theme["curb"],
				Vector3(s * (GameConfig.WORLD_HALF_WIDTH + 0.45), 0.275, z))

	# 树木与岩石（长在赛道两侧的大地上，因此要落到 APRON_TOP 高度）
	var n := _rng.randi_range(3, 6)
	for i in n:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var x := side * (GameConfig.WORLD_HALF_WIDTH + _rng.randf_range(2.0, 15.0))
		var z := -_rng.randf_range(0.0, GameConfig.CHUNK_LENGTH)

		if _rng.randf() < 0.7:
			var trunk_h := _rng.randf_range(1.8, 3.6)
			var leaf := _rng.randf_range(1.4, 2.6)
			var leaf_color: Color = (_theme["leaf"] as Color).lerp(
				Color.WHITE, _rng.randf_range(0.0, 0.18))
			_add_deco(c, Vector3(0.6, trunk_h, 0.6), _theme["trunk"],
				Vector3(x, APRON_TOP + trunk_h * 0.5, z))
			_add_deco(c, Vector3(leaf, leaf * 0.85, leaf), leaf_color,
				Vector3(x, APRON_TOP + trunk_h + leaf * 0.42, z))
		else:
			var s := _rng.randf_range(0.8, 1.8)
			_add_deco(c, Vector3(s, s * _rng.randf_range(0.5, 0.9), s),
				_theme["rock"], Vector3(x, APRON_TOP + s * 0.28, z))


func _add_deco(c: Chunk, size: Vector3, color: Color, pos: Vector3) -> void:
	var deco := _acquire(_deco_pool, _create_deco)
	deco.position = pos
	deco.visible = true
	(deco.mesh as BoxMesh).size = size
	(deco.material_override as StandardMaterial3D).albedo_color = color
	c.root.add_child(deco)
	c.decos.append(deco)


func _create_deco() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 0.0
	mesh.material_override = mat
	return mesh


# ================================================================ 敌人
func _update_enemies(delta: float) -> void:
	_enemy_timer -= delta
	if _enemy_timer <= 0.0:
		var interval := randf_range(
			GameConfig.ENEMY_SPAWN_MIN, GameConfig.ENEMY_SPAWN_MAX) / maxf(_enemy_mul, 0.5)
		_enemy_timer = interval * (1.0 - clampf(distance / 1500.0, 0.0, 1.0) * 0.35)
		if _active_enemies.size() < _max_enemies():
			_spawn_enemy()


func _max_enemies() -> int:
	# 无限模式：敌人上限随里程缓慢上涨（2 → 4），难度倍率照常生效
	var base := clampi(2 + int(distance / 700.0), 2, 4) if infinite \
		else int(round(float(_level.get("enemy_max", 2)) * _enemy_mul))
	var grow := 1 + int(distance / 450.0)
	return clampi(mini(grow, base), 1, 4)


func _spawn_enemy() -> void:
	var e := _acquire_enemy()
	var lane := _rng.randi_range(0, GameConfig.LANE_COUNT - 1)
	var z := player.position.z + GameConfig.ENEMY_SPAWN_BEHIND + _rng.randf_range(0.0, 15.0)
	var file: String = ENEMY_ANIMALS[_rng.randi() % ENEMY_ANIMALS.size()]
	# 凶悍度 = 跑动进度 × 难度追兵倍率：越往后、难度越高，狠角色出现得越频繁
	var intensity := clampf(distance / 1200.0, 0.0, 1.0) * clampf(_enemy_mul, 0.0, 1.6)
	var kind := GameConfig.pick_enemy_kind(_rng, intensity)
	e.spawn(self, lane, z,
		speed * _rng.randf_range(GameConfig.ENEMY_SPEED_RATIO_MIN, GameConfig.ENEMY_SPEED_RATIO_MAX),
		file, kind)
	_active_enemies.append(e)


func _acquire_enemy() -> Enemy:
	var e: Enemy
	if _enemy_pool.is_empty():
		e = Enemy.new()
		e.name = "Enemy"
		add_child(e)
	else:
		e = _enemy_pool.pop_back()
	return e


func recycle_enemy(e: Enemy) -> void:
	e.despawn()
	_active_enemies.erase(e)
	_enemy_pool.append(e)


## 敌人向 World 查询本关的速度系数
func enemy_speed_factor() -> float:
	return _enemy_speed_mul


# ================================================================ 敌人 AI 查询接口
## 车道 [lane] 在 z 前方 [ahead] 米内是否被障碍挡住
func lane_blocked_ahead(z: float, lane: int, ahead: float) -> bool:
	var z_hi := z + 1.0
	var z_lo := z - ahead
	for c in _chunks:
		for o in c.obs:
			# 闸门处于「打开」状态时不算挡路（B5）
			if bool(o.get("open", false)):
				continue
			if lane >= o["l0"] and lane <= o["l1"]:
				if o["z1"] < z_hi and o["z0"] > z_lo:
					return true
	return false


## z 前方 [ahead] 米内是否有坑洞（坑洞占满所有车道，与车道无关）
func pit_ahead(z: float, ahead: float) -> bool:
	var z_hi := z + 1.0
	var z_lo := z - ahead
	for c in _chunks:
		for p in c.pits:
			if p["z1"] < z_hi and p["z0"] > z_lo:
				return true
	return false


## 找一条前方畅通的车道，优先靠近 [prefer]；找不到返回 -1
func find_free_lane(z: float, prefer: int, ahead: float) -> int:
	var order := [prefer]
	for offset in range(1, GameConfig.LANE_COUNT):
		var left := prefer - offset
		var right := prefer + offset
		if left >= 0:
			order.append(left)
		if right < GameConfig.LANE_COUNT:
			order.append(right)

	for l in order:
		if l >= 0 and l < GameConfig.LANE_COUNT and not lane_blocked_ahead(z, l, ahead):
			return l
	return -1


# ================================================================ 对象池
func _acquire(pool: Array, factory: Callable) -> Node3D:
	if pool.is_empty():
		return factory.call() as Node3D
	return pool.pop_back() as Node3D


func _release(pool: Array, node: Node3D) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	pool.append(node)


# ================================================================ 内嵌数据结构
## 地面的一「行」。挖空这一行即形成必须跳跃跨越的坑洞。
class FloorSlab extends RefCounted:
	var root: Node3D
	var mesh: MeshInstance3D
	var mat: StandardMaterial3D
	var body: StaticBody3D
	var lane_mats: Array[StandardMaterial3D] = []
	var lane_lines: Array[MeshInstance3D] = []
	var col: CollisionShape3D
	var warn: MeshInstance3D               # 坑洞前的预警条纹
	var warn_mat: StandardMaterial3D
	var glow: MeshInstance3D               # 坑底发光面
	var glow_mat: StandardMaterial3D
	var is_pit: bool = false

	## 设为坑洞 / 恢复为地面。
	## 坑洞行不是整行挖空，而是把地面缩短到近端的一段窄「跳台」，
	## 剩下的部分才是缺口——既保证可跳越的容错，也让坑洞看起来是断崖而不是整格消失。
	func set_pit(pit: bool, glow_color: Color, width: float) -> void:
		is_pit = pit
		var row := GameConfig.ROW_LENGTH
		var len_z: float = GameConfig.PIT_LEDGE if pit else row
		# 缩短后的地面靠近端（+z 一侧）对齐
		var off_z := (row - len_z) * 0.5

		(mesh.mesh as BoxMesh).size = Vector3(width, GameConfig.FLOOR_THICKNESS, len_z)
		mesh.position.z = off_z
		(col.shape as BoxShape3D).size = Vector3(width, GameConfig.FLOOR_THICKNESS, len_z)
		col.position.z = off_z

		# 车道线跟着缩短，否则会悬空伸出到坑洞上方
		for l in lane_lines:
			(l.mesh as BoxMesh).size.z = len_z
			l.position.z = off_z

		var show_glow := pit and glow_color.a > 0.0
		glow.visible = show_glow
		if show_glow:
			glow_mat.albedo_color = glow_color
			glow_mat.emission = glow_color

	func set_warn(on: bool, color: Color) -> void:
		warn.visible = on
		if on:
			warn_mat.albedo_color = color
			warn_mat.emission = color


class Chunk extends RefCounted:
	var index: int = 0
	var root: Node3D
	var start_z: float = 0.0              # 地块近端（较大的 z）
	var apron_mat: StandardMaterial3D     # 赛道两侧的大地
	var slabs: Array[FloorSlab] = []      # 按行切分的地面板块
	var obstacles: Array[Node3D] = []     # 障碍节点
	var coins: Array[Node3D] = []         # 能量方块
	var powerups: Array[Area3D] = []      # 道具拾取物（B2）
	var decos: Array[Node3D] = []         # 纯装饰
	var obs: Array[Dictionary] = []       # 障碍的车道占用信息，供敌人 AI 与技巧判定查询
	var pits: Array[Dictionary] = []      # 坑洞的 z 范围，供敌人 AI 与技巧判定查询
	var dyn: Array[Dictionary] = []       # 动态障碍（B5）：平移 / 开合闸门
