# TE2, DAX Studio, and WinGet publishing audit

Audit date: 2026-08-26. Only vendor, Microsoft, and upstream GitHub sources were used.

## Accepted versions

| Component | Current stable | Lab decision |
| --- | --- | --- |
| Tabular Editor 2 | 2.28.0, released 2026-03-02 | Pin 2.28.0 for new installs |
| DAX Studio | 3.6.0, released 2026-08-23 | Pin 3.6.0 for new installs; retain 3.5.2 as the compatible runtime floor |
| WinGet | Client varies with App Installer | Do not pin a client number; capability-test every required option and fail if one is absent |
| PowerShell | Windows PowerShell 5.1 is the validated baseline | Keep all owned scripts 5.1-compatible; do not depend on PowerShell 7 native-argument changes |

Primary release sources:

- [Tabular Editor 2.28.0 release](https://github.com/TabularEditor/TabularEditor/releases/tag/2.28.0)
- [DAX Studio 3.6.0 release](https://github.com/DaxStudio/DaxStudio/releases/tag/v3.6.0)
- [WinGet install command](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)

## Audited WinGet manifests

### Tabular Editor 2

- Package ID: `TabularEditor.TabularEditor.2`
- Version: `2.28.0`
- Installer: x86 portable ZIP from the official GitHub release
- Installer SHA-256: `BA85F4653C850B06687E6E0B3C8AF3D7C951921EC281DEB5DF615B2CE43D4EF2`
- Installed `TabularEditor.exe` SHA-256: `8DA4E0C153F4E176B4DBA75577E4AB70ADD14667EBA61C984A8FC8B56DD979E4`
- [Current WinGet installer manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/t/TabularEditor/TabularEditor/2/2.28.0/TabularEditor.TabularEditor.2.installer.yaml)

The manifest declares `Microsoft.DotNet.Framework.DeveloperPack.4.6`, which is machine-scoped. TE2 2.28's own project targets .NET Framework 4.8. The run-once wrapper therefore checks the official 4.8 runtime release key first and skips only this mismatched developer-pack dependency. It does not skip DAX Studio dependencies.

- [TE2 2.28 target framework source](https://github.com/TabularEditor/TabularEditor/blob/2.28.0/TabularEditor/TabularEditor.csproj)
- [Microsoft .NET Framework release-key test](https://learn.microsoft.com/en-us/dotnet/framework/install/how-to-determine-which-versions-are-installed)
- [.NET 4.6 Developer Pack WinGet manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/m/Microsoft/DotNet/Framework/DeveloperPack/4/6/4.6.2/Microsoft.DotNet.Framework.DeveloperPack.4.6.installer.yaml)

### DAX Studio

- Package ID: `DaxStudio.DaxStudio`
- Version: `3.6.0`
- Installer: x64 Inno Setup from the official GitHub release
- User selection: `/CURRENTUSER`
- Installer SHA-256: `61B8CEF9743ECCDFB3486ACA5BDD6EF339E20BDD63C552D2EAFB5F19A108944F`
- Installed `dscmd.exe` version/hash validated in this build: `3.6.0.1243`, `81EFA7030D2EF7368D64EF3EB928303676868944E35F95ABF8D2400E66711404`
- [Current WinGet installer manifest](https://github.com/microsoft/winget-pkgs/blob/master/manifests/d/DaxStudio/DaxStudio/3.6.0/DaxStudio.DaxStudio.installer.yaml)
- [Vendor installation-mode comparison](https://daxstudio.org/docs/installation/index/)

DAX Studio documents current-user mode as not requiring administrator rights; all-users mode does. Current-user mode does not add the Power BI External Tools registration, which is irrelevant because this lab calls `dscmd.exe` directly. The WinGet manifest also declares `ElevationRequirement: elevatesSelf`, so the wrapper cannot guarantee that Windows or enterprise policy will never request UAC. It makes user scope mandatory and has no fallback.

## Release changes that affect commands

### TE2 2.27-2.28

- TE2 2.27.0 changed deployment: shared expressions are not deployed unless deployment `-S`/`-SHARED` is present.
- TE2 2.27.0/2.27.1 also broke top-level C# script `-S`; 2.27.2 fixed that regression.
- TE2 2.28.0 updated AMO/TOM to 19.112.0 and fixed another C# script compile regression.
- Top-level `-S` and deployment `-S` are context-dependent; this lab permits neither scripts nor deployment.
- `-B` and `-TMDL` remain supported read-only metadata exports and require separate invocations.
- `-L <PBIX filename>` can choose the first duplicate filename. The lab keeps its independent Desktop PID to model PID to port/catalog chain.
- The newer cross-platform `te` CLI is still limited preview, so it does not replace stable `TabularEditor.exe` here.

References:

- [Current TE2 command-line documentation](https://docs.tabulareditor.com/en/features/Command-line-Options.html)
- [TE2 2.28 command parser](https://github.com/TabularEditor/TabularEditor/blob/2.28.0/TabularEditor/CommandLineHandler.cs)
- [TE2 release history](https://github.com/TabularEditor/TabularEditor/releases)

### DAX Studio 3.6

- `dscmd` moved to Spectre.Console.Cli and commands/options became case-insensitive.
- New `auth` and `benchmark` commands do not affect intake.
- Non-interactive Entra account selection and dependency binding were improved.
- The lab retains lowercase command/option spelling because 3.5.2 is case-sensitive.
- The existing `csv ... --server ... --database ... --file ...` and metadata-only `vpax ... --donotreadstatsfromdata` grammar remains valid in both 3.5.2 and 3.6.0.
- Filename-based Desktop discovery still takes a filename, not a path, and can choose the first duplicate match. Explicit verified endpoint/catalog remains safer.

References:

- [DAX Studio 3.6 command registration](https://github.com/DaxStudio/DaxStudio/blob/v3.6.0/src/DaxStudio.CommandLine/Program.cs)
- [CSV command documentation](https://daxstudio.org/docs/features/command-line/commands/csv-command/)
- [VPAX command documentation](https://daxstudio.org/docs/features/command-line/commands/vpax-command/)
- [Desktop connection documentation](https://daxstudio.org/docs/features/command-line/connecting/)

## Exact run-once selections

The wrapper constructs these package operations as argument arrays, not shell-concatenated strings:

```text
winget install --id TabularEditor.TabularEditor.2 --exact --version 2.28.0 --source winget --scope user --architecture x86 --installer-type portable --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --verbose-logs --skip-dependencies

winget install --id DaxStudio.DaxStudio --exact --version 3.6.0 --source winget --scope user --architecture x64 --installer-type inno --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --verbose-logs
```

Before those commands, the wrapper confirms that source `winget` resolves to `https://cdn.winget.microsoft.com/cache` / `Microsoft.Winget.Source_8wekyb3d8bbwe`, updates it successfully, and runs exact `winget show` checks against the URLs and hashes above.

It never emits:

- `--scope machine`
- `Start-Process -Verb RunAs`
- `--force`
- `--override`
- `--ignore-security-hash`
- a retry with omitted scope/version/source

## Shell/version decision

The canonical outer command resolves `%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe` explicitly and passes `-NoProfile -File ...`. The scripts support Windows PowerShell 5.1 syntax and use their own Windows command-line quoting with `Start-Process -Wait` semantics. This avoids both PATH shadowing and reliance on PowerShell 7.3's changed `$PSNativeCommandArgumentPassing` modes. All native success decisions use the child process exit code plus output/artifact validation.

The publishing audit should be repeated before changing either package pin. A newer version is not automatically trusted by the intake runtime; it must pass release-note review, manifest URL/hash review, signer/hash registration, help grammar tests, adversarial tests, and at least one live PBIX export.
