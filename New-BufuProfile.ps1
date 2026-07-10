#requires -Version 7.4

<#
.SYNOPSIS
    Creates and installs the BuFuProfile modular PowerShell profile framework.

.DESCRIPTION
    New-BuFuProfile.ps1 creates a modular PowerShell profile framework beneath
    the user's PowerShell documents directory.

    Default framework location:

        C:\Users\<User>\Documents\PowerShell\BuFuProfile

    The script creates:

        config
        lib
        functions
        aliases
        modules
        integrations
        completions
        private
        themes
        hosts
        archive
        logs
        cache

    It also:

    - Backs up existing PowerShell profile files.
    - Replaces profile.ps1 with a lightweight framework bootstrap.
    - Replaces Microsoft.PowerShell_profile.ps1 with a host-specific bootstrap.
    - Creates a modular loader.
    - Creates starter configuration, functions, aliases, modules, and integrations.
    - Supports -WhatIf and -Confirm.
    - Supports repeatable/idempotent execution.

.PARAMETER FrameworkDirectoryName
    Name of the profile framework directory.

.PARAMETER PowerShellRoot
    Root PowerShell profile directory. Defaults to the parent directory of
    $PROFILE.CurrentUserAllHosts.

.PARAMETER Force
    Overwrites existing framework files.

    Existing PowerShell bootstrap profiles are backed up before replacement
    unless -SkipProfileUpdate is used.

.PARAMETER SkipProfileUpdate
    Creates the framework but does not modify PowerShell's standard profile files.

.PARAMETER SkipBackup
    Does not back up existing standard profile files before replacing them.

.PARAMETER IncludeExampleFiles
    Creates example completion and private configuration files.

.EXAMPLE
    .\New-BuFuProfile.ps1

.EXAMPLE
    .\New-BuFuProfile.ps1 -WhatIf

.EXAMPLE
    .\New-BuFuProfile.ps1 -Force

.EXAMPLE
    .\New-BuFuProfile.ps1 -FrameworkDirectoryName ProfileFramework

.EXAMPLE
    .\New-BuFuProfile.ps1 -SkipProfileUpdate

.NOTES
    Author: Nickolas E. Teuber
#>

[CmdletBinding(
    SupportsShouldProcess,
    ConfirmImpact = 'Medium'
)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[^\\/:*?"<>|]+$')]
    [string]$FrameworkDirectoryName = 'BuFuProfile',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PowerShellRoot = (
        Split-Path -Parent $PROFILE.CurrentUserAllHosts
    ),

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipProfileUpdate,

    [Parameter()]
    [switch]$SkipBackup,

    [Parameter()]
    [switch]$IncludeExampleFiles
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$frameworkRoot = Join-Path $PowerShellRoot $FrameworkDirectoryName
$archiveRoot   = Join-Path $frameworkRoot 'archive'
$timestamp     = Get-Date -Format 'yyyyMMdd_HHmmss'

$allHostsProfile = $PROFILE.CurrentUserAllHosts
$currentHostProfile = $PROFILE.CurrentUserCurrentHost

$directories = @(
    'config'
    'lib'
    'functions'
    'aliases'
    'modules'
    'integrations'
    'completions'
    'private'
    'themes'
    'hosts'
    'archive'
    'logs'
    'cache'
)

function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Info','Success','Warning','Skip','Error')]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $settings = switch ($Type) {
        'Info'    { @{ Prefix = '[INFO]'; Color = 'Cyan' } }
        'Success' { @{ Prefix = '[ OK ]'; Color = 'Green' } }
        'Warning' { @{ Prefix = '[WARN]'; Color = 'Yellow' } }
        'Skip'    { @{ Prefix = '[SKIP]'; Color = 'DarkGray' } }
        'Error'   { @{ Prefix = '[FAIL]'; Color = 'Red' } }
    }

    Write-Host "$($settings.Prefix) " -ForegroundColor $settings.Color -NoNewline
    Write-Host $Message
}

function New-DirectoryIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Write-Status -Type Skip -Message "Directory exists: $Path"
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Create directory')) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Status -Type Success -Message "Created directory: $Path"
    }
}

function Backup-ProfileFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$DestinationDirectory
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        New-DirectoryIfMissing -Path $DestinationDirectory
    }

    $leafName = Split-Path -Leaf $Path
    $baseName = [IO.Path]::GetFileNameWithoutExtension($leafName)
    $extension = [IO.Path]::GetExtension($leafName)
    $backupName = '{0}_{1}{2}' -f $baseName, $timestamp, $extension
    $backupPath = Join-Path $DestinationDirectory $backupName

    if ($PSCmdlet.ShouldProcess($Path, "Back up to '$backupPath'")) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Status -Type Success -Message "Backed up: $Path"
        return $backupPath
    }

    return $null
}

function Write-ScaffoldFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,

        [switch]$AlwaysOverwrite
    )

    $destination = Join-Path $frameworkRoot $RelativePath
    $parent = Split-Path -Parent $destination

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-DirectoryIfMissing -Path $parent
    }

    $exists = Test-Path -LiteralPath $destination -PathType Leaf
    $overwrite = $AlwaysOverwrite -or $Force

    if ($exists -and -not $overwrite) {
        Write-Status -Type Skip -Message "File exists: $RelativePath"
        return
    }

    $action = if ($exists) { 'Overwrite scaffold file' } else { 'Create scaffold file' }

    if ($PSCmdlet.ShouldProcess($destination, $action)) {
        Set-Content -LiteralPath $destination -Value $Content -Encoding utf8 -NoNewline
        Write-Status -Type Success -Message "$action`: $RelativePath"
    }
}

