extends Node
## 《！？珠珠？！》全局运行状态（Autoload 名：GameState）v1.4
## 依据《基础策划案 (2)》：命核碎片、三种琉璃珠与合成概率、10 关与关卡 buff、商店刷新、
## 走廊 NPC 关卡文案、结算/中途存档（关闭游戏后可继续当前关）。
## 由 Lead 维护。几何/数值常量见 FateConfig。

signal coins_changed(value: int)
signal score_changed(level_score: int, total_score: int)
signal balls_changed(balls_left: int, balls_total: int)
signal level_started(level: int, target: int, fate_event: Dictionary)
signal level_cleared(level: int, level_score: int)
signal run_finished(victory: bool, total_score: int, shards: int, best: int)
signal library_changed(normal_count: int, advanced_count: int, high_count: int)
signal items_changed
signal meta_changed
signal character_changed(level: int, exp: int, needed: int)

const SAVE_PATH := "user://fate_save.json"

# ---- 本局状态 ----
var coins: int = FateConfig.START_COINS
var level: int = 1
var level_score: int = 0
var total_score: int = 0
var balls_left: int = FateConfig.BALLS_PER_LEVEL
var balls_total: int = FateConfig.BALLS_PER_LEVEL
## 弹珠槽：{"type":0/1/2, "card":""/卡牌id}
var ball_slots: Array = []
## 底部随机框
var slot_configs: Array = []
## 弹珠库（跨房间累计，三种）
var library_normal: int = 0
var library_advanced: int = 0
var library_high: int = 0
## 本关已合成次数标记（每关只能合成一次）与商店刷新
var synth_used: bool = false
var refresh_count: int = 0
var level_coins_gained: int = 0
## 已购买待使用道具
var pending_items: Array[String] = []
var run_loadout_cards: Array[String] = []
var run_items: Dictionary = {}
var fate_event: Dictionary = {}
var run_active: bool = false
var double_mode: bool = false
var tutorial_seen: bool = false
## 主角等级与经验（v1.5：仅等级展示，暂无数值效果）
var character_level: int = 1
var character_exp: int = 0
## 本局已触发过走廊 NPC 文案的关卡（触发后对应 NPC 消失）
var npc_seen_levels: Array = []
## v1.6：本房间已购买过的道具（每轮限购1次）、槽位额外弹珠计数
var bought_items_this_room: Array[String] = []
var slot_bonus_count: int = 0
## v1.6：存档点（1走廊 2商店 3关卡 4关卡结束）与③存档点的购买记录
var checkpoint: int = 1
var checkpoint_purchases: Array[String] = []
## ② 存档点的资源快照（退出商店读档时恢复到进店前状态）
var checkpoint_coins: int = -1
var checkpoint_lib_normal: int = 0
var checkpoint_lib_advanced: int = 0
var checkpoint_lib_high: int = 0

# ---- 局外行囊 ----
var meta_balls_normal: int = 0
var meta_balls_advanced: int = 0
var meta_balls_high: int = 0
var meta_cards: Array[String] = []
var selected_balls_normal: int = 0
var selected_balls_advanced: int = 0
var selected_balls_high: int = 0
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

func start_new_run() -> void:
	coins = FateConfig.START_COINS
	level = 1
	level_score = 0
	total_score = 0
	library_normal = selected_balls_normal
	library_advanced = selected_balls_advanced
	library_high = selected_balls_high
	meta_balls_normal = maxi(0, meta_balls_normal - selected_balls_normal)
	meta_balls_advanced = maxi(0, meta_balls_advanced - selected_balls_advanced)
	meta_balls_high = maxi(0, meta_balls_high - selected_balls_high)
	run_loadout_cards.clear()
	for id in selected_cards:
		if meta_cards.has(id):
			meta_cards.erase(id)
			run_loadout_cards.append(id)
	meta_cards.sort()
	selected_balls_normal = 0
	selected_balls_advanced = 0
	selected_balls_high = 0
	selected_cards.clear()
	pending_items.clear()
	bought_items_this_room.clear()
	slot_bonus_count = 0
	checkpoint = FateConfig.CHECKPOINT_CORRIDOR
	checkpoint_purchases.clear()
	run_items.clear()
	fate_event = {}
	ball_slots.clear()
	slot_configs.clear()
	synth_used = false
	refresh_count = 0
	level_coins_gained = 0
	balls_total = FateConfig.BALLS_PER_LEVEL
	balls_left = balls_total
	run_active = true
	double_mode = false
	npc_seen_levels.clear()
	save_game()
	_emit_all()
	meta_changed.emit()
	print("[GameState] 新的一局开始：命核碎片=%d 带入=%d/%d 卡=%s" % [
		coins, library_normal, library_advanced, str(run_loadout_cards)])

