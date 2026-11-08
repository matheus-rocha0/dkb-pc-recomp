<#
.SYNOPSIS
    Pipeline de build local do DKB PC Recomp usando o toolchain portátil do DKB-Setup.
.DESCRIPTION
    Orquestra o lifter (recomp/gen.py) e o compilador (tools/build_game.py) sem depender de MSYS2.
    Reaproveita o código C gerado em -GenCache entre builds para permitir rebuilds rápidos de runtime/.
.PARAMETER Src
    Diretório raiz do código-fonte ou worktree (padrão: raiz deste repositório).
.PARAMETER Out
    Diretório de saída da compilação (padrão: C:\Users\Matheus_\dev\dkb-build\baseline).
.PARAMETER GenCache
    Diretório de cache do código C gerado (padrão: C:\Users\Matheus_\dev\dkb-build\gen_cache).
.PARAMETER SetupDir
    Caminho da pasta do DKB-Setup contendo o toolchain portátil.
.PARAMETER GameDump
    Caminho da pasta game_dump contendo ExeFS e RomFS descompactados.
.PARAMETER Jobs
    Número de workers paralelos para geração e compilação (padrão: número de threads do processador).
.PARAMETER ForceLift
    Força a re-execução do lifter (recomp/gen.py), mesmo se o cache estiver válido.
.PARAMETER FullBuild
    Força recompilação completa de todos os objetos no build_game.py.
#>
[CmdletBinding()]
param(
    [string]$Src = "",
    [string]$Out = "C:\Users\Matheus_\dev\dkb-build\baseline",
    [string]$GenCache = "C:\Users\Matheus_\dev\dkb-build\gen_cache",
    [string]$SetupDir = "C:\Users\Matheus_\OpenBot\Agents\agent-db4e3750-7de8-40c0-bbb8-3edd489aec8f\DKB-Recomp\DKB-Setup",
    [string]$GameDump = "C:\Users\Matheus_\OpenBot\Agents\agent-db4e3750-7de8-40c0-bbb8-3edd489aec8f\DKB-Recomp\game_dump",
    [int]$Jobs = [System.Environment]::ProcessorCount,
    [switch]$ForceLift,
    [switch]$FullBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Src)) {
    $Src = (Resolve-Path "$PSScriptRoot\..").Path
}

$tGlobalStart = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  DKB Recomp — Local Build Pipeline (Forja)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Fonte (Src)      : $Src"
Write-Host "  Saída (Out)      : $Out"
Write-Host "  Cache Gen        : $GenCache"
Write-Host "  Toolchain Setup  : $SetupDir"
Write-Host "  Game Dump        : $GameDump"
Write-Host "  Jobs Paralelos   : $Jobs"
Write-Host "----------------------------------------------------------"

# 1. Validação de Ferramentas e Diretórios
$Python   = Join-Path $SetupDir "python\python.exe"
$LlvmDir  = Join-Path $SetupDir "llvm"
$Clang    = Join-Path $LlvmDir "bin\clang.exe"
$Ninja    = Join-Path $SetupDir "bin\ninja.exe"
$DepsDir  = Join-Path $SetupDir "runtime\deps"
$ExeFSDir = Join-Path $GameDump "ExeFS"
$RomFSDir = Join-Path $GameDump "RomFS"

$expectedPaths = @{
    "Python portátil" = $Python
    "Clang portátil"  = $Clang
    "Ninja portátil"  = $Ninja
    "Deps portátil"   = $DepsDir
    "ExeFS do Dump"   = $ExeFSDir
    "RomFS do Dump"   = $RomFSDir
    "Gen script"      = (Join-Path $Src "recomp\gen.py")
    "Build script"    = (Join-Path $Src "tools\build_game.py")
}

foreach ($item in $expectedPaths.GetEnumerator()) {
    if (-not (Test-Path $item.Value)) {
        throw "Erro: caminho crítico não encontrado [$($item.Key)]: $($item.Value)"
    }
}

# Configura PATH do processo para priorizar LLVM e binários portáteis
$env:PATH = "$(Join-Path $LlvmDir 'bin');$(Join-Path $SetupDir 'bin');$env:PATH"

# Criação de diretórios necessários
if (-not (Test-Path $Out)) {
    New-Item -Path $Out -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $GenCache)) {
    New-Item -Path $GenCache -ItemType Directory -Force | Out-Null
}

# 2. Verificação de Cache do Lifter (recomp/gen.py)
$layoutJson    = Join-Path $GenCache "layout.json"
$patchesH      = Join-Path $GenCache "patches.h"
$mainManifest  = Join-Path $GenCache "main\manifest.json"
$sdkManifest   = Join-Path $GenCache "sdk\manifest.json"
$patchesTxt    = Join-Path $Src "recomp\patches-dkb100.txt"

$hasCache = (Test-Path $layoutJson) -and (Test-Path $patchesH) -and 
            (Test-Path $mainManifest) -and (Test-Path $sdkManifest)

