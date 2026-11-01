class_name FateConfig
extends RefCounted
## 《！？珠珠？！》全局配置 v1.3（像素风 + 错落立柱 + 双倍注 + 新手引导）
## 只由 Lead 维护；其他成员如需常量变更请先沟通。

const GAME_TITLE := "！？珠珠？！"
const GAME_SUBTITLE := "命运回廊 · 弹珠试炼"
const GAME_VERSION := "1.3.0"

# ---------------- 屏幕 ----------------
const VIEW_SIZE := Vector2(1280, 720)

# ---------------- P1 横屏 UI 布局 ----------------
const HUD_H := 104.0
const HUD_CELL_SCORE := Rect2(8.0, 8.0, 368.0, 88.0)     # ①
const HUD_CELL_COIN := Rect2(392.0, 8.0, 392.0, 88.0)     # ②
const HUD_CELL_BALL := Rect2(800.0, 8.0, 472.0, 88.0)     # ③
const ITEM_AREA := Rect2(8.0, 112.0, 624.0, 344.0)        # ⑦
const LIBRARY_AREA := Rect2(8.0, 464.0, 624.0, 248.0)     # ⑧
const CLOSE_RECT := Rect2(1216.0, 112.0, 56.0, 64.0)      # ⑥ ❌

# ---------------- 弹珠台（右侧弹簧发射） ----------------
const BOARD_LEFT := 640.0
const BOARD_RIGHT := 1216.0
const BOARD_TOP := 112.0
const PEG_AREA := Rect2(656.0, 168.0, 552.0, 424.0)       # ⑤ 立柱阵（v1.3 加宽间距）
const PEG_COLS := 6
const PEG_ROWS := 7
const PEG_RADIUS := 11.0
## 立柱错落：奇数行整体横移半个列距（六列七行、每层错开）
const PEG_ROW_OFFSET_RATIO := 0.5
const PEG_JITTER := 2.0

## 立柱类型与权重（新增黑色/白色）
const PEG_TYPE_NORMAL := 0
const PEG_TYPE_YELLOW := 1
const PEG_TYPE_GREEN := 2
const PEG_TYPE_BLACK := 3
const PEG_TYPE_WHITE := 4
## 普通55 / 黄色30 / 绿色15 / 黑色5 / 白色10（总 115）
const PEG_WEIGHTS: Array[int] = [55, 30, 15, 5, 10]
## 黑色立柱：每撞一次，该球最终得分 -1
const BLACK_PENALTY := 1
## 白色立柱：首次撞击 20% 概率 +1 金币，同一立柱每多撞一次概率 +10%
const WHITE_BASE_COIN_CHANCE := 0.20
const WHITE_CHANCE_STEP := 0.10

## ④ 右侧弹簧发射轨道
const RAIL_LEFT := 1216.0
const RAIL_RIGHT := 1272.0
const RAIL_TOP := 140.0
const RAIL_BOTTOM := 704.0
const DEFLECTOR_A := Vector2(1216.0, 140.0)
const DEFLECTOR_B := Vector2(1272.0, 196.0)
const LAUNCH_POS := Vector2(1244.0, 676.0)
const LAUNCH_ANGLE_DEG := -90.0
const LAUNCH_POWER_MIN := 1120.0
const LAUNCH_POWER_MAX := 1600.0
const CHARGE_TIME := 1.05
## ⑥ 运动改变区：球进入台面后关闭轨道缺口（防止反弹回轨道）
const GATE_RECT := Rect2(1216.0, 140.0, 56.0, 110.0)

## 底部槽位区（位置固定、内容每局随机，见 POCKET 配置）
const SLOT_TOP := 616.0
const SLOT_RECT := Rect2(656.0, 616.0, 544.0, 88.0)
const SLOT_WEIGHTS: Array[float] = [0.17, 0.17, 0.165, 0.165, 0.165, 0.165]
## 兼容旧代码的默认倍率/名称（v1.2 起实际内容由 GameState.get_slot_config 随机生成）
const SLOT_MULTIPLIERS: Array[float] = [3.0, 1.5, 1.0, 0.0, 1.0, 1.5]
const SLOT_NAMES: Array[String] = ["逆命·三倍", "偏转·壹", "顺流", "虚空裂隙", "顺流", "偏转·贰"]
## 每局随机生成的框内容：倍率池（权重）/ 奖励池
const POCKET_MULT_POOL: Array[Dictionary] = [	{"mult": 0.0, "weight": 10},
	{"mult": 1.0, "weight": 24},
	{"mult": 1.5, "weight": 24},
	{"mult": 2.0, "weight": 20},
	{"mult": 3.0, "weight": 15},
	{"mult": 5.0, "weight": 7},
]
const POCKET_BONUS_POOL: Array[Dictionary] = [
	{"id": "", "name": "", "weight": 62},
	{"id": "coin2", "name": "金币+2", "weight": 22},
	{"id": "ball1", "name": "再射一球", "weight": 16},
]