## 继续未完成的一局（关闭游戏后回到当前关）
func has_resumable_run() -> bool:
	return run_active and level >= 1 and level <= FateConfig.MAX_LEVEL

# ================= v1.8：隐藏关卡（命源琉璃珠彩蛋） =================

## 是否拥有命源琉璃珠（局内库 / 局外行囊 / 已选带入）
func has_source_ball() -> bool:
	return library_high > 0 or meta_balls_high > 0 or selected_balls_high > 0

## 当前可见的最大关卡：未拥有命源珠前，隐藏最后一关（不显示其存在）
func visible_max_level() -> int:
	return FateConfig.MAX_LEVEL if has_source_ball() else FateConfig.MAX_LEVEL - 1

## 是否为隐藏关卡（最后一关）
func is_hidden_level(lv: int) -> bool:
	return lv >= FateConfig.MAX_LEVEL

## 关卡进度显示：未解锁隐藏关时只显示「第 X 间」，不泄露总关数
func level_display() -> String:
	if has_source_ball():
		return "第 %d / %d 间" % [level, FateConfig.MAX_LEVEL]
	return "第 %d 间" % level

func max_level_display() -> String:
	return str(FateConfig.MAX_LEVEL) if has_source_ball() else "?"

func resume_run() -> void:
	if not has_resumable_run():
		start_new_run()

func abandon_run() -> void:
	run_active = false
	save_game()

func prepare_level(lv: int) -> void:
	level = clampi(lv, 1, visible_max_level())
	level_score = 0
	level_coins_gained = 0
	synth_used = false
	refresh_count = 0
	bought_items_this_room.clear()
	slot_bonus_count = 0
	pending_items.clear()
	for id in run_loadout_cards:
		pending_items.append(id)
	# ③存档点续关：恢复本关已购买的道具（关卡从零开始，但购买保留）
	if checkpoint == FateConfig.CHECKPOINT_LEVEL:
		for id in checkpoint_purchases:
			pending_items.append(id)
			bought_items_this_room.append(id)
	ball_slots.clear()
	var count := FateConfig.BALLS_PER_LEVEL
	fate_event = roll_fate_event()
	count += int(fate_event.get("bonus_ball", 0))
	for i in count:
		ball_slots.append({"type": FateConfig.BALL_TYPE_FATE, "card": ""})
	balls_total = count
	balls_left = count
	slot_configs = roll_pocket_configs()
	var extra_coins: int = int(fate_event.get("bonus_coin", 0))
	if extra_coins != 0:
		coins += extra_coins
	save_game()
	_emit_all()
	level_started.emit(level, get_target(), fate_event)
	print("[GameState] 第%d间「%s」目标=%d 事件=%s 弹珠=%d buff=%s" % [
		level, get_level_name(), get_target(), String(fate_event.get("name", "无")),
		balls_total, get_level_buff().get("name", "")])

func roll_pocket_configs() -> Array:
	var out: Array = []
	for i in FateConfig.SLOT_WEIGHTS.size():
		out.append({"mult": _pick_weighted_mult(), "bonus": _pick_weighted_bonus()})
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

func get_slot_config(index: int) -> Dictionary:
	if index < 0 or index >= slot_configs.size():
		return {"mult": 1.0, "bonus": ""}
	return slot_configs[index]