function Write-StandardProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $parent = Split-Path -Parent $Path

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-DirectoryIfMissing -Path $parent
    }

    if ($PSCmdlet.ShouldProcess($Path, "Install $Description")) {
        Set-Content -LiteralPath $Path -Value $Content -Encoding utf8 -NoNewline
        Write-Status -Type Success -Message "Installed $Description`: $Path"
    }
}

$files = [ordered]@{
    'config\Settings.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$global:BuFuProfileSettings = [ordered]@{
    DetailedTiming          = $false
    ShowStartupBanner       = $true
    ShowCompletionMessage   = $true
    EnableOhMyPosh          = $true
    EnablePSReadLine        = $true
    EnablePSFzf             = $true
    EnableKubernetesWarning = $true
    EnableExternalScripts   = $true
}

$global:ColorText    = 'Green'
$global:ColorLabel   = 'Magenta'
$global:ColorSubText = 'DarkGray'
$global:ColorBorder  = 'DarkCyan'
$global:ColorSpacer  = 'Yellow'
$global:BorderGlyph  = '═'
$global:SpacerGlyph  = '─'
'@

    'config\Paths.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

if (-not $global:BuFuProfileRoot) {
    throw 'BuFuProfileRoot has not been initialized.'
}

$global:BuFuPaths = [ordered]@{
    Root         = $global:BuFuProfileRoot
    Config       = Join-Path $global:BuFuProfileRoot 'config'
    Libraries    = Join-Path $global:BuFuProfileRoot 'lib'
    Functions    = Join-Path $global:BuFuProfileRoot 'functions'
    Aliases      = Join-Path $global:BuFuProfileRoot 'aliases'
    Modules      = Join-Path $global:BuFuProfileRoot 'modules'
    Integrations = Join-Path $global:BuFuProfileRoot 'integrations'
    Completions  = Join-Path $global:BuFuProfileRoot 'completions'
    Private      = Join-Path $global:BuFuProfileRoot 'private'
    Themes       = Join-Path $global:BuFuProfileRoot 'themes'
    Hosts        = Join-Path $global:BuFuProfileRoot 'hosts'
    Archive      = Join-Path $global:BuFuProfileRoot 'archive'
    Logs         = Join-Path $global:BuFuProfileRoot 'logs'
    Cache        = Join-Path $global:BuFuProfileRoot 'cache'
    SharedConfigs = Join-Path (Split-Path -Parent (Split-Path -Parent $global:BuFuProfileRoot)) 'SharedConfigs'
}

$global:BuFuPaths.OmpTheme = Join-Path $global:BuFuPaths.Themes 'bufu.omp.json'
$global:BuFuPaths.ThemeSettings = Join-Path $global:BuFuPaths.Private 'Theme.ps1'
'@

    'config\Environment.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$env:LOG_DIR = if ($global:BuFuPaths) {
    $global:BuFuPaths.Logs
} else {
    Join-Path $HOME 'Documents\PowerShell\BuFuProfile\logs'
}

$env:FZF_DEFAULT_OPTS = @(
    '--color=fg:-1,fg+:#ffffff,bg:-1,bg+:#3c4048'
    '--color=hl:#5ea1ff,hl+:#5ef1ff,info:#ffbd5e,marker:#5eff6c'
    '--color=prompt:#ff5ef1,spinner:#bd5eff,pointer:#ff5ea0,header:#5eff6c'
    '--color=gutter:-1,border:#3c4048,scrollbar:#7b8496,label:#7b8496'
    '--color=query:#ffffff'
    '--border=rounded'
    '--height=40%'
    '--layout=reverse'
    '--preview-window=border-rounded'
) -join ' '

$env:K8S_PRODUCTION = '0'
'@

    'lib\Loader.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$script:ProfileLoadErrors = [System.Collections.Generic.List[object]]::new()
$script:ProfileLoadResults = [System.Collections.Generic.List[object]]::new()

function global:Write-ProfileSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$ScriptBlock
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $succeeded = $false
    $errorRecord = $null

    try {
        & $ScriptBlock
        $succeeded = $true
    }
    catch {
        $errorRecord = $_
        $script:ProfileLoadErrors.Add([pscustomobject]@{
            Section   = $Name
            Exception = $_.Exception
            Message   = $_.Exception.Message
            Timestamp = Get-Date
        })
        Write-Warning "Profile section '$Name' failed: $($_.Exception.Message)"
    }
    finally {
        $stopwatch.Stop()
        $result = [pscustomobject]@{
            Section      = $Name
            Succeeded    = $succeeded
            Milliseconds = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            Error        = $errorRecord
        }
        $script:ProfileLoadResults.Add($result)

        if ($global:BuFuProfileSettings -and $global:BuFuProfileSettings.DetailedTiming) {
            $status = if ($succeeded) { 'Done' } else { 'Failed' }
            Write-Host ('{0,-35} {1,-7} {2,8:N2} ms' -f $Name, $status, $result.Milliseconds) -ForegroundColor $(if ($succeeded) { 'DarkGray' } else { 'Red' })
        }
    }
}

