class_name FateConfig
extends RefCounted
## 《！？珠珠？！》全局配置 v1.4
## 依据《基础策划案 (2)》：10 关、命核碎片、三种琉璃珠、合成概率、刷新、关卡 buff、走廊 NPC 文案。
## 只由 Lead 维护；其他成员如需常量变更请先沟通。

const GAME_TITLE := "！？珠珠？！"
const GAME_SUBTITLE := "命运回廊 · 弹珠试炼"
const GAME_VERSION := "1.8.0"

# ---------------- 屏幕 ----------------
const VIEW_SIZE := Vector2(1280, 720)

# ---------------- P1 布局 ----------------
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
## v1.4：右端与轨道之间留出 40px 通道，避免最右柱与边界太紧卡球
const PEG_AREA := Rect2(648.0, 168.0, 528.0, 424.0)       # ⑤
const PEG_COLS := 6
const PEG_ROWS := 7
const PEG_RADIUS := 11.0
const PEG_ROW_OFFSET_RATIO := 0.5
const PEG_JITTER := 2.0
## 右侧安全通道：立柱中心不得进入 x > RAIL_LEFT - PEG_RIGHT_GAP
const PEG_RIGHT_GAP := 40.0

const PEG_TYPE_NORMAL := 0
const PEG_TYPE_YELLOW := 1
const PEG_TYPE_GREEN := 2
const PEG_TYPE_BLACK := 3
const PEG_TYPE_WHITE := 4
const PEG_WEIGHTS: Array[int] = [55, 30, 15, 5, 10]
const BLACK_PENALTY := 1
const WHITE_BASE_COIN_CHANCE := 0.20
const WHITE_CHANCE_STEP := 0.10

## 绿色连线：只允许横/竖相邻，每颗绿柱最多连 2 条，避免随机乱连
const GREEN_LINK_ALLOWED_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
const GREEN_LINK_MAX_PER_PEG := 2

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
const GATE_RECT := Rect2(1216.0, 140.0, 56.0, 110.0)

## 底部槽位（位置固定、内容每局随机）
const SLOT_TOP := 616.0
const SLOT_RECT := Rect2(656.0, 616.0, 544.0, 88.0)
const SLOT_WEIGHTS: Array[float] = [0.17, 0.17, 0.165, 0.165, 0.165, 0.165]
const SLOT_MULTIPLIERS: Array[float] = [3.0, 1.5, 1.0, 0.0, 1.0, 1.5]
const SLOT_NAMES: Array[String] = ["逆命·三倍", "偏转·壹", "顺流", "虚空裂隙", "顺流", "偏转·贰"]
const POCKET_MULT_POOL: Array[Dictionary] = [
	{"mult": 0.0, "weight": 10},
	{"mult": 1.0, "weight": 24},
	{"mult": 1.5, "weight": 24},
	{"mult": 2.0, "weight": 20},
	{"mult": 3.0, "weight": 15},
	{"mult": 5.0, "weight": 7},
]
const POCKET_BONUS_POOL: Array[Dictionary] = [
	{"id": "", "name": "", "weight": 62},
	{"id": "coin2", "name": "命核+2", "weight": 22},
	{"id": "ball1", "name": "再射一球", "weight": 16},
]

# ---------------- 弹珠（三种琉璃珠） ----------------
const BALL_RADIUS := 12.0
const BALL_GRAVITY_SCALE := 1.0
const BALL_BOUNCE := 0.62
const BALL_TYPE_FATE := 0      # 命运琉璃珠（普通）
const BALL_TYPE_CORE := 1      # 命核琉璃珠（进阶）
const BALL_TYPE_SOURCE := 2    # 命源琉璃珠（高阶）
const BALL_BASE_SCORES: Array[int] = [5, 10, 20]
const BALL_NAMES: Array[String] = ["命运琉璃珠", "命核琉璃珠", "命源琉璃珠"]
const BALLS_PER_LEVEL := 5
const BALL_TRAIL_LENGTH := 12
const BUFFED_BALL_MULT := 1.5
const SPLIT_COUNT := 3
const MASS_BOUNCE := 0.28
const SHRINK_SCALE := 0.8
const SHRINK_SPEED_MULT := 1.2
const STICK_SECONDS := 0.9