func get_pocket_mult(index: int) -> float:
	return float(get_slot_config(index).get("mult", 1.0))

func get_pocket_bonus(index: int) -> String:
	return String(get_slot_config(index).get("bonus", ""))

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
		"type": int(slot.get("type", 0)),
		"advanced": int(slot.get("type", 0)) >= 1,
		"card": String(slot.get("card", "")),
	}

func award_ball_score(base: int, yellow_hits: int, slot_mult: float, buffed: bool = false) -> int:
	var raw := float(base + yellow_hits * get_yellow_bonus())
	var buff_mult := FateConfig.BUFFED_BALL_MULT if buffed else 1.0
	var value := int(floor(raw * slot_mult * get_score_multiplier() * buff_mult * get_double_score_mult()))
	value = maxi(value, 0)
	level_score += value
	total_score += value
	score_changed.emit(level_score, total_score)
	return value

func apply_pocket_bonus(index: int) -> String:
	var bonus := get_pocket_bonus(index)
	match bonus:
		"coin2":
			add_coins(2 * get_coin_mult())
		"ball1":
			# 每关通过槽位获得的额外弹珠最多 2 颗（关卡内最多 7 颗）
			if slot_bonus_count < FateConfig.SLOT_BALL_BONUS_MAX:
				slot_bonus_count += 1
				grant_extra_ball(FateConfig.BALL_TYPE_FATE)
			else:
				return "ball1_limit"
	return bonus

func grant_extra_ball(type: int = 0) -> void:
	ball_slots.append({"type": clampi(type, 0, 2), "card": ""})
	balls_total += 1
	balls_left += 1
	balls_changed.emit(balls_left, balls_total)
	items_changed.emit()

## 购买「命运的赠与/奖赏」：立刻获得一颗弹珠（加入本关可用弹珠）
func add_ball_to_slots(type: int) -> void:
	grant_extra_ball(type)

func get_double_score_mult() -> float:
	return float(FateConfig.DOUBLE_MODE_SCORE_MULT) if double_mode else 1.0

func get_coin_mult() -> int:
	return FateConfig.DOUBLE_MODE_COIN_MULT if double_mode else 1

func get_penalty_mult() -> int:
	return FateConfig.DOUBLE_MODE_PENALTY_MULT if double_mode else 1

func set_double_mode(enabled: bool) -> void:
	double_mode = enabled
	print("[GameState] 双倍注=", enabled)

func white_coin_amount() -> int:
	var n := 1 * get_coin_mult()
	n += int(get_level_buff().get("white_bonus", 0))
	return n

func should_show_tutorial() -> bool:
	return not tutorial_seen

func mark_tutorial_seen() -> void:
	if tutorial_seen:
		return
	tutorial_seen = true
	save_game()

# ================= 合成 / 弹珠库 =================

## 3 普通 → 1 进阶（60%）；每关一次
func synthesize_core() -> Dictionary:
	if synth_used:
		return {"ok": false, "reason": "本关已合成过"}
	if library_normal < FateConfig.SYNTH_CORE_COST:
		return {"ok": false, "reason": "命运琉璃珠不足3颗"}
	library_normal -= FateConfig.SYNTH_CORE_COST
	synth_used = true
	var ok := randf() < FateConfig.SYNTH_CORE_SUCCESS
	if ok:
		library_advanced += 1
	else:
		library_normal += FateConfig.SYNTH_CORE_COST
	library_changed.emit(library_normal, library_advanced, library_high)
	print("[GameState] 合成命核琉璃珠 success=", ok)
	return {"ok": ok, "type": FateConfig.BALL_TYPE_CORE}

