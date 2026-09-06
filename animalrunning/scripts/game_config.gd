extends Node
## 全局配置（Autoload 名：GameConfig）。
## 包含：赛道 / 速度 / 碰撞层等基础常量，以及角色、关卡、难度、主题四张数据表。
## 想调整游戏平衡，基本只需要改这个文件。

# ---------------------------------------------------------------- 赛道
const LANE_COUNT := 5
const LANE_WIDTH := 3.0
const WORLD_WIDTH := LANE_COUNT * LANE_WIDTH
const WORLD_HALF_WIDTH := WORLD_WIDTH * 0.5

const CHUNK_LENGTH := 30.0      # 单个地形块长度
const CHUNK_COUNT := 8          # 同时存在的地形块数量
const ROW_LENGTH := 6.0         # 一行障碍的间距
const FLOOR_THICKNESS := 1.0
const CAM_HEIGHT := 22.0
const CAM_BACK := 10.0

# ---------------------------------------------------------------- 速度
const BASE_SPEED := 15.0        # 起始前进速度 (m/s)
const MAX_SPEED := 46.0         # 速度上限
const SPEED_PER_SECOND := 0.42  # 每秒自然加速
const SPEED_PER_METER := 0.0035 # 每跑 1 米的额外加速
const HIT_SPEED_MUL := 0.55     # 受击瞬间速度惩罚
const HIT_RECOVER_TIME := 1.2   # 速度惩罚恢复时间（秒）

# ---------------------------------------------------------------- 玩家
const JUMP_VELOCITY := 11.5
const GRAVITY := -32.0
const FAST_FALL_VELOCITY := -24.0
const LANE_SWITCH_SPEED := 20.0 # 横向换道速度
const JUMP_BUFFER_TIME := 0.12
const PLAYER_HEIGHT := 1.7
const PLAYER_START_Z := 0.0
const FALL_DEATH_Y := -8.0      # 掉进坑洞后低于此高度判定坠落

# ---------------------------------------------------------------- 坑洞（断崖）
## 坑洞占满全部车道，必须跳过去。
## 坑洞所在的一行仍在近端保留一段实地（PIT_LEDGE），因此实际缺口 = ROW_LENGTH - PIT_LEDGE。
## 这样做是为了留出足够的「起跳容错窗口」：
##   最慢组合 = 悠闲难度(0.85) × 大象(速度 0.90) → 11.5 m/s，大象跳跃 0.95 滞空 0.68 s，
##   水平可飞越约 7.8 m。缺口 4 m 意味着允许提前 ~3.8 m（约 0.33 s）起跳，手感宽容；
##   若缺口取满 6 m，容错只剩 1.3 m（0.12 s），几乎是像素级判定，太苛刻。
const PIT_LEDGE := 2.0          # 坑洞行近端保留的实地长度（跳台）
const PIT_GAP := ROW_LENGTH - PIT_LEDGE  # 实际缺口宽度
## 坑底发光面的深度。不能太深，否则俯视视角下完全看不到熔岩 / 幽蓝的坑底，
## 坑洞就只是一条黑带，缺少「深渊」的暗示。
const PIT_DEPTH := 2.6

# ---------------------------------------------------------------- 生命 / 受击
const INVINCIBLE_TIME := 1.6        # 受击后无敌时长
const INVINCIBLE_BLINK := 12.0      # 无敌闪烁频率
const HP_HEAL_PER_COINS := 25       # 每收集多少个能量方块回复 1 点生命
const ENEMY_KNOCKBACK := 26.0       # 撞到敌人时把敌人弹开的距离

