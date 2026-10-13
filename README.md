# utils

Small Windows PowerShell utilities.

## Compare-Disks

[`Compare-Disks/Compare-Disks.ps1`](Compare-Disks/Compare-Disks.ps1) lists the files that differ between two disks or folder trees.

It runs in Windows PowerShell 5.1 and PowerShell 7. Any mix of drive, folder, or UNC path works (`D:\` vs `E:\`, `M:\` vs `P:\Backup\M`, `D:\Photos` vs `\\nas\Photos`).

Files are matched by path relative to each root, ignoring case. `M:\Docs\a.txt` is compared with `P:\Backup\M\Docs\a.txt`.

### What it reports

| Status | Meaning |
|---|---|
| `OnlyInLeft` | The file exists only under `-Left` |
| `OnlyInRight` | The file exists only under `-Right` |
| `Different` | The file exists on both sides but differs. `Reason` is `Size`, `Date`, or `Content` |
| `Same` | Identical. Listed only with `-IncludeSame` |

Each row also includes `LeftSize`, `RightSize`, `LeftModified`, and `RightModified`. Identical files are skipped unless `-IncludeSame` is set.

Compare modes:

| Mode | What it checks |
|---|---|
| `Size` (default) | Relative path and size. Timestamps are ignored |
| `SizeAndDate` | Size, or last-write time differing by more than `-TimeToleranceSeconds` |
| `Hash` | Size first, then SHA256 for same-size files. Exact, but it reads every file |

Inaccessible folders are skipped. Reparse points (junctions and symlinks) are not followed. Run with `-Verbose` to see skipped folders.

### Usage

```powershell
.\Compare-Disks\Compare-Disks.ps1 -Left D:\ -Right E:\
```

```powershell
.\Compare-Disks\Compare-Disks.ps1 -Left D:\ -Right E:\Backup\D
```

```powershell
.\Compare-Disks\Compare-Disks.ps1 -Left D:\Photos -Right \\nas\backup\Photos -Mode Hash -OutCsv C:\temp\diff.csv
```

```powershell
.\Compare-Disks\Compare-Disks.ps1 D:\ E:\ -Exclude 'node_modules','*.tmp','.git' | Out-GridView
```

If script execution is disabled:

```powershell
powershell -ExecutionPolicy Bypass -File .\Compare-Disks\Compare-Disks.ps1 D:\ E:\ -OutCsv C:\temp\diff.csv
```

Results are written to the pipeline, so they can be filtered:

```powershell
.\Compare-Disks\Compare-Disks.ps1 D:\ E:\ | Where-Object Status -eq 'OnlyInLeft'
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Left` (position 0) | required | First disk or folder |
| `-Right` (position 1) | required | Second disk or folder |
| `-Mode` | `Size` | `Size`, `SizeAndDate`, or `Hash` |
| `-Exclude` | `$RECYCLE.BIN`, `System Volume Information`, `pagefile.sys`, `hiberfil.sys`, `swapfile.sys` | Wildcard patterns matched against file and folder names, not full paths. Passing a value replaces the default list |
| `-TimeToleranceSeconds` | `2` | Allowed time difference in `SizeAndDate` mode. FAT and exFAT store times in 2-second steps |
| `-IncludeSame` | off | Also list identical files |
| `-OutCsv` | none | Save results to a UTF-8 CSV. The folder must already exist |
| `-Verbose` | off | Show file counts and skipped folders |

### Notes

- A progress bar is shown while scanning and comparing. A one-line summary is printed at the end, for example `OnlyInLeft=12, Different=3, OnlyInRight=40`.
- Paths with spaces must be quoted.
- Writing `-OutCsv` under `C:\` usually needs admin rights. Use a folder such as `C:\temp` or `$HOME`.
- With `powershell -File`, a trailing backslash inside double quotes (`"P:\Some folder\"`) is treated as an escaped quote and swallows the following arguments. Drop the trailing backslash, or call the script from a PowerShell prompt with single quotes: `'P:\Some folder\'`.
