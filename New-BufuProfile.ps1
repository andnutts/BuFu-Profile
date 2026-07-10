#requires -Version 7.4
<#
    .SYNOPSIS
        Creates, updates, validates, backs up, and documents the BuFuProfile
        modular PowerShell profile framework.
    .DESCRIPTION
        New-BuFuProfile.ps1 manages a modular PowerShell profile framework beneath
        the user's PowerShell documents directory.
        Launching the script without arguments opens an interactive main menu.
        The installer manages framework directories, scaffold files, the
        CurrentUserAllHosts bootstrap, and the CurrentUserCurrentHost bootstrap.
        Existing managed files are classified as Current, Modified, or Missing.
        Modified-file conflicts provide options to view a diff, overwrite, create
        a backup and overwrite, skip, apply an action to all remaining conflicts,
        or quit.
        The script supports PowerShell's native -WhatIf and -Confirm behavior.
        WhatIf previews create, overwrite, backup, and documentation-export
        operations without changing the filesystem.
        Backups are stored beneath:
            BuFuProfile\archive
        The generated framework includes a docs directory and runtime help
        functions for Markdown and HTML documentation export.
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
    .PARAMETER InteractiveMenu
        Opens the interactive main menu explicitly.
    .PARAMETER NonInteractive
        Runs without interactive conflict prompts. Modified files are skipped
        unless -Force is also supplied.
    .PARAMETER Validate
        Validates all managed files and reports Current, Modified, or Missing.
    .PARAMETER Backup
        Creates a timestamped backup set beneath BuFuProfile\archive.
    .PARAMETER ShowTree
        Displays the BuFuProfile framework directory tree.
    .PARAMETER ExportHelp
        Exports documentation in Markdown, HTML, or both formats.
    .PARAMETER Help
        Displays the complete BuFuProfile installer help. The aliases -h,
        --Help, and /? are also supported.
    .PARAMETER RemainingArguments
        Captures compatibility switches such as /?.
    .EXAMPLE
        .\New-BuFuProfile.ps1
        Opens the interactive main menu.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -NonInteractive
        Installs or updates missing files and skips modified files.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -Force
        Installs or updates all managed files without conflict prompts.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -WhatIf
        Previews the installation or update without making changes.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -Validate
        Reports each managed file as Current, Modified, or Missing.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -Backup
        Creates a timestamped backup set in BuFuProfile\archive.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -FrameworkDirectoryName ProfileFramework
    .EXAMPLE
        .\New-BuFuProfile.ps1 -SkipProfileUpdate
    .EXAMPLE
        .\New-BuFuProfile.ps1 -ExportHelp All
        Exports Markdown and HTML documentation.
    .EXAMPLE
        .\New-BuFuProfile.ps1 -Help
        Displays complete help.
    .INPUTS
        None.
    .OUTPUTS
        Validation, information, backup, and export commands return structured
        objects when appropriate.
    .NOTES
        Author: Nickolas E. Teuber
        Version: 2.0.0
        Requires: PowerShell 7.4 or later
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
    [switch]$IncludeExampleFiles,
    [Parameter()]
    [switch]$InteractiveMenu,
    [Parameter()]
    [switch]$NonInteractive,
    [Parameter()]
    [switch]$Validate,
    [Parameter()]
    [switch]$Backup,
    [Parameter()]
    [switch]$ShowTree,
    [Parameter()]
    [ValidateSet('Markdown', 'Html', 'All')]
    [string]$ExportHelp,
    [Parameter()]
    [Alias('h', '?', '-Help')]
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$RemainingArguments
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
#==================================================================#
#region --- Constants and state ---
#==================================================================#
$script:BuFuProfileInstallerVersion = [version]'2.0.0'
$script:ConflictMode    = 'Prompt'
$script:QuitRequested   = $false

$timestamp              = Get-Date -Format 'yyyyMMdd_HHmmss'

$frameworkRoot          = Join-Path $PowerShellRoot $FrameworkDirectoryName
$archiveRoot            = Join-Path $frameworkRoot 'archive'

$allHostsProfile        = $PROFILE.CurrentUserAllHosts
$currentHostProfile     = $PROFILE.CurrentUserCurrentHost

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
    'docs'
    'docs\markdown'
    'docs\html'
)
#endregion
#==================================================================#
#region --- Console and utility helpers ---
#==================================================================#
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

function Write-SectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * [Math]::Min(78, [Math]::Max(30, $Title.Length))) -ForegroundColor DarkCyan
}

function Pause-BuFuMenu {
    [CmdletBinding()]
    param()
    if (Test-InteractiveConsole) {
        [void](Read-Host 'Press Enter to continue')
    }
}

function Clear-BuFuScreen {
    [CmdletBinding()]
    param()
    try {
        Clear-Host
    }
    catch {
        Write-Host ''
    }
}

function Test-InteractiveConsole {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        return (
            [Environment]::UserInteractive -and
            -not [Console]::IsInputRedirected -and
            -not [Console]::IsOutputRedirected
        )
    }
    catch {
        return $false
    }
}

function ConvertTo-NormalizedText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )
    $normalized = $Text.TrimStart([char]0xFEFF)
    $normalized = $normalized -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    return $normalized.TrimEnd([char]10)
}

function Get-ManagedFileState {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ExpectedContent
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'Missing'
    }
    $actualContent = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
    if (
        (ConvertTo-NormalizedText -Text $actualContent) -ceq
        (ConvertTo-NormalizedText -Text $ExpectedContent)
    ) {
        return 'Current'
    }
    return 'Modified'
}

function New-DirectoryIfMissing {
    [CmdletBinding(SupportsShouldProcess)]
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

function Get-RelativeManagedPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if ($Path.StartsWith($frameworkRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return [IO.Path]::GetRelativePath($frameworkRoot, $Path)
    }
    if ($Path -eq $allHostsProfile) {
        return Join-Path 'profiles\CurrentUserAllHosts' (Split-Path -Leaf $Path)
    }
    if ($Path -eq $currentHostProfile) {
        return Join-Path 'profiles\CurrentUserCurrentHost' (Split-Path -Leaf $Path)
    }
    return Join-Path 'external' (Split-Path -Leaf $Path)
}

function Backup-ManagedFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Reason = 'manual',
        [string]$BackupSetName
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($BackupSetName)) {
        $BackupSetName = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    }
    $safeReason = $Reason -replace '[^A-Za-z0-9._-]', '_'
    $backupSetRoot = Join-Path $archiveRoot ("{0}_{1}" -f $BackupSetName, $safeReason)
    $relativePath = Get-RelativeManagedPath -Path $Path
    $backupPath = Join-Path $backupSetRoot $relativePath
    $backupParent = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $backupParent -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($backupParent, 'Create backup directory')) {
            New-Item -Path $backupParent -ItemType Directory -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($Path, "Back up to '$backupPath'")) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Status -Type Success -Message "Backed up: $Path"
        return $backupPath
    }
    return $null
}

function Backup-ProfileFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
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

function Show-FileDiff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ExpectedContent
    )
    Write-SectionHeader -Title "Differences: $Path"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Status -Type Warning -Message 'The existing file is missing.'
        return
    }
    $temporaryFile = [IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $temporaryFile -Value $ExpectedContent -Encoding utf8 -NoNewline
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($git) {
            Write-Host '--- Existing file'
            Write-Host '+++ Managed version'
            $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
            try {
                $PSNativeCommandUseErrorActionPreference = $false
                & $git.Source --no-pager diff --no-index -- $Path $temporaryFile
            }
            finally {
                $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
            }
            return
        }
        $existingLines = @(Get-Content -LiteralPath $Path)
        $expectedLines = @($ExpectedContent -split "`r?`n")
        $difference = Compare-Object -ReferenceObject $existingLines -DifferenceObject $expectedLines -IncludeEqual:$false
        if (-not $difference) {
            Write-Host 'No line-level differences were found after normalization.'
            return
        }
        foreach ($entry in $difference) {
            $prefix = if ($entry.SideIndicator -eq '<=') { '- ' } else { '+ ' }
            $color = if ($entry.SideIndicator -eq '<=') { 'Red' } else { 'Green' }
            Write-Host ($prefix + $entry.InputObject) -ForegroundColor $color
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-ManagedFileConflict {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ExpectedContent,
        [Parameter(Mandatory)]
        [string]$DisplayName
    )
    if ($WhatIfPreference) {
        return 'Overwrite'
    }
    if ($Force -or $script:ConflictMode -eq 'OverwriteAll') {
        return 'Overwrite'
    }
    if ($script:ConflictMode -eq 'SkipAll') {
        return 'Skip'
    }
    if ($NonInteractive -or -not (Test-InteractiveConsole)) {
        return 'Skip'
    }
    while ($true) {
        Write-Host ''
        Write-Status -Type Warning -Message "Managed file has been modified: $DisplayName"
        Write-Host "  $Path" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '[V] View differences'
        Write-Host '[O] Overwrite'
        Write-Host '[B] Backup + overwrite'
        Write-Host '[S] Skip'
        Write-Host '[A] Overwrite all remaining conflicts'
        Write-Host '[K] Skip all remaining conflicts'
        Write-Host '[Q] Quit'
        Write-Host ''
        $choice = (Read-Host 'Choose an action').Trim().ToUpperInvariant()
        switch ($choice) {
            'V' {
                Show-FileDiff -Path $Path -ExpectedContent $ExpectedContent
            }
            'O' {
                return 'Overwrite'
            }
            'B' {
                return 'BackupAndOverwrite'
            }
            'S' {
                return 'Skip'
            }
            'A' {
                $script:ConflictMode = 'OverwriteAll'
                return 'Overwrite'
            }
            'K' {
                $script:ConflictMode = 'SkipAll'
                return 'Skip'
            }
            'Q' {
                $script:QuitRequested = $true
                return 'Quit'
            }
            default {
                Write-Status -Type Warning -Message 'Invalid selection.'
            }
        }
    }
}

function Write-ManagedFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,
        [Parameter(Mandatory)]
        [string]$DisplayName,
        [switch]$BackupBeforeOverwrite
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-DirectoryIfMissing -Path $parent
    }
    $state = Get-ManagedFileState -Path $Path -ExpectedContent $Content
    if ($state -eq 'Current') {
        Write-Status -Type Skip -Message "Current: $DisplayName"
        return 'Current'
    }
    $action = if ($state -eq 'Missing') {
        'Create'
    }
    else {
        Resolve-ManagedFileConflict -Path $Path -ExpectedContent $Content -DisplayName $DisplayName
    }
    if ($action -eq 'Quit') {
        Write-Status -Type Warning -Message 'Operation cancelled by user.'
        return 'Quit'
    }
    if ($action -eq 'Skip') {
        Write-Status -Type Skip -Message "Skipped modified file: $DisplayName"
        return 'Skipped'
    }
    if ($state -eq 'Modified') {
        if ($action -eq 'BackupAndOverwrite') {
            [void](Backup-ManagedFile -Path $Path -Reason 'conflict')
        }
        elseif ($BackupBeforeOverwrite -and -not $SkipBackup) {
            [void](Backup-ManagedFile -Path $Path -Reason 'profile')
        }
    }
    $operation = if ($state -eq 'Missing') {
        'Create managed file'
    }
    else {
        'Overwrite managed file'
    }
    if ($PSCmdlet.ShouldProcess($Path, $operation)) {
        Set-Content -LiteralPath $Path -Value $Content -Encoding utf8 -NoNewline
        Write-Status -Type Success -Message "$operation`: $DisplayName"
        if ($state -eq 'Missing') {
            return 'Created'
        }
        return 'Updated'
    }
    return 'Previewed'
}

