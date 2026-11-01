extends Node
## 《？！珠珠！？》全局运行状态（Autoload 名：GameState）v1.2
## 新增：随机槽位内容、弹珠卡牌、局外行囊（跨局公共变量）、带入下一局的配置。
## 由 Lead 维护。几何/数值常量见 FateConfig；UI 与玩法层通过这里的方法读写状态。

signal coins_changed(value: int)
signal score_changed(level_score: int, total_score: int)
signal balls_changed(balls_left: int, balls_total: int)
signal level_started(level: int, target: int, fate_event: Dictionary)
signal level_cleared(level: int, level_score: int)
signal run_finished(victory: bool, total_score: int, shards: int, best: int)
signal library_changed(normal_count: int, advanced_count: int)
signal items_changed
signal meta_changed

const SAVE_PATH := "user://fate_save.json"

# ---- 本局状态 ----
var coins: int = FateConfig.START_COINS
var level: int = 1
var level_score: int = 0
var total_score: int = 0
var balls_left: int = FateConfig.BALLS_PER_LEVEL
var balls_total: int = FateConfig.BALLS_PER_LEVEL
## 本关弹珠槽：{"type":0普通/1进阶, "card":""/卡牌id}
var ball_slots: Array = []
## 本关底部 6 个框的随机内容：{"mult":float, "bonus":""/"coin2"/"ball1"}
var slot_configs: Array = []
## 弹珠库（跨房间累计）
var library_normal: int = 0
var library_advanced: int = 0
## 已购买但尚未拖拽使用的道具/卡
var pending_items: Array[String] = []
## 带入本局的局外卡牌（使用后从本局移除）
var run_loadout_cards: Array[String] = []
var run_items: Dictionary = {}
var fate_event: Dictionary = {}
var run_active: bool = false
## 双倍注：分数/金币奖励×2、黑柱惩罚×2、失败碎片减半
var double_mode: bool = false
## 新手引导是否已看过（跨局持久化）
var tutorial_seen: bool = false

# ---- 局外行囊（跨局持久化）----
var meta_balls_normal: int = 0
var meta_balls_advanced: int = 0
var meta_cards: Array[String] = []
## 玩家在局外勾选、准备带入下一局的内容
var selected_balls_normal: int = 0
var selected_balls_advanced: int = 0
var selected_cards: Array[String] = []

# ---- 跨局存档 ----
var best_score: int = 0
var best_level: int = 0
var total_shards: int = 0
var runs_played: int = 0

func _ready() -> void:
	randomize()
	load_save()

# ================= 流程 =================

## 开始新一局：消耗局外勾选的弹珠/卡牌，带入本局
func start_new_run() -> void:
	coins = FateConfig.START_COINS
	level = 1
	level_score = 0
	total_score = 0
	library_normal = selected_balls_normal
	library_advanced = selected_balls_advanced
	meta_balls_normal = maxi(0, meta_balls_normal - selected_balls_normal)
	meta_balls_advanced = maxi(0, meta_balls_advanced - selected_balls_advanced)
	run_loadout_cards.clear()
	for id in selected_cards:
		if meta_cards.has(id):
			meta_cards.erase(id)
			run_loadout_cards.append(id)
	meta_cards.sort()
	selected_balls_normal = 0
	selected_balls_advanced = 0
	selected_cards.clear()
	pending_items.clear()
	run_items.clear()
	fate_event = {}
	ball_slots.clear()
	slot_configs.clear()
	balls_total = FateConfig.BALLS_PER_LEVEL
	balls_left = balls_total
	run_active = true
	double_mode = false
	save_game()
	_emit_all()
	meta_changed.emit()
	print("[GameState] 新的一局开始：金币=%d 带入弹珠=%d/%d 卡牌=%s" % [
		coins, library_normal, library_advanced, str(run_loadout_cards)])