# ---------------------------------------------------------------- 敌人
const ENEMY_HEIGHT := 1.7
const ENEMY_LANE_SWITCH := 14.0
const ENEMY_THINK_MIN := 0.12       # AI 决策间隔
const ENEMY_THINK_MAX := 0.32
const ENEMY_ACCEL := 6.0
# 橡皮筋追击倍率（乘以玩家当前速度）
const ENEMY_CHASE_FAR := 1.22       # 落后 30 m 以上：全力追击
const ENEMY_CHASE_MID := 1.06       # 落后 12~30 m
const ENEMY_CHASE_NEAR := 0.99      # 落后 2~12 m：并驾齐驱
const ENEMY_CHASE_CONTACT := 0.88   # 已经贴身：略微收力，给玩家甩开的机会
const ENEMY_SPAWN_MIN := 4.0        # 生成间隔（秒）
const ENEMY_SPAWN_MAX := 8.0
const ENEMY_SPAWN_BEHIND := 45.0
const ENEMY_SPEED_RATIO_MIN := 0.95 # 出生速度 = 玩家当前速度 × [MIN, MAX]
const ENEMY_SPEED_RATIO_MAX := 1.15
const ENEMY_DESPAWN_BEHIND := 70.0
const ENEMY_LOOK_AHEAD := 12.0      # AI 避障前视距离

# ---------------------------------------------------------------- 追兵类型
## 四种行为原型，让「追兵更凶」不只体现在速度上。
##   speed       速度倍率
##   lane_switch 横向机动倍率
##   think       决策间隔倍率（越小反应越快）
##   miss        判断失误概率（越小越精准）
##   burst       冲刺爆发强度（0 表示不冲刺）
##   can_jump    是否会跳过矮栏（而不是绕开）
##   lock_lane   是否死咬玩家车道（封路型）
##   aggr        凶悍度：越高则在高难度 / 后期出现得越频繁
const ENEMY_KINDS: Array[Dictionary] = [
	{
		"id": "runner", "name": "追猎者", "weight": 1.00, "aggr": 0.0,
		"speed": 1.00, "lane_switch": 1.00, "think": 1.00, "miss": 0.20,
		"burst": 0.00, "can_jump": false, "lock_lane": false,
		"tint": Color8(0xff, 0xff, 0xff),
	},
	{
		"id": "sprinter", "name": "冲刺者", "weight": 0.55, "aggr": 1.0,
		"speed": 1.02, "lane_switch": 0.95, "think": 1.15, "miss": 0.26,
		"burst": 0.42, "can_jump": false, "lock_lane": false,
		"tint": Color8(0xff, 0xb0, 0x88),
	},
	{
		"id": "blocker", "name": "封路者", "weight": 0.45, "aggr": 1.3,
		"speed": 0.97, "lane_switch": 1.45, "think": 0.55, "miss": 0.06,
		"burst": 0.00, "can_jump": false, "lock_lane": true,
		"tint": Color8(0xa8, 0xc0, 0xff),
	},
	{
		"id": "jumper", "name": "跳跃者", "weight": 0.40, "aggr": 0.8,
		"speed": 1.00, "lane_switch": 0.85, "think": 0.85, "miss": 0.14,
		"burst": 0.00, "can_jump": true, "lock_lane": false,
		"tint": Color8(0xc4, 0xff, 0xc0),
	},
]

const ENEMY_BURST_MIN := 2.4        # 冲刺者的爆发间隔（秒）
const ENEMY_BURST_MAX := 4.6
const ENEMY_BURST_TIME := 1.1       # 单次爆发持续时长
const ENEMY_JUMP_VELOCITY := 9.5    # 跳跃者的起跳速度（纯动画，不参与物理）

# ---------------------------------------------------------------- 计分
const COIN_SCORE := 10
const DISTANCE_SCORE := 1.0     # 每米得分

# ---------------------------------------------------------------- 碰撞层
const LAYER_PLAYER := 1
const LAYER_WORLD := 2          # 地面
const LAYER_ENEMY := 4
const LAYER_PICKUP := 8
const LAYER_HAZARD := 16
const LAYER_OBSTACLE := 32      # 障碍物实体（无敌期间可穿过）

