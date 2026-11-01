extends Node
## 音频管理器（自动加载名 `Audio`）。由 audio-dev 实现。
##
## - BGM：双 AudioStreamPlayer 交叉淡入淡出；menu / battle / shop 循环播放，
##   victory / defeat 只播放一次（不循环，结尾自带淡出）。
## - SFX：8 路播放器池，支持音量偏移与音高变化（便于撞柱音随机化）。
## - 资源缺失时静默降级，绝不抛错；同一首 BGM 重复请求不会重启。
## - 音频文件由 tools/gen_audio.py 程序化合成：
##   assets/audio/bgm/bgm_*.ogg（44.1kHz 立体声 OGG Vorbis，无缝循环）
##   assets/audio/sfx/sfx_*.wav（44.1kHz 单声道 16bit）

const BGM_PATHS := {
	"menu": "res://assets/audio/bgm/bgm_menu.ogg",
	"battle": "res://assets/audio/bgm/bgm_battle.ogg",
	"shop": "res://assets/audio/bgm/bgm_shop.ogg",
	"victory": "res://assets/audio/bgm/bgm_victory.ogg",
	"defeat": "res://assets/audio/bgm/bgm_defeat.ogg",
}
const SFX_PATHS := {
	"launch": "res://assets/audio/sfx/sfx_launch.wav",
	"peg": "res://assets/audio/sfx/sfx_peg.wav",
	"peg_yellow": "res://assets/audio/sfx/sfx_peg_yellow.wav",
	"peg_green": "res://assets/audio/sfx/sfx_peg_green.wav",
	"slot": "res://assets/audio/sfx/sfx_slot.wav",
	"void": "res://assets/audio/sfx/sfx_void.wav",
	"coin": "res://assets/audio/sfx/sfx_coin.wav",
	"buy": "res://assets/audio/sfx/sfx_buy.wav",
	"click": "res://assets/audio/sfx/sfx_click.wav",
	"guardian": "res://assets/audio/sfx/sfx_guardian.wav",
	"crack": "res://assets/audio/sfx/sfx_crack.wav",
	"win": "res://assets/audio/sfx/sfx_win.wav",
	"lose": "res://assets/audio/sfx/sfx_lose.wav",
}

## 只有这三首循环；victory / defeat 是单次短曲。
const LOOPING_BGM := ["menu", "battle", "shop"]
const BGM_CROSSFADE := 0.8
const BGM_FADE_OUT := 0.6
const SILENCE_DB := -80.0
const SFX_POOL_SIZE := 8

var music_volume_db := -6.0
var sfx_volume_db := -3.0

var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_index := 0
var _current_bgm := ""
var _bgm_tween: Tween = null

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _stream_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "BgmPlayer%d" % i
		p.bus = "Master"
		p.volume_db = SILENCE_DB
		add_child(p)
		_bgm_players.append(p)
	for i in SFX_POOL_SIZE:
		var s := AudioStreamPlayer.new()
		s.name = "SfxPlayer%d" % i
		s.bus = "Master"
		s.volume_db = sfx_volume_db
		add_child(s)
		_sfx_players.append(s)
	# 预载短音效，避免第一次撞柱时卡一帧（在下一帧执行，不阻塞启动）。
	call_deferred("_warm_sfx_cache")


## 播放 BGM。track: "menu" | "battle" | "shop" | "victory" | "defeat"。
func play_bgm(track: StringName) -> void:
	var key := String(track)
	if key == _current_bgm and _bgm_players[_bgm_index].playing:
		return
	var path: String = BGM_PATHS.get(key, "")
	if path == "":
		return
	var stream := _get_stream(path, key in LOOPING_BGM)
	if stream == null:
		if _current_bgm != "":
			stop_bgm(BGM_FADE_OUT)
		return
	_current_bgm = key
	_kill_bgm_tween()
	var old := _bgm_players[_bgm_index]
	_bgm_index = (_bgm_index + 1) % _bgm_players.size()
	var new_player := _bgm_players[_bgm_index]
	new_player.stream = stream
	new_player.volume_db = SILENCE_DB
	new_player.play()
	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	_bgm_tween.tween_property(new_player, "volume_db", music_volume_db, BGM_CROSSFADE)
	if old.playing:
		_bgm_tween.tween_property(old, "volume_db", SILENCE_DB, BGM_FADE_OUT)
		_bgm_tween.chain().tween_callback(old.stop)


## 淡出并停止 BGM（fade <= 0 立即停止）。
func stop_bgm(fade: float = 0.6) -> void:
	_current_bgm = ""
	_kill_bgm_tween()
	if fade <= 0.0:
		_stop_all_bgm()
		return
	var had_playing := false
	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	for p in _bgm_players:
		if p.playing:
			had_playing = true
			_bgm_tween.tween_property(p, "volume_db", SILENCE_DB, fade)
	if had_playing:
		_bgm_tween.chain().tween_callback(_stop_all_bgm)


## 播放短音效。pitch 可做随机化（如撞击立柱时传 0.94~1.06）。
func play_sfx(sfx: StringName, volume_offset_db: float = 0.0, pitch: float = 1.0) -> void:
	var path: String = SFX_PATHS.get(String(sfx), "")
	if path == "":
		return
	var stream := _get_stream(path, false)
	if stream == null:
		return
	var p := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = sfx_volume_db + volume_offset_db
	p.pitch_scale = clampf(pitch, 0.4, 2.5)
	p.play()


func set_music_volume(db: float) -> void:
	music_volume_db = clampf(db, SILENCE_DB, 6.0)
	for p in _bgm_players:
		if p.playing:
			p.volume_db = music_volume_db


func set_sfx_volume(db: float) -> void:
	sfx_volume_db = clampf(db, SILENCE_DB, 6.0)
	for p in _sfx_players:
		p.volume_db = sfx_volume_db


## 当前 BGM key（空字符串表示没有 BGM）。供调试 / UI 判断使用。
func get_current_bgm() -> String:
	return _current_bgm


# ---------------------------------------------------------------- 内部实现
func _get_stream(path: String, loop: bool) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _stream_cache.has(path):
		return _stream_cache[path]
	var res := load(path) as AudioStream
	if res == null:
		return null
	_apply_loop(res, loop)
	_stream_cache[path] = res
	return res


func _apply_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if loop:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


func _kill_bgm_tween() -> void:
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null


func _stop_all_bgm() -> void:
	for p in _bgm_players:
		p.stop()
		p.volume_db = SILENCE_DB


func _warm_sfx_cache() -> void:
	for key in SFX_PATHS:
		var path: String = SFX_PATHS[key]
		if ResourceLoader.exists(path):
			_get_stream(path, false)
