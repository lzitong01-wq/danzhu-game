# Android APK 导出说明（？！珠珠！？ / Godot 4.6.3）

> 本文件由构建工程师维护。当前已验证可产出可安装的 debug APK。

## 0. 当前产物（已验证）

| 项目 | 值 |
|---|---|
| APK | `build\zhuzhu-fate-debug.apk`（别名副本 `build\zhuzhu-fate.apk`，内容相同） |
| 大小 | 47,109,668 字节（44.93 MB） |
| 包名 | `com.fatezhuzhu.game` |
| versionCode / versionName | 1 / 1.0 |
| minSdk / targetSdk（模板内置） | 24 / 36 |
| native-code | arm64-v8a |
| 横屏 | `android:screenOrientation=0`（landscape）+ uses-feature screen.landscape |
| 签名 | debug keystore，APK Signature Scheme v2 + v3 通过（apksigner: Verifies） |
| 启动 Activity | `com.godot.game.GodotAppLauncher`（activity-alias，MAIN/LAUNCHER） |

> SHA256 每次重新构建都会变化（APK 签名/时间戳），以构建日志输出为准。

## 1. 一键构建 debug APK

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "G:\GoDot\？！珠珠！？\tools\build_apk.ps1"
```

可选参数：`-SkipImport`（跳过重新导入）、`-SkipVerify`、`-SkipAlias`、`-OutApk <路径>`。

脚本流程：
1. 校验 Godot、双模板（`android_debug.apk` + `android_release.apk`）、项目文件、预设名 "Android"；
2. `--headless --import`；
3. `--headless --export-debug "Android" <输出>`；
4. 复制到 `%TEMP%` ASCII 路径后用 `aapt2 dump badging` 校验（aapt2 无法打开中文路径）；
5. `apksigner verify --verbose`；
6. 复制 `build\zhuzhu-fate.apk` 别名；输出路径/大小/SHA256；失败退出码非 0。

脚本使用 `Start-Process -Wait -PassThru` 获取 Godot 真实退出码（PS 5.1 直接 `&` 调用 Godot 不会等待、拿不到退出码）。
文件必须以 **UTF-8 BOM** 保存，否则 Windows PowerShell 5.1 会按 ANSI 读入导致中文乱码解析失败。

## 2. 手动构建（等价命令）

```powershell
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --import
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --export-debug "Android" 'G:\GoDot\？！珠珠！？\build\zhuzhu-fate-debug.apk'
```

## 3. 两个必须满足的导出前提（踩坑记录）

1. **项目必须开启 ETC2/ASTC 纹理导入**：`project.godot` 的 `[rendering]` 需要
   `textures/vram_compression/import_etc2_astc=true`。
   否则 Godot 4.6.3 会报 `Cannot export project with preset "Android" due to configuration errors:`
   且**后面没有任何错误文本**（源码 `has_valid_project_configuration()` 里只置 valid=false 不写错误）。
2. **非 Gradle 构建不能覆盖 min/target SDK**：`export_presets.cfg` 中
   `gradle_build/min_sdk` 与 `gradle_build/target_sdk` 必须留空（`""`），否则报
   “最小 SDK/目标 SDK 只有在启用使用 Gradle 构建时才能覆盖”。实际值由官方模板决定（24 / 36）。

另外：Godot 校验导出配置时**同时要求 debug 和 release 两个模板都存在**（哪怕只导 debug）。

## 4. 安装到 Android 手机

- debug 签名 APK 可直接安装：手机「设置 → 安全 → 允许安装未知来源应用」（Android 8+ 按应用授权）。
- USB：`adb install -r build\zhuzhu-fate-debug.apk`（需开启 USB 调试）。
- 或把 APK 拷贝到手机点击安装。

## 5. Release 版导出（上架/正式分发）

### 5.1 正式 keystore（推荐）

debug.keystore 只适合测试：公开口令、不能上架、换签名会导致无法覆盖升级。生成正式 keystore（离线备份）：

```powershell
& 'D:\Java\JDK_java\bin\keytool.exe' -genkeypair -v `
  -keystore "G:\GoDot\_toolchain\release.keystore" -storetype PKCS12 `
  -alias zhuzhu -storepass <口令> -keypass <口令> `
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=FateZhuzhu, O=FateZhuzhu, C=CN"
```

在 `export_presets.cfg` 的 `[preset.0.options]` 里设置（或编辑器 UI → Android 预设 → Keystore 段）：

```
keystore/release="G:/GoDot/_toolchain/release.keystore"
keystore/release_user="zhuzhu"
keystore/release_password="<口令>"
```

### 5.2 导出 release APK

```powershell
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --export-release "Android" 'G:\GoDot\？！珠珠！？\build\zhuzhu-fate-release.apk'
```

### 5.3 无正式 keystore 的临时方案

用 debug keystore 给 release 模板签名（可安装，但属测试签名，不可上架）：

```
keystore/release="G:/GoDot/_toolchain/debug.keystore"
keystore/release_user="androiddebugkey"
keystore/release_password="android"
```

## 6. 本机工具链

| 组件 | 路径 / 版本 |
|---|---|
| Godot | `D:\Godot_v4.6.3-stable_win64.exe`（4.6.3.stable.official.7d41c59c4） |
| Android SDK | `D:\VS\GGS\Android\android-sdk`（build-tools 36.0.0、platforms android-35/36、platform-tools） |
| JDK | `D:\Java\JDK_java`（17.0.12） |
| debug keystore | `G:\GoDot\_toolchain\debug.keystore`（alias `androiddebugkey`，口令 `android`） |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.6.3.stable\`（android_debug.apk / android_release.apk / version.txt） |
| 编辑器设置 | `%APPDATA%\Godot\editor_settings-4.6.tres`（android_sdk_path / java_sdk_path / debug_keystore*） |

## 7. APK 内部结构说明（Godot 4.6）

Godot 4.6 的 Android 导出**不使用 `assets/*.pck`**，而是把项目资源以「松散文件」方式放进 APK 的 `assets/`：

- `assets/project.binary`：二进制项目设置
- `assets/.godot/imported/*`：导入后的纹理/字体/音频（ETC2/ASTC 压缩后的 `.ctex` 等）
- `assets/.godot/exported/*`：导出的场景（`.scn`）
- `assets/scripts/**.gdc`：编译后的 GDScript 字节码
- `assets/assets.sparsepck`（12 KB）：Godot 4.6 的稀疏资源索引
- 所有 `*.remap` 指向的导出目标均已校验存在（32/32）
- `lib/arm64-v8a/libgodot_android.so`（75,345,928 字节）+ `libc++_shared.so`
- 自适应图标：`res/mipmap-anydpi-v26/icon.xml`

## 8. 已知限制 / 风险

- 本机无 Android 真机/模拟器：安装性通过 `aapt2 dump badging` + `apksigner verify` 静态验证；建议有手机时 `adb install` 冒烟一次。
- targetSdk 由官方模板决定为 36（无法在非 Gradle 导出中改为 35；36 满足商店 target 35+ 要求，通常更无兼容问题）。
- debug APK 带 `android:debuggable=true`，仅用于测试分发。
- 每次构建 SHA256 不同（签名时间戳），属正常现象。
- aapt（build-tools 36.0.0 的旧 aapt）解析本 manifest 的 `android:required` 会报错，校验请用 `aapt2`。
