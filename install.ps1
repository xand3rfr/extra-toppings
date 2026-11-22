param(
    [ValidateSet("pizzeria", "freezeria", "mocharia")]
    [string[]]$Game,
    [switch]$Uninstall,
    [string]$FFDec,
    [switch]$NoPause,
    [string]$BuildFrom,
    [string]$BuildTo,
    [ValidateSet("desktop", "web")]
    [string]$Platform = "desktop"
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Games = [ordered]@{
    pizzeria  = @{ Name = "Papa's Pizzeria Deluxe";  Pkg = "pizzaGame"; Supported = $true }
    freezeria = @{ Name = "Papa's Freezeria Deluxe"; Pkg = "iceGame";   Supported = $false }
    mocharia  = @{ Name = "Papa's Mocharia Deluxe";  Pkg = "mochaGame"; Supported = $false }
}
$Home_ = Join-Path $env:LOCALAPPDATA "ExtraToppings"
New-Item -ItemType Directory -Force $Home_ | Out-Null

function Say($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }
function Step($text) { Write-Host "  > $text" -ForegroundColor Cyan }
function Done { if (-not $NoPause -and $Host.Name -eq "ConsoleHost") { Read-Host "`nPress Enter to close" | Out-Null } }

function Get-SteamLibraries {
    $roots = @()
    foreach ($key in "HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam") {
        $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($p.SteamPath) { $roots += $p.SteamPath }
        if ($p.InstallPath) { $roots += $p.InstallPath }
    }
    $roots += "${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam"
    $libs = @()
    foreach ($root in $roots | Select-Object -Unique) {
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $libs += Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
        }
        $libs += $root
    }
    $libs | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique
}

function Find-Games {
    $found = [ordered]@{}
    foreach ($lib in Get-SteamLibraries) {
        foreach ($id in $Games.Keys) {
            $dir = Join-Path $lib "steamapps\common\$($Games[$id].Name)"
            if (-not $found.Contains($id) -and (Test-Path (Join-Path $dir "Data\assets\Main.assets"))) { $found[$id] = $dir }
        }
    }
    $found
}

function Get-Download($url, $dest) {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -Headers @{ "User-Agent" = "ExtraToppings-Installer" }
}

function Get-Java {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME "bin\java.exe" }
    $onPath = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $candidates += Get-ChildItem (Join-Path $Home_ "jre") -Recurse -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }

    Step "Downloading Java (one time, about 45 MB)..."
    $zip = Join-Path $Home_ "jre.zip"
    Get-Download "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jre/hotspot/normal/eclipse" $zip
    Expand-Archive $zip (Join-Path $Home_ "jre") -Force
    Remove-Item $zip
    $java = Get-ChildItem (Join-Path $Home_ "jre") -Recurse -Filter java.exe | Select-Object -First 1 -ExpandProperty FullName
    if (-not $java) { throw "Java download failed." }
    $java
}

function Get-FFDecJar {
    $dirs = @()
    if ($FFDec) { $dirs += Split-Path $FFDec }
    $dirs += "${env:ProgramFiles(x86)}\FFDec", "$env:ProgramFiles\FFDec", (Join-Path $Home_ "ffdec")
    foreach ($d in $dirs) {
        foreach ($jar in "ffdec-cli.jar", "ffdec.jar") {
            $p = Join-Path $d $jar
            if (Test-Path $p) { return $p }
        }
    }
    Step "Downloading FFDec (one time, about 23 MB)..."
    $release = Invoke-RestMethod "https://api.github.com/repos/jindrapetrik/jpexs-decompiler/releases/latest" -Headers @{ "User-Agent" = "ExtraToppings-Installer" }
    $asset = $release.assets | Where-Object { $_.name -match '^ffdec_[\d.]+\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw "Couldn't find an FFDec download." }
    $zip = Join-Path $Home_ "ffdec.zip"
    Get-Download $asset.browser_download_url $zip
    Expand-Archive $zip (Join-Path $Home_ "ffdec") -Force
    Remove-Item $zip
    foreach ($jar in "ffdec-cli.jar", "ffdec.jar") {
        $p = Join-Path $Home_ "ffdec\$jar"
        if (Test-Path $p) { return $p }
    }
    throw "FFDec download failed."
}

function Invoke-FFDec([string[]]$FFArgs) {
    $ErrorActionPreference = "Continue"
    $out = & $script:Java -jar $script:Jar @FFArgs 2>&1 | Out-String
    $ErrorActionPreference = "Stop"
    $out
}

function Wait-GameClosed($dir) {
    $running = { Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, "OrdinalIgnoreCase") } }
    if (& $running) {
        Say "  The game is running. Close it and the installer will continue..." Yellow
        while (& $running) { Start-Sleep -Seconds 1 }
    }
}