function global:Import-ProfileScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Optional
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($Optional) { return $false }
        throw "Profile script not found: $Path"
    }

    try {
        . $Path
        return $true
    }
    catch {
        $script:ProfileLoadErrors.Add([pscustomobject]@{
            Section   = 'Script'
            Path      = $Path
            Exception = $_.Exception
            Message   = $_.Exception.Message
            Timestamp = Get-Date
        })

        if ($Optional) {
            Write-Warning "Optional profile script failed '$Path': $($_.Exception.Message)"
            return $false
        }

        throw
    }
}

function global:Import-ProfileDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Exclude = @(),
        [switch]$Optional,
        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        if ($Optional) { return }
        throw "Profile directory not found: $Path"
    }

    $parameters = @{
        LiteralPath = $Path
        Filter      = '*.ps1'
        File        = $true
        ErrorAction = 'Stop'
    }

    if ($Recurse) { $parameters.Recurse = $true }

    $scripts = @(Get-ChildItem @parameters |
        Where-Object { $_.Name -notin $Exclude -and -not $_.Name.StartsWith('_') } |
        Sort-Object FullName)

    foreach ($scriptFile in $scripts) {
        try {
            . $scriptFile.FullName
        }
        catch {
            $script:ProfileLoadErrors.Add([pscustomobject]@{
                Section   = 'Directory'
                Path      = $scriptFile.FullName
                Exception = $_.Exception
                Message   = $_.Exception.Message
                Timestamp = Get-Date
            })
            Write-Warning "Failed to load '$($scriptFile.FullName)': $($_.Exception.Message)"
        }
    }
}

function global:Get-ProfileLoadError { $script:ProfileLoadErrors.ToArray() }
function global:Get-ProfileLoadResult { $script:ProfileLoadResults.ToArray() }

function global:Initialize-PowerShellProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Profile framework root does not exist: $Root"
    }

    $global:BuFuProfileRoot = $Root
    $profileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Write-ProfileSection 'Loading profile settings' { Import-ProfileScript -Path (Join-Path $Root 'config\Settings.ps1') }
        Write-ProfileSection 'Loading profile paths' { Import-ProfileScript -Path (Join-Path $Root 'config\Paths.ps1') }
        Write-ProfileSection 'Setting environment variables' { Import-ProfileScript -Path (Join-Path $Root 'config\Environment.ps1') }
        Write-ProfileSection 'Loading profile libraries' { Import-ProfileDirectory -Path (Join-Path $Root 'lib') -Exclude 'Loader.ps1' }
        Write-ProfileSection 'Loading functions' { Import-ProfileDirectory -Path (Join-Path $Root 'functions') }
        Write-ProfileSection 'Loading aliases' { Import-ProfileDirectory -Path (Join-Path $Root 'aliases') }
        Write-ProfileSection 'Importing modules' { Import-ProfileDirectory -Path (Join-Path $Root 'modules') }
        Write-ProfileSection 'Loading integrations' { Import-ProfileDirectory -Path (Join-Path $Root 'integrations') }
        Write-ProfileSection 'Loading completions' { Import-ProfileDirectory -Path (Join-Path $Root 'completions') -Optional }
        Write-ProfileSection 'Loading private configuration' { Import-ProfileDirectory -Path (Join-Path $Root 'private') -Optional }
    }
    finally {
        $profileStopwatch.Stop()
        $global:BuFuProfileLoadTime = [math]::Round($profileStopwatch.Elapsed.TotalMilliseconds, 2)

        if ($global:BuFuProfileSettings -and $global:BuFuProfileSettings.ShowCompletionMessage) {
            $errorCount = $script:ProfileLoadErrors.Count
            $message = if ($errorCount -eq 0) {
                'BuFuProfile loaded in {0:N0} ms' -f $global:BuFuProfileLoadTime
            } else {
                'BuFuProfile loaded in {0:N0} ms with {1} error(s)' -f $global:BuFuProfileLoadTime, $errorCount
            }
            Write-Host $message -ForegroundColor $(if ($errorCount -eq 0) { 'DarkGray' } else { 'Yellow' })
        }
    }
}
'@

    'lib\Console.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Get-ColorFromMilliseconds {
    [CmdletBinding()]
    [OutputType([ConsoleColor])]
    param(
        [Parameter(Mandatory)]
        [Alias('ms')]
        [double]$Milliseconds,
        [hashtable]$Thresholds
    )

    if (-not $Thresholds) {
        $Thresholds = [ordered]@{
            25 = 'DarkGreen'; 50 = 'Green'; 75 = 'DarkCyan'; 100 = 'Cyan';
            150 = 'DarkYellow'; 200 = 'Yellow'; 300 = 'DarkMagenta'; 400 = 'Magenta';
            500 = 'Blue'; 650 = 'DarkBlue'; 800 = 'Gray'; 1000 = 'DarkGray';
            1500 = 'DarkRed'; 2000 = 'Red'; [double]::PositiveInfinity = 'White'
        }
    }

    foreach ($limit in ($Thresholds.Keys | Sort-Object { [double]$_ })) {
        if ($Milliseconds -le [double]$limit) {
            return [ConsoleColor]$Thresholds[$limit]
        }
    }

    return [ConsoleColor]::White
}