function Write-ScaffoldFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content,
        [switch]$AlwaysOverwrite
    )
    $destination = Join-Path $frameworkRoot $RelativePath
    $result = Write-ManagedFile -Path $destination -Content $Content -DisplayName $RelativePath
    return $result
}

function Write-StandardProfile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Content,
        [Parameter(Mandatory)]
        [string]$Description
    )
    $result = Write-ManagedFile `
        -Path $Path `
        -Content $Content `
        -DisplayName $Description `
        -BackupBeforeOverwrite
    return $result
}
#endregion
#==================================================================#
#region --- Information and help data ---
#==================================================================#
function Get-ParameterHelpData {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Parameter = '-FrameworkDirectoryName'; Description = 'Framework directory name. Default: BuFuProfile.' }
        [pscustomobject]@{ Parameter = '-PowerShellRoot'; Description = 'PowerShell profile root directory.' }
        [pscustomobject]@{ Parameter = '-Force'; Description = 'Overwrite modified managed files without conflict prompts.' }
        [pscustomobject]@{ Parameter = '-SkipProfileUpdate'; Description = 'Do not modify standard PowerShell profile files.' }
        [pscustomobject]@{ Parameter = '-SkipBackup'; Description = 'Do not automatically back up modified bootstrap profiles.' }
        [pscustomobject]@{ Parameter = '-IncludeExampleFiles'; Description = 'Create example private and completion files.' }
        [pscustomobject]@{ Parameter = '-InteractiveMenu'; Description = 'Open the main menu explicitly.' }
        [pscustomobject]@{ Parameter = '-NonInteractive'; Description = 'Skip prompts; modified files require -Force to overwrite.' }
        [pscustomobject]@{ Parameter = '-Validate'; Description = 'Report managed files as Current, Modified, or Missing.' }
        [pscustomobject]@{ Parameter = '-Backup'; Description = 'Create a timestamped backup set in BuFuProfile\archive.' }
        [pscustomobject]@{ Parameter = '-ShowTree'; Description = 'Display the framework directory tree.' }
        [pscustomobject]@{ Parameter = '-ExportHelp'; Description = 'Export Markdown, HTML, or All documentation formats.' }
        [pscustomobject]@{ Parameter = '-WhatIf'; Description = 'Preview changes using native PowerShell WhatIf behavior.' }
        [pscustomobject]@{ Parameter = '-Confirm'; Description = 'Request native PowerShell confirmation for managed changes.' }
        [pscustomobject]@{ Parameter = '-Help, --Help, -h, /?'; Description = 'Display complete installer help.' }
    )
}

function Get-CommandReferenceData {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1'; Description = 'Open the interactive main menu.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -NonInteractive'; Description = 'Install missing files and skip modified files.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -Force'; Description = 'Install or update without conflict prompts.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -WhatIf'; Description = 'Preview installation and update operations.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -Validate'; Description = 'Validate all managed files.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -Backup'; Description = 'Create a timestamped backup set.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -ShowTree'; Description = 'Show the framework directory tree.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -ExportHelp All'; Description = 'Export Markdown and HTML documentation.' }
        [pscustomobject]@{ Command = '.\New-BuFuProfile.ps1 -Help'; Description = 'Display complete help.' }
        [pscustomobject]@{ Command = 'Get-Help .\New-BuFuProfile.ps1 -Full'; Description = 'Use native comment-based PowerShell help.' }
    )
}

function Get-KeyboardShortcutData {
    [CmdletBinding()]
    param()
    @(
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'V'; Action = 'View differences.' }
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'O'; Action = 'Overwrite the current file.' }
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'B'; Action = 'Back up and overwrite the current file.' }
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'S'; Action = 'Skip the current file.' }
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'A'; Action = 'Overwrite all remaining conflicts.' }
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'K'; Action = 'Skip all remaining conflicts.' }
        [pscustomobject]@{ Context = 'Conflict menu'; Key = 'Q'; Action = 'Quit the current operation.' }
        [pscustomobject]@{ Context = 'PSReadLine'; Key = 'Tab'; Action = 'Menu completion.' }
        [pscustomobject]@{ Context = 'PSReadLine'; Key = 'Ctrl+R'; Action = 'Reverse history search.' }
        [pscustomobject]@{ Context = 'PSReadLine'; Key = 'Ctrl+L'; Action = 'Clear screen.' }
        [pscustomobject]@{ Context = 'PSReadLine'; Key = 'Ctrl+Left'; Action = 'Move backward one word.' }
        [pscustomobject]@{ Context = 'PSReadLine'; Key = 'Ctrl+Right'; Action = 'Move forward one word.' }
    )
}

function Get-ExpectedDirectoryTreeText {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    @"
$FrameworkDirectoryName
├── aliases
├── archive
├── cache
├── completions
├── config
├── docs
│   ├── html
│   └── markdown
├── functions
├── hosts
├── integrations
├── lib
├── logs
├── modules
├── private
└── themes
"@
}

function Get-TroubleshootingText {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    @'
1. Loader not found
   Confirm that BuFuProfile\lib\Loader.ps1 exists, then run validation.
2. A managed file is reported as Modified
   Run the installer interactively, view the diff, and choose overwrite,
   backup + overwrite, or skip.
3. A managed file is reported as Missing
   Run the installer normally or use -WhatIf first to preview creation.
4. Profile fails to load
   Start a clean shell:
       pwsh -NoProfile
   Then parse and validate:
       .\New-BuFuProfile.ps1 -Validate
5. Execution policy blocks profile scripts
   Inspect the effective policies:
       Get-ExecutionPolicy -List
6. Duplicate imports or repeated startup output
   Confirm that the bootstrap exists only in the intended CurrentUser profiles.
7. WhatIf appears to make no changes
   This is expected. -WhatIf previews operations and never writes files.
8. Restore a backup
   Browse BuFuProfile\archive, select the desired timestamped backup set,
   and copy the saved file back to its original relative location.
'@
}

function Show-FirstRunGuide {
    [CmdletBinding()]
    param()
    Write-SectionHeader -Title 'BuFuProfile First-Run Guide'
    $guide = @"
1. Preview the installation:
   .\New-BuFuProfile.ps1 -WhatIf
2. Run the installer:
   .\New-BuFuProfile.ps1 -NonInteractive
   Or launch the interactive menu:
   .\New-BuFuProfile.ps1
3. Validate managed files:
   .\New-BuFuProfile.ps1 -Validate
4. Start a clean PowerShell session:
   pwsh -NoLogo
5. Test the loaded framework:
   Test-BuFuProfile
6. Open the runtime Help Center:
   Show-BuFuProfileHelpCenter
Framework root:
   $frameworkRoot
Backup root:
   $archiveRoot
"@
    Write-Host $guide
}

function Show-DirectoryTree {
    [CmdletBinding()]
    param(
        [string]$Path = $frameworkRoot,
        [ValidateRange(1, 20)]
        [int]$MaxDepth = 6
    )
    Write-SectionHeader -Title 'BuFuProfile Directory Tree'
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Status -Type Warning -Message "Directory does not exist: $Path"
        Write-Host ''
        Write-Host 'Expected structure:' -ForegroundColor Cyan
        Write-Host (Get-ExpectedDirectoryTreeText)
        return
    }
    Write-Host (Split-Path -Leaf $Path)
    function Write-TreeLevel {
        param(
            [Parameter(Mandatory)]
            [string]$CurrentPath,
            [Parameter(Mandatory)]
            [string]$Prefix,
            [Parameter(Mandatory)]
            [int]$Depth
        )
        if ($Depth -gt $MaxDepth) {
            return
        }
        $items = @(
            Get-ChildItem -LiteralPath $CurrentPath -Force -ErrorAction SilentlyContinue |
                Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
        )
        for ($index = 0; $index -lt $items.Count; $index++) {
            $item = $items[$index]
            $isLast = $index -eq ($items.Count - 1)
            $connector = if ($isLast) { '└── ' } else { '├── ' }
            Write-Host ($Prefix + $connector + $item.Name)
            if ($item.PSIsContainer -and $Depth -lt $MaxDepth) {
                $nextPrefix = $Prefix + $(if ($isLast) { '    ' } else { '│   ' })
                Write-TreeLevel -CurrentPath $item.FullName -Prefix $nextPrefix -Depth ($Depth + 1)
            }
        }
    }
    Write-TreeLevel -CurrentPath $Path -Prefix '' -Depth 1
}

function Show-ParameterHelp {
    [CmdletBinding()]
    param()
    Write-SectionHeader -Title 'BuFuProfile Parameter Help'
    Get-ParameterHelpData | Format-Table -AutoSize -Wrap
}

function Show-TroubleshootingGuide {
    [CmdletBinding()]
    param()
    Write-SectionHeader -Title 'BuFuProfile Troubleshooting Guide'
    Write-Host (Get-TroubleshootingText)
}