$hash = { param($f) (Get-FileHash $f -Algorithm SHA256).Hash }

function Uninstall-Game($id, $dir) {
    $main = Join-Path $dir "Data\assets\Main.assets"
    $backup = "$main.original"
    if (-not (Test-Path $backup)) { Say "  $($Games[$id].Name): not installed, nothing to do." DarkGray; return }
    Wait-GameClosed $dir
    Copy-Item $backup $main -Force
    Remove-Item $backup, "$main.extratoppings" -ErrorAction SilentlyContinue
    Say "  $($Games[$id].Name): original game restored. Your mods folder was left in place." Green
}

function Install-Game($id, $dir) {
    $g = $Games[$id]
    Say "`n$($g.Name)" White
    Wait-GameClosed $dir
    $main = Join-Path $dir "Data\assets\Main.assets"
    $backup = "$main.original"
    $marker = "$main.extratoppings"

    if ((Test-Path $backup) -and (Test-Path $marker)) {
        $now = & $hash $main
        if ($now -ne (Get-Content $marker -Raw).Trim() -and $now -ne (& $hash $backup)) {
            Step "Steam updated the game. Using the new version as the backup."
            Copy-Item $main $backup -Force
        }
    }
    if (-not (Test-Path $backup)) {
        Step "Backing up the original game file..."
        Copy-Item $main $backup
    }

    $out = Build-Modded $id $backup "desktop"
    Copy-Item $out $main -Force
    & $hash $main | Set-Content $marker

    $mods = Join-Path $dir "mods"
    New-Item -ItemType Directory -Force $mods | Out-Null
    $examples = Join-Path $mods "_examples"
    if (-not (Test-Path $examples)) {
        Copy-Item (Join-Path $PSScriptRoot "mods") $examples -Recurse
        Set-Content (Join-Path $examples "README.txt") "These example mods are switched off. Move a folder out of _examples (into mods) to turn it on."
    }
    Say "  Installed! Mods folder: $mods" Green
    $script:InstalledMods += $mods
}

function Get-LoaderSource($platform) {
    $strip = { param($file) (Get-Content (Join-Path $PSScriptRoot "src\flipline\mods\$file") -Raw) -replace '^\s*\uFEFF?\s*package flipline\.mods\s*\{', '' -replace '\}\s*$', '' }
    $core = (& $strip "ModLoader.as") -replace 'public class ModLoader', 'class ModLoader'
    $plat = if ($platform -eq "web") { "WebPlatform" } else { "DesktopPlatform" }
    $core + "`r`n" + ((& $strip "$plat.as") -replace "public class $plat", 'class Platform')
}

