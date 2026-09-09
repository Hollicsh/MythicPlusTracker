---
name: wow-api-lookup
description: Looks up WoW API documentation for a specific function, method, namespace, or event name. Use whenever you need the exact signature, parameters, return values, or usage notes for any World of Warcraft Lua API — for example C_MythicPlus, C_ChallengeMode, CreateFrame, or any game event.
---

# WoW API Lookup

Two sources, different jobs. Start with the wiki; reach for Blizzard's own definitions when the wiki is silent, ambiguous, or possibly stale.

| Source | Use it for |
|---|---|
| **warcraft.wiki.gg** | Routine lookups. Prose, examples, patch history, community notes on quirks and deprecations. |
| **townlong-yak.com/framexml** | Verification and edge cases. Blizzard's own generated definitions, pinned to a build: exact types, `Nilable`, `Default`, enum values, event payloads. Also the full FrameXML source. |

Reach for townlong-yak when: the wiki has no page, the wiki contradicts observed behaviour, you need exact nullability/defaults, you need an enum or constant value, or you must prove whether an API changed in a patch.

## Steps

### Quick lookup

```bash
bash Tools/wow-api-lookup.sh [--source wiki|framexml] <API_NAME>
```

```bash
bash Tools/wow-api-lookup.sh C_MythicPlus.GetRunHistory
bash Tools/wow-api-lookup.sh CHALLENGE_MODE_MAPS_UPDATE
bash Tools/wow-api-lookup.sh CreateFrame
bash Tools/wow-api-lookup.sh --source framexml C_MythicPlus.GetRunHistory
bash Tools/wow-api-lookup.sh --source framexml C_WeeklyRewards   # namespace only: lists all symbols
```

The script resolves the page title itself. Worth knowing if you fetch by hand: the wiki puts API functions under an `API_` prefix (`API_C_ChallengeMode.GetMapTable`) but events under the bare name (`CHALLENGE_MODE_MAPS_UPDATE`).

### Browsing warcraft.wiki.gg

- **Full API index**: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- **Events index**: https://warcraft.wiki.gg/wiki/Events
- **Widget API**: https://warcraft.wiki.gg/wiki/Widget_API

### Browsing townlong-yak

URL scheme: `https://www.townlong-yak.com/framexml/live/<path>` for the current live build, or `…/framexml/<build>/<path>` (e.g. `69587`) to pin one. Build index: https://www.townlong-yak.com/framexml/live

**Generated API definitions** live under `Blizzard_APIDocumentationGenerated/`. File names follow the namespace with one of three suffixes — `<Base>Documentation.lua`, `<Base>InfoDocumentation.lua`, `<Base>ConstantsDocumentation.lua`, where `Base` is the namespace without its `C_` prefix. Verified for this addon:

| Namespace | File |
|---|---|
| `C_MythicPlus` | `MythicPlusInfoDocumentation.lua` |
| `C_ChallengeMode` | `ChallengeModeInfoDocumentation.lua` |
| `C_WeeklyRewards` | `WeeklyRewardsDocumentation.lua` |
| `C_CurrencyInfo` | `CurrencyInfoDocumentation.lua` |
| `C_PlayerInfo` | `PlayerInfoDocumentation.lua` |
| currency enums and IDs | `CurrencyConstantsDocumentation.lua` |

Each file documents functions, **events with their payloads**, and the struct types referenced in signatures — all three appear in the script's namespace-only symbol listing.

**FrameXML source** is browsable at the same root and is the reference for Atlas and template names when extending `Core/Theme.lua`. Blizzard's own Mythic+ UI: `Blizzard_ChallengesUI/Blizzard_ChallengesUI.lua`. Every file states which build last changed it, so you can tell a stable API from a churning one.

## Constraints

- **Directory listings return 404.** You must know the file name; only the build index page lists them.
- **The "Globe" search is a JS app** with hash URLs (`/globe/#h:…`). Unusable from `curl` or a fetch tool — don't try.
- **townlong-yak's `robots.txt` disallows `/framexml/` for crawlers.** Single, on-demand lookups only: never loop over files, never bulk-download, never wire this into CI. `warcraft.wiki.gg` stays the default source for that reason.

## Key Namespaces Used in This Addon

| Namespace | Purpose |
|-----------|---------|
| `C_MythicPlus` | Run history, season scores, key levels |
| `C_ChallengeMode` | Dungeon map info, time limits, affixes |
| `C_CurrencyInfo` | Currency IDs and amounts |
| `C_WeeklyRewards` | Weekly vault slots and progress |
| `C_PlayerInfo` | Player level, spec, class info |

## Important Notes

- This addon targets **Interface 120100** (patch 12.1.0, Midnight) — see `MythicPlusTracker.toc`. The townlong-yak live build matches it, so its definitions are authoritative for us.
- WoW uses **Lua 5.1** — standard library differences apply.
- Deprecated APIs may still work but should be replaced with current equivalents.