if ($hasCache -and (-not $ForceLift)) {
    if (Test-Path $patchesTxt) {
        $patchesMtime = (Get-Item $patchesTxt).LastWriteTimeUtc
        $headerMtime  = (Get-Item $patchesH).LastWriteTimeUtc
        if ($patchesMtime -gt $headerMtime) {
            Write-Host "[Forja] patches-dkb100.txt é mais recente que patches.h do cache. Forçando relift..." -ForegroundColor Yellow
            $hasCache = $false
        }
    }
}

if ($hasCache -and (-not $ForceLift)) {
    Write-Host "[Forja: 1/2] Reutilizando código C gerado em cache ($GenCache)" -ForegroundColor Green
} else {
    Write-Host "[Forja: 1/2] Executando lifter (recomp/gen.py)..." -ForegroundColor Yellow
    $tLift = [System.Diagnostics.Stopwatch]::StartNew()

    $genArgs = @(
        (Join-Path $Src "recomp\gen.py"),
        "--exefs", $ExeFSDir,
        "--out", $GenCache,
        "--modules", "main,sdk",
        "--jobs", $Jobs,
        "--patches", $patchesTxt
    )

    & $Python @genArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Erro no lifter (recomp/gen.py): exit code $LASTEXITCODE"
    }
    $tLift.Stop()
    Write-Host ("[Forja: 1/2] Lifter concluído em {0:N1} s." -f $tLift.Elapsed.TotalSeconds) -ForegroundColor Green
}

# 3. Compilação e Linkagem (tools/build_game.py)
Write-Host "[Forja: 2/2] Compilando e linkando (tools/build_game.py)..." -ForegroundColor Yellow
$tBuild = [System.Diagnostics.Stopwatch]::StartNew()

$expectedJson = Join-Path $Src "tools\data\expected-dkb100.json"
$profileDir   = Join-Path $Out "profile"
if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

$buildArgs = @(
    (Join-Path $Src "tools\build_game.py"),
    "--version", "dkb100",
    "--expected", $expectedJson,
    "--gen", $GenCache,
    "--out", $Out,
    "--modules", "main,sdk",
    "--exefs", $ExeFSDir,
    "--romfs", $RomFSDir,
    "--profile", $profileDir,
    "--runtime", (Join-Path $Src "runtime"),
    "--toolchain", $LlvmDir,
    "--deps", $DepsDir,
    "--ninja", $Ninja,
    "--jobs", $Jobs
)

if ($FullBuild) {
    $buildArgs += "--full-build"
}

& $Python @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Erro na compilação/link (tools/build_game.py): exit code $LASTEXITCODE"
}
$tBuild.Stop()
Write-Host ("[Forja: 2/2] Compilação/link concluídos em {0:N1} s." -f $tBuild.Elapsed.TotalSeconds) -ForegroundColor Green

# 4. Cópia de Dependências de Execução para $Out
Write-Host "[Forja] Sincronizando DLLs e utilitários auxiliares..." -ForegroundColor Gray
$runtimeBinFiles = @(
    (Join-Path $SetupDir "bin\SDL3.dll"),
    (Join-Path $SetupDir "bin\libopus-0.dll"),
    (Join-Path $SetupDir "bin\totk_xlate.exe"),
    (Join-Path $SetupDir "bin\totk_xlate.id")
)

foreach ($f in $runtimeBinFiles) {
    if (Test-Path $f) {
        $destFile = Join-Path $Out (Split-Path $f -Leaf)
        if ((-not (Test-Path $destFile)) -or ((Get-Item $f).Length -ne (Get-Item $destFile).Length)) {
            Copy-Item -Path $f -Destination $destFile -Force
        }
    }
}

$tGlobalStart.Stop()
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ("[Forja] Build concluído com sucesso em {0:N1} s!" -f $tGlobalStart.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan

# 5. Verificação do Binário Gerado
$targetExe = Join-Path $Out "dkb.exe"
if (Test-Path $targetExe) {
    $fileInfo = Get-Item $targetExe
    $hashInfo = Get-FileHash $targetExe -Algorithm SHA256
    Write-Host "Binário gerado  : $targetExe"
    Write-Host "Tamanho         : $($fileInfo.Length) bytes ($([Math]::Round($fileInfo.Length / 1MB, 2)) MB)"
    Write-Host "SHA256          : $($hashInfo.Hash)"

    $installedExe = "C:\Users\Matheus_\OpenBot\Agents\agent-db4e3750-7de8-40c0-bbb8-3edd489aec8f\DKB-Recomp\installed_game\dkb.exe"
    if (Test-Path $installedExe) {
        $instInfo = Get-Item $installedExe
        Write-Host "Instalado (ref) : $($instInfo.Length) bytes"
        $diff = $fileInfo.Length - $instInfo.Length
        Write-Host "Diferença tam   : $diff bytes"
    }
} else {
    throw "Erro: dkb.exe não foi gerado em $Out!"
}
