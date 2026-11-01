#requires -Version 5.1
<#
.SYNOPSIS
  为 Godot 4.6.3 项目构建 Android 调试 APK（？！珠珠！？）。

.DESCRIPTION
  1) 校验 Godot 可执行文件、Android 导出模板、项目文件、导出预设；
  2) --headless --import 重新导入资源；
  3) --headless --export-debug 导出 APK；
  4) 用 aapt2 dump badging + apksigner verify 做静态校验；
  5) 复制 build/zhuzhu-fate.apk 别名副本；
  6) 打印 APK 路径、大小与 SHA256；失败时退出码非 0 并给出明确原因。

  说明：Windows PowerShell 5.1 直接调用 Godot（GUI 子系统）不会等待进程，
  因此这里统一用 Start-Process -Wait -PassThru 获取真实退出码。
  另外 aapt/aapt2 不能打开含非 ASCII 字符的路径，校验前会复制到 %TEMP% 的 ASCII 路径。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -SkipImport
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\GoDot\？！珠珠！？',
    [string]$GodotExe = 'D:\Godot_v4.6.3-stable_win64.exe',
    [string]$Preset = 'Android',
    [string]$OutApk = 'build\zhuzhu-fate-debug.apk',
    [string]$AndroidSdk = 'D:\VS\GGS\Android\android-sdk',
    [switch]$SkipImport,
    [switch]$SkipVerify,
    [switch]$SkipAlias
)

$ErrorActionPreference = 'Stop'

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "================ BUILD FAILED ================" -ForegroundColor Red
    Write-Host $msg -ForegroundColor Red
    Write-Host "=============================================" -ForegroundColor Red
    exit 1
}

function StepLog([string]$msg) {
    Write-Host ""
    Write-Host ">>> $msg" -ForegroundColor Cyan
}

function Quote([string]$s) {
    return '"' + $s + '"'
}

function Invoke-Godot {
    param(
        [string[]]$GodotArgs,
        [string]$LogPath,
        [string]$Title
    )
    $so = [System.IO.Path]::GetTempFileName()
    $se = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $GodotExe -ArgumentList $GodotArgs -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $so -RedirectStandardError $se
    $out = ''
    if (Test-Path -LiteralPath $so) { $out += [System.IO.File]::ReadAllText($so, [System.Text.Encoding]::UTF8) }
    if (Test-Path -LiteralPath $se) { $out += [System.IO.File]::ReadAllText($se, [System.Text.Encoding]::UTF8) }
    Remove-Item -LiteralPath $so, $se -Force -ErrorAction SilentlyContinue
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value ("`r`n===== $Title =====") -Encoding UTF8
        Add-Content -LiteralPath $LogPath -Value $out -Encoding UTF8
    }
    if ($out) { Write-Host $out }
    return $proc.ExitCode
}

# ---------- 0. 基础校验 ----------
if (-not (Test-Path -LiteralPath $GodotExe)) {
    Fail "找不到 Godot 可执行文件: $GodotExe"
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'project.godot'))) {
    Fail "找不到项目文件: $(Join-Path $ProjectRoot 'project.godot')"
}
$presetsFile = Join-Path $ProjectRoot 'export_presets.cfg'
if (-not (Test-Path -LiteralPath $presetsFile)) {
    Fail "找不到导出预设文件: $presetsFile"
}
if (-not (Select-String -LiteralPath $presetsFile -Pattern ('name="' + [regex]::Escape($Preset) + '"') -Quiet)) {
    Fail "export_presets.cfg 中不存在名为 `"$Preset`" 的导出预设。"
}

$templateDir = Join-Path $env:APPDATA 'Godot\export_templates\4.6.3.stable'
$templateApk = Join-Path $templateDir 'android_debug.apk'
$templateApkRelease = Join-Path $templateDir 'android_release.apk'
if (-not (Test-Path -LiteralPath $templateApk) -or -not (Test-Path -LiteralPath $templateApkRelease)) {
    Fail @"
缺少 Android 导出模板（Godot 要求 debug 和 release 两个模板同时存在）:
  $templateApk
  $templateApkRelease
请安装 Godot 4.6.3 导出模板（android_debug.apk / android_release.apk / version.txt
放到 $templateDir）。
"@
}

# ---------- 1. 计算输出路径 ----------
if ([System.IO.Path]::IsPathRooted($OutApk)) {
    $outFull = $OutApk
} else {
    $outFull = Join-Path $ProjectRoot $OutApk
}
$outDir = Split-Path -Parent $outFull
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
if (Test-Path -LiteralPath $outFull) {
    Remove-Item -LiteralPath $outFull -Force
}
$logFile = Join-Path $outDir 'build.log'
Set-Content -LiteralPath $logFile -Value ("===== build_apk.ps1 $(Get-Date -Format o) =====") -Encoding UTF8

Write-Host "项目:     $ProjectRoot"
Write-Host "Godot:    $GodotExe"
Write-Host "预设:     $Preset"
Write-Host "输出:     $outFull"
Write-Host "模板目录: $templateDir"
Write-Host "日志:     $logFile"

# ---------- 2. 导入资源 ----------
if (-not $SkipImport) {
    StepLog "重新导入项目资源 (--import)"
    $importCode = Invoke-Godot -GodotArgs @('--headless', '--path', (Quote $ProjectRoot), '--import') `
        -LogPath $logFile -Title 'import'
    if ($importCode -ne 0) {
        Fail "资源导入失败（退出码 $importCode）。请检查日志 $logFile 中的脚本/资源错误。"
    }
}