function Show-KeyboardShortcuts {
    [CmdletBinding()]
    param()
    Write-SectionHeader -Title 'BuFuProfile Keyboard Shortcuts'
    Get-KeyboardShortcutData | Format-Table -AutoSize -Wrap
}

function Show-CommandReference {
    [CmdletBinding()]
    param()
    Write-SectionHeader -Title 'BuFuProfile Command Reference'
    Get-CommandReferenceData | Format-Table -AutoSize -Wrap
}

function Show-HelpInfo {
    [CmdletBinding()]
    param(
        [ValidateSet(
            'General',
            'Install',
            'Structure',
            'Options',
            'Conflicts',
            'Backup',
            'Validation',
            'Documentation',
            'Troubleshooting'
        )]
        [string]$Topic = 'General'
    )
    $content = switch ($Topic) {
        'General' {
@'
BuFuProfile is a modular PowerShell 7 profile framework with managed
installation, validation, backup, conflict handling, diagnostics, and
documentation export.
'@
        }
        'Install' {
@'
Launching without arguments opens the interactive menu.
Use -WhatIf to preview.
Use -NonInteractive for unattended creation of missing files.
Use -Force to overwrite modified managed files without conflict prompts.
'@
        }
        'Structure' {
            Get-ExpectedDirectoryTreeText
        }
        'Options' {
@'
Use Show-ParameterHelp for the complete parameter table.
Native common parameters include -Verbose, -Debug, -WhatIf, and -Confirm.
'@
        }
        'Conflicts' {
@'
Modified-file actions:
[V] View differences
[O] Overwrite
[B] Backup + overwrite
[S] Skip
[A] Overwrite all remaining conflicts
[K] Skip all remaining conflicts
[Q] Quit
'@
        }
        'Backup' {
@"
Backups are timestamped beneath:
$archiveRoot
Manual backup creates a complete backup set of existing managed files.
Profile overwrite backups preserve the original profile before replacement.
"@
        }
        'Validation' {
@'
Managed files are reported using exactly three states:
Current  - File exists and matches the managed content.
Modified - File exists but differs from the managed content.
Missing  - File does not exist.
'@
        }
        'Documentation' {
@"
Documentation directories:
$(Join-Path $frameworkRoot 'docs\markdown')
$(Join-Path $frameworkRoot 'docs\html')
Use:
  Export-HelpToMarkdown
  Export-HelpToHtml
  .\New-BuFuProfile.ps1 -ExportHelp All
"@
        }
        'Troubleshooting' {
            Get-TroubleshootingText
        }
    }
    Write-SectionHeader -Title "Help Topic: $Topic"
    Write-Host $content
}

function Get-BuFuProfileInfo {
    [CmdletBinding()]
    param()
    $managed = @()
    if (Get-Command Get-ManagedFileManifest -ErrorAction SilentlyContinue) {
        $managed = @(Get-ManagedFileManifest)
    }
    $validationResults = @()
    if ($managed.Count -gt 0) {
        $validationResults = @(
            foreach ($item in $managed) {
                [pscustomobject]@{
                    Status = Get-ManagedFileState -Path $item.Path -ExpectedContent $item.ExpectedContent
                }
            }
        )
    }
    [pscustomobject]@{
        InstallerVersion     = $script:BuFuProfileInstallerVersion
        PowerShellVersion    = $PSVersionTable.PSVersion
        ScriptPath           = $PSCommandPath
        PowerShellRoot       = $PowerShellRoot
        FrameworkRoot        = $frameworkRoot
        ArchiveRoot          = $archiveRoot
        AllHostsProfile      = $allHostsProfile
        CurrentHostProfile   = $currentHostProfile
        FrameworkExists      = Test-Path -LiteralPath $frameworkRoot -PathType Container
        ManagedFileCount     = $managed.Count
        CurrentFileCount     = @($validationResults | Where-Object Status -EQ 'Current').Count
        ModifiedFileCount    = @($validationResults | Where-Object Status -EQ 'Modified').Count
        MissingFileCount     = @($validationResults | Where-Object Status -EQ 'Missing').Count
        InteractiveConsole   = Test-InteractiveConsole
    }
}

function Get-HelpMarkdownContent {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $parameterRows = Get-ParameterHelpData | ForEach-Object {
        '| `{0}` | {1} |' -f $_.Parameter, ($_.Description -replace '\|', '\|')
    }
    $commandRows = Get-CommandReferenceData | ForEach-Object {
        '| `{0}` | {1} |' -f $_.Command, ($_.Description -replace '\|', '\|')
    }
    $shortcutRows = Get-KeyboardShortcutData | ForEach-Object {
        '| {0} | `{1}` | {2} |' -f $_.Context, $_.Key, ($_.Action -replace '\|', '\|')
    }
    $tree = Get-ExpectedDirectoryTreeText
    $troubleshooting = Get-TroubleshootingText
    @"
# BuFuProfile Help
Generated by New-BuFuProfile.ps1 version $script:BuFuProfileInstallerVersion.
## Overview
BuFuProfile is a modular PowerShell 7 profile framework with interactive
installation, managed-file conflict handling, validation, timestamped backups,
and documentation export.
## First Run
~~~powershell
.\New-BuFuProfile.ps1 -WhatIf
.\New-BuFuProfile.ps1
.\New-BuFuProfile.ps1 -Validate
~~~
## Directory Structure
~~~text
$tree
~~~
## Parameters
| Parameter | Description |
|---|---|
$($parameterRows -join "`n")
## Conflict Actions
| Key | Action |
|---|---|
| `V` | View differences |
| `O` | Overwrite |
| `B` | Backup and overwrite |
| `S` | Skip |
| `A` | Overwrite all remaining conflicts |
| `K` | Skip all remaining conflicts |
| `Q` | Quit |
## Validation States
- **Current**: the file exists and matches the managed content.
- **Modified**: the file exists but differs from the managed content.
- **Missing**: the file does not exist.
## Backup Location
~~~text
$archiveRoot
~~~
## Command Reference
| Command | Description |
|---|---|
$($commandRows -join "`n")
## Keyboard Shortcuts
| Context | Key | Action |
|---|---|---|
$($shortcutRows -join "`n")
## Troubleshooting
~~~text
$troubleshooting
~~~
"@
}

function Export-HelpToMarkdown {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([IO.FileInfo])]
    param(
        [string]$Path = (
            Join-Path $frameworkRoot 'docs\markdown\New-BuFuProfile-Help.md'
        ),
        [switch]$PassThru
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($parent, 'Create documentation directory')) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Export Markdown help')) {
        Set-Content -LiteralPath $Path -Value (Get-HelpMarkdownContent) -Encoding utf8
        Write-Status -Type Success -Message "Exported Markdown help: $Path"
        if ($PassThru) {
            return Get-Item -LiteralPath $Path
        }
    }
}

function Export-HelpToHtml {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([IO.FileInfo])]
    param(
        [string]$Path = (
            Join-Path $frameworkRoot 'docs\html\New-BuFuProfile-Help.html'
        ),
        [switch]$PassThru
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($parent, 'Create documentation directory')) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }
    $encodedMarkdown = [Net.WebUtility]::HtmlEncode((Get-HelpMarkdownContent))
    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BuFuProfile Help</title>
