extends Node
## 全局存档与选择状态（Autoload 名：GameState）。
## 负责：记住玩家选择的角色 / 难度、关卡解锁进度、每个「关卡 + 难度」的最佳成绩，
## 以及生涯统计（C2）、总货币与角色解锁（C1）、成就进度（C3）。

const SAVE_PATH := "user://save.cfg"

## 当前选择的角色索引
var character_index: int = 0
## 当前选择的难度索引
var difficulty_index: int = 1
## 当前进入的关卡索引
var current_level: int = 0
## 已解锁的关卡数量（至少 1）
var unlocked_levels: int = 1
## 键："关卡索引_难度id"，值：最佳分数
var best_scores: Dictionary = {}
## 音效音量（0~1）与静音开关
var sfx_volume: float = 0.8
var sfx_muted: bool = false

# ---------------------------------------------------------------- 货币与角色解锁（C1）
## 总货币（能量方块）：局内收集的方块在结算时全额沉淀为货币
var coins_total: int = 0
## 已解锁的角色 id 列表（新档默认只有熊猫）
var unlocked_characters: Array = ["panda"]

# ---------------------------------------------------------------- 生涯统计（C2）
var stats_runs: int = 0              # 总局数（只统计打完的局）
var stats_distance: float = 0.0      # 总里程（米）
var stats_coins: int = 0             # 总共收集的能量方块
var stats_best_distance: float = 0.0 # 最远单局（米）
var stats_hitless_clears: int = 0    # 无伤通关次数
var stats_insane_clears: int = 0     # 噩梦难度通关次数
## 键：关卡索引（字符串），值：通关次数
var level_clears: Dictionary = {}

# ---------------------------------------------------------------- 成就（C3）
## 已解锁的成就 id -> true
var achievements: Dictionary = {}

# ---------------------------------------------------------------- 每日挑战（B1）
## 键：日期字符串 "YYYY-MM-DD"，值：当日最佳分数
var daily_best: Dictionary = {}


func _ready() -> void:
	load_save()


# ---------------------------------------------------------------- 存档
func load_save() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return

	unlocked_levels = maxi(1, int(file.get_value("progress", "unlocked", 1)))
	var loaded_best = file.get_value("progress", "best", {})
	if loaded_best is Dictionary:
		best_scores = loaded_best
	character_index = clampi(int(file.get_value("settings", "character", 0)),
		0, GameConfig.CHARACTERS.size() - 1)
	difficulty_index = clampi(int(file.get_value("settings", "difficulty", 1)),
		0, GameConfig.DIFFICULTIES.size() - 1)
	sfx_volume = clampf(float(file.get_value("settings", "sfx_volume", 0.8)), 0.0, 1.0)
	sfx_muted = bool(file.get_value("settings", "sfx_muted", false))

	# ---- 货币 / 角色解锁
	coins_total = maxi(0, int(file.get_value("meta", "coins", 0)))
	var saved_chars = file.get_value("meta", "unlocked_characters", [])
	if saved_chars is Array:
		unlocked_characters = _sanitize_characters(saved_chars)

	# ---- 生涯统计
	stats_runs = maxi(0, int(file.get_value("stats", "runs", 0)))
	stats_distance = maxf(0.0, float(file.get_value("stats", "distance", 0.0)))
	stats_coins = maxi(0, int(file.get_value("stats", "coins", 0)))
	stats_best_distance = maxf(0.0, float(file.get_value("stats", "best_distance", 0.0)))
	stats_hitless_clears = maxi(0, int(file.get_value("stats", "hitless_clears", 0)))
	stats_insane_clears = maxi(0, int(file.get_value("stats", "insane_clears", 0)))
	var saved_clears = file.get_value("stats", "level_clears", {})
	if saved_clears is Dictionary:
		level_clears = saved_clears

	# ---- 成就
	var saved_ach = file.get_value("meta", "achievements", {})
	if saved_ach is Dictionary:
		achievements = saved_ach

	# ---- 每日挑战
	var saved_daily = file.get_value("meta", "daily_best", {})
	if saved_daily is Dictionary:
		daily_best = saved_daily

	# 旧档迁移：当前选择的角色若未解锁（曾经全解锁的存档），回退到第一个已解锁角色
	if not is_character_unlocked(character_index):
		for i in GameConfig.CHARACTERS.size():
			if is_character_unlocked(i):
				character_index = i
				break


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("progress", "unlocked", unlocked_levels)
	file.set_value("progress", "best", best_scores)
	file.set_value("settings", "character", character_index)
	file.set_value("settings", "difficulty", difficulty_index)
	file.set_value("settings", "sfx_volume", sfx_volume)
	file.set_value("settings", "sfx_muted", sfx_muted)

	file.set_value("meta", "coins", coins_total)
	file.set_value("meta", "unlocked_characters", unlocked_characters)
	file.set_value("meta", "achievements", achievements)
	file.set_value("meta", "daily_best", daily_best)

	file.set_value("stats", "runs", stats_runs)
	file.set_value("stats", "distance", stats_distance)
	file.set_value("stats", "coins", stats_coins)
	file.set_value("stats", "best_distance", stats_best_distance)
	file.set_value("stats", "hitless_clears", stats_hitless_clears)
	file.set_value("stats", "insane_clears", stats_insane_clears)
	file.set_value("stats", "level_clears", level_clears)
	file.save(SAVE_PATH)