# ---------------- 弹珠 ----------------
const BALL_RADIUS := 12.0
const BALL_GRAVITY_SCALE := 1.0
const BALL_BOUNCE := 0.62
const BALL_BASE_NORMAL := 5
const BALL_BASE_ADVANCED := 10
const BALLS_PER_LEVEL := 5
const BALL_TRAIL_LENGTH := 12
const BUFFED_BALL_MULT := 1.5
## 分裂卡：撞到第一根柱子后分裂成 3 颗
const SPLIT_COUNT := 3
## 质量卡：反弹更少、免疫粘性、可撞落被黏住的弹珠
const MASS_BOUNCE := 0.28
## 缩小卡：体积 ×0.8，发射速度 ×1.2
const SHRINK_SCALE := 0.8
const SHRINK_SPEED_MULT := 1.2
## 粘性立柱：弹珠被黏住的时间（秒）
const STICK_SECONDS := 0.9

# ---------------- 守命者 ----------------
const GUARDIAN_Y := 590.0
const GUARDIAN_RADIUS := 18.0
const GUARDIAN_SPEED := 190.0
const GUARDIAN_MIN_X := 700.0
const GUARDIAN_MAX_X := 1150.0

# ---------------- 2D 走廊 ----------------
const CORRIDOR_LENGTH := 4200.0
const CORRIDOR_FLOOR_Y := 566.0
const CORRIDOR_DOOR_X: Array[float] = [1100.0, 2300.0, 3500.0]
const CORRIDOR_PLAYER_START := Vector2(280.0, 566.0)
const CORRIDOR_PLAYER_SPEED := 430.0
const JOYSTICK_CENTER := Vector2(140.0, 606.0)
const JOYSTICK_RADIUS := 82.0

# ---------------- 局外行囊（跨局公共变量） ----------------
## 一局结束最多带出的弹珠/卡牌数量
const META_CARRY_BALLS := 3
const META_CARRY_CARDS := 2
## 带入下一局的上限
const META_MAX_SELECT_BALLS := 3
const META_MAX_SELECT_CARDS := 2

# ---------------- 双倍注（准备阶段结束前的风险选择） ----------------
## 得分×2、金币奖励×2、黑柱惩罚×2、失败碎片减半
const DOUBLE_MODE_SCORE_MULT := 2
const DOUBLE_MODE_COIN_MULT := 2
const DOUBLE_MODE_PENALTY_MULT := 2
const DOUBLE_MODE_FAIL_SHARD_DIV := 2

# ---------------- 新手引导 ----------------
const TUTORIAL_TEXT_1 := "长按⑦道具库里的卡牌/装备"
const TUTORIAL_TEXT_2 := "拖到⑤立柱（装备）或③弹珠灯（增益卡）"
const TUTORIAL_TEXT_3 := "松开手指即可生效，弹珠灯会变红"

# ---------------- 主题色 ----------------
const COLOR_BG_DEEP := Color("0a0713")
const COLOR_BG_MID := Color("161028")
const COLOR_BG_LOW := Color("1e1536")
const COLOR_PANEL := Color("221838")
const COLOR_PANEL_EDGE := Color("5b4a86")
const COLOR_GOLD := Color("e8c36a")
const COLOR_GOLD_DIM := Color("a98b45")
const COLOR_JADE := Color("6fe0b0")
const COLOR_VIOLET := Color("9a7bff")
const COLOR_VIOLET_DIM := Color("5c45a8")
const COLOR_CRIMSON := Color("ff5d6c")
const COLOR_TEXT := Color("f3e9d2")
const COLOR_TEXT_DIM := Color("b6aec9")
const COLOR_VOID := Color("05030a")
const COLOR_BLACK_PEG := Color("2b2438")
const COLOR_WHITE_PEG := Color("f4f0ff")

