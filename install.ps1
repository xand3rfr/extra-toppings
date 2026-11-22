param(
    [ValidateSet("pizzeria", "freezeria", "mocharia")]
    [string]$Game = "pizzeria",
    [string]$SteamCommon = "C:\Program Files (x86)\Steam\steamapps\common",
    [string]$FFDec = "C:\Program Files (x86)\FFDec\ffdec-cli.exe",
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"

$games = @{
    pizzeria  = @{ Folder = "Papa's Pizzeria Deluxe";  Pkg = "pizzaGame" }
    freezeria = @{ Folder = "Papa's Freezeria Deluxe"; Pkg = "iceGame" }
    mocharia  = @{ Folder = "Papa's Mocharia Deluxe";  Pkg = "mochaGame" }
}
$g = $games[$Game]
$gameDir = Join-Path $SteamCommon $g.Folder
$main = Join-Path $gameDir "Data\assets\Main.assets"
$backup = "$main.original"

if (-not (Test-Path $main)) { throw "Game not found: $main" }

if ($Uninstall) {
    if (-not (Test-Path $backup)) { throw "No backup at $backup - nothing to restore." }
    Copy-Item $backup $main -Force
    Write-Host "Restored original Main.assets. Your mods folder was left in place."
    return
}

if (-not (Test-Path $backup)) {
    Copy-Item $main $backup
    Write-Host "Backed up original to $backup"
}

if (-not (Test-Path $FFDec)) { throw "FFDec not found at $FFDec. Install it from https://github.com/jindrapetrik/jpexs-decompiler/releases or pass -FFDec <path>." }

# Decompile only the two classes we hook, from the user's own copy of the game.
$extract = Join-Path $PSScriptRoot "build\$Game\original"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
$ErrorActionPreference = "Continue"
& $FFDec -selectclass "$($g.Pkg).utils.DataHelper,$($g.Pkg).managers.CustomerManager" -export script $extract $backup 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
$src = Join-Path $extract "scripts\$($g.Pkg)"
if (-not (Test-Path "$src\utils\DataHelper.as")) { throw "Could not decompile game classes from $backup." }

$stage = Join-Path $PSScriptRoot "build\$Game\scripts"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force "$stage\$($g.Pkg)\utils", "$stage\$($g.Pkg)\managers" | Out-Null
function Add-Hook($rel, $pattern, $replacement, $import = $null, $append = "") {
    $staged = Join-Path "$stage\$($g.Pkg)" $rel
    $text = Get-Content $(if (Test-Path $staged) { $staged } else { Join-Path $src $rel }) -Raw
    if ($import) { $text = $text -replace '(package [\w.]+\s*\{)', "`$1`r`n   import $import;" }
    # FFDec's compiler rejects .init() on Object-typed vars that the decompiler emits.
    $text = $text -replace 'var useContent:Object', 'var useContent:*'
    $patched = [regex]::Replace($text, $pattern, $replacement, "Singleline")
    if ($patched -eq $text) { throw "Hook point not found in $rel - game version may differ." }
    Set-Content $staged ($patched + $append) -NoNewline -Encoding UTF8
}

# FFDec's -importScript can only replace existing classes, so ModLoader rides along as a
# file-private class inside DataHelper.as; other hooks reach it through DataHelper.mod().
$loader = Get-Content (Join-Path $PSScriptRoot "src\flipline\mods\ModLoader.as") -Raw
$loader = $loader -replace '^\s*package flipline\.mods\s*\{', '' -replace '\}\s*$', '' -replace 'public class ModLoader', 'class ModLoader'
$bridge = "public static function mod(event:String, target:Object) : void`r`n      {`r`n         ModLoader.emit(event,target);`r`n      }`r`n"

# All game data objects exist by the time loadData runs (end of GameModule.initGame).
Add-Hook "utils\DataHelper.as" '(public function loadData\([^)]*\) : void\s*\{)' "`$1`r`n         ModLoader.init(this.gameObj);" -append "`r`n$loader"
Add-Hook "utils\DataHelper.as" '(public function DataHelper\()' "$bridge`r`n      `$1"
# CustomerManager builds its lineup in the same call it's created, so it needs a synchronous hook.
Add-Hook "managers\CustomerManager.as" '(public function setupManager\(\) : void\s*\{.*?)(\r?\n      \})' "`$1`r`n         DataHelper.mod(`"customerManager`",this);`$2" -import "$($g.Pkg).utils.DataHelper"

$out = Join-Path $PSScriptRoot "build\$Game\Main.assets"
if (Test-Path $out) { Remove-Item $out }
$ErrorActionPreference = "Continue"
$log = & $FFDec -air -importScript $backup $out $stage 2>&1 | Out-String
$ErrorActionPreference = "Stop"
$log | Set-Content (Join-Path $PSScriptRoot "build\$Game\ffdec.log")
if ($log -match "(?i)error|exception") { Write-Host $log }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { throw "FFDec compile failed." }

$check = Join-Path $PSScriptRoot "build\$Game\verify"
if (Test-Path $check) { Remove-Item $check -Recurse -Force }
$ErrorActionPreference = "Continue"
& $FFDec -selectclass "$($g.Pkg).utils.DataHelper,$($g.Pkg).managers.CustomerManager" -export script $check $out 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
$dh = Get-Content "$check\scripts\$($g.Pkg)\utils\DataHelper.as" -Raw -ErrorAction SilentlyContinue
$cm = Get-Content "$check\scripts\$($g.Pkg)\managers\CustomerManager.as" -Raw -ErrorAction SilentlyContinue
if ($dh -notmatch "class ModLoader" -or $dh -notmatch "ModLoader\.init" -or $cm -notmatch "DataHelper\.mod\(") {
    throw "Built SWF is missing the loader or hooks - not installing."
}

Copy-Item $out $main -Force
$modsDir = Join-Path $gameDir "mods"
New-Item -ItemType Directory -Force $modsDir | Out-Null
Write-Host "Extra Toppings installed into $($g.Folder). Put mods in: $modsDir"
