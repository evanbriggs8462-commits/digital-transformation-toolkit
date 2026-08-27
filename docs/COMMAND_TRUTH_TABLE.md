# Command truth table

This file exists because agents repeatedly confuse flags that look similar across Tabular Editor 2 and DAX Studio.

## Tabular Editor 2

Authoritative grammar:

```text
TabularEditor.exe <server> <database> -B <model.bim>
TabularEditor.exe <server> <database> -TMDL <output-folder>
TabularEditor.exe -L "Report.pbix" -B <model.bim>
TabularEditor.exe -L "Report.pbix" -TMDL <output-folder>
```

| Token | Meaning at the top level | Lab policy |
| --- | --- | --- |
| `-L` / `-LOCAL` | Connect to a running local Power BI Desktop model | Documented but the lab prefers a PID-verified `localhost:port` and catalog |
| `-S` / `-SCRIPT` | Execute a C# script | Not used by the lab |
| `-B` / `-BIM` | Save metadata as one BIM JSON file | Allowed |
| `-TMDL` | Save metadata as a TMDL folder | Allowed |
| `-D` / `-DEPLOY` | Save/deploy changes | Forbidden |
| `-E` | Deployment error handling | Forbidden; it does not mean export |
| `-W` | Warn about unprocessed objects | Not a wait switch |

Important parser traps:

- `-L` and `-S` are not interchangeable.
- `-L <name>` uses a PBIX filename, not a path. TE2 2.28 selects the first name match, so duplicate open basenames are unsafe; the lab resolves PID/port/catalog itself instead.
- Under TE2 deployment syntax, short switches change meaning: top-level `-S` is C# script, while after `-D` it includes shared expressions; top-level `-F` is folder export, while after `-D` it means full deployment. The lab forbids the entire deployment grammar.
- TE2 2.27.0/2.27.1 regressed top-level `-S`; 2.27.2 fixed it. The lab pins 2.28.0 and does not execute scripts.
- A closed `.pbix` is not a valid positional model file. Positional files are BIM/model folders. An open PBIX requires local/server connection semantics.
- `-B` and `-TMDL` are separate invocations.
- Do not pass the optional replacement ID after `-TMDL <directory>`; the 2.28.0 parser has inconsistent assignment logic for that optional value.
- Never pass a full PBIX path to `-L`; use the filename only.
- TE2 is WinForms. Wait for the actual process and verify its output; do not trust shell return alone.

Official reference: https://docs.tabulareditor.com/en/features/Command-line-Options.html

## DAX Studio command line

Authoritative grammar:

```text
dscmd.exe csv <output.csv> --server <server> [--database <catalog>] --file <query.dax>
dscmd.exe vpax <output.vpax> --server <server> [--database <catalog>] --donotreadstatsfromdata
```

| Token | Meaning | Lab policy |
| --- | --- | --- |
| `--server` / `-s` | PBIX filename or Analysis Services endpoint | Allowed only through the argument builder |
| `--database` / `-d` | Catalog for an explicit endpoint | Required for the lab's verified localhost route |
| `--file` / `-f` | Read DAX from a file | Allowed for the fixed connection test |
| `--query` / `-q` | Inline DAX text | Not used |
| `--excludeTom` / `-t` | Remove TOM metadata from VPAX | Forbidden |
| `--donotreadstatsfromdata` / `-r` | Avoid data-statistic scans | Required |
| VPAX `--DirectLakeMode` / `-l` | Choose a Direct Lake statistics mode | Not a connection option; not used by the baseline |

Important parser traps:

- The executable is `dscmd.exe`, not `DaxStudio.exe`.
- DAX Studio 3.6.0 made commands/options case-insensitive, but `dscmd` 3.5.2 is case-sensitive. Use lowercase `csv`, `vpax`, and lowercase long options across both versions even when current web examples show uppercase commands.
- The command comes first: `csv <output>`, then options.
- DAX Studio `-s` means server; TE2 `-S` means script.
- TE2 `-L` means a local Desktop connection, while VPAX `-l` means Direct Lake mode. Switch case and executable context matter.
- Do not use TE2 `-L` with `dscmd`.
- `-q <path>` runs the path as inline DAX and is wrong; use `-f <path>`.
- Do not combine `--connectionstring` with `--server` or `--database`.
- DAX Studio's filename discovery also accepts only a PBIX/PBIP filename and selects the first duplicate name match. The lab therefore supplies the PID-verified `localhost:<port>` and exact catalog.

### DAX short-switch collisions

| Executable/subcommand | `-f` | `-q` | `-l` | `-r` | `-t` |
| --- | --- | --- | --- | --- | --- |
| `dscmd csv/file` | DAX query file | inline DAX | none | none | output type |
| `dscmd vpax` | none | read DirectQuery statistics | Direct Lake mode | do not read statistics from data | exclude TOM |
| `DaxStudio.exe` | open file | none | enable log | reset preferences | none |

The baseline permits VPAX `-r`/`--donotreadstatsfromdata` and forbids VPAX `-q`, `-l`, and `-t`. In particular, VPAX `-q` is not inline DAX and VPAX `-t` removes the TOM metadata this lab needs.

## Shell compatibility

- Canonical automation uses the explicit `%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile` host and is continuously tested on Windows PowerShell 5.1.
- Neither vendor CLI depends on PowerShell, but PowerShell's launcher behavior matters. `Start-Process -ArgumentList` joins values into a Windows command line; the lab quotes every value itself, waits for the actual process, and reads its `ExitCode`.
- PowerShell 7.3 changed direct native argument passing. The lab does not depend on `$PSNativeCommandArgumentPassing` or `$PSNativeCommandUseErrorActionPreference`, so the same builder remains valid when called from newer PowerShell.
- From `cmd.exe`, TE2's WinForms process needs `start /wait`. Do not assume the prompt returning means the export finished.

Official references:

- https://daxstudio.org/docs/features/command-line/connecting/
- https://daxstudio.org/docs/features/command-line/commands/csv-command/
- https://daxstudio.org/docs/features/command-line/commands/vpax-command/
- https://github.com/DaxStudio/DaxStudio/releases/tag/v3.6.0
- https://github.com/DaxStudio/DaxStudio/blob/v3.6.0/src/DaxStudio.CommandLine/Program.cs