function global:Write-Banner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [ConsoleColor]$ColorText = 'White',
        [ConsoleColor]$ColorBorder = 'DarkCyan',
        [ValidateRange(20, 200)]
        [int]$Width = 50
    )

    $content = " $Text "
    if ($content.Length -gt $Width) {
        $maximumTextLength = [Math]::Max(1, $Width - 6)
        $content = ' ' + $Text.Substring(0, $maximumTextLength) + '... '
    }

    $remaining = [Math]::Max(0, $Width - $content.Length)
    $leftLength = [Math]::Floor($remaining / 2)
    $rightLength = $remaining - $leftLength

    Write-Host ('=' * $leftLength) -ForegroundColor $ColorBorder -NoNewline
    Write-Host $content -ForegroundColor $ColorText -NoNewline
    Write-Host ('=' * $rightLength) -ForegroundColor $ColorBorder
}
'@

    'lib\Platform.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Test-IsAdministrator {
    if (-not $IsWindows) {
        try { return ([int](& id -u 2>$null) -eq 0) } catch { return $false }
    }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function global:Test-IsWindowsTerminal { return -not [string]::IsNullOrWhiteSpace($env:WT_SESSION) }
function global:Test-IsVSCodeTerminal { return ($env:TERM_PROGRAM -eq 'vscode' -or $env:VSCODE_INJECTION -eq '1') }
function global:Test-IsWSL {
    if ($env:WSL_DISTRO_NAME) { return $true }
    if (-not $IsLinux) { return $false }
    try { return (Get-Content -LiteralPath '/proc/version' -ErrorAction Stop) -match 'microsoft|wsl' } catch { return $false }
}
function global:Test-IsSSH { return [bool]($env:SSH_CLIENT -or $env:SSH_TTY -or $env:SSH_CONNECTION) }
function global:Test-IsInteractiveShell { return (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) }
function global:Test-SupportsVirtualTerminal { return [bool]($Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION -or $env:TERM_PROGRAM) }
'@

    'lib\Modules.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Test-ModuleAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [version]$MinimumVersion
    )

    $modules = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)
    if ($modules.Count -eq 0) { return $false }
    if ($MinimumVersion) { return [bool]($modules | Where-Object Version -GE $MinimumVersion | Select-Object -First 1) }
    return $true
}

function global:Import-IfAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [version]$MinimumVersion,
        [switch]$Force,
        [switch]$PassThru
    )

    $availableModule = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue |
        Where-Object { -not $MinimumVersion -or $_.Version -ge $MinimumVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $availableModule) { return $false }

    try {
        $module = Import-Module -Name $availableModule.Path -Force:$Force -PassThru -ErrorAction Stop
        if ($PassThru) { return $module }
        return $true
    }
    catch {
        Write-Warning "Failed to import module '$Name': $($_.Exception.Message)"
        return $false
    }
}

function global:Import-FirstAvailableModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Name)
    foreach ($moduleName in $Name) {
        if (Import-IfAvailable -Name $moduleName) { return $moduleName }
    }
    return $null
}
'@

    'lib\Timing.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$global:BuFuProfileTimers = [ordered]@{}

function global:Start-ProfileTimer {
    param([Parameter(Mandatory)][string]$Name)
    $global:BuFuProfileTimers[$Name] = [pscustomobject]@{
        Name      = $Name
        Stopwatch = [Diagnostics.Stopwatch]::StartNew()
        Started   = Get-Date
        Ended     = $null
        TotalMs   = $null
        Steps     = [System.Collections.Generic.List[object]]::new()
    }
    return $global:BuFuProfileTimers[$Name]
}

function global:Stop-ProfileTimer {
    param([Parameter(Mandatory)][string]$Name,[switch]$PassThru)
    $timer = $global:BuFuProfileTimers[$Name]
    if (-not $timer) { return }
    $timer.Stopwatch.Stop()
    $timer.Ended = Get-Date
    $timer.TotalMs = [math]::Round($timer.Stopwatch.Elapsed.TotalMilliseconds, 2)
    if ($PassThru) { return $timer }
}

function global:Measure-ProfileAction {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$ScriptBlock,[switch]$PassThru)
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try { $result = & $ScriptBlock } finally { $stopwatch.Stop() }
    $measurement = [pscustomobject]@{
        Name         = $Name
        Milliseconds = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
        Result       = $result
    }
    if ($PassThru) { return $measurement }
    return $result
}
'@

    'functions\Profile-Management.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Get-ProfileRoot { return $global:BuFuProfileRoot }

function global:Reload-Profile {
    [CmdletBinding()]
    param([switch]$Clear)
    if ($Clear) { Clear-Host }
    . $PROFILE.CurrentUserAllHosts
    if (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost -PathType Leaf) {
        . $PROFILE.CurrentUserCurrentHost
    }
}