<style>
body { font-family: Consolas, "Cascadia Code", monospace; line-height: 1.5; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; background: #111827; color: #e5e7eb; }
h1 { color: #67e8f9; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #0b1220; border: 1px solid #334155; border-radius: 8px; padding: 1rem; }
</style>
</head>
<body>
<h1>BuFuProfile Help</h1>
<pre>$encodedMarkdown</pre>
</body>
</html>
"@
    if ($PSCmdlet.ShouldProcess($Path, 'Export HTML help')) {
        Set-Content -LiteralPath $Path -Value $html -Encoding utf8
        Write-Status -Type Success -Message "Exported HTML help: $Path"
        if ($PassThru) {
            return Get-Item -LiteralPath $Path
        }
    }
}

function Show-CompleteHelp {
    [CmdletBinding()]
    param()
    Write-SectionHeader -Title 'BuFuProfile Complete Help'
    Write-Host 'A modular PowerShell profile framework installer and manager.'
    Write-Host ''
    Show-FirstRunGuide
    Show-ParameterHelp
    Show-CommandReference
    Show-KeyboardShortcuts
    Show-HelpInfo -Topic Conflicts
    Show-HelpInfo -Topic Validation
    Show-HelpInfo -Topic Backup
    Show-TroubleshootingGuide
}

function Show-HelpTopicMenu {
    [CmdletBinding()]
    param()
    while ($true) {
        Clear-BuFuScreen
        Write-SectionHeader -Title 'BuFuProfile Help Topics'
        Write-Host '[1] General'
        Write-Host '[2] Install'
        Write-Host '[3] Structure'
        Write-Host '[4] Options'
        Write-Host '[5] Conflicts'
        Write-Host '[6] Backup'
        Write-Host '[7] Validation'
        Write-Host '[8] Documentation'
        Write-Host '[9] Troubleshooting'
        Write-Host '[B] Back'
        Write-Host ''
        $choice = (Read-Host 'Selection').Trim().ToUpperInvariant()
        $topic = switch ($choice) {
            '1' { 'General' }
            '2' { 'Install' }
            '3' { 'Structure' }
            '4' { 'Options' }
            '5' { 'Conflicts' }
            '6' { 'Backup' }
            '7' { 'Validation' }
            '8' { 'Documentation' }
            '9' { 'Troubleshooting' }
            'B' { return }
            default { $null }
        }
        if ($topic) {
            Clear-BuFuScreen
            Show-HelpInfo -Topic $topic
            Pause-BuFuMenu
        }
        else {
            Write-Status -Type Warning -Message 'Invalid selection.'
            Pause-BuFuMenu
        }
    }
}

function Show-BuFuProfileHelpCenter {
    [CmdletBinding()]
    param()
    if (-not (Test-InteractiveConsole)) {
        Show-CompleteHelp
        return
    }
    while ($true) {
        Clear-BuFuScreen
        Write-SectionHeader -Title 'BuFuProfile Help Center'
        Write-Host '[1] First-run guide'
        Write-Host '[2] Directory tree'
        Write-Host '[3] Parameter help'
        Write-Host '[4] Troubleshooting guide'
        Write-Host '[5] Keyboard shortcuts'
        Write-Host '[6] Command reference'
        Write-Host '[7] Browse help topics'
        Write-Host '[8] Complete help'
        Write-Host '[9] Framework information'
        Write-Host '[M] Export Markdown documentation'
        Write-Host '[H] Export HTML documentation'
        Write-Host '[A] Export all documentation'
        Write-Host '[B] Back'
        Write-Host ''
        $choice = (Read-Host 'Selection').Trim().ToUpperInvariant()
        Clear-BuFuScreen
        switch ($choice) {
            '1' { Show-FirstRunGuide; Pause-BuFuMenu }
            '2' { Show-DirectoryTree; Pause-BuFuMenu }
            '3' { Show-ParameterHelp; Pause-BuFuMenu }
            '4' { Show-TroubleshootingGuide; Pause-BuFuMenu }
            '5' { Show-KeyboardShortcuts; Pause-BuFuMenu }
            '6' { Show-CommandReference; Pause-BuFuMenu }
            '7' { Show-HelpTopicMenu }
            '8' { Show-CompleteHelp; Pause-BuFuMenu }
            '9' { Write-SectionHeader -Title 'BuFuProfile Information'; Get-BuFuProfileInfo | Format-List; Pause-BuFuMenu }
            'M' { Export-HelpToMarkdown; Pause-BuFuMenu }
            'H' { Export-HelpToHtml; Pause-BuFuMenu }
            'A' { Export-HelpToMarkdown; Export-HelpToHtml; Pause-BuFuMenu }
            'B' { return }
            default { Write-Status -Type Warning -Message 'Invalid selection.'; Pause-BuFuMenu }
        }
    }
}
#endregion
#==================================================================#
#region --- Scaffold file contents ---
#==================================================================#
$files = [ordered]@{
    'config\Settings.ps1'               = @'
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
    'config\Paths.ps1'                  = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

if (-not $global:BuFuProfileRoot) {
    throw 'BuFuProfileRoot has not been initialized.'
}

function global:Get-ProfileRoot {
    <#
        .SYNOPSIS
            Returns the BuFuProfile root directory.
        .DESCRIPTION
            Uses $global:BuFuProfileRoot when configured. If the variable has
            not been initialized, the parent directory of the current user's
            AllHosts profile is used.
        .PARAMETER Resolve
            Returns the provider-resolved absolute path.
        .EXAMPLE
            Get-ProfileRoot
        .EXAMPLE
            Get-ProfileRoot -Resolve
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$Resolve
    )
    $rootVariable = Get-Variable `
        -Name 'BuFuProfileRoot' `
        -Scope Global `
        -ErrorAction SilentlyContinue
    $root = if (
        $null -ne $rootVariable -and
        -not [string]::IsNullOrWhiteSpace([string]$rootVariable.Value)
    ) {
        [string]$rootVariable.Value
    } else {
        Split-Path -Parent $PROFILE.CurrentUserAllHosts
    }
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'Unable to determine the BuFuProfile root directory.'
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "BuFuProfile root directory was not found: $root"
    }
    $resolvedRoot = (
        Resolve-Path -LiteralPath $root -ErrorAction Stop
    ).ProviderPath
    # Cache the resolved value for subsequent commands.
    $global:BuFuProfileRoot = $resolvedRoot
    if ($Resolve) {
        return $resolvedRoot
    }
    return $global:BuFuProfileRoot
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
    'config\Environment.ps1'            = @'
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

    'lib\Loader.ps1'                    = @'
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
    'lib\Console.ps1'                   = @'
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
    'lib\Platform.ps1'                  = @'
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
    'lib\Modules.ps1'                   = @'
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
    'lib\Timing.ps1'                    = @'
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

    'functions\Profile-Management.ps1'  = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Get-ProfileRoot {
    <#
        .SYNOPSIS
            Returns the configured BuFuProfile root directory.
        .PARAMETER Resolve
            Returns the provider-resolved absolute path.
        .EXAMPLE
            Get-ProfileRoot
        .EXAMPLE
            Get-ProfileRoot -Resolve
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$Resolve
    )
    $rootVariable = Get-Variable `
        -Name 'BuFuProfileRoot' `
        -Scope Global `
        -ErrorAction SilentlyContinue
    if ($null -eq $rootVariable -or
        [string]::IsNullOrWhiteSpace([string]$rootVariable.Value)) {
        throw '$global:BuFuProfileRoot is not configured.'
    }
    $root = [string]$rootVariable.Value
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "BuFuProfile root directory was not found: $root"
    }
    if ($Resolve) {
        return (Resolve-Path -LiteralPath $root -ErrorAction Stop).ProviderPath
    }
    return $root
}

