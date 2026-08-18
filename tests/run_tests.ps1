# 跑 tests/ 下所有 *_test.tscn（headless）。全过退出码 0，有失败非 0。
#
#   powershell -File tests\run_tests.ps1
#   powershell -File tests\run_tests.ps1 -Godot "D:\Apps\Godot_v4.8\godot_console.exe"
#   powershell -File tests\run_tests.ps1 -Only bgm
#
# headless 用的是 dummy 渲染器，theme/cartoon_backgram.gdshader 会刷
# "custom_samplers" 报错——真机 D3D12 跑不会出现，所以这里直接滤掉。

param(
    [string]$Godot = "D:\Apps\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Only = ""
)

# 不要设 $ErrorActionPreference = "Stop"：Godot 往 stderr 写东西时 PowerShell 5.1
# 会造一个 NativeCommandError，Stop 之下它是终止错误，整个脚本当场断掉。
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Godot)) {
    Write-Error "找不到 Godot：$Godot（用 -Godot 指一个）"
    exit 2
}

$scenes = Get-ChildItem -Path $PSScriptRoot -Filter "*_test.tscn" | Sort-Object Name
if ($Only) {
    $scenes = $scenes | Where-Object { $_.BaseName -like "*$Only*" }
}
if (-not $scenes) {
    Write-Error "tests\ 下没有匹配的 *_test.tscn"
    exit 2
}

# headless 下 dummy 渲染器刷的噪音，真机跑不会出现。
$noise = 'custom_samplers|_dump_node_code|GDScript backtrace|^\s+\[\d+\]\s|^\s+at:\s|^Godot Engine v'
$failed = 0
foreach ($scene in $scenes) {
    & $Godot --headless --path $projectRoot "res://tests/$($scene.Name)" 2>&1 |
        Where-Object { $_ -notmatch $noise }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $failed++
        Write-Host "!! $($scene.BaseName) 失败（退出码 $code）" -ForegroundColor Red
    }
}

if ($failed -gt 0) {
    Write-Host "$failed 个测试场景失败。" -ForegroundColor Red
    exit 1
}
Write-Host "全部测试场景通过。" -ForegroundColor Green
exit 0