function global:Edit-Profile {
    [CmdletBinding()]
    param(
        [ValidateSet('Root','AllHosts','CurrentHost','Settings','Environment','Paths','Functions','Aliases','Modules','Integrations','Private')]
        [string]$Target = 'Root'
    )

    $path = switch ($Target) {
        'Root'         { $global:BuFuProfileRoot }
        'AllHosts'     { $PROFILE.CurrentUserAllHosts }
        'CurrentHost'  { $PROFILE.CurrentUserCurrentHost }
        'Settings'     { Join-Path $global:BuFuProfileRoot 'config\Settings.ps1' }
        'Environment'  { Join-Path $global:BuFuProfileRoot 'config\Environment.ps1' }
        'Paths'        { Join-Path $global:BuFuProfileRoot 'config\Paths.ps1' }
        'Functions'    { Join-Path $global:BuFuProfileRoot 'functions' }
        'Aliases'      { Join-Path $global:BuFuProfileRoot 'aliases' }
        'Modules'      { Join-Path $global:BuFuProfileRoot 'modules' }
        'Integrations' { Join-Path $global:BuFuProfileRoot 'integrations' }
        'Private'      { Join-Path $global:BuFuProfileRoot 'private' }
    }

    if (Get-Command code -ErrorAction SilentlyContinue) { & code $path; return }
    if ($IsWindows -and (Get-Command notepad.exe -ErrorAction SilentlyContinue)) { & notepad.exe $path; return }
    throw 'No supported profile editor was found.'
}

function global:Show-ProfileFiles {
    Get-ChildItem -LiteralPath $global:BuFuProfileRoot -Filter '*.ps1' -File -Recurse |
        Sort-Object FullName |
        Select-Object @{Name='RelativePath';Expression={[IO.Path]::GetRelativePath($global:BuFuProfileRoot,$_.FullName)}},Length,LastWriteTime
}

function global:Test-BuFuProfile {
    [CmdletBinding()]
    param()

    $errors = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -LiteralPath $global:BuFuProfileRoot -Filter '*.ps1' -File -Recurse)

    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        foreach ($parseError in $parseErrors) {
            $errors.Add([pscustomobject]@{
                File    = $file.FullName
                Line    = $parseError.Extent.StartLineNumber
                Column  = $parseError.Extent.StartColumnNumber
                Message = $parseError.Message
            })
        }
    }

    if ($errors.Count -eq 0) {
        Write-Host 'All BuFuProfile scripts parsed successfully.' -ForegroundColor Green
        return $true
    }

    $errors
    return $false
}
'@

    'functions\Terminal.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Clear-Terminal {
    if (Test-SupportsVirtualTerminal) { [Console]::Write("`e[2J`e[H"); return }
    Clear-Host
}
function global:Clear-Scrollback {
    if (Test-SupportsVirtualTerminal) { [Console]::Write("`e[3J"); return }
}
function global:Clear-TerminalAll {
    if (Test-SupportsVirtualTerminal) { [Console]::Write("`e[2J`e[3J`e[H"); return }
    Clear-Host
}
function global:Clear-TerminalLine {
    if (Test-SupportsVirtualTerminal) { [Console]::Write("`e[2K`r") }
}
'@

    'functions\Theme.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Set-BuFuTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Dark','Light')]
        [string]$Name = 'Dark',
        [switch]$Toggle
    )

    if ($Toggle) { $Name = if ($global:CurrentThemeName -eq 'Light') { 'Dark' } else { 'Light' } }

    $themes = @{
        Dark = @{ UiText='Yellow';UiLabel='White';UiSubText='DarkGray';UiBorder='DarkCyan';UiSpacer='Yellow';PrlCommand='Yellow';PrlParameter='Cyan';PrlString='Magenta';PrlComment='Green';PrlPrediction='DarkGray';PrlError='Red' }
        Light = @{ UiText='Black';UiLabel='DarkBlue';UiSubText='DarkGray';UiBorder='DarkRed';UiSpacer='DarkBlue';PrlCommand='Blue';PrlParameter='DarkGray';PrlString='DarkCyan';PrlComment='DarkGreen';PrlPrediction='Gray';PrlError='Red' }
    }

    $theme = $themes[$Name]
    $global:Theme = $theme
    $global:CurrentThemeName = $Name
    $global:ColorText = $theme.UiText
    $global:ColorLabel = $theme.UiLabel
    $global:ColorSubText = $theme.UiSubText
    $global:ColorBorder = $theme.UiBorder
    $global:ColorSpacer = $theme.UiSpacer

    if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
        Set-PSReadLineOption -Colors @{
            Command=$theme.PrlCommand;Parameter=$theme.PrlParameter;String=$theme.PrlString;
            Comment=$theme.PrlComment;InlinePrediction=$theme.PrlPrediction;Error=$theme.PrlError
        }
    }
}
'@

    'functions\OhMyPosh.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Get-OmpConfigs {
    [CmdletBinding()]
    param(
        [string[]]$SearchPath = @(
            (Join-Path $HOME '.config\omp'),
            (Join-Path $HOME '.config\ohmyposh'),
            (Join-Path $HOME 'Documents\SharedConfigs\Themes'),
            $global:BuFuPaths.Themes
        ),
        [switch]$ListOnly,
        [switch]$Persist
    )

    $configFiles = [System.Collections.Generic.List[IO.FileInfo]]::new()
    foreach ($path in $SearchPath) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
            foreach ($file in (Get-ChildItem -LiteralPath $path -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue)) {
                $configFiles.Add($file)
            }
        }
    }

    $uniqueConfigs = @($configFiles | Group-Object FullName | ForEach-Object {
        $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    } | Select-Object @{Name='Name';Expression={$_.BaseName}},@{Name='Path';Expression={$_.FullName}},@{Name='LastModified';Expression={$_.LastWriteTime}} | Sort-Object Name)

    if ($uniqueConfigs.Count -eq 0) { Write-Warning 'No Oh My Posh JSON configurations were found.'; return }
    if ($ListOnly) { return $uniqueConfigs }

    $selectedConfig = $null
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        $selection = $uniqueConfigs | ForEach-Object { '{0}`t{1}' -f $_.Name, $_.Path } | fzf --delimiter "`t" --with-nth 1 --header 'Select an Oh My Posh configuration' --height 50% --layout reverse
        if ($selection) {
            $targetPath = ($selection -split "`t", 2)[1]
            $selectedConfig = $uniqueConfigs | Where-Object Path -EQ $targetPath | Select-Object -First 1
        }
    }
    elseif (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
        $selectedConfig = $uniqueConfigs | Out-GridView -Title 'Select an Oh My Posh configuration' -OutputMode Single
    }

    if (-not $selectedConfig) { return }
    Initialize-OhMyPosh -ConfigPath $selectedConfig.Path
    if ($Persist) { Set-BuFuOmpTheme -Path $selectedConfig.Path }
    return $selectedConfig
}