function global:Reload-Profile {
    <#
        .SYNOPSIS
            Reloads the current user's PowerShell profiles.
        .DESCRIPTION
            Dot-sources CurrentUserAllHosts followed by
            CurrentUserCurrentHost when those files exist.
        .PARAMETER Clear
            Clears the terminal before reloading the profiles.
        .PARAMETER SkipCurrentHost
            Reloads CurrentUserAllHosts but skips CurrentUserCurrentHost.
        .EXAMPLE
            Reload-Profile
        .EXAMPLE
            Reload-Profile -Clear
        .EXAMPLE
            Reload-Profile -SkipCurrentHost
    #>
    [CmdletBinding()]
    param(
        [switch]$Clear,
        [switch]$SkipCurrentHost
    )
    if ($Clear) {
        Clear-Host
    }
    $profilePaths = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts -PathType Leaf) {
        $profilePaths.Add($PROFILE.CurrentUserAllHosts)
    }
    else {
        Write-Warning (
            'CurrentUserAllHosts profile was not found: {0}' -f
            $PROFILE.CurrentUserAllHosts
        )
    }
    if (-not $SkipCurrentHost -and
        (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost -PathType Leaf)) {
        $allHostsFullPath = [System.IO.Path]::GetFullPath(
            $PROFILE.CurrentUserAllHosts
        )
        $currentHostFullPath = [System.IO.Path]::GetFullPath(
            $PROFILE.CurrentUserCurrentHost
        )
        if (-not $currentHostFullPath.Equals(
                $allHostsFullPath,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            $profilePaths.Add($PROFILE.CurrentUserCurrentHost)
        }
    }
    foreach ($profilePath in $profilePaths) {
        Write-Verbose "Reloading profile: $profilePath"
        try {
            . $profilePath
        }
        catch {
            $message = 'Failed to reload profile "{0}": {1}' -f (
                $profilePath,
                $_.Exception.Message
            )
            $exception = [System.InvalidOperationException]::new(
                $message,
                $_.Exception
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'BuFuProfileReloadFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $profilePath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
    Write-Host (
        'Reloaded {0} PowerShell profile file(s).' -f $profilePaths.Count
    ) -ForegroundColor Green
}

function global:Edit-Profile {
    <#
        .SYNOPSIS
            Opens a BuFuProfile file or directory in a supported editor.
        .PARAMETER Target
            Identifies the profile file or framework directory to open.
        .EXAMPLE
            Edit-Profile
        .EXAMPLE
            Edit-Profile -Target Functions
        .EXAMPLE
            Edit-Profile -Target Settings
    #>
    [CmdletBinding()]
    param(
        [ValidateSet(
            'Root',
            'AllHosts',
            'CurrentHost',
            'Settings',
            'Environment',
            'Paths',
            'Functions',
            'Aliases',
            'Modules',
            'Integrations',
            'Private'
        )]
        [string]$Target = 'Root'
    )
    $root = Get-ProfileRoot -Resolve
    $path = switch ($Target) {
        'Root'          { $root }
        'AllHosts'      { $PROFILE.CurrentUserAllHosts }
        'CurrentHost'   { $PROFILE.CurrentUserCurrentHost }
        'Settings'      { Join-Path $root 'config\Settings.ps1' }
        'Environment'   { Join-Path $root 'config\Environment.ps1' }
        'Paths'         { Join-Path $root 'config\Paths.ps1' }
        'Functions'     { Join-Path $root 'functions' }
        'Aliases'       { Join-Path $root 'aliases' }
        'Modules'       { Join-Path $root 'modules' }
        'Integrations'  { Join-Path $root 'integrations' }
        'Private'       { Join-Path $root 'private' }
    }
    $isDirectoryTarget = $Target -in @(
        'Root',
        'Functions',
        'Aliases',
        'Modules',
        'Integrations',
        'Private'
    )
    if ($isDirectoryTarget) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Profile directory was not found: $path"
        }
    }
    else {
        $parentDirectory = Split-Path -Parent $path
        if (-not [string]::IsNullOrWhiteSpace($parentDirectory) -and
            -not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
            throw "Parent directory was not found: $parentDirectory"
        }
    }
    $codeCommand = Get-Command 'code' -ErrorAction SilentlyContinue
    if ($null -ne $codeCommand) {
        & $codeCommand.Source --reuse-window $path
        return
    }
    if ($IsWindows) {
        if ($isDirectoryTarget) {
            $explorerCommand = Get-Command 'explorer.exe' `
                -ErrorAction SilentlyContinue
            if ($null -ne $explorerCommand) {
                & $explorerCommand.Source $path
                return
            }
        }
        else {
            $notepadCommand = Get-Command 'notepad.exe' `
                -ErrorAction SilentlyContinue
            if ($null -ne $notepadCommand) {
                & $notepadCommand.Source $path
                return
            }
        }
    }
    if ($IsMacOS) {
        $openCommand = Get-Command 'open' -ErrorAction SilentlyContinue
        if ($null -ne $openCommand) {
            & $openCommand.Source $path
            return
        }
    }
    if ($IsLinux) {
        $xdgOpenCommand = Get-Command 'xdg-open' `
            -ErrorAction SilentlyContinue
        if ($null -ne $xdgOpenCommand) {
            & $xdgOpenCommand.Source $path
            return
        }
    }
    throw "No supported editor or file browser was found for: $path"
}

function global:Show-ProfileFiles {
    <#
        .SYNOPSIS
            Lists the PowerShell files managed by BuFuProfile.
        .PARAMETER Extension
            File extensions to include.
        .PARAMETER IncludeArchive
            Includes files stored under the archive directory.
        .EXAMPLE
            Show-ProfileFiles
        .EXAMPLE
            Show-ProfileFiles -Extension '.ps1', '.psm1'
        .EXAMPLE
            Show-ProfileFiles -IncludeArchive
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('.ps1', '.psm1', '.psd1')]
        [string[]]$Extension = @(
            '.ps1',
            '.psm1',
            '.psd1'
        ),
        [switch]$IncludeArchive
    )
    $root = Get-ProfileRoot -Resolve
    $files = @(
        Get-ChildItem `
            -LiteralPath $root `
            -File `
            -Recurse `
            -ErrorAction Stop |
            Where-Object {
                if ($_.Extension -notin $Extension) {
                    return $false
                }
                if ($IncludeArchive) {
                    return $true
                }
                $relativePath = [System.IO.Path]::GetRelativePath(
                    $root,
                    $_.FullName
                )
                $pathSegments = $relativePath -split '[\\/]'
                return 'archive' -notin $pathSegments
            } |
            Sort-Object FullName
    )
    foreach ($file in $files) {
        [pscustomobject]@{
            PSTypeName   = 'BuFuProfile.FileInfo'
            RelativePath = [System.IO.Path]::GetRelativePath(
                $root,
                $file.FullName
            )
            Extension    = $file.Extension
            Length       = $file.Length
            LastWriteTime = $file.LastWriteTime
            FullName     = $file.FullName
        }
    }
}

function global:Test-BuFuProfile {
    <#
        .SYNOPSIS
            Validates BuFuProfile files with PowerShell's native parser.
        .DESCRIPTION
            Recursively parses PowerShell scripts, modules, and data files
            without executing them.

            Files under the archive directory are excluded by default so that
            historical backups do not cause the current profile validation to
            fail.
        .PARAMETER Path
            Root directory to validate.

            Defaults to $global:BuFuProfileRoot.
        .PARAMETER Extension
            PowerShell file extensions to validate.
        .PARAMETER IncludeArchive
            Includes files stored under an archive directory.
        .PARAMETER PassThru
            Returns a detailed validation result rather than a Boolean value.
        .PARAMETER Quiet
            Suppresses status and error-table output.
        .EXAMPLE
            Test-BuFuProfile
        .EXAMPLE
            Test-BuFuProfile -PassThru
        .EXAMPLE
            Test-BuFuProfile -Extension '.ps1'
        .EXAMPLE
            Test-BuFuProfile -IncludeArchive -PassThru
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [ValidateSet('.ps1', '.psm1', '.psd1')]
        [string[]]$Extension = @(
            '.ps1',
            '.psm1',
            '.psd1'
        ),
        [switch]$IncludeArchive,
        [switch]$PassThru,
        [switch]$Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Path')) {
        $Path = Get-ProfileRoot -Resolve
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        $message = "BuFuProfile directory was not found: $Path"
        if ($PassThru) {
            return [pscustomobject]@{
                PSTypeName       = 'BuFuProfile.ValidationResult'
                Path             = $Path
                IsValid          = $false
                FileCount        = 0
                ValidFileCount   = 0
                InvalidFileCount = 0
                ErrorCount       = 1
                Files            = @()
                Errors           = @(
                    [pscustomobject]@{
                        PSTypeName      = 'BuFuProfile.ValidationError'
                        File            = $Path
                        RelativePath    = $null
                        Line            = $null
                        Column          = $null
                        EndLine         = $null
                        EndColumn       = $null
                        ErrorId         = 'ProfileRootNotFound'
                        Message         = $message
                        Text            = $null
                        IncompleteInput = $false
                    }
                )
                ValidatedAt      = Get-Date
            }
        }
        Write-Error $message
        return $false
    }
    $resolvedPath = (
        Resolve-Path -LiteralPath $Path -ErrorAction Stop
    ).ProviderPath
    $errors = [System.Collections.Generic.List[object]]::new()
    try {
        $files = @(
            Get-ChildItem `
                -LiteralPath $resolvedPath `
                -File `
                -Recurse `
                -ErrorAction Stop |
                Where-Object {
                    if ($_.Extension -notin $Extension) {
                        return $false
                    }
                    if ($IncludeArchive) {
                        return $true
                    }
                    $relativePath = [System.IO.Path]::GetRelativePath(
                        $resolvedPath,
                        $_.FullName
                    )
                    $pathSegments = $relativePath -split '[\\/]'
                    return 'archive' -notin $pathSegments
                } |
                Sort-Object FullName
        )
    }
    catch {
        $message = 'Unable to enumerate profile files: {0}' -f (
            $_.Exception.Message
        )
        if (-not $Quiet) {
            Write-Error $message
        }
        if ($PassThru) {
            return [pscustomobject]@{
                PSTypeName       = 'BuFuProfile.ValidationResult'
                Path             = $resolvedPath
                IsValid          = $false
                FileCount        = 0
                ValidFileCount   = 0
                InvalidFileCount = 0
                ErrorCount       = 1
                Files            = @()
                Errors           = @(
                    [pscustomobject]@{
                        PSTypeName      = 'BuFuProfile.ValidationError'
                        File            = $resolvedPath
                        RelativePath    = $null
                        Line            = $null
                        Column          = $null
                        EndLine         = $null
                        EndColumn       = $null
                        ErrorId         = 'FileEnumerationFailed'
                        Message         = $message
                        Text            = $null
                        IncompleteInput = $false
                    }
                )
                ValidatedAt      = Get-Date
            }
        }
        return $false
    }
    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        try {
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName,
                [ref]$tokens,
                [ref]$parseErrors
            )
        }
        catch {
            $errors.Add(
                [pscustomobject]@{
                    PSTypeName      = 'BuFuProfile.ValidationError'
                    File            = $file.FullName
                    RelativePath    = [System.IO.Path]::GetRelativePath(
                        $resolvedPath,
                        $file.FullName
                    )
                    Line            = $null
                    Column          = $null
                    EndLine         = $null
                    EndColumn       = $null
                    ErrorId         = 'ParserInvocationFailed'
                    Message         = $_.Exception.Message
                    Text            = $null
                    IncompleteInput = $false
                }
            )
            continue
        }
        foreach ($parseError in @($parseErrors)) {
            $errors.Add(
                [pscustomobject]@{
                    PSTypeName      = 'BuFuProfile.ParseError'
                    File            = $file.FullName
                    RelativePath    = [System.IO.Path]::GetRelativePath(
                        $resolvedPath,
                        $file.FullName
                    )
                    Line            = $parseError.Extent.StartLineNumber
                    Column          = $parseError.Extent.StartColumnNumber
                    EndLine         = $parseError.Extent.EndLineNumber
                    EndColumn       = $parseError.Extent.EndColumnNumber
                    ErrorId         = $parseError.ErrorId
                    Message         = $parseError.Message
                    Text            = $parseError.Extent.Text
                    IncompleteInput = $parseError.IncompleteInput
                }
            )
        }
    }
    $invalidFiles = @(
        $errors |
            Select-Object -ExpandProperty File -Unique
    )
    $isValid = $errors.Count -eq 0
    $result = [pscustomobject]@{
        PSTypeName       = 'BuFuProfile.ValidationResult'
        Path             = $resolvedPath
        IsValid          = $isValid
        FileCount        = $files.Count
        ValidFileCount   = $files.Count - $invalidFiles.Count
        InvalidFileCount = $invalidFiles.Count
        ErrorCount       = $errors.Count
        Files            = @($files.FullName)
        Errors           = @($errors)
        ValidatedAt      = Get-Date
    }
    if (-not $Quiet) {
        if ($files.Count -eq 0) {
            Write-Warning (
                'No matching PowerShell files were found under: {0}' -f
                $resolvedPath
            )
        }
        elseif ($isValid) {
            Write-Host (
                'All {0} BuFuProfile file(s) parsed successfully.' -f
                $files.Count
            ) -ForegroundColor Green
        }
        else {
            Write-Host (
                'BuFuProfile validation failed with {0} error(s) in ' +
                '{1} file(s).'
            ) -f (
                $result.ErrorCount,
                $result.InvalidFileCount
            ) -ForegroundColor Red
            $errors |
                Select-Object `
                    RelativePath,
                    Line,
                    Column,
                    ErrorId,
                    Message |
                Format-Table -AutoSize -Wrap |
                Out-Host
        }
    }
    if ($PassThru) {
        return $result
    }
    return $isValid
}
'@
    'functions\Terminal.ps1'            = @'
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
    'functions\Theme.ps1'               = @'
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
    'functions\OhMyPosh.ps1'            = @'
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
    'functions\Help.ps1'                = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

function global:Write-BuFuHelpHeader {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * [Math]::Min(78, [Math]::Max(30, $Title.Length))) -ForegroundColor DarkCyan
}

function global:Get-BuFuProfileInfo {
    [CmdletBinding()]
    param()
    $root = $global:BuFuProfileRoot
    $scriptFiles = if (Test-Path -LiteralPath $root -PathType Container) {
        @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue)
    }
    else {
        @()
    }
    [pscustomobject]@{
        FrameworkName      = 'BuFuProfile'
        FrameworkVersion   = '2.0.0'
        PowerShellVersion  = $PSVersionTable.PSVersion
        FrameworkRoot      = $root
        ArchiveRoot        = if ($global:BuFuPaths) { $global:BuFuPaths.Archive } else { Join-Path $root 'archive' }
        DocumentationRoot  = if ($global:BuFuPaths -and $global:BuFuPaths.Docs) { $global:BuFuPaths.Docs } else { Join-Path $root 'docs' }
        ScriptFileCount    = $scriptFiles.Count
        ProfileLoadTimeMs  = $global:BuFuProfileLoadTime
        ProfileLoadErrors  = if (Get-Command Get-ProfileLoadError -ErrorAction SilentlyContinue) { @(Get-ProfileLoadError).Count } else { 0 }
    }
}

function global:Show-FirstRunGuide {
    [CmdletBinding()]
    param()
    Write-BuFuHelpHeader -Title 'BuFuProfile First-Run Guide'
    $guide = @"
1. Reload the profile:
   Reload-Profile
2. Validate every profile script:
   Test-BuFuProfile
3. Display framework information:
   Get-BuFuProfileInfo
4. Review generated files:
   Show-ProfileFiles
5. Open the Help Center:
   Show-BuFuProfileHelpCenter
6. Export documentation:
   Export-HelpToMarkdown
   Export-HelpToHtml
"@
    Write-Host $guide
}