## 合成概率（每关各一次）
const SYNTH_CORE_SUCCESS := 0.60   # 3 普通 → 1 进阶（失败返还 3 普通）
const SYNTH_SOURCE_SUCCESS := 0.40 # 3 进阶 → 1 高阶（失败返还 2 进阶）
const SYNTH_CORE_COST := 3
const SYNTH_SOURCE_COST := 3

# ---------------- 守命者 ----------------
const GUARDIAN_Y := 590.0
const GUARDIAN_RADIUS := 18.0
const GUARDIAN_SPEED := 190.0
const GUARDIAN_MIN_X := 700.0
const GUARDIAN_MAX_X := 1150.0

# ---------------- 2D 走廊（10 间房） ----------------
const CORRIDOR_LENGTH := 10600.0
const CORRIDOR_FLOOR_Y := 566.0
## 10 扇门 x 坐标
const CORRIDOR_DOOR_X: Array[float] = [1100, 2100, 3100, 4100, 5100, 6100, 7100, 8100, 9100, 10100]
## 每关前 NPC 站位（门左侧距离）
const CORRIDOR_NPC_OFFSET := 320.0
const CORRIDOR_PLAYER_START := Vector2(280.0, 566.0)
const CORRIDOR_PLAYER_SPEED := 430.0
const JOYSTICK_CENTER := Vector2(140.0, 606.0)
const JOYSTICK_RADIUS := 82.0
## 玩家像素角色动画（ui-dev 生成）
const PLAYER_WALK_SPRITE := "res://assets/art/player_walk.png"
const PLAYER_IDLE_SPRITE := "res://assets/art/player_idle.png"
const PLAYER_FRAME_SIZE := Vector2(72, 222)
const PLAYER_WALK_FRAMES := 6
const PLAYER_IDLE_FRAMES := 4
const PLAYER_FPS := 10.0
const PLAYER_SCALE := 0.85

# ---------------- 局外行囊 ----------------
const META_CARRY_BALLS := 3
const META_CARRY_CARDS := 2
const META_MAX_SELECT_BALLS := 3
const META_MAX_SELECT_CARDS := 2

# ---------------- 双倍注 ----------------
const DOUBLE_MODE_SCORE_MULT := 2
const DOUBLE_MODE_COIN_MULT := 2
const DOUBLE_MODE_PENALTY_MULT := 2
const DOUBLE_MODE_FAIL_SHARD_DIV := 2

# ---------------- 新手引导 ----------------
const TUTORIAL_TEXT_1 := "长按⑦道具库里的卡牌/装备"
const TUTORIAL_TEXT_2 := "拖到⑤立柱（装备）或③弹珠灯（增益卡）"
const TUTORIAL_TEXT_3 := "松开手指即可生效，弹珠灯会变红"

# ---------------- 主题色（像素） ----------------
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

# ---------------- 关卡（10 关） ----------------
const MAX_LEVEL := 10
const START_COINS := 9
const LEVEL_NAMES: Array[String] = [
	"微光之径", "回风之廊", "因果回响", "命核共鸣", "裂隙侵蚀",
	"守命低语", "命运重压", "万流归宗", "倒戈止逆", "命源再现",
]
const LEVEL_TARGETS: Array[int] = [30, 35, 40, 50, 50, 60, 60, 70, 90, 130]
## 关卡 buff（effect 字段供 gameplay/GameState 读取）
const LEVEL_BUFFS: Array[Dictionary] = [
	{"id": "micro_light", "name": "命运微光", "type": "buff", "desc": "弹珠基础分+1", "base_bonus": 1},
	{"id": "hall_wind", "name": "回廊之风", "type": "buff", "desc": "弹珠弹射速度+10%", "bounce_bonus": 0.10},
	{"id": "karma_echo", "name": "因果回响", "type": "debuff", "desc": "弹珠撞柱后有30%概率随机改变方向", "chaos_chance": 0.30},
	{"id": "core_resonance", "name": "命核共鸣", "type": "buff", "desc": "每撞一次白色立柱额外获得1枚命核碎片", "white_bonus": 1},
	{"id": "rift_erosion", "name": "裂隙侵蚀", "type": "debuff", "desc": "弹珠3次撞绿柱/连线后自毁，绿色立柱权重+20", "green_limit": 3, "green_weight_bonus": 20},
	{"id": "guardian_whisper", "name": "守命低语", "type": "buff", "desc": "价格≥7的道具刷新权重+130", "price7_weight_bonus": 130},
	{"id": "fate_press", "name": "命运重压", "type": "debuff", "desc": "弹珠重力+15%", "gravity_bonus": 0.15},
	{"id": "all_flows", "name": "万流归宗", "type": "buff", "desc": "本关命核≥50时触发10秒破命状态：弹珠不灭且得分翻倍", "break_threshold": 50, "break_seconds": 10.0},
	{"id": "reverse_stop", "name": "倒戈止逆", "type": "debuff", "desc": "最终得分-30%", "score_mult": 0.7},
	{"id": "source_return", "name": "命源再现", "type": "buff", "desc": "删除所有普通与负面立柱", "remove_normal": true, "remove_negative": true},
]
const CLEAR_COIN_REWARD := 5
## 每关通关额外命核碎片（便于 10 关推进）
const LEVEL_CLEAR_BONUS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10]