## 进入某个房间：重置本关数据、抽命运事件、随机底部框内容、生成弹珠槽
func prepare_level(lv: int) -> void:
	level = clampi(lv, 1, FateConfig.MAX_LEVEL)
	level_score = 0
	pending_items.clear()
	for id in run_loadout_cards:
		pending_items.append(id)
	ball_slots.clear()
	var count := FateConfig.BALLS_PER_LEVEL
	if run_items.has("gold_eye"):
		count += 1
	fate_event = roll_fate_event()
	count += int(fate_event.get("bonus_ball", 0))
	for i in count:
		ball_slots.append({"type": 0, "card": ""})
	balls_total = count
	balls_left = count
	slot_configs = roll_pocket_configs()
	var extra_coins: int = int(fate_event.get("bonus_coin", 0))
	if extra_coins != 0:
		coins += extra_coins
	_emit_all()
	level_started.emit(level, get_target(), fate_event)
	print("[GameState] 进入第%d间房「%s」目标=%d 命运事件=%s 弹珠=%d 框=%s" % [
		level, get_level_name(), get_target(), String(fate_event.get("name", "无")),
		balls_total, str(_pocket_desc())])

## 随机生成底部 6 个框的内容
func roll_pocket_configs() -> Array:
	var out: Array = []
	for i in FateConfig.SLOT_WEIGHTS.size():
		out.append({
			"mult": _pick_weighted_mult(),
			"bonus": _pick_weighted_bonus(),
		})
	return out

func _pick_weighted_mult() -> float:
	var total := 0
	for e in FateConfig.POCKET_MULT_POOL:
		total += int(e["weight"])
	var roll := randi() % maxi(total, 1)
	var acc := 0
	for e in FateConfig.POCKET_MULT_POOL:
		acc += int(e["weight"])
		if roll < acc:
			return float(e["mult"])
	return 1.0

func _pick_weighted_bonus() -> String:
	var total := 0
	for e in FateConfig.POCKET_BONUS_POOL:
		total += int(e["weight"])
	var roll := randi() % maxi(total, 1)
	var acc := 0
	for e in FateConfig.POCKET_BONUS_POOL:
		acc += int(e["weight"])
		if roll < acc:
			return String(e["id"])
	return ""

func _pocket_desc() -> String:
	var parts: Array[String] = []
	for c in slot_configs:
		var s := "x%s" % str(c.get("mult", 1.0))
		if String(c.get("bonus", "")) != "":
			s += "/" + String(c.get("bonus", ""))
		parts.append(s)
	return ",".join(parts)

func get_slot_config(index: int) -> Dictionary:
	if index < 0 or index >= slot_configs.size():
		return {"mult": 1.0, "bonus": ""}
	return slot_configs[index]

func get_pocket_mult(index: int) -> float:
	return float(get_slot_config(index).get("mult", 1.0))

func get_pocket_bonus(index: int) -> String:
	return String(get_slot_config(index).get("bonus", ""))

## 取下一颗待发射弹珠：返回 {index, advanced, card}
func take_next_ball() -> Dictionary:
	if balls_left <= 0:
		return {}
	var idx := balls_total - balls_left
	idx = clampi(idx, 0, maxi(ball_slots.size() - 1, 0))
	var slot: Dictionary = ball_slots[idx]
	balls_left -= 1
	balls_changed.emit(balls_left, balls_total)
	return {
		"index": idx,
		"advanced": int(slot.get("type", 0)) == 1,
		"card": String(slot.get("card", "")),
	}

## 单球结算（双倍注时得分×2）
func award_ball_score(base: int, yellow_hits: int, slot_mult: float, buffed: bool = false) -> int:
	var raw := float(base + yellow_hits * get_yellow_bonus())
	var buff_mult := FateConfig.BUFFED_BALL_MULT if buffed else 1.0
	var value := int(floor(raw * slot_mult * get_score_multiplier() * buff_mult * get_double_score_mult()))
	value = maxi(value, 0)
	level_score += value
	total_score += value
	score_changed.emit(level_score, total_score)
	return value

## 双倍注：得分倍率（普通 1 / 双倍 2）
func get_double_score_mult() -> float:
	return float(FateConfig.DOUBLE_MODE_SCORE_MULT) if double_mode else 1.0

## 双倍注：金币奖励倍率
func get_coin_mult() -> int:
	return FateConfig.DOUBLE_MODE_COIN_MULT if double_mode else 1

## 双倍注：惩罚倍率（黑柱扣分等）
func get_penalty_mult() -> int:
	return FateConfig.DOUBLE_MODE_PENALTY_MULT if double_mode else 1