function global:Show-DirectoryTree {
    [CmdletBinding()]
    param(
        [string]$Path = $global:BuFuProfileRoot,
        [ValidateRange(1, 20)]
        [int]$MaxDepth = 6
    )
    Write-BuFuHelpHeader -Title 'BuFuProfile Directory Tree'
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Directory not found: $Path"
        return
    }
    Write-Host (Split-Path -Leaf $Path)
    function Write-TreeLevel {
        param([string]$CurrentPath,[string]$Prefix,[int]$Depth)
        if ($Depth -gt $MaxDepth) { return }
        $items = @(
            Get-ChildItem -LiteralPath $CurrentPath -Force -ErrorAction SilentlyContinue |
                Sort-Object @{Expression={-not $_.PSIsContainer}}, Name
        )
        for ($index = 0; $index -lt $items.Count; $index++) {
            $item = $items[$index]
            $last = $index -eq ($items.Count - 1)
            $connector = if ($last) { '└── ' } else { '├── ' }
            Write-Host ($Prefix + $connector + $item.Name)
            if ($item.PSIsContainer -and $Depth -lt $MaxDepth) {
                $nextPrefix = $Prefix + $(if ($last) { '    ' } else { '│   ' })
                Write-TreeLevel -CurrentPath $item.FullName -Prefix $nextPrefix -Depth ($Depth + 1)
            }
        }
    }
    Write-TreeLevel -CurrentPath $Path -Prefix '' -Depth 1
}

function global:Show-ParameterHelp {
    [CmdletBinding()]
    param()
    Write-BuFuHelpHeader -Title 'New-BuFuProfile Installer Parameters'
    @(
        [pscustomobject]@{Parameter='-Force';Description='Overwrite modified managed files without conflict prompts.'}
        [pscustomobject]@{Parameter='-WhatIf';Description='Preview all filesystem changes.'}
        [pscustomobject]@{Parameter='-Validate';Description='Report Current, Modified, and Missing managed files.'}
        [pscustomobject]@{Parameter='-Backup';Description='Create a timestamped backup set.'}
        [pscustomobject]@{Parameter='-SkipProfileUpdate';Description='Do not modify standard bootstrap profiles.'}
        [pscustomobject]@{Parameter='-SkipBackup';Description='Do not automatically back up modified profiles.'}
        [pscustomobject]@{Parameter='-IncludeExampleFiles';Description='Create example private and completion files.'}
        [pscustomobject]@{Parameter='-ExportHelp Markdown|Html|All';Description='Export documentation.'}
        [pscustomobject]@{Parameter='-Help, --Help, -h, /?';Description='Display complete installer help.'}
    ) | Format-Table -AutoSize -Wrap
}

function global:Show-TroubleshootingGuide {
    [CmdletBinding()]
    param()
    Write-BuFuHelpHeader -Title 'BuFuProfile Troubleshooting Guide'
    $guide = @"
Loader not found:
  Confirm that lib\Loader.ps1 exists beneath BuFuProfile.
Profile parse errors:
  Run Test-BuFuProfile and inspect the returned file, line, and column.
Profile startup errors:
  Run Get-ProfileLoadError and Get-ProfileLoadResult.
Framework path problems:
  Run Get-BuFuProfileInfo and confirm FrameworkRoot.
Modified managed files:
  Run New-BuFuProfile.ps1 interactively and use V to inspect differences.
Restore:
  Browse the timestamped backup sets beneath BuFuProfile\archive.
"@
    Write-Host $guide
}

function global:Show-KeyboardShortcuts {
    [CmdletBinding()]
    param()
    Write-BuFuHelpHeader -Title 'BuFuProfile Keyboard Shortcuts'
    @(
        [pscustomobject]@{Context='PSReadLine';Key='Tab';Action='Menu completion'}
        [pscustomobject]@{Context='PSReadLine';Key='Ctrl+R';Action='Reverse history search'}
        [pscustomobject]@{Context='PSReadLine';Key='Ctrl+L';Action='Clear screen'}
        [pscustomobject]@{Context='PSReadLine';Key='Ctrl+Left';Action='Move backward one word'}
        [pscustomobject]@{Context='PSReadLine';Key='Ctrl+Right';Action='Move forward one word'}
        [pscustomobject]@{Context='Installer conflict';Key='V';Action='View differences'}
        [pscustomobject]@{Context='Installer conflict';Key='O';Action='Overwrite'}
        [pscustomobject]@{Context='Installer conflict';Key='B';Action='Backup and overwrite'}
        [pscustomobject]@{Context='Installer conflict';Key='S';Action='Skip'}
        [pscustomobject]@{Context='Installer conflict';Key='Q';Action='Quit'}
    ) | Format-Table -AutoSize -Wrap
}

function global:Show-CommandReference {
    [CmdletBinding()]
    param()
    Write-BuFuHelpHeader -Title 'BuFuProfile Command Reference'
    @(
        [pscustomobject]@{Command='Reload-Profile';Description='Reload all-host and current-host profiles.'}
        [pscustomobject]@{Command='Edit-Profile';Description='Open a framework file or directory in an editor.'}
        [pscustomobject]@{Command='Show-ProfileFiles';Description='List framework PowerShell files.'}
        [pscustomobject]@{Command='Test-BuFuProfile';Description='Parse every framework PowerShell script.'}
        [pscustomobject]@{Command='Get-ProfileLoadResult';Description='Show profile section timing and status.'}
        [pscustomobject]@{Command='Get-ProfileLoadError';Description='Show profile loading errors.'}
        [pscustomobject]@{Command='Get-BuFuProfileInfo';Description='Show framework information.'}
        [pscustomobject]@{Command='Show-BuFuProfileHelpCenter';Description='Open the interactive Help Center.'}
        [pscustomobject]@{Command='Export-HelpToMarkdown';Description='Export Markdown documentation.'}
        [pscustomobject]@{Command='Export-HelpToHtml';Description='Export HTML documentation.'}
    ) | Format-Table -AutoSize -Wrap
}

function global:Show-HelpInfo {
    [CmdletBinding()]
    param(
        [ValidateSet('General','Structure','Commands','Shortcuts','Troubleshooting','Documentation')]
        [string]$Topic = 'General'
    )
    switch ($Topic) {
        'General' {
            Write-BuFuHelpHeader -Title 'BuFuProfile Help'
            Write-Host 'A modular PowerShell 7 profile framework with diagnostics, backups, and documentation.'
        }
        'Structure' { Show-DirectoryTree }
        'Commands' { Show-CommandReference }
        'Shortcuts' { Show-KeyboardShortcuts }
        'Troubleshooting' { Show-TroubleshootingGuide }
        'Documentation' {
            Write-BuFuHelpHeader -Title 'BuFuProfile Documentation'
            Write-Host "Markdown: $($global:BuFuPaths.DocsMarkdown)"
            Write-Host "HTML:     $($global:BuFuPaths.DocsHtml)"
        }
    }
}

function global:Get-BuFuHelpMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $info = Get-BuFuProfileInfo | Format-List | Out-String
    @"
# BuFuProfile Help
## Framework Information
~~~text
$($info.Trim())
~~~
## Core Commands
- `Reload-Profile`
- `Edit-Profile`
- `Show-ProfileFiles`
- `Test-BuFuProfile`
- `Get-ProfileLoadResult`
- `Get-ProfileLoadError`
- `Get-BuFuProfileInfo`
- `Show-BuFuProfileHelpCenter`
- `Export-HelpToMarkdown`
- `Export-HelpToHtml`
## Directory Structure
- aliases
- archive
- cache
- completions
- config
- docs
  - html
  - markdown
- functions
- hosts
- integrations
- lib
- logs
- modules
- private
- themes
## Validation
Use the installer with `-Validate` to classify managed files as Current,
Modified, or Missing.
## Backups
Timestamped backups are stored beneath:
~~~text
$($global:BuFuPaths.Archive)
~~~
"@
}

function global:Export-HelpToMarkdown {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = (Join-Path $global:BuFuPaths.DocsMarkdown 'BuFuProfile-Help.md'),
        [switch]$PassThru
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($parent, 'Create documentation directory')) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Export Markdown help')) {
        Set-Content -LiteralPath $Path -Value (Get-BuFuHelpMarkdown) -Encoding utf8
        Write-Host "Exported Markdown help: $Path" -ForegroundColor Green
        if ($PassThru) { Get-Item -LiteralPath $Path }
    }
}

function global:Export-HelpToHtml {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = (Join-Path $global:BuFuPaths.DocsHtml 'BuFuProfile-Help.html'),
        [switch]$PassThru
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($parent, 'Create documentation directory')) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }
    }
    $encoded = [Net.WebUtility]::HtmlEncode((Get-BuFuHelpMarkdown))
    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BuFuProfile Help</title>