function Build-Modded($id, $inputSwf, $platform) {
    $g = $Games[$id]
    $build = Join-Path $Home_ "build\$id-$platform"
    if (Test-Path $build) { Remove-Item $build -Recurse -Force }
    $extract = Join-Path $build "original"
    $stage = Join-Path $build "scripts"
    $classes = "$($g.Pkg).utils.DataHelper,$($g.Pkg).managers.CustomerManager"

    Step "Reading the game's code..."
    Invoke-FFDec @("-selectclass", $classes, "-export", "script", $extract, $inputSwf) | Out-Null
    $src = Join-Path $extract "scripts\$($g.Pkg)"
    if (-not (Test-Path "$src\utils\DataHelper.as")) { throw "Couldn't read the game's code." }

    Step "Adding the mod loader..."
    New-Item -ItemType Directory -Force "$stage\$($g.Pkg)\utils", "$stage\$($g.Pkg)\managers" | Out-Null
    function Add-Hook($rel, $pattern, $replacement, $import = $null, $append = "") {
        $staged = Join-Path "$stage\$($g.Pkg)" $rel
        $text = Get-Content $(if (Test-Path $staged) { $staged } else { Join-Path $src $rel }) -Raw
        if ($import) { $text = $text -replace '(package [\w.]+\s*\{)', "`$1`r`n   import $import;" }
        # FFDec's compiler rejects .init() on Object-typed vars that the decompiler emits.
        $text = $text -replace 'var useContent:Object', 'var useContent:*'
        $patched = [regex]::Replace($text, $pattern, $replacement, "Singleline")
        if ($patched -eq $text) { throw "Hook point not found in $rel. This game version isn't supported yet." }
        Set-Content $staged ($patched + $append) -NoNewline -Encoding UTF8
    }
    # FFDec's -importScript can only replace existing classes, so ModLoader rides along as a
    # file-private class inside DataHelper.as; other hooks reach it through DataHelper.mod().
    $loader = Get-LoaderSource $platform
    $bridge = "public static function mod(event:String, target:Object) : void`r`n      {`r`n         ModLoader.emit(event,target);`r`n      }`r`n"
    # All game data objects exist by the time loadData runs (end of GameModule.initGame).
    Add-Hook "utils\DataHelper.as" '(public function loadData\([^)]*\) : void\s*\{)' "`$1`r`n         ModLoader.init(this.gameObj);" -append "`r`n$loader"
    Add-Hook "utils\DataHelper.as" '(public function DataHelper\()' "$bridge`r`n      `$1"
    # CustomerManager builds its lineup in the same call it's created, so it needs a synchronous hook.
    Add-Hook "managers\CustomerManager.as" '(public function setupManager\(\) : void\s*\{.*?)(\r?\n      \})' "`$1`r`n         DataHelper.mod(`"customerManager`",this);`$2" -import "$($g.Pkg).utils.DataHelper"

    Step "Building the modded game (this takes a minute)..."
    $out = Join-Path $build "Main.assets"
    $log = Invoke-FFDec @("-air", "-importScript", $inputSwf, $out, $stage)
    $log | Set-Content (Join-Path $build "ffdec.log")
    if (-not (Test-Path $out)) { Say $log DarkGray; throw "Building failed. Details: $build\ffdec.log" }

    Step "Checking the build..."
    $check = Join-Path $build "verify"
    Invoke-FFDec @("-selectclass", $classes, "-export", "script", $check, $out) | Out-Null
    $dh = Get-Content "$check\scripts\$($g.Pkg)\utils\DataHelper.as" -Raw -ErrorAction SilentlyContinue
    $cm = Get-Content "$check\scripts\$($g.Pkg)\managers\CustomerManager.as" -Raw -ErrorAction SilentlyContinue
    if ($dh -notmatch "class ModLoader" -or $dh -notmatch "ModLoader\.init" -or $cm -notmatch "DataHelper\.mod\(") {
        throw "The build is missing the loader, so nothing was installed."
    }
    $out
}

Say "`n  EXTRA TOPPINGS  |  mod loader for Papa's Deluxe games`n" Magenta
try {
    if ($BuildFrom) {
        if (-not $BuildTo) { throw "-BuildFrom needs -BuildTo." }
        $script:Java = Get-Java
        $script:Jar = Get-FFDecJar
        $id = if ($Game) { $Game[0] } else { "pizzeria" }
        Copy-Item (Build-Modded $id (Resolve-Path $BuildFrom).Path $Platform) $BuildTo -Force
        Say "Built $Platform version: $BuildTo" Green
        exit 0
    }
    $found = Find-Games
    if (-not $found.Count) { throw "Couldn't find any Papa's Deluxe games in your Steam libraries. Install one from Steam first." }

    $targets = if ($Game) { $Game } else { $found.Keys | Where-Object { $Games[$_].Supported -or $Uninstall } }
    $targets = @($targets | Where-Object { $found.Contains($_) })
    foreach ($id in $found.Keys) {
        if (-not $Games[$id].Supported -and $targets -notcontains $id -and -not $Uninstall) {
            Say "  Found $($Games[$id].Name): not supported yet (experimental: install.ps1 -Game $id)" DarkGray
        }
    }
    if (-not $targets.Count) { throw "None of the games you have are supported yet. Papa's Pizzeria Deluxe works today." }

    if ($Uninstall) {
        foreach ($id in $targets) { Uninstall-Game $id $found[$id] }
    } else {
        Step "Checking tools..."
        $script:Java = Get-Java
        $script:Jar = Get-FFDecJar
        $script:InstalledMods = @()
        foreach ($id in $targets) { Install-Game $id $found[$id] }
        Say "`nAll done. Start the game from Steam as usual." Green
        if ($script:InstalledMods.Count -and -not $NoPause) { Start-Process explorer.exe $script:InstalledMods[0] }
    }
} catch {
    Say "`nSomething went wrong: $($_.Exception.Message)" Red
    Say "Nothing was changed if it failed before 'Installed!'. Run Uninstall to restore the original game anytime." DarkGray
    Done
    exit 1
}
Done