func set_double_mode(enabled: bool) -> void:
	double_mode = enabled
	print("[GameState] 双倍注=", enabled)

## 白柱给的金币数（双倍注时 2）
func white_coin_amount() -> int:
	return 1 * get_coin_mult()

## 新手引导：是否需要显示
func should_show_tutorial() -> bool:
	return not tutorial_seen

func mark_tutorial_seen() -> void:
	if tutorial_seen:
		return
	tutorial_seen = true
	save_game()

## 底部框奖励（入框后由 gameplay 调用）
func apply_pocket_bonus(index: int) -> String:
	var bonus := get_pocket_bonus(index)
	match bonus:
		"coin2":
			coins += 2 * get_coin_mult()
			coins_changed.emit(coins)
		"ball1":
			grant_extra_ball()
	if bonus != "":
		return bonus
	return ""

## 额外获得一颗普通弹珠（再射一球）
func grant_extra_ball() -> void:
	ball_slots.append({"type": 0, "card": ""})
	balls_total += 1
	balls_left += 1
	balls_changed.emit(balls_left, balls_total)
	items_changed.emit()

## 过关：+5 金币，未使用弹珠按类型进入弹珠库
func finish_level(victory: bool) -> void:
	if not victory:
		return
	coins += FateConfig.CLEAR_COIN_REWARD * get_coin_mult()
	for i in range(balls_total - balls_left, ball_slots.size()):
		var slot: Dictionary = ball_slots[i]
		if int(slot.get("type", 0)) == 1:
			library_advanced += 1
		else:
			library_normal += 1
	balls_left = 0
	coins_changed.emit(coins)
	library_changed.emit(library_normal, library_advanced)
	balls_changed.emit(balls_left, balls_total)
	level_cleared.emit(level, level_score)

func complete_room() -> Dictionary:
	finish_level(true)
	var cleared := level
	if level >= FateConfig.MAX_LEVEL:
		var summary := finish_run(true)
		return {"last": true, "cleared": cleared, "summary": summary}
	level += 1
	return {"last": false, "cleared": cleared, "next": level}

func fail_room() -> Dictionary:
	var shards := int(total_score / 10.0) + int(fate_event.get("shard_bonus", 0))
	if double_mode:
		shards = int(shards / float(FateConfig.DOUBLE_MODE_FAIL_SHARD_DIV))
	total_shards += shards
	var carried := carry_over(false)
	run_active = false
	save_game()
	return {
		"victory": false,
		"total_score": total_score,
		"shards": shards,
		"best": best_score,
		"level": level,
		"carried": carried,
	}

func finish_run(victory: bool) -> Dictionary:
	var shards := int(total_score / 5.0) + int(fate_event.get("shard_bonus", 0))
	if victory:
		shards += 20
	var is_new_best := total_score > best_score
	if is_new_best:
		best_score = total_score
	best_level = maxi(best_level, level)
	total_shards += shards
	runs_played += 1
	var carried := carry_over(victory)
	run_active = false
	save_game()
	run_finished.emit(victory, total_score, shards, best_score)
	meta_changed.emit()
	print("[GameState] 本局结束 victory=%s 总分=%d 碎片+%d 带出=%s" % [victory, total_score, shards, str(carried)])
	return {
		"victory": victory,
		"total_score": total_score,
		"shards": shards,
		"is_new_best": is_new_best,
		"best": best_score,
		"level": level,
		"carried": carried,
	}

## 一局结束：把部分弹珠与卡牌带到局外行囊
func carry_over(victory: bool) -> Dictionary:
	var carry_balls := mini(library_normal, FateConfig.META_CARRY_BALLS)
	var carry_adv := mini(library_advanced, 1)
	library_normal -= carry_balls
	library_advanced -= carry_adv
	meta_balls_normal += carry_balls
	meta_balls_advanced += carry_adv
	var carry_cards: Array[String] = []
	var pool := pending_items.duplicate()
	if victory:
		# 胜利额外随机赠送一件卡/装备
		var keys: Array = FateConfig.ITEMS.keys()
		if not keys.is_empty():
			pool.append(String(keys[randi() % keys.size()]))
	for id in pool:
		if carry_cards.size() >= FateConfig.META_CARRY_CARDS:
			break
		carry_cards.append(id)
		meta_cards.append(id)
	library_changed.emit(library_normal, library_advanced)
	meta_changed.emit()
	print("[GameState] 局外行囊 +%d普通珠 +%d进阶珠 卡牌=%s" % [carry_balls, carry_adv, str(carry_cards)])
	return {
		"balls_normal": carry_balls,
		"balls_advanced": carry_adv,
		"cards": carry_cards,
	}