<style>
body { font-family: Consolas, monospace; line-height: 1.5; max-width: 1000px; margin: 2rem auto; padding: 0 1rem; background: #111827; color: #e5e7eb; }
h1 { color: #67e8f9; }
pre { white-space: pre-wrap; background: #0b1220; border: 1px solid #334155; border-radius: 8px; padding: 1rem; }
</style>
</head>
<body>
<h1>BuFuProfile Help</h1>
<pre>$encoded</pre>
</body>
</html>
"@
    if ($PSCmdlet.ShouldProcess($Path, 'Export HTML help')) {
        Set-Content -LiteralPath $Path -Value $html -Encoding utf8
        Write-Host "Exported HTML help: $Path" -ForegroundColor Green
        if ($PassThru) { Get-Item -LiteralPath $Path }
    }
}

function global:Show-CompleteHelp {
    [CmdletBinding()]
    param()
    Show-FirstRunGuide
    Show-ParameterHelp
    Show-CommandReference
    Show-KeyboardShortcuts
    Show-TroubleshootingGuide
}

function global:Show-BuFuProfileHelpCenter {
    [CmdletBinding()]
    param()
    while ($true) {
        try { Clear-Host } catch { }
        Write-BuFuHelpHeader -Title 'BuFuProfile Help Center'
        Write-Host '[1] First-run guide'
        Write-Host '[2] Directory tree'
        Write-Host '[3] Parameter help'
        Write-Host '[4] Troubleshooting guide'
        Write-Host '[5] Keyboard shortcuts'
        Write-Host '[6] Command reference'
        Write-Host '[7] Complete help'
        Write-Host '[8] Framework information'
        Write-Host '[M] Export Markdown'
        Write-Host '[H] Export HTML'
        Write-Host '[A] Export both'
        Write-Host '[Q] Quit'
        Write-Host ''
        $choice = (Read-Host 'Selection').Trim().ToUpperInvariant()
        try { Clear-Host } catch { }
        switch ($choice) {
            '1' { Show-FirstRunGuide }
            '2' { Show-DirectoryTree }
            '3' { Show-ParameterHelp }
            '4' { Show-TroubleshootingGuide }
            '5' { Show-KeyboardShortcuts }
            '6' { Show-CommandReference }
            '7' { Show-CompleteHelp }
            '8' { Get-BuFuProfileInfo | Format-List }
            'M' { Export-HelpToMarkdown }
            'H' { Export-HelpToHtml }
            'A' { Export-HelpToMarkdown; Export-HelpToHtml }
            'Q' { return }
            default { Write-Warning 'Invalid selection.' }
        }
        [void](Read-Host 'Press Enter to continue')
    }
}
'@

    'aliases\General.ps1'               = @'
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

    'modules\Common.ps1'                = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$commonModules = @('Terminal-Icons','posh-git','PowerColorLS','ZLocation')
foreach ($moduleName in $commonModules) { [void](Import-IfAvailable -Name $moduleName) }
'@
    'modules\Predictors.ps1'            = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$predictorModules = @('CompletionPredictor','Az.Tools.Predictor','PSCompletions')
[void](Import-FirstAvailableModule -Name $predictorModules)
'@
    'modules\PSReadLine.ps1'            = @'
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
    'modules\PSFzf.ps1'                 = @'
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

    'integrations\Kubernetes.ps1'       = @'
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
    'integrations\Oh-My-Posh.ps1'       = @'
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

    'hosts\Microsoft.PowerShell.ps1'    = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

# Add ConsoleHost or Windows Terminal-specific settings here.
'@
    'hosts\Visual Studio Code Host.ps1' = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

# Add Visual Studio Code PowerShell host-specific settings here.
'@

    'private\.gitignore'                = @'
*
!.gitignore
!Example.ps1
'@

    'logs\.gitkeep'                     = ''
    'cache\.gitkeep'                    = ''

    '.gitignore'                        = @'
archive/
.history/
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
    'docs\README.md'                    = @'
# BuFuProfile Documentation
Generated documentation is stored in:
- `docs/markdown`
- `docs/html`
Export or refresh documentation from PowerShell:
~~~powershell
Export-HelpToMarkdown
Export-HelpToHtml
Show-BuFuProfileHelpCenter
~~~
'@
    'README.md'                         = @'
# BuFuProfile

A modular PowerShell 7 profile framework.

## Core Commands
```powershell
Reload-Profile
Edit-Profile
Show-ProfileFiles
Test-BuFuProfile
Get-ProfileLoadResult
Get-ProfileLoadError
Get-BuFuProfileInfo
Show-BuFuProfileHelpCenter
Export-HelpToMarkdown
Export-HelpToHtml
~~~
## Documentation
Documentation is stored beneath `docs/markdown` and `docs/html`.
## Backups
Timestamped backups are stored beneath `archive`.
'@
}

if ($IncludeExampleFiles) {
    $files['private\Example.ps1']       = @'
#requires -Version 7.4
# Store private local values in this directory.
'@
    $files['completions\Example.ps1']   = @'
#requires -Version 7.4
# Add native argument completers here.
'@
}
#endregion
#==================================================================#
#region --- Profile contents ---
#==================================================================#
$allHostsProfileContent = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$script:PowerShellRoot = Split-Path -Parent $PROFILE.CurrentUserAllHosts
$script:ProfileRoot = Join-Path $script:PowerShellRoot '__FRAMEWORK_DIRECTORY_NAME__'

$global:BuFuProfileRoot = $script:ProfileRoot

if (-not (Test-Path -LiteralPath $global:BuFuProfileRoot -PathType Container)) {
    Write-Warning (
        'BuFuProfile framework directory was not found: {0}' -f
        $global:BuFuProfileRoot
    )
    return
}

$loaderPath = Join-Path $global:BuFuProfileRoot 'lib\Loader.ps1'

if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
    Write-Warning (
        'BuFuProfile loader was not found: {0}' -f
        $loaderPath
    )
    return
}

try {
    . $loaderPath
    $initializeCommand = Get-Command `
        -Name 'Initialize-PowerShellProfile' `
        -CommandType Function `
        -ErrorAction SilentlyContinue
    if ($null -eq $initializeCommand) {
        throw 'Initialize-PowerShellProfile was not defined by the profile loader.'
    }
    Initialize-PowerShellProfile -Root $global:BuFuProfileRoot
} catch {
    Write-Warning 'PowerShell profile initialization failed.'
    Write-Warning (
        '{0}: {1}' -f
        $_.Exception.GetType().FullName,
        $_.Exception.Message
    )
}
'@
$allHostsProfileContent = $allHostsProfileContent.Replace('__FRAMEWORK_DIRECTORY_NAME__', $FrameworkDirectoryName.Replace("'", "''"))

$currentHostProfileContent = @'
#requires -Version 7.4
Set-StrictMode -Version 3.0

$rootVariable = Get-Variable `
    -Name 'BuFuProfileRoot' `
    -Scope Global `
    -ErrorAction SilentlyContinue

if ($null -eq $rootVariable -or
    [string]::IsNullOrWhiteSpace([string]$rootVariable.Value)) {
    $powerShellRoot = Split-Path -Parent $PROFILE.CurrentUserAllHosts
    $global:BuFuProfileRoot = Join-Path `
        $powerShellRoot `
        '__FRAMEWORK_DIRECTORY_NAME__'
}

$hostProfilePath = Join-Path $script:ProfileRoot 'hosts\Microsoft.PowerShell.ps1'
if (Test-Path -LiteralPath $hostProfilePath -PathType Leaf) {
    try { . $hostProfilePath }
    catch { Write-Warning "Failed to load host profile '$hostProfilePath': $($_.Exception.Message)" }
}
'@
$currentHostProfileContent = $currentHostProfileContent.Replace('__FRAMEWORK_DIRECTORY_NAME__', $FrameworkDirectoryName.Replace("'", "''"))
#endregion
#==================================================================#
#region --- Managed manifest, validation, and backup ---
#==================================================================#
function Get-ManagedFileManifest {
    [CmdletBinding()]
    param()
    foreach ($entry in $files.GetEnumerator()) {
        [pscustomobject]@{
            Kind            = 'Framework'
            Name            = $entry.Key
            RelativePath    = $entry.Key
            Path            = Join-Path $frameworkRoot $entry.Key
            ExpectedContent = [string]$entry.Value
        }
    }
    if (-not $SkipProfileUpdate) {
        [pscustomobject]@{
            Kind            = 'Profile'
            Name            = 'CurrentUserAllHosts bootstrap'
            RelativePath    = 'profiles\CurrentUserAllHosts'
            Path            = $allHostsProfile
            ExpectedContent = $allHostsProfileContent
        }
        if ($currentHostProfile -ne $allHostsProfile) {
            [pscustomobject]@{
                Kind            = 'Profile'
                Name            = 'CurrentUserCurrentHost bootstrap'
                RelativePath    = 'profiles\CurrentUserCurrentHost'
                Path            = $currentHostProfile
                ExpectedContent = $currentHostProfileContent
            }
        }
    }
}

function Test-BuFuProfileManagedFiles {
    [CmdletBinding()]
    param(
        [switch]$Display
    )
    $results = @(
        foreach ($item in (Get-ManagedFileManifest)) {
            [pscustomobject]@{
                Status       = Get-ManagedFileState -Path $item.Path -ExpectedContent $item.ExpectedContent
                Kind         = $item.Kind
                ManagedFile  = $item.Name
                Path         = $item.Path
            }
        }
    )
    if ($Display) {
        Write-SectionHeader -Title 'BuFuProfile Managed-File Validation'
        $table = $results |
            Sort-Object Status, Kind, ManagedFile |
            Format-Table Status, Kind, ManagedFile, Path -AutoSize -Wrap |
            Out-String
        Write-Host $table.TrimEnd()
        $currentCount = @($results | Where-Object Status -EQ 'Current').Count
        $modifiedCount = @($results | Where-Object Status -EQ 'Modified').Count
        $missingCount = @($results | Where-Object Status -EQ 'Missing').Count
        Write-Host ''
        Write-Host ('Current : {0}' -f $currentCount) -ForegroundColor Green
        Write-Host ('Modified: {0}' -f $modifiedCount) -ForegroundColor Yellow
        Write-Host ('Missing : {0}' -f $missingCount) -ForegroundColor Red
    }
    return $results
}

function Test-BuFuProfileInstallation {
    [CmdletBinding()]
    param()
    Test-BuFuProfileManagedFiles -Display
}

function Backup-BuFuProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$PassThru
    )
    $backupSetName = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $backupSetRoot = Join-Path $archiveRoot ("{0}_manual" -f $backupSetName)
    $backups = [System.Collections.Generic.List[object]]::new()
    Write-SectionHeader -Title 'BuFuProfile Backup'
    Write-Status -Type Info -Message "Backup set: $backupSetRoot"
    $manifest = @(
        Get-ManagedFileManifest |
            Group-Object Path |
            ForEach-Object { $_.Group | Select-Object -First 1 }
    )
    foreach ($item in $manifest) {
        if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
            Write-Status -Type Skip -Message "Missing: $($item.Name)"
            continue
        }
        $backupPath = Backup-ManagedFile `
            -Path $item.Path `
            -Reason 'manual' `
            -BackupSetName $backupSetName
        if ($backupPath) {
            $backups.Add([pscustomobject]@{
                ManagedFile = $item.Name
                Source      = $item.Path
                Backup      = $backupPath
            })
        }
    }
    if ($backups.Count -eq 0) {
        Write-Status -Type Warning -Message 'No existing managed files were backed up.'
    }
    else {
        Write-Status -Type Success -Message ("Created {0} backup file(s)." -f $backups.Count)
    }
    if ($PassThru) {
        return $backups.ToArray()
    }
}
#endregion
#==================================================================#
#region --- Installation workflow ---
#==================================================================#
function Invoke-BuFuProfileInstall {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium'
    )]
    param()
    $script:ConflictMode = 'Prompt'
    $script:QuitRequested = $false
    Write-Host ''
    Write-Host 'BuFuProfile Framework Installer' -ForegroundColor Cyan
    Write-Host ('=' * 50) -ForegroundColor DarkCyan
    Write-Status -Type Info -Message "PowerShell root: $PowerShellRoot"
    Write-Status -Type Info -Message "Framework root: $frameworkRoot"
    if ($WhatIfPreference) {
        Write-Status -Type Info -Message 'Preview mode enabled. No changes will be made.'
    }
    try {
        New-DirectoryIfMissing -Path $PowerShellRoot
        New-DirectoryIfMissing -Path $frameworkRoot
        foreach ($directory in $directories) {
            New-DirectoryIfMissing -Path (Join-Path $frameworkRoot $directory)
        }
        Write-SectionHeader -Title 'Creating or updating framework files'
        foreach ($entry in $files.GetEnumerator()) {
            $result = Write-ScaffoldFile -RelativePath $entry.Key -Content ([string]$entry.Value)
            if ($result -eq 'Quit' -or $script:QuitRequested) {
                break
            }
        }
        if (-not $script:QuitRequested) {
            if (-not $SkipProfileUpdate) {
                Write-SectionHeader -Title 'Installing PowerShell bootstrap profiles'
                $result = Write-StandardProfile `
                    -Path $allHostsProfile `
                    -Content $allHostsProfileContent `
                    -Description 'CurrentUserAllHosts bootstrap'
                if (
                    $result -ne 'Quit' -and
                    -not $script:QuitRequested -and
                    $currentHostProfile -ne $allHostsProfile
                ) {
                    [void](Write-StandardProfile `
                        -Path $currentHostProfile `
                        -Content $currentHostProfileContent `
                        -Description 'CurrentUserCurrentHost bootstrap')
                }
            }
            else {
                Write-Status -Type Skip -Message 'Standard profile files were not modified.'
            }
        }
        if ($script:QuitRequested) {
            Write-Status -Type Warning -Message 'Installation stopped before completion.'
            return
        }
        Write-Host ''
        Write-Host ('=' * 50) -ForegroundColor DarkCyan
        if ($WhatIfPreference) {
            Write-Status -Type Success -Message 'BuFuProfile preview completed. No files were changed.'
        }
        else {
            Write-Status -Type Success -Message 'BuFuProfile installation or update completed.'
        }
        Write-Host ''
        Write-Host 'Framework:' -ForegroundColor Cyan
        Write-Host "  $frameworkRoot"
        Write-Host ''
        Write-Host 'Backup location:' -ForegroundColor Cyan
        Write-Host "  $archiveRoot"
        Write-Host ''
        Write-Host 'Validate managed files:' -ForegroundColor Cyan
        Write-Host '  .\New-BuFuProfile.ps1 -Validate'
        Write-Host ''
        Write-Host 'Reload the current session:' -ForegroundColor Cyan
        Write-Host '  . $PROFILE.CurrentUserAllHosts'
        Write-Host '  . $PROFILE.CurrentUserCurrentHost'
        Write-Host ''
        Write-Host 'Open the Help Center after reload:' -ForegroundColor Cyan
        Write-Host '  Show-BuFuProfileHelpCenter'
        Write-Host ''
        if (-not $WhatIfPreference) {
            $validationResults = @(Test-BuFuProfileManagedFiles)
            $currentCount = @($validationResults | Where-Object Status -EQ 'Current').Count
            $modifiedCount = @($validationResults | Where-Object Status -EQ 'Modified').Count
            $missingCount = @($validationResults | Where-Object Status -EQ 'Missing').Count
            Write-Host (
                'Managed files: {0} Current, {1} Modified, {2} Missing' -f
                $currentCount,
                $modifiedCount,
                $missingCount
            ) -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host ''
        Write-Status -Type Error -Message $_.Exception.Message
        throw
    }
}
#endregion
#==================================================================#
#region --- Interactive menus ---
#==================================================================#
function Show-DocumentationExportMenu {
    [CmdletBinding()]
    param()
    while ($true) {
        Clear-BuFuScreen
        Write-SectionHeader -Title 'Documentation Export'
        Write-Host '[1] Export Markdown'
        Write-Host '[2] Export HTML'
        Write-Host '[3] Export both'
        Write-Host '[4] Preview Markdown export'
        Write-Host '[5] Preview HTML export'
        Write-Host '[B] Back'
        Write-Host ''
        $choice = (Read-Host 'Selection').Trim().ToUpperInvariant()
        switch ($choice) {
            '1' { Export-HelpToMarkdown; Pause-BuFuMenu }
            '2' { Export-HelpToHtml; Pause-BuFuMenu }
            '3' { Export-HelpToMarkdown; Export-HelpToHtml; Pause-BuFuMenu }
            '4' { Export-HelpToMarkdown -WhatIf; Pause-BuFuMenu }
            '5' { Export-HelpToHtml -WhatIf; Pause-BuFuMenu }
            'B' { return }
            default { Write-Status -Type Warning -Message 'Invalid selection.'; Pause-BuFuMenu }
        }
    }
}

