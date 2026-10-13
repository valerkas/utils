# Compare-Disks.ps1

Finds the files that differ between two disks or folders, by file name and size.

Works in Windows PowerShell 5.1 and PowerShell 7. Any combination of disk, folder or network path is fine (`D:\` vs `E:\`, `M:\` vs `P:\Backup\M`, `D:\Photos` vs `\\nas\Photos`).

## What it reports

Files are matched by their path relative to each root, ignoring upper and lower case: `M:\Docs\a.txt` is compared with `P:\Backup\M\Docs\a.txt`.

| Status | Meaning |
|---|---|
| `OnlyInLeft` | The file exists only under `-Left` |
| `OnlyInRight` | The file exists only under `-Right` |
| `Different` | The file exists on both sides but differs; `Reason` says why: `Size`, `Date` or `Content` |
| `Same` | Identical; listed only with `-IncludeSame` |

Each row also has `LeftSize`, `RightSize`, `LeftModified` and `RightModified`.

## Usage

```powershell
D:\Origami\tmp\Compare-Disks.ps1 M:\ 'P:\Backup\M\' -OutCsv C:\temp\diff_M.csv
```

If script execution is disabled on the machine:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Origami\tmp\Compare-Disks.ps1 M:\ "P:\Backup\M" -OutCsv C:\temp\diff_M.csv
```

The results are also written to the pipeline, so they can be filtered or viewed:

```powershell
.\Compare-Disks.ps1 D:\ E:\ | Where-Object Status -eq 'OnlyInLeft' | Out-GridView
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Left` (position 0) | required | First disk or folder |
| `-Right` (position 1) | required | Second disk or folder |
| `-Mode` | `Size` | `Size`: name and size only. `SizeAndDate`: also flags a last-modified time that differs by more than `-TimeToleranceSeconds`. `Hash`: compares SHA256 of same-size files; exact but reads every file, so slow on whole disks |
| `-Exclude` | `$RECYCLE.BIN`, `System Volume Information`, `pagefile.sys`, `hiberfil.sys`, `swapfile.sys` | Wildcard patterns matched against file and folder names (not full paths). Passing a value replaces the default list |
| `-TimeToleranceSeconds` | `2` | Allowed time difference in `SizeAndDate` mode; FAT/exFAT store times in 2-second steps |
| `-IncludeSame` | off | Also list identical files |
| `-OutCsv` | none | Save the results to a CSV file (UTF-8). The folder must exist |
| `-Verbose` | off | Show file counts and the folders that were skipped |

## Behaviour notes

- Folders that cannot be read (access denied, path too long) are skipped; run with `-Verbose` to see them.
- Junctions and symbolic links are not followed.
- A progress bar is shown while scanning and comparing; a one-line summary is printed at the end, for example `OnlyInLeft=12, Different=3, OnlyInRight=40`.

## Pitfalls

- **Trailing backslash with `-File`.** In `powershell -File ... "P:\Some folder\"` the `\"` is read as a literal quote, so the path swallows the following arguments. Drop the trailing backslash, or run the script directly from a PowerShell prompt with single quotes: `'P:\Some folder\'`.
- **Paths with spaces** must be quoted.
- **Writing to `C:\`** usually needs admin rights; use a folder such as `C:\temp` or `$HOME` for `-OutCsv`.