func reset_to_title() -> void:
	run_active = false

# ================= 查询 =================

func get_target() -> int:
	var base: int = FateConfig.LEVEL_TARGETS[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]
	var delta: int = int(fate_event.get("target_delta", 0))
	return maxi(5, base + delta)

func get_score_multiplier() -> float:
	return FateConfig.LEVEL_SCORE_MULT[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]

func get_ball_base(advanced: bool) -> int:
	var base := float(FateConfig.BALL_BASE_ADVANCED if advanced else FateConfig.BALL_BASE_NORMAL)
	var mult: float = FateConfig.LEVEL_BALL_BASE_MULT[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]
	return int(round(base * mult))

func get_yellow_bonus() -> int:
	return 1 + int(fate_event.get("yellow_bonus", 0))

func is_normal_pegs_removed() -> bool:
	return level >= 3

func get_level_name() -> String:
	return FateConfig.LEVEL_NAMES[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]

func get_level_buff_text() -> String:
	return FateConfig.LEVEL_BUFFS[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]

func get_ball_slot(index: int) -> Dictionary:
	if index < 0 or index >= ball_slots.size():
		return {}
	return ball_slots[index]

func get_card_name(card_id: String) -> String:
	if card_id == "" or not FateConfig.ITEMS.has(card_id):
		return ""
	return String(FateConfig.ITEMS[card_id].get("name", card_id))

# ================= 道具 / 弹珠库 =================

func has_item(id: String) -> bool:
	return run_items.has(id)

func buy_item(id: String) -> bool:
	if not FateConfig.ITEMS.has(id):
		return false
	var info: Dictionary = FateConfig.ITEMS[id]
	var cost: int = int(info.get("cost", 0))
	if not spend_coins(cost):
		return false
	var kind := String(info.get("kind", "equipment"))
	match kind:
		"passive":
			run_items[id] = true
		"library":
			library_advanced += 2
			library_changed.emit(library_normal, library_advanced)
		_:
			pending_items.append(id)
	items_changed.emit()
	return true

func can_buy_item(id: String) -> bool:
	if not FateConfig.ITEMS.has(id):
		return false
	var kind := String(FateConfig.ITEMS[id].get("kind", "equipment"))
	if kind == "passive" and run_items.has(id):
		return false
	return coins >= int(FateConfig.ITEMS[id].get("cost", 0))

func get_pending_items() -> Array[String]:
	return pending_items.duplicate()

func consume_pending_item(id: String) -> bool:
	for i in pending_items.size():
		if pending_items[i] == id:
			pending_items.remove_at(i)
			# 带入本局的卡牌使用后也从 loadout 移除
			for j in run_loadout_cards.size():
				if run_loadout_cards[j] == id:
					run_loadout_cards.remove_at(j)
					break
			items_changed.emit()
			return true
	return false

## 给某颗弹珠附加卡牌（图标变红）
func set_ball_card(index: int, card_id: String) -> bool:
	if index < 0 or index >= ball_slots.size():
		return false
	if not FateConfig.ITEMS.has(card_id):
		return false
	if String(ball_slots[index].get("card", "")) != "":
		return false
	ball_slots[index]["card"] = card_id
	items_changed.emit()
	return true

## 兼容旧接口：默认强力卡
func buff_ball_slot(index: int) -> bool:
	return set_ball_card(index, "powercard")

func get_ball_card(index: int) -> String:
	return String(get_ball_slot(index).get("card", ""))

func set_ball_slot_type(index: int, type: int) -> void:
	if index < 0 or index >= ball_slots.size():
		return
	ball_slots[index]["type"] = type
	items_changed.emit()

