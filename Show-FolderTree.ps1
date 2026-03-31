#Requires -Version 5.0
<#
.SYNOPSIS
    Displays a recursive folder structure as a visual tree.

.DESCRIPTION
    Shows the directory and file hierarchy starting from a given path,
    with optional filtering, depth limiting, and export to file.

.PARAMETER Path
    The root folder to scan. Defaults to the current directory.

.PARAMETER Depth
    Maximum recursion depth. Use -1 for unlimited. Default: -1 (unlimited).

.PARAMETER ShowFiles
    If set, files are included alongside folders in the tree.

.PARAMETER ExcludeHidden
    If set, hidden files and folders are excluded.

.PARAMETER ExportPath
    Optional path to save the output as a .txt file.

.EXAMPLE
    .\Show-FolderTree.ps1
    .\Show-FolderTree.ps1 -Path "C:\Projects" -ShowFiles
    .\Show-FolderTree.ps1 -Path "C:\Projects" -Depth 3 -ShowFiles -ExportPath "tree.txt"
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$Path = ".",

    [int]$Depth = -1,

    [switch]$ShowFiles,

    [switch]$ExcludeHidden,

    [string]$ExportPath
)

# ─── Counters ────────────────────────────────────────────────────────────────
$script:totalDirs  = 0
$script:totalFiles = 0

# ─── Output buffer (for optional export) ─────────────────────────────────────
$script:outputLines = [System.Collections.Generic.List[string]]::new()

function Write-Tree {
    param (
        [string]$CurrentPath,
        [string]$Indent = "",
        [int]$CurrentDepth = 0
    )

    # Depth guard
    if ($Depth -ge 0 -and $CurrentDepth -gt $Depth) { return }

    # Enumerate child directories
    $dirParams = @{
        Path        = $CurrentPath
        Directory   = $true
        ErrorAction = "SilentlyContinue"
    }
    if ($ExcludeHidden) { $dirParams["Attributes"] = "!Hidden" }

    $dirs = Get-ChildItem @dirParams | Sort-Object Name

    # Enumerate child files (optional)
    $files = @()
    if ($ShowFiles) {
        $fileParams = @{
            Path        = $CurrentPath
            File        = $true
            ErrorAction = "SilentlyContinue"
        }
        if ($ExcludeHidden) { $fileParams["Attributes"] = "!Hidden" }
        $files = Get-ChildItem @fileParams | Sort-Object Name
    }

    $allItems  = @($dirs) + @($files)
    $lastIndex = $allItems.Count - 1

    for ($i = 0; $i -le $lastIndex; $i++) {
        $item     = $allItems[$i]
        $isLast   = ($i -eq $lastIndex)
        $branch   = if ($isLast) { "└── " } else { "├── " }
        $childIndent = if ($isLast) { "$Indent    " } else { "$Indent│   " }

        $isDir = $item -is [System.IO.DirectoryInfo]

        if ($isDir) {
            $script:totalDirs++
            $label = "📁 $($item.Name)"
            $line  = "$Indent$branch$label"
        } else {
            $script:totalFiles++
            $ext  = $item.Extension.ToLower()
            $icon = switch ($ext) {
                ".ps1"  { "⚙️ " } ".psm1" { "⚙️ " } ".psd1" { "⚙️ " }
                ".py"   { "🐍 " } ".js"   { "📜 " } ".ts"   { "📜 " }
                ".json" { "🔧 " } ".xml"  { "🔧 " } ".yaml" { "🔧 " } ".yml" { "🔧 " }
                ".md"   { "📝 " } ".txt"  { "📝 " } ".csv"  { "📊 " }
                ".jpg"  { "🖼️ "  } ".jpeg" { "🖼️ "  } ".png"  { "🖼️ "  } ".gif" { "🖼️ "  }
                ".zip"  { "📦 " } ".tar"  { "📦 " } ".gz"   { "📦 " }
                ".exe"  { "🔵 " } ".dll"  { "🔵 " }
                default { "📄 " }
            }
            $label = "$icon$($item.Name)"
            $line  = "$Indent$branch$label"
        }

        Write-Host $line
        $script:outputLines.Add($line)

        # Recurse into directories
        if ($isDir) {
            Write-Tree -CurrentPath $item.FullName -Indent $childIndent -CurrentDepth ($CurrentDepth + 1)
        }
    }
}

# ─── Resolve root path ────────────────────────────────────────────────────────
$resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty Path

# ─── Print header ─────────────────────────────────────────────────────────────
$header = "📂 $resolvedPath"
Write-Host ""
Write-Host $header -ForegroundColor Cyan
$script:outputLines.Add("")
$script:outputLines.Add($header)

# ─── Run tree ─────────────────────────────────────────────────────────────────
Write-Tree -CurrentPath $resolvedPath

# ─── Print summary ────────────────────────────────────────────────────────────
Write-Host ""
$summary = "  $($script:totalDirs) director$(if ($script:totalDirs -eq 1){'y'}else{'ies'})"
if ($ShowFiles) {
    $summary += ", $($script:totalFiles) file$(if ($script:totalFiles -eq 1){''}else{'s'})"
}
Write-Host $summary -ForegroundColor DarkGray
Write-Host ""
$script:outputLines.Add("")
$script:outputLines.Add($summary)

# ─── Export if requested ──────────────────────────────────────────────────────
if ($ExportPath) {
    $script:outputLines | Out-File -FilePath $ExportPath -Encoding UTF8
    Write-Host "Tree saved to: $ExportPath" -ForegroundColor Green
}
