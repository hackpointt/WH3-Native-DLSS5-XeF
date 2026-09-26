$ErrorActionPreference = 'Stop'
$baseCommit = '20d9d147a4334a49a99d67d235ad7915e0d6d846'

function Assert-Success([string] $step) {
    if ($LASTEXITCODE -ne 0) { throw "$step failed with exit code $LASTEXITCODE" }
}

git clone https://github.com/optiscaler/OptiScaler.git optiscaler-src
Assert-Success 'git clone'
Push-Location optiscaler-src
try {
    git checkout $baseCommit
    Assert-Success 'git checkout'
    git submodule update --init --recursive
    Assert-Success 'git submodule update'

    git apply --check ..\experiments\mfg\wh3-dlss5-xefg-dlssg-mfg.patch
    Assert-Success 'git apply --check'
    git apply ..\experiments\mfg\wh3-dlss5-xefg-dlssg-mfg.patch
    Assert-Success 'git apply'
    git diff --check
    Assert-Success 'git diff --check'

    msbuild /m /p:Configuration=Release . /verbosity:minimal
    Assert-Success 'MSBuild'
} finally {
    Pop-Location
}

$dll = 'optiscaler-src\x64\Release\a\OptiScaler.dll'
if (-not (Test-Path $dll)) { throw 'Compiled OptiScaler.dll missing' }
$ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($dll))
foreach ($marker in @(
    'WH3 native DLSS passthrough:',
    'WH3 native DLSS bridge: private shadow active',
    'WH3 XeFG compatibility:',
    'WH3 DLSSG compatibility:',
    'WH3 DLSSG two-stage:'
)) {
    if (-not $ascii.Contains($marker)) { throw "Missing compiled marker: $marker" }
}

New-Item -ItemType Directory -Force package | Out-Null
Copy-Item -Recurse -Force 'optiscaler-src\x64\Release\a\*' package\
Copy-Item -Force 'experiments\mfg\wh3-dlss5-xefg-dlssg-mfg.patch' package\
@"
Experimental WH3 DLSS-G two-stage swapchain candidate
OptiScaler base: $baseCommit
The DLSS-G swapchain creation fix previously compiled and created a swapchain,
but DLSS5 Feed failed during native DLSS CreateFeature while DLSS-G was active.
This revision starts with a plain DX12 presenter and defers OptiScaler's
Streamline load until native DLSS evaluates successfully. It then waits for
the queues and recreates the presenter as a Streamline DLSS-G swapchain.
If that fails, it attempts to restore plain DX12.
No 3D game test has been performed for this revision.
Preserve the existing stable DLSS5 + XeFG baseline when testing.
"@ | Set-Content -Encoding UTF8 package\README-MFG-EXPERIMENT.txt