## 3 进阶 → 1 高阶（40%）；每关一次
func synthesize_source() -> Dictionary:
	if synth_used:
		return {"ok": false, "reason": "本关已合成过"}
	if library_advanced < FateConfig.SYNTH_SOURCE_COST:
		return {"ok": false, "reason": "命核琉璃珠不足3颗"}
	library_advanced -= FateConfig.SYNTH_SOURCE_COST
	synth_used = true
	var ok := randf() < FateConfig.SYNTH_SOURCE_SUCCESS
	if ok:
		library_high += 1
	else:
		library_advanced += 2
	library_changed.emit(library_normal, library_advanced, library_high)
	print("[GameState] 合成命源琉璃珠 success=", ok)
	return {"ok": ok, "type": FateConfig.BALL_TYPE_SOURCE}

## 兼容旧调用：3 普通 → 进阶（带概率）
func merge_library_balls() -> bool:
	var r := synthesize_core()
	return bool(r.get("ok", false))

func replace_ball_slot(index: int, advanced: bool) -> bool:
	return replace_ball_slot_type(index, FateConfig.BALL_TYPE_CORE if advanced else FateConfig.BALL_TYPE_FATE)

func replace_ball_slot_type(index: int, type: int) -> bool:
	if index < 0 or index >= ball_slots.size():
		return false
	match type:
		FateConfig.BALL_TYPE_CORE:
			if library_advanced <= 0:
				return false
			library_advanced -= 1
		FateConfig.BALL_TYPE_SOURCE:
			if library_high <= 0:
				return false
			library_high -= 1
		_:
			if library_normal <= 0:
				return false
			library_normal -= 1
	ball_slots[index]["type"] = clampi(type, 0, 2)
	library_changed.emit(library_normal, library_advanced, library_high)
	items_changed.emit()
	return true

func apply_high_ball_effect(type: int) -> void:
	if type == FateConfig.BALL_TYPE_SOURCE:
		pass

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

## 兼容旧接口
func buff_ball_slot(index: int) -> bool:
	return set_ball_card(index, "powercard")

func get_ball_card(index: int) -> String:
	return String(get_ball_slot(index).get("card", ""))

func set_ball_slot_type(index: int, type: int) -> void:
	if index < 0 or index >= ball_slots.size():
		return
	ball_slots[index]["type"] = clampi(type, 0, 2)
	items_changed.emit()

func get_ball_slot(index: int) -> Dictionary:
	if index < 0 or index >= ball_slots.size():
		return {}
	return ball_slots[index]

func get_ball_base(type: int) -> int:
	var t := clampi(type, 0, 2)
	return FateConfig.BALL_BASE_SCORES[t] + int(get_level_buff().get("base_bonus", 0))

## 兼容旧接口
func get_ball_base_advanced(advanced: bool) -> int:
	return get_ball_base(FateConfig.BALL_TYPE_CORE if advanced else FateConfig.BALL_TYPE_FATE)

## 结算用：旧签名（advanced）
func get_ball_base_by_advanced(advanced: bool) -> int:
	return get_ball_base(FateConfig.BALL_TYPE_CORE if advanced else FateConfig.BALL_TYPE_FATE)

# ================= 商店 / 刷新 =================

func buy_item(id: String) -> bool:
	if not FateConfig.ITEMS.has(id):
		return false
	# 每种道具每轮限购 1 次（刷新后仍出现但不可再买）
	if bought_items_this_room.has(id):
		return false
	var info: Dictionary = FateConfig.ITEMS[id]
	var cost: int = int(info.get("cost", 0))
	if not spend_coins(cost):
		return false
	bought_items_this_room.append(id)
	var kind := String(info.get("kind", "equipment"))
	match kind:
		"passive":
			run_items[id] = true
		"library":
			library_advanced += 2
			library_changed.emit(library_normal, library_advanced, library_high)
		"instant":
			# 购买的弹珠直接进入弹药库，不计入关卡内可用弹珠次数
			if id == "fate_gift":
				library_normal += 1
			elif id == "fate_reward":
				library_advanced += 1
			library_changed.emit(library_normal, library_advanced, library_high)
		_:
			pending_items.append(id)
	items_changed.emit()
	save_game()
	return true

