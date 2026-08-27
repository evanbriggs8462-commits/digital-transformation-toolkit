# Official PBIX test corpus

Live tests use Microsoft's `powerbi-desktop-samples` repository at immutable commit:

```text
2b6de5e08496edbb543f059cc171f35b47322899
```

Repository: https://github.com/microsoft/powerbi-desktop-samples  
License: MIT (as published in that repository)

| Purpose | Repository path | Bytes | Expected SHA-256 |
| --- | --- | ---: | --- |
| Small baseline | `2026 Power BI Samples Revamp/Revenue Opportunities.pbix` | 245930 | `3C95C4FB5A261E9D13A7152A2E14B18EA9E9EFAC0105DBD9ED46BA0137489C27` |
| Rich model | `2026 Power BI Samples Revamp/AdventureWorks Sales.pbix` | 8390782 | `76C89B64CD1C5A9514B43CC5EA356EFC82F8E92F9A96B49F6679D9CCD57FC4F5` |
| Legacy/minimal | `Monthly Desktop Blog Samples/2018/2018SU10 Fuzzy Matching Demo - October.pbix` | 45177 | `B04EF67CE8B113A9199F6C849667FF390DF95B0E6C8A97F5017D2C1F4078AF4D` |
| Feature-heavy optional | `Sample Reports/Sales & Returns Sample v201912.pbix` | 6530381 | `C0A51FBAE6C9E3C3CF0FF0564CC3408DAD614449B5B27EC3E47FBAEA4BA7F04B` |

`tests/Get-OfficialPbixSamples.ps1` downloads only explicitly selected entries, verifies byte length and SHA-256, and writes provenance beside the local test copy. PBIX files are ignored by Git and excluded from releases.

The corpus is deliberately varied. It proves that discovery and export work across a tiny legacy file, a current small file, a richer semantic model, and an optional feature-heavy report. It is not evidence that the report canvas was captured.