# ---------- 3. 导出 APK ----------
StepLog "导出 Android 调试 APK (--export-debug `"$Preset`")"
$exportCode = Invoke-Godot -GodotArgs @('--headless', '--path', (Quote $ProjectRoot), '--export-debug', (Quote $Preset), (Quote $outFull)) `
    -LogPath $logFile -Title 'export-debug'
if (-not (Test-Path -LiteralPath $outFull)) {
    Fail "导出未生成 APK（退出码 $exportCode）。常见原因：主场景未设置、脚本编译错误、模板/keystore/JDK 配置错误、项目未开启 ETC2/ASTC 纹理导入。日志: $logFile"
}
$apkItem = Get-Item -LiteralPath $outFull
if ($apkItem.Length -lt 1MB) {
    Fail "生成的 APK 异常小（$([math]::Round($apkItem.Length / 1MB, 2)) MB），导出很可能失败。日志: $logFile"
}
if ($exportCode -ne 0) {
    Write-Host "警告: Godot 返回退出码 $exportCode，但 APK 已生成，继续校验。" -ForegroundColor Yellow
}

# ---------- 4. 静态校验 ----------
$btRoot = Join-Path $AndroidSdk 'build-tools'
$btDir = $null
if (Test-Path -LiteralPath $btRoot) {
    $btDir = Get-ChildItem -LiteralPath $btRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending | Select-Object -First 1
}
$badgingOk = $false
# 原生工具（aapt2/apksigner）会把警告写到 stderr；PS 5.1 在 Stop 模式下会把它当终止错误，
# 因此校验段临时改用 Continue。
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
if (-not $SkipVerify -and $btDir) {
    $aapt2 = Join-Path $btDir.FullName 'aapt2.exe'
    $aapt = Join-Path $btDir.FullName 'aapt.exe'
    $apksigner = Join-Path $btDir.FullName 'apksigner.bat'
    $verifyDir = Join-Path $env:TEMP 'godot_apk_verify'
    New-Item -ItemType Directory -Path $verifyDir -Force | Out-Null
    $verifyApk = Join-Path $verifyDir 'verify.apk'
    Copy-Item -LiteralPath $outFull -Destination $verifyApk -Force

    $badging = $null
    if (Test-Path -LiteralPath $aapt2) {
        StepLog "aapt2 dump badging"
        $badging = & $aapt2 dump badging $verifyApk 2>&1
    }
    if (-not $badging -and (Test-Path -LiteralPath $aapt)) {
        StepLog "aapt dump badging"
        $badging = & $aapt dump badging $verifyApk 2>&1
    }
    if ($badging) {
        $badging | Out-File -LiteralPath (Join-Path $outDir 'apk-badging.txt') -Encoding utf8
        Write-Host "---- badging 关键字段 ----" -ForegroundColor Cyan
        $badging | Where-Object {
            $_ -match '^(package:|sdkVersion:|minSdkVersion:|targetSdkVersion:|native-code:|launchable-activity:|application:)'
        } | Where-Object { $_ -notmatch '^application-label|^application-icon' } | ForEach-Object { Write-Host "  $_" }
        if ($badging -match 'package: name=') { $badgingOk = $true }
        if ($badging -match 'screen.landscape') { Write-Host "  orientation: landscape" }
    }
    if (-not $badgingOk) { Write-Host "警告: 未能解析出 package 信息。" -ForegroundColor Yellow }

    if (Test-Path -LiteralPath $apksigner) {
        StepLog "apksigner verify"
        $verify = & $apksigner verify --verbose $outFull 2>&1
        $verify | Write-Host
        $verify | Out-File -LiteralPath (Join-Path $outDir 'apk-signature.txt') -Encoding utf8
        if ($LASTEXITCODE -ne 0) {
            Fail "APK 签名校验失败（apksigner 退出码 $LASTEXITCODE）。"
        }
    } else {
        Write-Host "跳过签名校验: 未找到 $apksigner" -ForegroundColor Yellow
    }
} else {
    Write-Host "跳过静态校验（-SkipVerify 或未找到 build-tools）。" -ForegroundColor Yellow
}
$ErrorActionPreference = $prevEAP

# ---------- 5. 别名副本 ----------
$aliasPath = Join-Path $outDir 'zhuzhu-fate.apk'
if (-not $SkipAlias) {
    Copy-Item -LiteralPath $outFull -Destination $aliasPath -Force
    Write-Host "别名副本: $aliasPath"
}

# ---------- 6. 结果 ----------
$hash = (Get-FileHash -LiteralPath $outFull -Algorithm SHA256).Hash
$sizeMB = [math]::Round($apkItem.Length / 1MB, 2)
Write-Host ""
Write-Host "================ BUILD OK ================" -ForegroundColor Green
Write-Host "APK : $outFull"
Write-Host "大小: $sizeMB MB ($($apkItem.Length) bytes)"
Write-Host "SHA256: $hash"
Write-Host "日志: $logFile"
Write-Host "==========================================" -ForegroundColor Green
exit 0