func can_buy_item(id: String) -> bool:
	if not FateConfig.ITEMS.has(id):
		return false
	if bought_items_this_room.has(id):
		return false
	return coins >= int(FateConfig.ITEMS[id].get("cost", 0))

func is_item_bought(id: String) -> bool:
	return bought_items_this_room.has(id)

func get_pending_items() -> Array[String]:
	return pending_items.duplicate()

func consume_pending_item(id: String) -> bool:
	for i in pending_items.size():
		if pending_items[i] == id:
			pending_items.remove_at(i)
			for j in run_loadout_cards.size():
				if run_loadout_cards[j] == id:
					run_loadout_cards.remove_at(j)
					break
			items_changed.emit()
			return true
	return false

## 按权重随机抽 3 件（价≥7 的权重受守命低语加成；prep 的刷新也用它）
func roll_shop_offers() -> Array[String]:
	var ids: Array[String] = []
	for id in FateConfig.ITEMS.keys():
		ids.append(String(id))
	var chosen: Array[String] = []
	var bonus := int(get_level_buff().get("price7_weight_bonus", 0))
	while chosen.size() < FateConfig.SHOP_OFFER_COUNT and not ids.is_empty():
		var total := 0
		for id in ids:
			total += item_roll_weight(id, bonus)
		var roll := randi() % maxi(total, 1)
		var acc := 0
		var picked := ids[ids.size() - 1]
		for id in ids:
			acc += item_roll_weight(id, bonus)
			if roll < acc:
				picked = id
				break
		chosen.append(picked)
		ids.erase(picked)
	return chosen

func item_roll_weight(id: String, bonus: int = 0) -> int:
	if not FateConfig.ITEMS.has(id):
		return 0
	var info: Dictionary = FateConfig.ITEMS[id]
	var w := int(info.get("weight", 100))
	if bonus > 0 and int(info.get("cost", 0)) >= 7:
		w += bonus
	return maxi(w, 1)

func get_refresh_cost() -> int:
	return FateConfig.REFRESH_BASE_COST + FateConfig.REFRESH_COST_STEP * refresh_count

## 刷新商店（扣命核碎片），成功返回新 offer 列表
func refresh_shop_offers() -> Array[String]:
	var cost := get_refresh_cost()
	if not spend_coins(cost):
		return []
	refresh_count += 1
	save_game()
	return roll_shop_offers()

# ================= 关卡 buff =================

func get_level_buff() -> Dictionary:
	var idx := clampi(level, 1, FateConfig.MAX_LEVEL) - 1
	return FateConfig.LEVEL_BUFFS[idx]

func get_target() -> int:
	var base: int = FateConfig.LEVEL_TARGETS[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]
	var delta: int = int(fate_event.get("target_delta", 0))
	return maxi(5, base + delta)

func get_score_multiplier() -> float:
	var m := 1.0
	var b := get_level_buff()
	if b.has("score_mult"):
		m *= float(b["score_mult"])
	return m

func get_ball_base_for_type(type: int) -> int:
	return get_ball_base(type)

func get_yellow_bonus() -> int:
	return 1 + int(fate_event.get("yellow_bonus", 0))

func is_normal_pegs_removed() -> bool:
	return bool(get_level_buff().get("remove_normal", false))

func is_negative_pegs_removed() -> bool:
	return bool(get_level_buff().get("remove_negative", false))

func get_green_weight_bonus() -> int:
	return int(get_level_buff().get("green_weight_bonus", 0))

func get_chaos_chance() -> float:
	return float(get_level_buff().get("chaos_chance", 0.0))

func get_bounce_bonus() -> float:
	return float(get_level_buff().get("bounce_bonus", 0.0))

func get_gravity_mult() -> float:
	return 1.0 + float(get_level_buff().get("gravity_bonus", 0.0))

func get_green_limit() -> int:
	return int(get_level_buff().get("green_limit", 0))

func get_break_threshold() -> int:
	return int(get_level_buff().get("break_threshold", 0))

func get_break_seconds() -> float:
	return float(get_level_buff().get("break_seconds", 0.0))