function global:Set-BuFuOmpTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $escapedPath = $resolvedPath.Replace("'", "''")
    $content = @"
# Generated by Set-BuFuOmpTheme.
`$global:BuFuSelectedOmpTheme = '$escapedPath'
"@
    Set-Content -LiteralPath $global:BuFuPaths.ThemeSettings -Value $content -Encoding utf8 -NoNewline
    $global:BuFuSelectedOmpTheme = $resolvedPath
}
'@

    'aliases\General.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

Set-Alias -Name rp -Value Reload-Profile -Scope Global -Force
Set-Alias -Name ep -Value Edit-Profile -Scope Global -Force
Set-Alias -Name clst -Value Clear-Terminal -Scope Global -Force
Set-Alias -Name clsb -Value Clear-Scrollback -Scope Global -Force
Set-Alias -Name clsa -Value Clear-TerminalAll -Scope Global -Force

function global:ll { Get-ChildItem -Force @args }
if (Get-Command notepad.exe -ErrorAction SilentlyContinue) {
    Set-Alias -Name note -Value notepad.exe -Scope Global -Force
}
'@

    'modules\Common.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$commonModules = @('Terminal-Icons','posh-git','PowerColorLS','ZLocation')
foreach ($moduleName in $commonModules) { [void](Import-IfAvailable -Name $moduleName) }
'@

    'modules\Predictors.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$predictorModules = @('CompletionPredictor','Az.Tools.Predictor','PSCompletions')
[void](Import-FirstAvailableModule -Name $predictorModules)
'@

    'modules\PSReadLine.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

if ($global:BuFuProfileSettings -and -not $global:BuFuProfileSettings.EnablePSReadLine) { return }
if (-not (Get-Module PSReadLine)) { [void](Import-IfAvailable -Name PSReadLine) }

$optionCommand = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
$keyCommand = Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue
if (-not $optionCommand) { return }

$supportedOptions = $optionCommand.Parameters.Keys
$options = @{}
if ($supportedOptions -contains 'EditMode') { $options.EditMode = 'Windows' }
if ($supportedOptions -contains 'MaximumHistoryCount') { $options.MaximumHistoryCount = 4096 }
if ($supportedOptions -contains 'HistorySaveStyle') { $options.HistorySaveStyle = 'SaveIncrementally' }
if ($supportedOptions -contains 'HistoryNoDuplicates') { $options.HistoryNoDuplicates = $true }
if ($supportedOptions -contains 'PredictionSource') { $options.PredictionSource = 'HistoryAndPlugin' }
if ($supportedOptions -contains 'PredictionViewStyle') { $options.PredictionViewStyle = 'ListView' }
if ($supportedOptions -contains 'AddToHistoryHandler') {
    $options.AddToHistoryHandler = {
        param($Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
        foreach ($pattern in @('(?i)password\s*=','(?i)token\s*=','(?i)secret\s*=','(?i)api[_-]?key\s*=','(?i)credential','(?i)convertto-securestring.+-asplaintext')) {
            if ($Line -match $pattern) { return $false }
        }
        return $true
    }
}
if ($supportedOptions -contains 'Colors') {
    $options.Colors = @{ Command='Yellow';Parameter='Cyan';String='Magenta';Comment='Green';InlinePrediction='DarkGray';Error='Red' }
}

try { Set-PSReadLineOption @options } catch { Write-Verbose $_.Exception.Message }
if (-not $keyCommand) { return }

foreach ($handler in @(
    @{Key='Tab';Function='MenuComplete'},
    @{Key='Ctrl+r';Function='ReverseSearchHistory'},
    @{Key='Ctrl+l';Function='ClearScreen'},
    @{Key='Ctrl+LeftArrow';Function='BackwardWord'},
    @{Key='Ctrl+RightArrow';Function='ForwardWord'}
)) {
    try { Set-PSReadLineKeyHandler @handler } catch { Write-Verbose $_.Exception.Message }
}
'@

    'modules\PSFzf.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

if ($global:BuFuProfileSettings -and -not $global:BuFuProfileSettings.EnablePSFzf) { return }
if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }
if (-not (Get-Module PSFzf)) { [void](Import-IfAvailable -Name PSFzf) }
if (-not (Get-Module PSFzf)) { return }

try {
    Set-PsFzfOption -TabExpansion -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
catch { Write-Verbose $_.Exception.Message }
'@

    'integrations\Kubernetes.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Get-KubernetesContext {
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) { return $null }
    try {
        $context = & kubectl config current-context 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return $context
    }
    catch { return $null }
}

function global:Test-ProductionCluster {
    param([string]$Context = (Get-KubernetesContext))
    if ([string]::IsNullOrWhiteSpace($Context)) { return $false }
    return $Context -match '(?i)(^|[-_.])(prod|production|live)([-_.]|$)'
}

function global:Write-KubeProdWarning {
    $context = Get-KubernetesContext
    if (-not (Test-ProductionCluster -Context $context)) { return }
    Write-Host ''
    Write-Host "  WARNING: KUBERNETES CONTEXT $context  " -ForegroundColor White -BackgroundColor DarkRed
    Write-Host ''
}

if ($global:BuFuProfileSettings.EnableKubernetesWarning -and (Test-IsInteractiveShell)) {
    $context = Get-KubernetesContext
    $env:K8S_PRODUCTION = if (Test-ProductionCluster -Context $context) { '1' } else { '0' }
    if ($env:K8S_PRODUCTION -eq '1') { Write-KubeProdWarning }
}
'@

    'integrations\Oh-My-Posh.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:New-BuFuOmpTheme {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }

    $theme = @{
        '$schema' = 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json'
        version = 3
        final_space = $true
        transient_prompt = @{ foreground = '#888888'; template = '❯ ' }
        blocks = @(
            @{ type='prompt'; alignment='left'; segments=@(
                @{ type='session';style='diamond';foreground='#FFFFFF';background='#C50F1F';template='{{ if .Root }} ADMIN {{ end }}' },
                @{ type='os';style='diamond';foreground='#FFFFFF';background='#0078D7' },
                @{ type='shell';style='diamond';foreground='#FFFFFF';background='#6A5ACD' },
                @{ type='path';style='powerline';foreground='#FFFFFF';background='#005F87';properties=@{style='full'} },
                @{ type='git';style='powerline';foreground='#000000';background='#FFD700';properties=@{fetch_status=$true;fetch_upstream_icon=$true} }
            )},
            @{ type='rprompt';alignment='right';segments=@(
                @{type='python';style='plain';foreground='#FFD43B'},
                @{type='node';style='plain';foreground='#68A063'},
                @{type='executiontime';style='plain';foreground='#FF8800';properties=@{threshold=500}},
                @{type='time';style='plain';foreground='#AAAAAA';template='15:04:05'}
            )},
            @{ type='prompt';alignment='left';newline=$true;segments=@(
                @{type='text';style='plain';foreground='#00FF00';template='❯'}
            )}
        )
    }

    $theme | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}

function global:Initialize-OhMyPosh {
    [CmdletBinding()]
    param([string]$ConfigPath)

    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $omp) {
        function global:Prompt {
            $admin = if (Test-IsAdministrator) { '[ADMIN] ' } else { '' }
            $ssh = if (Test-IsSSH) { '[SSH] ' } else { '' }
            $wsl = if (Test-IsWSL) { '[WSL] ' } else { '' }
            return "$admin$ssh$wsl$(Get-Location)`n❯ "
        }
        return
    }

    if (-not $ConfigPath) {
        if ($global:BuFuSelectedOmpTheme -and (Test-Path -LiteralPath $global:BuFuSelectedOmpTheme)) {
            $ConfigPath = $global:BuFuSelectedOmpTheme
        } else {
            $ConfigPath = $global:BuFuPaths.OmpTheme
        }
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { New-BuFuOmpTheme -Path $ConfigPath }
    try { & $omp.Source init pwsh --config $ConfigPath | Invoke-Expression }
    catch { Write-Warning "Oh My Posh initialization failed: $($_.Exception.Message)" }
}