# ---------------- 道具（商店，权重制） ----------------
## kind: equipment=拖立柱；card=拖弹珠灯；instant=购买即生效
const ITEMS := {
	"reflector": {
		"name": "命运偏转器", "desc": "拖到立柱上：该立柱反弹大幅增强",
		"cost": 5, "weight": 336, "kind": "equipment", "tag": "装备",
	},
	"sticky": {
		"name": "命链粘性勾", "desc": "拖到立柱上：弹珠撞上会被黏住约0.9秒",
		"cost": 5, "weight": 336, "kind": "equipment", "tag": "装备",
	},
	"rift_note": {
		"name": "歧路回廊帖", "desc": "拖到立柱上：撞到此柱的弹珠会被随机传送到其他立柱",
		"cost": 7, "weight": 240, "kind": "equipment", "tag": "装备",
	},
	"recall_pouch": {
		"name": "归命拾珠囊", "desc": "拖到立柱上：撞到此柱的弹珠被收回弹珠库，60%概率额外获得一颗同型珠",
		"cost": 12, "weight": 140, "kind": "equipment", "tag": "装备",
	},
	"spindle_nail": {
		"name": "命运纺锤钉", "desc": "拖到立柱上：该立柱变为只有基础反弹的普通立柱",
		"cost": 7, "weight": 240, "kind": "equipment", "tag": "装备",
	},
	"pass_chisel": {
		"name": "穿命透障凿", "desc": "拖到立柱上：该立柱失去所有功能，弹珠可直接穿过",
		"cost": 10, "weight": 168, "kind": "equipment", "tag": "装备",
	},
	"powercard": {
		"name": "破名蓄力卡", "desc": "拖到弹珠上：该球发射力度+30%",
		"cost": 4, "weight": 420, "kind": "card", "tag": "增益卡",
	},
	"splitcard": {
		"name": "万象分裂卡", "desc": "拖到弹珠上：撞到第一根柱子后分裂成3颗",
		"cost": 12, "weight": 140, "kind": "card", "tag": "增益卡",
	},
	"masscard": {
		"name": "因果质量卡", "desc": "拖到弹珠上：反弹更少、免疫粘性、可撞落黏住的弹珠",
		"cost": 7, "weight": 240, "kind": "card", "tag": "增益卡",
	},
	"shrinkcard": {
		"name": "微尘缩小卡", "desc": "拖到弹珠上：体积×0.8，发射速度×1.2",
		"cost": 4, "weight": 420, "kind": "card", "tag": "增益卡",
	},
	"fate_gift": {
		"name": "命运的赠与", "desc": "购买后立刻获得1枚命运琉璃珠",
		"cost": 4, "weight": 420, "kind": "instant", "tag": "道具",
	},
	"fate_reward": {
		"name": "命运的奖赏", "desc": "购买后立刻获得1枚命核琉璃珠",
		"cost": 7, "weight": 240, "kind": "instant", "tag": "道具",
	},
}
const SHOP_OFFER_COUNT := 3
## 道具选择区刷新：基础 1 命核碎片，同关每刷一次 +1
const REFRESH_BASE_COST := 1
const REFRESH_COST_STEP := 1
const REFRESH_PRICE7_EXTRA_WEIGHT := 130