# ---------------------------------------------------------------- 角色
## speed / jump / lane 为倍率，hp 为生命值加成；color 为该角色在界面上的主题色；
## cost 为解锁所需的能量方块（0 表示初始即解锁）
const CHARACTERS: Array[Dictionary] = [
	{
		"id": "panda", "name": "熊猫", "file": "animal-panda.glb",
		"desc": "全能选手，没有明显短板", "tag": "均衡",
		"color": Color8(0x8f, 0xc7, 0xf0),
		"speed": 1.00, "jump": 1.00, "lane": 1.00, "hp": 0, "cost": 0,
	},
	{
		"id": "tiger", "name": "老虎", "file": "animal-tiger.glb",
		"desc": "速度 +12%，但生命 -1", "tag": "极速",
		"color": Color8(0xff, 0x9d, 0x4d),
		"speed": 1.12, "jump": 1.00, "lane": 1.00, "hp": -1, "cost": 600,
	},
	{
		"id": "bunny", "name": "兔子", "file": "animal-bunny.glb",
		"desc": "跳跃 +15%，换道 +15%", "tag": "灵巧",
		"color": Color8(0xff, 0xa8, 0xc8),
		"speed": 1.00, "jump": 1.15, "lane": 1.15, "hp": 0, "cost": 400,
	},
	{
		"id": "fox", "name": "狐狸", "file": "animal-fox.glb",
		"desc": "换道 +30%，跳跃略弱", "tag": "机动",
		"color": Color8(0xff, 0xc2, 0x6b),
		"speed": 1.05, "jump": 0.92, "lane": 1.30, "hp": 0, "cost": 800,
	},
	{
		"id": "penguin", "name": "企鹅", "file": "animal-penguin.glb",
		"desc": "生命 +1，速度 -5%", "tag": "稳健",
		"color": Color8(0x7f, 0xe3, 0xe0),
		"speed": 0.95, "jump": 1.00, "lane": 1.00, "hp": 1, "cost": 1000,
	},
	{
		"id": "elephant", "name": "大象", "file": "animal-elephant.glb",
		"desc": "生命 +2，但速度 -10%", "tag": "坦克",
		"color": Color8(0xa8, 0xb4, 0xe8),
		"speed": 0.90, "jump": 0.95, "lane": 0.90, "hp": 2, "cost": 1200,
	},
]

# ---------------------------------------------------------------- 难度
## hp 为基础生命；score 为得分倍率；obstacle / enemy 为密度倍率；speed 为速度倍率
const DIFFICULTIES: Array[Dictionary] = [
	{
		"id": "easy", "name": "悠闲散步", "color": Color8(0x7e, 0xd9, 0x8d),
		"hp": 5, "speed": 0.85, "obstacle": 0.75, "enemy": 0.60, "score": 0.7,
		"desc": "生命充足、追兵稀少，适合先熟悉手感",
	},
	{
		"id": "normal", "name": "标准逃亡", "color": Color8(0xff, 0xd2, 0x3f),
		"hp": 3, "speed": 1.00, "obstacle": 1.00, "enemy": 1.00, "score": 1.0,
		"desc": "平衡的速度与密度，推荐首选",
	},
	{
		"id": "hard", "name": "亡命狂奔", "color": Color8(0xf4, 0x8c, 0x5a),
		"hp": 2, "speed": 1.15, "obstacle": 1.20, "enemy": 1.35, "score": 1.5,
		"desc": "障碍更密、追兵更凶，得分 ×1.5",
	},
	{
		"id": "insane", "name": "噩梦模式", "color": Color8(0xe5, 0x4b, 0x4b),
		"hp": 1, "speed": 1.30, "obstacle": 1.40, "enemy": 1.70, "score": 2.2,
		"desc": "只剩一点生命，全靠完美操作，得分 ×2.2",
	},
]