function Show-BuFuProfileMainMenu {
    [CmdletBinding()]
    param()
    if (-not (Test-InteractiveConsole)) {
        Write-Status -Type Warning -Message 'Interactive input is unavailable.'
        Show-CompleteHelp
        return
    }
    while ($true) {
        $validationResults = @(Test-BuFuProfileManagedFiles)
        $currentCount = @($validationResults | Where-Object Status -EQ 'Current').Count
        $modifiedCount = @($validationResults | Where-Object Status -EQ 'Modified').Count
        $missingCount = @($validationResults | Where-Object Status -EQ 'Missing').Count
        Clear-BuFuScreen
        Write-Host 'BuFuProfile Manager' -ForegroundColor Cyan
        Write-Host ('=' * 60) -ForegroundColor DarkCyan
        Write-Host "Framework: $frameworkRoot" -ForegroundColor DarkGray
        Write-Host (
            'Managed files: {0} Current | {1} Modified | {2} Missing' -f
            $currentCount,
            $modifiedCount,
            $missingCount
        ) -ForegroundColor DarkGray
        Write-Host ('Archive: {0}' -f $archiveRoot) -ForegroundColor DarkGray
        Write-Host ('=' * 60) -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host '[1] Install or update BuFuProfile'
        Write-Host '[2] Preview install or update (WhatIf)'
        Write-Host '[3] Validate managed files'
        Write-Host '[4] Create timestamped backup'
        Write-Host '[5] Show directory tree'
        Write-Host '[6] Show framework information'
        Write-Host '[7] Export documentation'
        Write-Host '[8] Help Center'
        Write-Host '[Q] Quit'
        Write-Host ''
        $choice = (Read-Host 'Selection').Trim().ToUpperInvariant()
        Clear-BuFuScreen
        switch ($choice) {
            '1' {
                Invoke-BuFuProfileInstall
                Pause-BuFuMenu
            }
            '2' {
                Invoke-BuFuProfileInstall -WhatIf
                Pause-BuFuMenu
            }
            '3' {
                [void](Test-BuFuProfileManagedFiles -Display)
                Pause-BuFuMenu
            }
            '4' {
                Backup-BuFuProfile
                Pause-BuFuMenu
            }
            '5' {
                Show-DirectoryTree
                Pause-BuFuMenu
            }
            '6' {
                Write-SectionHeader -Title 'BuFuProfile Information'
                Get-BuFuProfileInfo | Format-List
                Pause-BuFuMenu
            }
            '7' {
                Show-DocumentationExportMenu
            }
            '8' {
                Show-BuFuProfileHelpCenter
            }
            'Q' {
                return
            }
            default {
                Write-Status -Type Warning -Message 'Invalid selection.'
                Pause-BuFuMenu
            }
        }
    }
}
#endregion
#==================================================================#
#region --- Command dispatch ---
#==================================================================#
$compatibilityHelpRequested = (
    $Help -or
    ($RemainingArguments -contains '/?') -or
    ($RemainingArguments -contains '--Help') -or
    ($RemainingArguments -contains '--help')
)
$unsupportedArguments = @(
    $RemainingArguments |
        Where-Object { $_ -notin @('/?', '--Help', '--help') }
)
if ($unsupportedArguments.Count -gt 0) {
    throw "Unsupported argument(s): $($unsupportedArguments -join ', ')"
}
if ($compatibilityHelpRequested) {
    Show-CompleteHelp
    return
}
$performedDirectAction = $false
if ($Validate) {
    [void](Test-BuFuProfileManagedFiles -Display)
    $performedDirectAction = $true
}
if ($Backup) {
    Backup-BuFuProfile
    $performedDirectAction = $true
}
if ($ShowTree) {
    Show-DirectoryTree
    $performedDirectAction = $true
}
if ($ExportHelp) {
    switch ($ExportHelp) {
        'Markdown' {
            Export-HelpToMarkdown
        }
        'Html' {
            Export-HelpToHtml
        }
        'All' {
            Export-HelpToMarkdown
            Export-HelpToHtml
        }
    }
    $performedDirectAction = $true
}
if ($performedDirectAction) {
    return
}
$launchMenu = $InteractiveMenu -or ($PSBoundParameters.Count -eq 0)
if ($launchMenu) {
    Show-BuFuProfileMainMenu
    return
}
$installParameters = @{}
if ($PSBoundParameters.ContainsKey('WhatIf')) {
    $installParameters.WhatIf = [bool]$PSBoundParameters['WhatIf']
}
if ($PSBoundParameters.ContainsKey('Confirm')) {
    $installParameters.Confirm = [bool]$PSBoundParameters['Confirm']
}
Invoke-BuFuProfileInstall @installParameters
#endregion