# ---------------- 命运事件（保留） ----------------
const FATE_EVENTS: Array[Dictionary] = [
	{"id": "fate_bless", "name": "命运垂青", "desc": "本关额外获得1枚弹珠", "bonus_ball": 1},
	{"id": "fate_gold", "name": "金珠现世", "desc": "立刻获得2枚命核碎片", "bonus_coin": 2},
	{"id": "fate_yellow", "name": "因果共鸣", "desc": "黄色立柱每次加成+1", "yellow_bonus": 1},
	{"id": "fate_target_down", "name": "裂痕示警", "desc": "本关目标分数-5", "target_delta": -5},
	{"id": "fate_shard", "name": "碎片回响", "desc": "本局结算额外获得5枚命运碎片", "shard_bonus": 5},
	{"id": "fate_void", "name": "虚空低语", "desc": "本关目标分数+5，但结算碎片+8", "target_delta": 5, "shard_bonus": 8},
]

# ---------------- 走廊 NPC 关卡文案 ----------------
const LEVEL_STORY_LINES: Array[String] = [
	"命运写定了城邦的终局，但我不愿做一个只会等待的人。",
	"回廊里的琉璃墙映着无数碎片般的光——每一道光里，都有某个人的一生在重演。原来命运的回廊，是一座由所有人生堆砌的坟场。",
	"我能推迟灾祸，便以为能抹去灾祸，却是忘记，它本就是链锁。",
	"他们的琉璃珠碎在弹珠台上，化作墙上一道淡淡的疤痕。原来推迟和抹除命运，中间隔着的不是努力，而是......代价。",
	"守命者说命运不可逆转。那时的我，只当是枷锁的谎言。",
	"所到之处皆是守命者的目光。我像是它的木偶，欣赏着一场注定落幕的戏。可它不知道，凡人最擅长的就是在剧本的缝隙里写字。",
	"我离击碎宿命只差一瞬。就差那么一瞬！就在那一刻，我倾覆改写的万象齐齐溯流折返，奔涌而来，险些将我吞没。",
	"故土尚未陷落，我拼尽全力的抗争，怎能只是空梦一场？",
	"纵使翻不过命运的大山，可我掷出琉璃的那一刻，便燃尽了所有不肯俯首的执念。",
	"他是边境城邦的琉璃匠，能读懂命运轨迹。灾荒降临时，他以自身琉璃为引踏入命运回廊，拨动一城人的命运推迟末日。但他不甘仅推迟——他要永久抹除覆灭的命运线。触及宿命节点时，全城命运琉璃反噬，他被投入无尽轮回。可轮回杀不死不屈之人，他一次次重来，掷出每一颗琉璃——因为投掷的瞬间，便是自由本身。",
]
const FAILURE_STORY_LINE := "命运杀不死我，纵使此身沦陷，亦有来世之身。"

# ---------------- 剧情/界面文案 ----------------
const STORY_OPENING := "当命运琉璃绽开第一道裂纹，你被拉入命运回廊。\n沿着回廊走下去，每一个房间都是一次命运试炼。"
const STORY_LINES: Array[String] = [
	"你的命运琉璃珠已经有了裂痕。",
	"回廊深处，守命者正注视着每一个房间。",
	"走进房间，把命运琉璃珠发射出去——或者被它改写。",
]
## 腾讯式启动页/健康游戏忠告（风格致敬，不涉及真实商标）
const SPLASH_STUDIO := "琉璃回廊工作室"
const SPLASH_PUBLISHER := "命运互动"
const HEALTH_TIP_TITLE := "健康游戏忠告"
const HEALTH_TIPS: Array[String] = [
	"抵制不良游戏，拒绝盗版游戏。",
	"注意自我保护，谨防受骗上当。",
	"适度游戏益脑，沉迷游戏伤身。",
	"合理安排时间，享受健康生活。",
]
const AGE_TIP := "适龄提示 12+"
const LOADING_TIPS: Array[String] = [
	"小提示：长按道具可以拖到立柱与弹珠灯上。",
	"小提示：弹珠卡住时会被命运之风救走。",
	"小提示：绿色立柱之间的连线会把弹珠再次弹开。",
	"小提示：每关只能合成一次琉璃珠，谨慎选择。",
	"小提示：局外行囊里的琉璃珠与卡牌可带入下一局。",
]