# ---------------------------------------------------------------- 关卡
## distance 为通关所需距离；obstacle 为障碍密度基线；enemy_max 为同时存在的敌人上限
const LEVELS: Array[Dictionary] = [
	{
		"name": "翠绿草原", "subtitle": "阳光明媚的起点", "theme": "grass",
		"distance": 700.0, "obstacle": 0.50, "enemy_max": 2, "enemy_speed": 0.98,
	},
	{
		"name": "金色沙漠", "subtitle": "热浪与流沙", "theme": "desert",
		"distance": 900.0, "obstacle": 0.58, "enemy_max": 2, "enemy_speed": 1.02,
	},
	{
		"name": "白雪旷野", "subtitle": "打滑的冰雪赛道", "theme": "snow",
		"distance": 1100.0, "obstacle": 0.64, "enemy_max": 3, "enemy_speed": 1.05,
	},
	{
		"name": "幽暗森林", "subtitle": "密林中的追逐", "theme": "forest",
		"distance": 1300.0, "obstacle": 0.70, "enemy_max": 3, "enemy_speed": 1.08,
	},
	{
		"name": "熔岩峡谷", "subtitle": "炽热的生死时速", "theme": "volcano",
		"distance": 1600.0, "obstacle": 0.76, "enemy_max": 3, "enemy_speed": 1.12,
	},
	{
		"name": "极夜冰原", "subtitle": "最终试炼", "theme": "night",
		"distance": 2000.0, "obstacle": 0.82, "enemy_max": 4, "enemy_speed": 1.16,
	},
]