func get_level_name() -> String:
	return FateConfig.LEVEL_NAMES[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]

func get_level_buff_text() -> String:
	var b := get_level_buff()
	return "%s：%s" % [String(b.get("name", "")), String(b.get("desc", ""))]

func get_story_line() -> String:
	var idx := clampi(level, 1, FateConfig.MAX_LEVEL) - 1
	if idx < FateConfig.LEVEL_STORY_LINES.size():
		return FateConfig.LEVEL_STORY_LINES[idx]
	return ""

# ================= 结算 =================

func add_coins(n: int) -> void:
	coins += n
	level_coins_gained += n
	coins_changed.emit(coins)

func apply_pocket_coin_bonus(amount: int) -> void:
	add_coins(amount)

func spend_coins(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins)
	return true

func finish_level(victory: bool) -> void:
	if not victory:
		return
	var reward := FateConfig.CLEAR_COIN_REWARD * get_coin_mult()
	var idx := clampi(level, 1, FateConfig.MAX_LEVEL) - 1
	reward += FateConfig.LEVEL_CLEAR_BONUS[idx]
	coins += reward
	for i in range(balls_total - balls_left, ball_slots.size()):
		var slot: Dictionary = ball_slots[i]
		match int(slot.get("type", 0)):
			FateConfig.BALL_TYPE_SOURCE:
				library_high += 1
			FateConfig.BALL_TYPE_CORE:
				library_advanced += 1
			_:
				library_normal += 1
	balls_left = 0
	coins_changed.emit(coins)
	library_changed.emit(library_normal, library_advanced, library_high)
	balls_changed.emit(balls_left, balls_total)
	level_cleared.emit(level, level_score)

func complete_room() -> Dictionary:
	finish_level(true)
	add_character_exp(FateConfig.EXP_PER_ROOM_CLEAR)
	var cleared := level
	checkpoint = FateConfig.CHECKPOINT_CLEAR
	save_game()
	if level >= visible_max_level():
		var summary := finish_run(true)
		return {"last": true, "cleared": cleared, "summary": summary}
	level += 1
	checkpoint = FateConfig.CHECKPOINT_CORRIDOR
	checkpoint_purchases.clear()
	save_game()
	return {"last": false, "cleared": cleared, "next": level}

## 存档点：1走廊入口 2商店入口(记录是否完成对话) 3关卡开始(记录购买) 4关卡结束
func mark_checkpoint(point: int, purchases: Array[String] = []) -> void:
	checkpoint = clampi(point, FateConfig.CHECKPOINT_CORRIDOR, FateConfig.CHECKPOINT_CLEAR)
	if checkpoint == FateConfig.CHECKPOINT_LEVEL:
		checkpoint_purchases = purchases.duplicate()
	elif checkpoint == FateConfig.CHECKPOINT_CORRIDOR or checkpoint == FateConfig.CHECKPOINT_SHOP:
		checkpoint_purchases.clear()
	if checkpoint == FateConfig.CHECKPOINT_SHOP:
		checkpoint_coins = coins
		checkpoint_lib_normal = library_normal
		checkpoint_lib_advanced = library_advanced
		checkpoint_lib_high = library_high
	else:
		checkpoint_coins = -1
	save_game()

func get_checkpoint_purchases() -> Array[String]:
	return checkpoint_purchases.duplicate()

# ================= 主角等级 / 走廊 NPC 已读 =================

func exp_needed() -> int:
	return FateConfig.EXP_BASE_REQUIRED + (character_level - 1) * FateConfig.EXP_GROWTH

func add_character_exp(amount: int) -> void:
	if amount <= 0:
		return
	character_exp += amount
	while character_exp >= exp_needed():
		character_exp -= exp_needed()
		character_level += 1
		print("[GameState] 主角升级 → Lv.%d" % character_level)
	character_changed.emit(character_level, character_exp, exp_needed())

func is_npc_seen(lv: int) -> bool:
	return npc_seen_levels.has(lv)

