# source provenance

Super Hotkey v1.0.0 was integrated from these earlier projects. the source snapshots and migration scripts were removed from the working tree after integration; their original committed bytes remain accessible in the repository's Git history, including the initial `main` checkpoint.

| project | original repository | pinned commit |
| --- | --- | --- |
| Keybindings | https://github.com/nroj95/keybindings | `42261fa924c74ccd0c5887ff3408c03cbcc6c0d0` |
| Power Hotkey | https://github.com/nroj95/power-hotkey | `8838312c1096efbf055a72d79f1bf715aed9297c` |
| Window Cascade | https://github.com/nroj95/window-cascade | `4153235e454e204a21c04766822a7032a37df02a` |
| Scratchpad | https://github.com/nroj95/scratchpad | `b26a252b82d11dc965f60717f564bffed6a4eadc` |
| Caps + Pause Layers | https://github.com/nroj95/caps-pause-layers | `f674ff57543b8ddbadac49b43d7248c89581c003` |
| Win Key Overhaul | https://github.com/nroj95/win-key-overhaul | `02a28d906868a883a33d3081c1bd4bd7ad0e0274` |

the adapted source components and their original repositories use the MIT license, with copyright (c) 2026 nroj95; see the root [LICENSE](../LICENSE).

the current app icon incorporates FatCow Farm-Fresh Web Icons artwork under CC BY 3.0. retain [icon attribution](../assets/ATTRIBUTION.md) and its bundled [license notes](../assets/fatcow-readme.txt).

the live runtime is in `core/` and `modules/`. none of the historical snapshots is required to run or test the suite.