# ---------------------------------------------------------------- 主题（配色 + 机制）
## 除配色外，每个主题都带一组机制参数，让 6 个关卡的手感真正不同：
##   traction  抓地力（1.0 正常）。越低则换道越「飘」，需要提前打方向
##   wind      逆风强度（0 表示无风）。周期性阵风会压低前进速度
##   gap       每行出现坑洞的概率（0 表示没有坑洞）。坑洞必须跳过去
##   pit_glow  坑底发光色；Color.TRANSPARENT 表示纯黑深渊
##   warn      坑洞前预警条纹的颜色
const THEMES: Dictionary = {
	"grass": {
		"sky": Color8(0xa8, 0xd8, 0xf0), "fog": Color8(0xb6, 0xdd, 0xf2),
		"ambient": Color8(0x9f, 0xb4, 0xd8), "sun": Color8(0xff, 0xf6, 0xdc),
		"ground_a": Color8(0x74, 0xb3, 0x55), "ground_b": Color8(0x66, 0xa5, 0x4c),
		"lane": Color8(0x57, 0x93, 0x42), "curb": Color8(0x3f, 0x77, 0x36),
		"leaf": Color8(0x3f, 0x8f, 0x5f), "trunk": Color8(0x8b, 0x5e, 0x3c),
		"rock": Color8(0x9a, 0xa0, 0xa6),
		"low": Color8(0xe0, 0xa4, 0x58), "high": Color8(0xc8, 0x55, 0x3d),
		"block": Color8(0x8d, 0x87, 0x7e),
		"traction": 1.00, "wind": 0.00, "gap": 0.00,
		"pit_glow": Color.TRANSPARENT, "warn": Color8(0xff, 0xd2, 0x4d),
	},
	"desert": {
		"sky": Color8(0xe8, 0xc0, 0x84), "fog": Color8(0xdc, 0xb4, 0x7a),
		"ambient": Color8(0xa0, 0x80, 0x5a), "sun": Color8(0xff, 0xd8, 0x88),
		"ground_a": Color8(0xd4, 0x9c, 0x54), "ground_b": Color8(0x8a, 0x5e, 0x2e),
		"lane": Color8(0x52, 0x36, 0x1c), "curb": Color8(0x3a, 0x26, 0x18),
		"leaf": Color8(0x5a, 0x84, 0x36), "trunk": Color8(0x6e, 0x4e, 0x30),
		"rock": Color8(0x4a, 0x3e, 0x36),
		"low": Color8(0xa8, 0x42, 0x28), "high": Color8(0x6f, 0x2a, 0x30),
		"block": Color8(0x3e, 0x2c, 0x24),
		# 热浪与流沙：周期性逆风阵，需要预判节奏
		"traction": 0.88, "wind": 0.30, "gap": 0.00,
		"pit_glow": Color.TRANSPARENT, "warn": Color8(0xff, 0xe0, 0x70),
	},
	"snow": {
		"sky": Color8(0xd6, 0xe8, 0xf5), "fog": Color8(0xdc, 0xea, 0xf4),
		"ambient": Color8(0xc2, 0xd4, 0xe8), "sun": Color8(0xff, 0xff, 0xff),
		"ground_a": Color8(0xe8, 0xf0, 0xf7), "ground_b": Color8(0xda, 0xe6, 0xf0),
		"lane": Color8(0xc0, 0xd4, 0xe4), "curb": Color8(0xa4, 0xbc, 0xd2),
		"leaf": Color8(0x4f, 0x8a, 0x6a), "trunk": Color8(0x77, 0x62, 0x55),
		"rock": Color8(0xa8, 0xb4, 0xc0),
		"low": Color8(0x6f, 0xa8, 0xd8), "high": Color8(0x3f, 0x6f, 0xa8),
		"block": Color8(0x8a, 0x9a, 0xaa),
		# 打滑的冰雪赛道：抓地力大幅下降，换道会滑过头
		"traction": 0.45, "wind": 0.10, "gap": 0.00,
		"pit_glow": Color.TRANSPARENT, "warn": Color8(0x4f, 0x8f, 0xd8),
	},
	"forest": {
		"sky": Color8(0x8f, 0xb4, 0x8c), "fog": Color8(0x9c, 0xbc, 0x9a),
		"ambient": Color8(0x7a, 0x96, 0x7e), "sun": Color8(0xdc, 0xf0, 0xc0),
		"ground_a": Color8(0x4f, 0x8f, 0x4a), "ground_b": Color8(0x45, 0x82, 0x41),
		"lane": Color8(0x3a, 0x6d, 0x36), "curb": Color8(0x2e, 0x58, 0x2c),
		"leaf": Color8(0x2f, 0x6b, 0x3f), "trunk": Color8(0x6b, 0x4a, 0x33),
		"rock": Color8(0x7c, 0x86, 0x80),
		"low": Color8(0xc0, 0x8a, 0x4a), "high": Color8(0x8f, 0x45, 0x30),
		"block": Color8(0x6f, 0x6a, 0x60),
		# 密林中的追逐：开始出现塌陷的沟壑
		"traction": 0.92, "wind": 0.00, "gap": 0.17,
		"pit_glow": Color.TRANSPARENT, "warn": Color8(0xff, 0xe0, 0x60),
	},
	"volcano": {
		"sky": Color8(0x4a, 0x30, 0x38), "fog": Color8(0x5c, 0x38, 0x36),
		"ambient": Color8(0x8c, 0x54, 0x4a), "sun": Color8(0xff, 0xb0, 0x70),
		"ground_a": Color8(0x4f, 0x3c, 0x3c), "ground_b": Color8(0x44, 0x33, 0x33),
		"lane": Color8(0x30, 0x24, 0x24), "curb": Color8(0x2a, 0x1f, 0x1f),
		"leaf": Color8(0x7a, 0x3a, 0x2c), "trunk": Color8(0x4a, 0x33, 0x2c),
		"rock": Color8(0x5a, 0x50, 0x50),
		"low": Color8(0xff, 0x8c, 0x3a), "high": Color8(0xff, 0x4a, 0x2a),
		"block": Color8(0x3a, 0x33, 0x33),
		# 炽热的生死时速：熔岩裂谷 + 上升热气流带来的扰动
		"traction": 0.86, "wind": 0.18, "gap": 0.32,
		"pit_glow": Color8(0xff, 0x6a, 0x1e), "warn": Color8(0xff, 0xc8, 0x40),
	},
	"night": {
		"sky": Color8(0x1c, 0x24, 0x3c), "fog": Color8(0x26, 0x30, 0x4c),
		"ambient": Color8(0x5a, 0x6c, 0x9c), "sun": Color8(0xc0, 0xd4, 0xff),
		"ground_a": Color8(0x3c, 0x4a, 0x6c), "ground_b": Color8(0x33, 0x40, 0x60),
		"lane": Color8(0x28, 0x33, 0x4f), "curb": Color8(0x22, 0x2b, 0x44),
		"leaf": Color8(0x3f, 0x6f, 0x8f), "trunk": Color8(0x4a, 0x44, 0x58),
		"rock": Color8(0x6a, 0x74, 0x8c),
		"low": Color8(0x8f, 0xd4, 0xff), "high": Color8(0xc0, 0x6f, 0xd4),
		"block": Color8(0x4a, 0x54, 0x70),
		# 最终试炼：冰滑 + 寒风 + 裂隙，三种机制叠加
		"traction": 0.58, "wind": 0.22, "gap": 0.26,
		"pit_glow": Color8(0x4a, 0x8f, 0xff), "warn": Color8(0x9f, 0xd8, 0xff),
	},
}