# ---------------- v1.5：主角等级 / 主菜单（简洁独游风） ----------------
## 每通过一间房获得的主角经验
const EXP_PER_ROOM_CLEAR := 40
## 升级所需经验 = BASE + (等级-1) * GROWTH
const EXP_BASE_REQUIRED := 100
const EXP_GROWTH := 60
## 主菜单五项
const MENU_CONTINUE := "继续未尽之命运"
const MENU_NEW := "起新途之命运"
const MENU_SETTINGS := "设置"
const MENU_ABOUT := "关于我们"
const MENU_QUIT := "退出"
const ABOUT_TEXT := "《！？珠珠？！》\n命运回廊 · 弹珠试炼\n\n一个琉璃匠走进命运回廊，\n掷出每一颗命运琉璃珠，\n在注定的剧本缝隙里写下自己的字。\n\n像素弹珠肉鸽 · Godot 4.6.3\nv1.8.0"
## 角色/行囊面板顶部目录
const PANEL_TABS: Array[String] = ["角色信息", "弹珠", "卡牌"]

# ---------------- v1.6：存档点 / 购买限制 / 携带 / 对话 / 说明文案 ----------------
## 存档点（①走廊 ②商店 ③关卡 ④关卡结束）
const CHECKPOINT_CORRIDOR := 1
const CHECKPOINT_SHOP := 2
const CHECKPOINT_LEVEL := 3
const CHECKPOINT_CLEAR := 4
## 商店每种道具每轮限购 1 次（刷新后仍会出现但不可再买）
const SHOP_ITEM_PURCHASE_LIMIT := 1
## 关卡内通过槽位获得的额外弹珠上限（每关最多 7 颗）
const SLOT_BALL_BONUS_MAX := 2
## 带入下一局上限
const BALL_CARRY_MAX := 3
const ITEM_CARRY_MAX := 2
## 走廊 NPC 交互
const NPC_W_LABEL := "W"
const NPC_INTERACT_RADIUS := 90.0
## 关卡文案逐字速度（秒/字）
const STORY_TYPE_SPEED := 0.045
## 个人信息图标（右上角，若使用）
const PERSONAL_ICON_PATH := "res://assets/art/personal_icon.png"

## 弹珠说明（详情弹窗：基础得分 / 获取方式 / 文案）
const BALL_BASE_DESC: Array[String] = ["5", "10", "20"]
const BALL_GET_WAYS: Array[String] = [
	"初始自带",
	"三颗命运琉璃珠合成（60% 成功率）",
	"三颗命核琉璃珠合成（40% 成功率）",
]
const BALL_LORES: Array[String] = [
	"最普通的命运之珠，表面还残留着持有者掌心的温度。每一颗都曾映照过一个人的悲欢。",
	"由三颗普通琉璃珠融合而成，内部流转着更凝练的命运之光。三珠归一，命运之力倍增。",
	"祂曾是过去的命运，亦是现在的命运，却唯独不是未来的命运。",
]

## 道具/装备文案（详情弹窗用；键同 FateConfig.ITEMS）
const ITEM_LORES := {
	"reflector": "琉璃匠当年在回廊使用的偏转挡板残片。它曾无数次改变弹珠的轨迹，也改变过许多人的命运。",
	"sticky": "一根缠绕着命运丝线的旧绳。被它黏住的弹珠不会掉落——就像那些被命运抓住的人，暂时无法挣脱。",
	"rift_note": "不知何人的旧贴，使命运有了更多的可能。",
	"recall_pouch": "琉璃匠收拢散落命珠的旧囊，囊口磨得发亮。倒出弹珠时，偶尔会多滚出一颗——命运在回收时，似乎总爱留下一点余数。",
	"spindle_nail": "这是一枚普通的命运之钉，它唯一的作用就是让其它命运之物变得一样普通。",
	"pass_chisel": "一柄细长的琉璃凿尖，专凿立柱上盘踞的命纹。被它凿空的立柱不再拦路，弹珠径直穿过，仿佛命运从未在那里设过墙。",
	"powercard": "琉璃匠打磨弹珠时用来蓄力的旧工具。握柄上刻着「以凡人之力，亦可蓄破命一击」。",
	"splitcard": "守命者当年丢弃的残片，据说能模拟命运的分岔——一条路走不通，便化作三条。",
	"masscard": "刻着「重则不欺」的琉璃石板。命运之重不可回避，但可以被承担。",
	"shrinkcard": "「再大的命运，缩小了看也不过一粒微尘。」——某位无名试炼者的刻字。",
	"fate_gift": "命运的馈赠无关大小。",
	"fate_reward": "领取命运的赏赐吧，试图反抗命运之人。",
}