if ($global:BuFuProfileSettings.EnableOhMyPosh -and (Test-IsInteractiveShell)) {
    Initialize-OhMyPosh
}
'@

    'hosts\Microsoft.PowerShell.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

# Add ConsoleHost or Windows Terminal-specific settings here.
'@

    'hosts\Visual Studio Code Host.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

# Add Visual Studio Code PowerShell host-specific settings here.
'@

    'private\.gitignore' = @'
*
!.gitignore
!Example.ps1
'@

    'logs\.gitkeep' = ''
    'cache\.gitkeep' = ''

    '.gitignore' = @'
archive/
cache/*
!cache/.gitkeep
logs/*
!logs/.gitkeep
private/*
!private/.gitignore
!private/Example.ps1
*.bak
*.tmp
'@

    'README.md' = @'
# BuFuProfile

A modular PowerShell 7 profile framework.

## Commands

```powershell
Reload-Profile
Edit-Profile
Show-ProfileFiles
Test-BuFuProfile
Get-ProfileLoadResult
Get-ProfileLoadError
```
'@
}

if ($IncludeExampleFiles) {
    $files['private\Example.ps1'] = @'
#requires -Version 7.4
# Store private local values in this directory.
'@

    $files['completions\Example.ps1'] = @'
#requires -Version 7.4
# Add native argument completers here.
'@
}

$allHostsProfileContent = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$script:PowerShellRoot = Split-Path -Parent $PROFILE.CurrentUserAllHosts
$script:ProfileRoot = Join-Path $script:PowerShellRoot '__FRAMEWORK_DIRECTORY_NAME__'

if (-not (Test-Path -LiteralPath $script:ProfileRoot -PathType Container)) {
    Write-Warning ('BuFuProfile framework directory was not found: ' + $script:ProfileRoot)
    return
}

$loaderPath = Join-Path $script:ProfileRoot 'lib\Loader.ps1'
if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
    Write-Warning ('BuFuProfile loader was not found: ' + $loaderPath)
    return
}

try {
    . $loaderPath
    Initialize-PowerShellProfile -Root $script:ProfileRoot
}
catch {
    Write-Warning 'PowerShell profile initialization failed.'
    Write-Warning ('{0}: {1}' -f $_.Exception.GetType().Name, $_.Exception.Message)
}
'@
$allHostsProfileContent = $allHostsProfileContent.Replace('__FRAMEWORK_DIRECTORY_NAME__', $FrameworkDirectoryName.Replace("'", "''"))

$currentHostProfileContent = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

if (-not $script:ProfileRoot) {
    $powerShellRoot = Split-Path -Parent $PROFILE.CurrentUserAllHosts
    $script:ProfileRoot = Join-Path $powerShellRoot '__FRAMEWORK_DIRECTORY_NAME__'
}

$hostProfilePath = Join-Path $script:ProfileRoot 'hosts\Microsoft.PowerShell.ps1'
if (Test-Path -LiteralPath $hostProfilePath -PathType Leaf) {
    try { . $hostProfilePath }
    catch { Write-Warning "Failed to load host profile '$hostProfilePath': $($_.Exception.Message)" }
}
'@
$currentHostProfileContent = $currentHostProfileContent.Replace('__FRAMEWORK_DIRECTORY_NAME__', $FrameworkDirectoryName.Replace("'", "''"))

Write-Host ''
Write-Host 'BuFuProfile Framework Installer' -ForegroundColor Cyan
Write-Host ('=' * 50) -ForegroundColor DarkCyan
Write-Status -Type Info -Message "PowerShell root: $PowerShellRoot"
Write-Status -Type Info -Message "Framework root: $frameworkRoot"
Write-Host ''

try {
    New-DirectoryIfMissing -Path $PowerShellRoot
    New-DirectoryIfMissing -Path $frameworkRoot

    foreach ($directory in $directories) {
        New-DirectoryIfMissing -Path (Join-Path $frameworkRoot $directory)
    }

    Write-Host ''
    Write-Status -Type Info -Message 'Creating framework files...'

    foreach ($entry in $files.GetEnumerator()) {
        Write-ScaffoldFile -RelativePath $entry.Key -Content $entry.Value
    }

    if (-not $SkipProfileUpdate) {
        Write-Host ''
        Write-Status -Type Info -Message 'Installing PowerShell bootstrap profiles...'

        if (-not $SkipBackup) {
            [void](Backup-ProfileFile -Path $allHostsProfile -DestinationDirectory $archiveRoot)
            if ($currentHostProfile -ne $allHostsProfile) {
                [void](Backup-ProfileFile -Path $currentHostProfile -DestinationDirectory $archiveRoot)
            }
        }

        Write-StandardProfile -Path $allHostsProfile -Content $allHostsProfileContent -Description 'CurrentUserAllHosts bootstrap'
        Write-StandardProfile -Path $currentHostProfile -Content $currentHostProfileContent -Description 'CurrentUserCurrentHost bootstrap'
    }
    else {
        Write-Status -Type Skip -Message 'Standard profile files were not modified.'
    }

    Write-Host ''
    Write-Host ('=' * 50) -ForegroundColor DarkCyan
    Write-Status -Type Success -Message 'BuFuProfile scaffold completed.'

    Write-Host ''
    Write-Host 'Framework:' -ForegroundColor Cyan
    Write-Host "  $frameworkRoot"

    Write-Host ''
    Write-Host 'Validate in a clean PowerShell session:' -ForegroundColor Cyan
    Write-Host '  pwsh -NoLogo -Command ". $PROFILE.CurrentUserAllHosts; Test-BuFuProfile"'

    Write-Host ''
    Write-Host 'Reload the current session:' -ForegroundColor Cyan
    Write-Host '  . $PROFILE.CurrentUserAllHosts'
    Write-Host '  . $PROFILE.CurrentUserCurrentHost'
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Status -Type Error -Message $_.Exception.Message
    throw
}