## 主题机制的中文摘要，用于在难度界面提前告知玩家本关特性
static func theme_traits(theme_name: String) -> Array[String]:
	var t := theme(theme_name)
	var out: Array[String] = []
	var traction := float(t.get("traction", 1.0))
	if traction <= 0.6:
		out.append("地面极滑")
	elif traction <= 0.9:
		out.append("地面湿滑")
	if float(t.get("wind", 0.0)) >= 0.25:
		out.append("强逆风")
	elif float(t.get("wind", 0.0)) > 0.0:
		out.append("阵风")
	var gap := float(t.get("gap", 0.0))
	if gap >= 0.22:
		out.append("大量裂谷")
	elif gap > 0.0:
		out.append("有裂谷")
	if out.is_empty():
		out.append("路况良好")
	return out

# ---------------------------------------------------------------- 成就
## id     唯一标识（存档键）
## name   成就名
## desc   达成条件说明
## goal   目标值（进度达到即解锁，进度取值见 GameState.achievement_progress）
## unit   进度数值的单位（用于生涯界面显示）
const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_run", "name": "初次逃亡", "desc": "完成第一局",
		"goal": 1, "unit": "局"},
	{"id": "runs_10", "name": "常客", "desc": "累计完成 10 局",
		"goal": 10, "unit": "局"},
	{"id": "runs_30", "name": "逃亡惯犯", "desc": "累计完成 30 局",
		"goal": 30, "unit": "局"},
	{"id": "dist_10km", "name": "十里奔袭", "desc": "累计跑动 10 km",
		"goal": 10000, "unit": "m"},
	{"id": "dist_50km", "name": "马拉松方阵", "desc": "累计跑动 50 km",
		"goal": 50000, "unit": "m"},
	{"id": "coins_500", "name": "收集狂", "desc": "累计收集 500 个能量方块",
		"goal": 500, "unit": "个"},
	{"id": "coins_2000", "name": "方块大亨", "desc": "累计收集 2000 个能量方块",
		"goal": 2000, "unit": "个"},
	{"id": "single_1000", "name": "千里之行", "desc": "单局跑出 1000 m",
		"goal": 1000, "unit": "m"},
	{"id": "single_2000", "name": "一骑绝尘", "desc": "单局跑出 2000 m",
		"goal": 2000, "unit": "m"},
	{"id": "hitless", "name": "毫发无损", "desc": "单局不受任何伤害并通关",
		"goal": 1, "unit": "次"},
	{"id": "insane_clear", "name": "噩梦终结者", "desc": "以噩梦难度通关任意关卡",
		"goal": 1, "unit": "次"},
	{"id": "all_levels", "name": "通关大满贯", "desc": "通关全部 6 个关卡",
		"goal": 6, "unit": "关"},
	{"id": "all_chars", "name": "动物庄园", "desc": "解锁全部 6 个角色",
		"goal": 6, "unit": "个"},
]