func mark_npc_seen(lv: int) -> void:
	if npc_seen_levels.has(lv):
		return
	npc_seen_levels.append(lv)
	save_game()

func fail_room() -> Dictionary:
	var shards := int(total_score / 10.0) + int(fate_event.get("shard_bonus", 0))
	if double_mode:
		shards = int(shards / float(FateConfig.DOUBLE_MODE_FAIL_SHARD_DIV))
	total_shards += shards
	# 失败不结算带出，保留 ③ 存档点（重试本关从零开始，购买保留）
	checkpoint = FateConfig.CHECKPOINT_LEVEL
	save_game()
	return {
		"victory": false,
		"level_score": level_score,
		"total_score": total_score,
		"shards": shards,
		"best": best_score,
		"level": level,
		"story": FateConfig.FAILURE_STORY_LINE,
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
	print("[GameState] 本局结束 victory=%s 总分=%d" % [victory, total_score])
	return {
		"victory": victory, "total_score": total_score, "shards": shards,
		"is_new_best": is_new_best, "best": best_score, "level": level,
		"carried": carried, "story": FateConfig.FAILURE_STORY_LINE if not victory else "",
	}

func carry_over(victory: bool) -> Dictionary:
	# v1.6：局末所有弹珠（三种）与所有剩余道具均可带出
	var carry_balls := library_normal
	var carry_adv := library_advanced
	var carry_high := library_high
	library_normal = 0
	library_advanced = 0
	library_high = 0
	meta_balls_normal += carry_balls
	meta_balls_advanced += carry_adv
	meta_balls_high += carry_high
	var carry_cards: Array[String] = pending_items.duplicate()
	for id in carry_cards:
		meta_cards.append(id)
	pending_items.clear()
	library_changed.emit(library_normal, library_advanced, library_high)
	meta_changed.emit()
	return {"balls_normal": carry_balls, "balls_advanced": carry_adv, "balls_high": carry_high, "cards": carry_cards}

func reset_to_title() -> void:
	run_active = false

# ================= 局外行囊 =================

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

## 兼容旧调用（普通/进阶）
func select_meta_balls(advanced: bool, delta: int) -> void:
	select_meta_ball_type(FateConfig.BALL_TYPE_CORE if advanced else FateConfig.BALL_TYPE_FATE, delta)

## 三种弹珠勾选带入下一局（合计上限 3）
func select_meta_ball_type(type: int, delta: int) -> void:
	var t := clampi(type, 0, 2)
	var total := get_selected_ball_total()
	if delta > 0 and total >= FateConfig.META_MAX_SELECT_BALLS:
		return
	match t:
		FateConfig.BALL_TYPE_CORE:
			selected_balls_advanced = clampi(selected_balls_advanced + delta, 0, meta_balls_advanced)
		FateConfig.BALL_TYPE_SOURCE:
			selected_balls_high = clampi(selected_balls_high + delta, 0, meta_balls_high)
		_:
			selected_balls_normal = clampi(selected_balls_normal + delta, 0, meta_balls_normal)
	meta_changed.emit()

func get_selected_ball_total() -> int:
	return selected_balls_normal + selected_balls_advanced + selected_balls_high

func roll_fate_event() -> Dictionary:
	var pool := FateConfig.FATE_EVENTS
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()].duplicate(true)

# ================= 存档（含进行中的一局） =================