func replace_ball_slot(index: int, advanced: bool) -> bool:
	if index < 0 or index >= ball_slots.size():
		return false
	if advanced:
		if library_advanced <= 0:
			return false
		library_advanced -= 1
		ball_slots[index]["type"] = 1
	else:
		if library_normal <= 0:
			return false
		library_normal -= 1
		ball_slots[index]["type"] = 0
	library_changed.emit(library_normal, library_advanced)
	items_changed.emit()
	return true

func merge_library_balls() -> bool:
	if library_normal < 3:
		return false
	library_normal -= 3
	library_advanced += 1
	library_changed.emit(library_normal, library_advanced)
	return true

func add_coins(n: int) -> void:
	coins += n
	coins_changed.emit(coins)

func spend_coins(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins)
	return true

func roll_fate_event() -> Dictionary:
	var pool := FateConfig.FATE_EVENTS
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()].duplicate(true)

# ================= 局外行囊（公共变量） =================

## 局外可选卡牌去重计数：返回 [{"id":id,"count":n}]
func get_meta_card_stacks() -> Array:
	var counts := {}
	for id in meta_cards:
		counts[id] = int(counts.get(id, 0)) + 1
	var out: Array = []
	for id in counts.keys():
		out.append({"id": String(id), "count": int(counts[id])})
	out.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return out

func is_card_selected(id: String) -> bool:
	return selected_cards.has(id)

## 勾选/取消一张局外卡牌（受带入上限限制）
func toggle_selected_card(id: String) -> bool:
	if not meta_cards.has(id):
		return false
	for i in selected_cards.size():
		if selected_cards[i] == id:
			selected_cards.remove_at(i)
			meta_changed.emit()
			return true
	if selected_cards.size() >= FateConfig.META_MAX_SELECT_CARDS:
		return false
	selected_cards.append(id)
	meta_changed.emit()
	return true

## 局外弹珠勾选：一次点击调整数量（普通/进阶）
func select_meta_balls(advanced: bool, delta: int) -> void:
	var max_count: int = FateConfig.META_MAX_SELECT_BALLS
	if advanced:
		selected_balls_advanced = clampi(selected_balls_advanced + delta, 0,
			mini(meta_balls_advanced, max_count - selected_balls_normal))
	else:
		selected_balls_normal = clampi(selected_balls_normal + delta, 0,
			mini(meta_balls_normal, max_count - selected_balls_advanced))
	meta_changed.emit()

func get_selected_ball_total() -> int:
	return selected_balls_normal + selected_balls_advanced

# ================= 存档 =================

func save_game() -> void:
	var data := {
		"version": 4,
		"best_score": best_score,
		"best_level": best_level,
		"total_shards": total_shards,
		"runs_played": runs_played,
		"meta_balls_normal": meta_balls_normal,
		"meta_balls_advanced": meta_balls_advanced,
		"meta_cards": meta_cards,
		"selected_balls_normal": selected_balls_normal,
		"selected_balls_advanced": selected_balls_advanced,
		"selected_cards": selected_cards,
		"tutorial_seen": tutorial_seen,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[GameState] 无法写入存档：" + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	best_score = int(parsed.get("best_score", 0))
	best_level = int(parsed.get("best_level", 0))
	total_shards = int(parsed.get("total_shards", 0))
	runs_played = int(parsed.get("runs_played", 0))
	meta_balls_normal = int(parsed.get("meta_balls_normal", 0))
	meta_balls_advanced = int(parsed.get("meta_balls_advanced", 0))
	var cards: Array = parsed.get("meta_cards", [])
	meta_cards.clear()
	for c in cards:
		meta_cards.append(String(c))
	selected_balls_normal = int(parsed.get("selected_balls_normal", 0))
	selected_balls_advanced = int(parsed.get("selected_balls_advanced", 0))
	selected_cards.clear()
	for c in parsed.get("selected_cards", []):
		selected_cards.append(String(c))
	tutorial_seen = bool(parsed.get("tutorial_seen", false))
	print("[GameState] 存档读取：最高分=%d 碎片=%d 行囊=%d/%d 卡=%d" % [
		best_score, total_shards, meta_balls_normal, meta_balls_advanced, meta_cards.size()])

func _emit_all() -> void:
	coins_changed.emit(coins)
	score_changed.emit(level_score, total_score)
	balls_changed.emit(balls_left, balls_total)
	library_changed.emit(library_normal, library_advanced)
	items_changed.emit()