## 只保留配置表里真实存在的角色 id，并保证熊猫永远在列
func _sanitize_characters(list: Array) -> Array:
	var out: Array = []
	for id in list:
		var s := String(id)
		for ch in GameConfig.CHARACTERS:
			if String(ch["id"]) == s and not out.has(s):
				out.append(s)
	if not out.has("panda"):
		out.push_front("panda")
	return out


# ---------------------------------------------------------------- 关卡进度
func is_level_unlocked(index: int) -> bool:
	return index < unlocked_levels


func unlock_level(index: int) -> void:
	if index + 1 > unlocked_levels and index + 1 <= GameConfig.LEVELS.size():
		unlocked_levels = index + 1
		save()


# ---------------------------------------------------------------- 成绩
static func score_key(level_index: int, difficulty_id: String) -> String:
	return "%d_%s" % [level_index, difficulty_id]


func get_best(level_index: int, difficulty_id: String) -> int:
	return int(best_scores.get(score_key(level_index, difficulty_id), 0))


## 返回是否刷新了纪录
func record_score(level_index: int, difficulty_id: String, score: int) -> bool:
	var key := score_key(level_index, difficulty_id)
	if score > int(best_scores.get(key, 0)):
		best_scores[key] = score
		save()
		return true
	return false


# ---------------------------------------------------------------- 货币与角色解锁（C1）
func is_character_unlocked(index: int) -> bool:
	return unlocked_characters.has(String(GameConfig.character(index)["id"]))


## 解锁角色需要的货币数
func character_cost(index: int) -> int:
	return int(GameConfig.character(index).get("cost", 0))


# ---------------------------------------------------------------- 复活 / 续关（C4）
## 货币是否够一次复活
func can_revive() -> bool:
	return coins_total >= GameConfig.REVIVE_COST


## 扣除一次复活的花费。成功返回 true，货币不足返回 false（不扣钱）。
func spend_revive() -> bool:
	if coins_total < GameConfig.REVIVE_COST:
		return false
	coins_total -= GameConfig.REVIVE_COST
	save()
	return true


## 花费货币解锁角色。成功（或早已解锁）返回 true；货币不足返回 false。
func try_unlock_character(index: int) -> bool:
	if is_character_unlocked(index):
		return true
	var cost := character_cost(index)
	if coins_total < cost:
		return false
	coins_total -= cost
	unlocked_characters.append(String(GameConfig.character(index)["id"]))
	check_achievements()  # 可能顺便达成「动物庄园」
	save()
	return true


# ---------------------------------------------------------------- 生涯结算（C2 + C1 + C3）
## 一局结束时调用：累加统计、沉淀货币、刷新成就。
## [param hits] 本局受到的伤害次数（无伤判定用）。
## 返回本次新达成的成就 id 列表。
func record_run(completed: bool, coins: int, distance: float, hits: int,
		level_index: int, difficulty_id: String) -> Array[String]:
	stats_runs += 1
	stats_distance += maxf(0.0, distance)
	stats_coins += maxi(0, coins)
	coins_total += maxi(0, coins)
	if distance > stats_best_distance:
		stats_best_distance = distance

	if completed:
		level_clears[str(level_index)] = int(level_clears.get(str(level_index), 0)) + 1
		if hits <= 0:
			stats_hitless_clears += 1
		if difficulty_id == "insane":
			stats_insane_clears += 1

	var new_achievements := check_achievements()
	save()
	return new_achievements


# ---------------------------------------------------------------- 成就（C3）
## 某项成就的当前进度（达到 goal 即解锁）
func achievement_progress(id: String) -> float:
	match id:
		"first_run", "runs_10", "runs_30":
			return float(stats_runs)
		"dist_10km", "dist_50km":
			return stats_distance
		"coins_500", "coins_2000":
			return float(stats_coins)
		"single_1000", "single_2000":
			return stats_best_distance
		"hitless":
			return float(stats_hitless_clears)
		"insane_clear":
			return float(stats_insane_clears)
		"all_levels":
			return float(level_clears.size())
		"all_chars":
			return float(unlocked_characters.size())
	return 0.0


## 检查所有成就，解锁已达标的。返回本次新达成的 id 列表。
func check_achievements() -> Array[String]:
	var out: Array[String] = []
	for a in GameConfig.ACHIEVEMENTS:
		var id := String(a["id"])
		if achievements.has(id):
			continue
		if achievement_progress(id) >= float(a["goal"]):
			achievements[id] = true
			out.append(id)
	return out


## 已解锁成就数 / 总数
func achievement_count() -> int:
	return achievements.size()


# ---------------------------------------------------------------- 每日挑战（B1）
## 今日最佳分数；返回是否刷新了纪录
func record_daily(score: int) -> bool:
	var today := Time.get_date_string_from_system()
	if score > int(daily_best.get(today, 0)):
		daily_best[today] = score
		# 只保留最近 30 天，存档不至于无限膨胀
		if daily_best.size() > 30:
			var keys := daily_best.keys()
			keys.sort()
			while keys.size() > 30:
				daily_best.erase(keys.pop_front())
		save()
		return true
	return false


func get_daily_best() -> int:
	return int(daily_best.get(Time.get_date_string_from_system(), 0))


# ---------------------------------------------------------------- 对局参数
## 最终生命值 = 难度基础生命 + 角色加成（至少 1）
func final_hp() -> int:
	var base := int(GameConfig.difficulty(difficulty_index)["hp"])
	var bonus := int(GameConfig.character(character_index)["hp"])
	return maxi(1, base + bonus)


func final_score(score: int) -> int:
	return int(score * float(GameConfig.difficulty(difficulty_index)["score"]))