static func achievement(index: int) -> Dictionary:
	return ACHIEVEMENTS[clampi(index, 0, ACHIEVEMENTS.size() - 1)]


# ---------------------------------------------------------------- 通用配色（UI）
## 原则：正文与深色底的对比度足够高；辅助文字不再使用灰蓝色 + 粗描边，避免糊成一团。
const COLOR_TEXT := Color8(0xf4, 0xf8, 0xff)        # 主要文字
const COLOR_DIM := Color8(0xbe, 0xcc, 0xe4)         # 次要文字（比原来更亮）
const COLOR_MUTED := Color8(0x92, 0xa2, 0xbe)       # 弱化文字（仅用于大面积说明）
const COLOR_ACCENT := Color8(0xff, 0xcc, 0x4d)      # 主强调色：金
const COLOR_INFO := Color8(0x7d, 0xc8, 0xff)        # 数值 / 信息蓝
const COLOR_GOOD := Color8(0x74, 0xdd, 0x9c)        # 正向
const COLOR_BAD := Color8(0xff, 0x6b, 0x6b)         # 负向 / 危险

const COLOR_BG_TOP := Color8(0x1a, 0x25, 0x42)      # 背景渐变（上）
const COLOR_BG_BOTTOM := Color8(0x08, 0x0c, 0x18)   # 背景渐变（下）
const COLOR_PANEL := Color8(0x1a, 0x24, 0x3c, 238)
const COLOR_PANEL_SOFT := Color8(0x23, 0x30, 0x4e, 220)
const COLOR_CARD := Color8(0x1e, 0x2a, 0x45)
const COLOR_CARD_HOVER := Color8(0x2a, 0x39, 0x5c)
const COLOR_CARD_SELECTED := Color8(0x2f, 0x41, 0x69)
const COLOR_LINE := Color8(0x3c, 0x4c, 0x70)        # 分隔线 / 弱边框
const COLOR_OUTLINE := Color8(0x07, 0x0b, 0x16, 230)
const COLOR_SHADOW := Color8(0x00, 0x00, 0x00, 120)


## 车道索引 -> 世界 X 坐标
static func lane_x(lane: int) -> float:
	return (float(lane) - (LANE_COUNT - 1) * 0.5) * LANE_WIDTH


## 限制车道索引在合法范围内
static func clamp_lane(lane: int) -> int:
	return clampi(lane, 0, LANE_COUNT - 1)


static func character(index: int) -> Dictionary:
	return CHARACTERS[clampi(index, 0, CHARACTERS.size() - 1)]


static func difficulty(index: int) -> Dictionary:
	return DIFFICULTIES[clampi(index, 0, DIFFICULTIES.size() - 1)]


static func level(index: int) -> Dictionary:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


static func theme(name: String) -> Dictionary:
	return THEMES.get(name, THEMES["grass"])


static func enemy_kind(index: int) -> Dictionary:
	return ENEMY_KINDS[clampi(index, 0, ENEMY_KINDS.size() - 1)]


## 按凶悍度加权随机挑一种追兵。
## [param intensity] 0~1，由跑动距离与难度的追兵倍率共同决定：越大越容易出现狠角色。
static func pick_enemy_kind(rng: RandomNumberGenerator, intensity: float) -> int:
	var t := clampf(intensity, 0.0, 1.0)
	var weights: Array[float] = []
	var total := 0.0
	for k in ENEMY_KINDS:
		var w: float = float(k["weight"]) * (1.0 + float(k["aggr"]) * t * 2.0)
		weights.append(w)
		total += w
	if total <= 0.0:
		return 0

	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return 0