# ---------------- 关卡 ----------------
const MAX_LEVEL := 3
const START_COINS := 9
const LEVEL_TARGETS: Array[int] = [25, 38, 45]
const LEVEL_NAMES: Array[String] = ["裂纹初现", "因果倒错", "无柱之渊"]
const LEVEL_BUFFS: Array[String] = [
	"命运压制：最终得分降低20%",
	"因果倒错：弹珠基础分提升20%",
	"无柱之渊：普通立柱全部消失",
]
const LEVEL_SCORE_MULT: Array[float] = [0.8, 1.0, 1.0]
const LEVEL_BALL_BASE_MULT: Array[float] = [1.0, 1.2, 1.0]
const CLEAR_COIN_REWARD := 5

# ---------------- 道具（商店） ----------------
## kind: equipment=拖到立柱；card=拖到弹珠灯；passive=购买即生效；library=进入弹珠库
const ITEMS := {
	"reflector": {
		"name": "反射器",
		"desc": "拖到立柱上：该立柱反弹大幅增强",
		"cost": 5,
		"kind": "equipment",
		"tag": "装备",
	},
	"sticky": {
		"name": "粘性器",
		"desc": "拖到立柱上：弹珠撞上会被黏住约0.9秒",
		"cost": 5,
		"kind": "equipment",
		"tag": "装备",
	},
	"powercard": {
		"name": "强力卡",
		"desc": "拖到弹珠上：该球发射力度+30%",
		"cost": 4,
		"kind": "card",
		"tag": "增益卡",
	},
	"splitcard": {
		"name": "分裂卡",
		"desc": "拖到弹珠上：撞到第一根柱子后分裂成3颗",
		"cost": 12,
		"kind": "card",
		"tag": "增益卡",
	},
	"masscard": {
		"name": "质量卡",
		"desc": "拖到弹珠上：反弹更少、免疫粘性、可撞落黏住的弹珠",
		"cost": 7,
		"kind": "card",
		"tag": "增益卡",
	},
	"shrinkcard": {
		"name": "缩小卡",
		"desc": "拖到弹珠上：体积×0.8，发射速度×1.2",
		"cost": 4,
		"kind": "card",
		"tag": "增益卡",
	},
	"gold_eye": {
		"name": "金瞳",
		"desc": "每关开始时额外获得1枚弹珠",
		"cost": 6,
		"kind": "passive",
		"tag": "命运遗物",
	},
	"advanced_ball": {
		"name": "进阶弹珠",
		"desc": "立即获得2枚进阶弹珠（放入弹珠库）",
		"cost": 4,
		"kind": "library",
		"tag": "弹珠",
	},
}
const SHOP_OFFER_COUNT := 3

# ---------------- 命运事件 ----------------
const FATE_EVENTS: Array[Dictionary] = [
	{"id": "fate_bless", "name": "命运垂青", "desc": "本关额外获得1枚弹珠", "bonus_ball": 1},
	{"id": "fate_gold", "name": "金珠现世", "desc": "立刻获得2枚金币", "bonus_coin": 2},
	{"id": "fate_yellow", "name": "因果共鸣", "desc": "黄色立柱每次加成+1", "yellow_bonus": 1},
	{"id": "fate_target_down", "name": "裂痕示警", "desc": "本关目标分数-5", "target_delta": -5},
	{"id": "fate_shard", "name": "碎片回响", "desc": "本局结算额外获得5枚命运碎片", "shard_bonus": 5},
	{"id": "fate_void", "name": "虚空低语", "desc": "本关目标分数+5，但结算碎片+8", "target_delta": 5, "shard_bonus": 8},
]

# ---------------- 剧情文案 ----------------
const STORY_OPENING := "当命运琉璃绽开第一道裂纹，你被拉入命运回廊。\n沿着回廊走下去，每一个房间都是一次命运试炼。"
const STORY_LINES: Array[String] = [
	"你的命运琉璃珠已经有了裂痕。",
	"回廊深处，守命者正注视着每一个房间。",
	"走进房间，把命运弹珠发射出去——或者被它改写。",
]
