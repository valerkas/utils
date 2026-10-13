#Requires -Version 5.1
<#
.SYNOPSIS
    Lists the files that differ between two disks (or any two folder trees).

.DESCRIPTION
    Walks both trees, matches files by their path relative to each root and reports:
      OnlyInLeft   - the file exists only under -Left
      OnlyInRight  - the file exists only under -Right
      Different    - the file exists on both sides but its content differs
    Identical files are skipped unless -IncludeSame is set.

    Compare modes:
      Size (default)        - file name (relative path) and size only, ignores timestamps
      SizeAndDate           - size differs, or LastWriteTime differs by more than -TimeToleranceSeconds
      Hash                  - size first, then SHA256 for same-size files (exact, reads every file)

    Inaccessible folders are skipped silently; reparse points (junctions, symlinks) are not followed.

.EXAMPLE
    .\Compare-Disks.ps1 -Left D:\ -Right E:\

.EXAMPLE
    .\Compare-Disks.ps1 -Left D:\ -Right E:\Backup\D    # a whole disk against a folder

.EXAMPLE
    .\Compare-Disks.ps1 -Left D:\Photos -Right \\nas\backup\Photos -Mode Hash -OutCsv C:\temp\diff.csv

.EXAMPLE
    .\Compare-Disks.ps1 D:\ E:\ -Exclude 'node_modules','*.tmp','.git' | Out-GridView
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [string] $Left,
    [Parameter(Mandatory, Position = 1)] [string] $Right,
    [ValidateSet('SizeAndDate', 'Size', 'Hash')] [string] $Mode = 'Size',
    # Wildcard patterns matched against every file and folder name (not the full path).
    [string[]] $Exclude = @('$RECYCLE.BIN', 'System Volume Information', 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys'),
    # FAT/exFAT store times with 2-second precision, so a small tolerance avoids false positives.
    [int] $TimeToleranceSeconds = 2,
    [switch] $IncludeSame,
    [string] $OutCsv
)

$ErrorActionPreference = 'Stop'

function Resolve-Root([string] $Path) {
    $full = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)
    if (-not [System.IO.Directory]::Exists($full)) { throw "Not a folder: $Path" }
    return $full.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
}

function Test-Excluded([string] $Name) {
    foreach ($pattern in $Exclude) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Returns a case-insensitive dictionary: relative path -> FileInfo.
function Get-FileMap([string] $Root, [string] $Label) {
    $map = [System.Collections.Generic.Dictionary[string, System.IO.FileInfo]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $reparse = [System.IO.FileAttributes]::ReparsePoint

    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push([System.IO.DirectoryInfo]::new($Root))
    $count = 0

    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            foreach ($entry in $dir.EnumerateFileSystemInfos()) {
                if (($entry.Attributes -band $reparse) -or (Test-Excluded $entry.Name)) { continue }
                if ($entry -is [System.IO.DirectoryInfo]) {
                    $stack.Push($entry)
                }
                else {
                    $map[$entry.FullName.Substring($Root.Length)] = $entry
                    if ((++$count % 5000) -eq 0) {
                        Write-Progress -Activity "Scanning $Label ($Root)" -Status "$count files" -CurrentOperation $dir.FullName
                    }
                }
            }
        }
        catch {
            Write-Verbose "Skipped $($dir.FullName): $($_.Exception.Message)"
        }
    }
    Write-Progress -Activity "Scanning $Label ($Root)" -Completed
    return $map
}

function Get-Sha256([System.IO.FileInfo] $File) {
    try { return (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash }
    catch { return "ERROR: $($_.Exception.Message)" }
}

function New-Row($Status, $RelativePath, [System.IO.FileInfo] $L, [System.IO.FileInfo] $R, $Reason) {
    [pscustomobject]@{
        Status       = $Status
        RelativePath = $RelativePath
        Reason       = $Reason
        LeftSize      = if ($L) { $L.Length } else { $null }
        RightSize     = if ($R) { $R.Length } else { $null }
        LeftModified  = if ($L) { $L.LastWriteTime } else { $null }
        RightModified = if ($R) { $R.LastWriteTime } else { $null }
    }
}

$leftRoot = Resolve-Root $Left
$rightRoot = Resolve-Root $Right
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$leftMap = Get-FileMap $leftRoot 'left'
$rightMap = Get-FileMap $rightRoot 'right'
Write-Verbose "Left: $($leftMap.Count) files, right: $($rightMap.Count) files"

$results = [System.Collections.Generic.List[object]]::new()
$i = 0
$total = $leftMap.Count

foreach ($pair in $leftMap.GetEnumerator()) {
    $rel = $pair.Key
    $l = $pair.Value
    if ((++$i % 2000) -eq 0) {
        Write-Progress -Activity 'Comparing' -Status "$i / $total" -PercentComplete ($i * 100 / [Math]::Max($total, 1))
    }

    $r = $null
    if (-not $rightMap.TryGetValue($rel, [ref] $r)) {
        $results.Add((New-Row 'OnlyInLeft' $rel $l $null ''))
        continue
    }

    $reason = $null
    if ($l.Length -ne $r.Length) {
        $reason = 'Size'
    }
    elseif ($Mode -eq 'SizeAndDate' -and
        [Math]::Abs(($l.LastWriteTimeUtc - $r.LastWriteTimeUtc).TotalSeconds) -gt $TimeToleranceSeconds) {
        $reason = 'Date'
    }
    elseif ($Mode -eq 'Hash' -and (Get-Sha256 $l) -ne (Get-Sha256 $r)) {
        $reason = 'Content'
    }

    if ($reason) { $results.Add((New-Row 'Different' $rel $l $r $reason)) }
    elseif ($IncludeSame) { $results.Add((New-Row 'Same' $rel $l $r '')) }
}
Write-Progress -Activity 'Comparing' -Completed

foreach ($pair in $rightMap.GetEnumerator()) {
    if (-not $leftMap.ContainsKey($pair.Key)) {
        $results.Add((New-Row 'OnlyInRight' $pair.Key $null $pair.Value ''))
    }
}

$sorted = $results | Sort-Object Status, RelativePath

$summary = $results | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host ("Compared {0} vs {1} ({2} mode) in {3:n1}s: {4}" -f $leftRoot, $rightRoot, $Mode, $sw.Elapsed.TotalSeconds,
    ($(if ($summary) { $summary -join ', ' } else { 'no differences' }))) -ForegroundColor Cyan

if ($OutCsv) {
    $sorted | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding utf8
    Write-Host "Saved to $OutCsv" -ForegroundColor Cyan
}

$sorted