func save_game() -> void:
	var data := {
		"version": 6,
		"best_score": best_score,
		"best_level": best_level,
		"total_shards": total_shards,
		"runs_played": runs_played,
		"meta_balls_normal": meta_balls_normal,
		"meta_balls_advanced": meta_balls_advanced,
		"meta_balls_high": meta_balls_high,
		"meta_cards": meta_cards,
		"selected_balls_normal": selected_balls_normal,
		"selected_balls_advanced": selected_balls_advanced,
		"selected_balls_high": selected_balls_high,
		"selected_cards": selected_cards,
		"tutorial_seen": tutorial_seen,
		"character_level": character_level,
		"character_exp": character_exp,
		"npc_seen_levels": npc_seen_levels,
		"checkpoint": checkpoint,
		"checkpoint_purchases": checkpoint_purchases,
		"checkpoint_coins": checkpoint_coins,
		"checkpoint_lib_normal": checkpoint_lib_normal,
		"checkpoint_lib_advanced": checkpoint_lib_advanced,
		"checkpoint_lib_high": checkpoint_lib_high,
		# 进行中的一局
		"run_active": run_active,
		"run_level": level,
		"run_coins": coins,
		"run_total_score": total_score,
		"run_library_normal": library_normal,
		"run_library_advanced": library_advanced,
		"run_library_high": library_high,
		"run_loadout_cards": run_loadout_cards,
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
	meta_balls_high = int(parsed.get("meta_balls_high", 0))
	meta_cards.clear()
	for c in parsed.get("meta_cards", []):
		meta_cards.append(String(c))
	selected_balls_normal = int(parsed.get("selected_balls_normal", 0))
	selected_balls_advanced = int(parsed.get("selected_balls_advanced", 0))
	selected_balls_high = int(parsed.get("selected_balls_high", 0))
	checkpoint = clampi(int(parsed.get("checkpoint", FateConfig.CHECKPOINT_CORRIDOR)),
		FateConfig.CHECKPOINT_CORRIDOR, FateConfig.CHECKPOINT_CLEAR)
	checkpoint_purchases.clear()
	for c in parsed.get("checkpoint_purchases", []):
		checkpoint_purchases.append(String(c))
	checkpoint_coins = int(parsed.get("checkpoint_coins", -1))
	checkpoint_lib_normal = int(parsed.get("checkpoint_lib_normal", 0))
	checkpoint_lib_advanced = int(parsed.get("checkpoint_lib_advanced", 0))
	checkpoint_lib_high = int(parsed.get("checkpoint_lib_high", 0))
	selected_cards.clear()
	for c in parsed.get("selected_cards", []):
		selected_cards.append(String(c))
	tutorial_seen = bool(parsed.get("tutorial_seen", false))
	character_level = maxi(1, int(parsed.get("character_level", 1)))
	character_exp = maxi(0, int(parsed.get("character_exp", 0)))
	npc_seen_levels.clear()
	for lv in parsed.get("npc_seen_levels", []):
		npc_seen_levels.append(int(lv))
	run_active = bool(parsed.get("run_active", false))
	level = clampi(int(parsed.get("run_level", 1)), 1, FateConfig.MAX_LEVEL)
	coins = int(parsed.get("run_coins", FateConfig.START_COINS))
	total_score = int(parsed.get("run_total_score", 0))
	library_normal = int(parsed.get("run_library_normal", 0))
	library_advanced = int(parsed.get("run_library_advanced", 0))
	library_high = int(parsed.get("run_library_high", 0))
	run_loadout_cards.clear()
	for c in parsed.get("run_loadout_cards", []):
		run_loadout_cards.append(String(c))
	# ② 商店存档点读档：恢复到进店前的资源快照（未购买成功则重新购买）
	if checkpoint == FateConfig.CHECKPOINT_SHOP and checkpoint_coins >= 0:
		coins = checkpoint_coins
		library_normal = checkpoint_lib_normal
		library_advanced = checkpoint_lib_advanced
		library_high = checkpoint_lib_high
	if run_active and level > FateConfig.MAX_LEVEL:
		run_active = false
	print("[GameState] 存档读取：最高分=%d 碎片=%d 行囊=%d/%d 卡=%d 进行中=%s 第%d关" % [
		best_score, total_shards, meta_balls_normal, meta_balls_advanced, meta_cards.size(),
		str(run_active), level])

func _emit_all() -> void:
	coins_changed.emit(coins)
	score_changed.emit(level_score, total_score)
	balls_changed.emit(balls_left, balls_total)
	library_changed.emit(library_normal, library_advanced, library_high)
	items_changed.emit()
