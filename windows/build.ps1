#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Build, test and package the Windows port.

.DESCRIPTION
    Commands:

      build       Build the whole solution. Works off Windows too, but a green
                  build there says nothing about whether the app runs.
      test        Run every test project. Windows only.
      core-test   Run Codenotch.Core.Tests. Runs anywhere, including the Linux
                  sessions most of this code is written in, and is the check
                  that must be green before any session ends (rule C2).
      guard-test  Prove the core purity guard still refuses what it is supposed
                  to refuse. Runs anywhere.
      run         Build and start the app. Windows only.
      clean       Delete build output.
      pack        Publish the app for a runtime identifier.

.EXAMPLE
    .\build.ps1 core-test
.EXAMPLE
    .\build.ps1 run
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('build', 'test', 'core-test', 'guard-test', 'run', 'clean', 'pack')]
    [string] $Command = 'build',

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Debug',

    [ValidateSet('win-x64', 'win-arm64')]
    [string] $Runtime = 'win-x64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$solution = Join-Path $root 'Codenotch.sln'
$coreTests = Join-Path $root 'tests/Codenotch.Core.Tests/Codenotch.Core.Tests.csproj'
$platformTests = Join-Path $root 'tests/Codenotch.Platform.Tests/Codenotch.Platform.Tests.csproj'
$app = Join-Path $root 'src/Codenotch.App/Codenotch.App.csproj'
$probe = Join-Path $root 'tools/CorePurityProbe/CorePurityProbe.csproj'

# $IsWindows exists on PowerShell 6+; on Windows PowerShell 5.1 it does not.
$onWindows = if (Test-Path 'variable:IsWindows') { $IsWindows } else { $true }

function Invoke-Dotnet {
    param([string[]] $Arguments)

    Write-Host "> dotnet $($Arguments -join ' ')" -ForegroundColor DarkGray
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Assert-Windows {
    param([string] $What)

    if (-not $onWindows) {
        throw "$What needs Windows. Off Windows, 'build', 'core-test' and 'guard-test' are the commands that mean anything."
    }
}

# Builds the probe with one deliberate violation and reports whether the build
# was refused. See tools/CorePurityProbe.
function Test-PurityVector {
    param(
        [string] $Vector,
        [string] $ExpectedPattern,
        [bool] $ShouldBuild
    )

    $output = & dotnet build $probe -p:PurityVector=$Vector -v q --nologo 2>&1 | Out-String
    $built = $LASTEXITCODE -eq 0

    if ($ShouldBuild) {
        if (-not $built) {
            Write-Host "  FAIL  $Vector — the guard rejected a clean project:" -ForegroundColor Red
            Write-Host $output
            return $false
        }
        Write-Host "  ok    $Vector — clean project still builds" -ForegroundColor Green
        return $true
    }

    if ($built) {
        Write-Host "  FAIL  $Vector — the build succeeded. The guard is not firing." -ForegroundColor Red
        return $false
    }

    if ($output -notmatch $ExpectedPattern) {
        Write-Host "  FAIL  $Vector — refused, but not by $ExpectedPattern :" -ForegroundColor Red
        Write-Host $output
        return $false
    }

    $matched = [regex]::Match($output, $ExpectedPattern).Value
    Write-Host "  ok    $Vector — refused by $matched" -ForegroundColor Green
    return $true
}

try {

switch ($Command) {

    'build' {
        if (-not $onWindows) {
            # The .NET 10 SDK will compile the WPF project off Windows, which is
            # useful for catching C# mistakes early — but it is not a supported
            # configuration and it proves nothing about the running app (rule C1).
            Write-Host 'Not on Windows: this compiles, but nothing here can be run or looked at.' -ForegroundColor Yellow
        }
        Invoke-Dotnet @('build', $solution, '-c', $Configuration)
    }

    'test' {
        Assert-Windows 'Running the full test suite'
        Invoke-Dotnet @('test', '--project', $coreTests, '-c', $Configuration)
        Invoke-Dotnet @('test', '--project', $platformTests, '-c', $Configuration)
    }

    'core-test' {
        Invoke-Dotnet @('test', '--project', $coreTests, '-c', $Configuration)
    }

    'guard-test' {
        Write-Host 'Core purity guard — each vector must be refused, the control must not.'

        # 'Wpf' and 'Project' are refused by the SDK before the guard is reached
        # (NETSDK1136, NU1201). That is a correct outcome, and the expectation
        # below says so rather than pretending CODENOTCH0002 caught them.
        $results = @(
            (Test-PurityVector -Vector 'None'      -ExpectedPattern ''                        -ShouldBuild $true),
            (Test-PurityVector -Vector 'Platform'  -ExpectedPattern 'CODENOTCH0001'           -ShouldBuild $false),
            (Test-PurityVector -Vector 'Wpf'       -ExpectedPattern 'CODENOTCH0002|NETSDK1136' -ShouldBuild $false),
            (Test-PurityVector -Vector 'Framework' -ExpectedPattern 'CODENOTCH0003'           -ShouldBuild $false),
            (Test-PurityVector -Vector 'Package'   -ExpectedPattern 'CODENOTCH0004'           -ShouldBuild $false),
            (Test-PurityVector -Vector 'Project'   -ExpectedPattern 'CODENOTCH0004|NU1201'    -ShouldBuild $false)
        )

        if ($results -contains $false) {
            throw 'The core purity guard did not behave as specified. See above.'
        }
        Write-Host 'Core purity guard: all vectors refused, control unaffected.' -ForegroundColor Green
    }

    'run' {
        Assert-Windows 'Running the app'
        Invoke-Dotnet @('run', '--project', $app, '-c', $Configuration)
    }

    'clean' {
        Get-ChildItem -Path $root -Include 'bin', 'obj', 'publish' -Recurse -Directory |
            ForEach-Object {
                Write-Host "  removing $($_.FullName)" -ForegroundColor DarkGray
                Remove-Item $_.FullName -Recurse -Force
            }
    }

    'pack' {
        Assert-Windows 'Publishing the app'

        $out = Join-Path $root "publish/$Runtime"
        Invoke-Dotnet @('publish', $app, '-c', 'Release', '-r', $Runtime, '--self-contained', 'false', '-o', $out)

        Write-Host "Published to $out." -ForegroundColor Green
        Write-Host 'This is a plain publish. Single-file, ReadyToRun and the Velopack installer are M9.'
    }
}

}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
