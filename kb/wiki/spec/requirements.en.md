---
id: requirements
title: "JinMac, a workload checkup app for the Mac: development requirements"
type: requirements
version: "1.3"
date: "2026-09-22"
lang: en
parents: []
entities:
  - name: collector
    type: component
    definition: "the layer that reads memory, CPU, GPU, disk, thermal and context metrics every 5 seconds by default. it records a failed read as missing rather than 0, never stops, and keeps its own load under 1% CPU"
    code: [CoreKit/Sources/Collector/Sampler.swift]
  - name: sample-store
    type: component
    definition: "the layer that stores checkup data in a single SQLite file under ~/Library/Application Support/JinMac/. it uses the system SQLite3 directly, with no third-party dependency"
    code: [CoreKit/Sources/Store/SampleStore.swift]
  - name: workload-tagging
    type: mechanism
    definition: "sorts the frontmost app's bundle ID into 10 workload categories. it is the evidence for which task a limit signal happened under, and the mapping is a bundled JSON the user can edit"
    code:
      - CoreKit/Sources/Workload/WorkloadCategory.swift
      - CoreKit/Sources/Workload/Resources/app-categories.json
  - name: rule-engine
    type: component
    definition: "the layer that turns the share of active time each resource spent at its limit signal into ample, watch or limit. same input must give same output, so it uses no clock, no randomness and no unordered iteration"
    code:
      - CoreKit/Sources/Verdict/RuleEngine.swift
      - CoreKit/Sources/Verdict/RuleSet.swift
  - name: rule-thresholds
    type: constraint
    definition: "keeps thresholds and per-resource grade caps in a bundled JSON rather than code, so they can be recalibrated from community feedback without shipping a new app"
    code: [CoreKit/Sources/Verdict/Resources/rules.json]
  - name: limit-signal
    type: concept
    definition: "the definition of the moment a resource counts as at its limit. grades come from the share of active time this signal covers, so a wrong definition cannot be fixed by tuning thresholds"
  - name: active-time
    type: concept
    definition: "the denominator of every verdict, with idle time removed. under 10 hours the verdict is withheld instead of graded"
  - name: intended-full-load
    type: mechanism
    definition: "an auxiliary rule that treats a CPU limit during work that is meant to saturate the CPU, such as rendering, compiling or exporting, as normal operation rather than a bottleneck, and lowers the grade by one step"
  - name: memory-pressure-level
    type: api
    definition: "the memory pressure level macOS assigns (normal, warning, critical). RAM cannot be upgraded after purchase on Apple Silicon, so this signal is judged most conservatively"
  - name: checkup-report
    type: component
    definition: "the report, holding the verdict and the prose separately. it carries schema_version so that compatibility is checked first when a report from another machine is compared side by side"
    code: [CoreKit/Sources/Report/CheckupReport.swift]
  - name: report-card
    type: concept
    definition: "a single PNG for community posts. it carries only machine specs, checkup period, per-resource grades and top workloads with no personal data, and doubles as promotion for an app with no App Store presence"
  - name: narrator
    type: component
    definition: "the layer that takes only the rule engine's result and polishes it into Korean prose with Foundation Models. it cannot change grades or numbers, and falls back to template sentences when unavailable"
    code: [CoreKit/Sources/Narrator/NarratorAvailability.swift]
  - name: menu-bar-app
    type: component
    definition: "an app that lives as a single menu bar icon. it draws no live graphs, so it does not compete with existing monitor apps"
    code:
      - App/JinMacApp.swift
      - App/Views/MenuContentView.swift
  - name: no-network
    type: constraint
    definition: "the promise that the app makes no network request other than the update check. collection, storage, analysis and report generation all finish on the user's machine"
  - name: ad-hoc-signing
    type: constraint
    definition: "signing with no developer enrollment. users must get past the Gatekeeper warning themselves. a development build signed with codesign -s - changes its signature every build, which undoes the login item registration, so the released build is signed with a self-signed certificate that pins the designated requirement across versions"
    code: [scripts/release.sh]
  - name: xcodegen
    type: script
    definition: "the tool that generates JinMac.xcodeproj from project.yml. the .xcodeproj is a generated artifact and is never edited by hand"
    code: [project.yml]
tags: [requirements, v1, menu-bar-app, workload-checkup, rule-engine, on-device-ai]
---

# JinMac, a workload checkup app for the Mac: development requirements

> Translation of [requirements.md](requirements.md) v1.0. The Korean edition is the source of
> record where wording differs. Do not edit here.

> Sources: requirements draft (2026-09-17, @Someone)
> Raw: [2026-09-17-requirements-draft.md](../../raw/references/2026-09-17-requirements-draft.md)

Requirements for an app that measures the real work done on a Mac over 1 to 2 weeks, grades each
resource as ample, watch or limit, and produces a Korean report that can back the decision on the
next machine to buy.

§1 through §13 are carried over verbatim from the draft. Decisions made while building the project
skeleton, and review notes from checking the draft against the APIs macOS actually provides, are in
§14. When a review note is adopted, the affected section of the body is edited and its status in §14
changes.

---

## 1. Overview and purpose

This app answers the question "is this Mac handling the work I do right now?" with measured data.
It is a checkup tool, not a permanent monitor. After installation it records usage in the background
for 1 to 2 weeks, and when recording ends it generates a Korean "workload profile report"
(`작업 부하 프로파일 리포트`) once.

Existing monitoring apps (iStat Menus, Stats, TG Pro) stop at showing numbers, and MacPulse explains
events such as throttling and battery. What sets this app apart is that it grades, per resource, how
well the user's real workload fits the machine, and leaves evidence that can be used for the next
purchase decision.

The three things the report answers:

- how often each resource (RAM, CPU, GPU, disk, thermals) hit its limit over the period
- what work (frontmost app) was going on at the time
- if buying the next Mac, which items to upgrade and which can stay as they are

## 2. Core principles and constraints

Zero operating cost, zero data leaving the machine and no Apple developer enrollment shape the whole
design.

| Constraint | Requirement |
| --- | --- |
| Cost | No servers, cloud APIs, paid SDKs or paid certificates at all. The Apple Developer Program ($99/year) is not joined either. |
| Local only | Collection, storage, analysis and report generation all finish on the user's machine. The app makes no network requests (except the update check). |
| Interpretation | A deterministic rule engine makes the verdict; on-device AI is used only to polish the verdict into Korean prose. The AI never changes a verdict or makes up a number. |
| Distribution | Direct distribution through GitHub Releases. No App Store, no notarization, no Developer ID signing. |
| Revenue | Free. No ads, in-app purchases or telemetry. |
| Evidence first | Every verdict sentence is shown with its supporting numbers (share of time, count of occurrences, the app at the time). No recommendation without evidence is output. |

## 3. Target users and usage scenarios

The primary user is a Mac user facing their next purchase and wondering "is my current machine
enough, and what should I upgrade?". The person who asks in a community "is this spec enough for
this work?" is exactly this user.

| Scenario | User action | What the app does |
| --- | --- | --- |
| Pre-purchase checkup | Install and use as usual for 1 to 2 weeks | Record in the background → generate the report at the end |
| Checking a specific task | Click "start session" (`세션 시작`) before work such as video editing or a build, and "end session" (`세션 종료`) after | Record only that span at high resolution, 1-second interval → session report |
| Community sharing | Export the report card (PNG) and attach it to a post | Generate a standard-format card + JSON |
| Re-checkup | After switching to a new Mac, record the same period again | Compare with the previous report |

Users must be able to read the report without knowing technical terms. Terms such as "memory
pressure" (`메모리 압박`) and "swap" (`스왑`) are used in the report together with a one-line
explanation.

## 4. Functional requirements

Features fall into five stages: collection → tagging → verdict → report → export. The code in front
of each item (F-xx) is an identifier for issue tracking.

### 4.1 Collection (Collector)

| Code | Requirement | Note |
| --- | --- | --- |
| F-01 | Sample the metrics below at a default 5-second interval (configurable, 1 to 30 seconds) | Checkup period defaults to 14 days; the user picks 7/14/30 days |
| F-02 | Memory: total, used, compressed, swap used, cumulative swap in/out, macOS memory pressure level (normal/warning/critical) | `host_statistics64`, `sysctl vm.swapusage`, pressure level read on every sample from `sysctl kern.memorystatus_vm_pressure_level` (§14.2a) |
| F-03 | CPU: overall utilization, P-core and E-core utilization, current frequency | `host_processor_info`, IOReport (frequency) |
| F-04 | GPU: utilization, memory in use | IOKit `AGXAccelerator` statistics |
| F-05 | Disk: read/write throughput, I/O wait ratio, free space ratio | IOKit block storage statistics |
| F-06 | Thermals: CPU/GPU temperature, fan RPM, throttling state | SMC (IOHIDFamily on Apple Silicon). If a read fails, disable the item and carry on |
| F-07 | Power: whether there is a battery, whether on AC power | Battery mode is reflected in verdict weighting |
| F-08 | Context: per sample, the frontmost app's bundle ID and whether the screen is locked or idle | `NSWorkspace.frontmostApplication`, `CGEventSource` idle time |
| F-09 | Per sample, the names and usage of the top 5 CPU/memory processes | User data (file names, window titles) is not collected |
| F-10 | The collector's own CPU usage averages under 1%, resident memory under 50MB | The measuring tool must not create load |
| F-11 | Resume automatically after sleep or reboot. Login item registration only with the user's consent. Check the registration on every launch and say so in the menu when it has come undone | `SMAppService.mainApp`. The registration is tied to the code signature, so the released build is signed with a self-signed certificate (§10.1, §14.5a) |

### 4.2 Workload tagging

| Code | Requirement |
| --- | --- |
| F-20 | Automatically classify the frontmost app's bundle ID into a workload category via a built-in mapping table: video editing, photo and design, development (IDE and compiling), 3D and rendering, music production, virtual machines and containers, browsing and documents, games, AI and machine learning, other |
| F-21 | The mapping table is bundled in the app as JSON, and the user can override categories directly |
| F-22 | Manual session: when a span is marked with "start/end session" from the menu bar, that span is recorded at a 1-second interval and given a name |
| F-23 | Idle state (no input for 5 minutes or more, screen locked) is excluded from the verdict denominator. But if overall CPU utilization or GPU utilization stays at or above a threshold during that time (initial value 50%, in the bundled JSON), the time is classified as `무인 작업` ("unattended work") and kept in the denominator (§14.2f). Background load (indexing, backup) is shown as a separate item |

### 4.3 Rule engine

| Code | Requirement |
| --- | --- |
| F-30 | When the checkup period ends (or on user request), compute per-resource verdicts from the stored samples. For the criteria, see §5 |
| F-31 | A verdict consists of a per-resource grade (ample/watch/limit, `여유`/`경계`/`한계`) + supporting numbers + the top 3 workloads at the time + the top 3 processes at the time |
| F-32 | Rules and thresholds live in a bundled JSON, not in code, so they can be tuned without an app update |
| F-33 | The same input always gives the same output (deterministic). Guaranteed by unit tests |
| F-34 | If the data is not enough for a verdict (under 10 hours of active time), output "verdict withheld" (`판정 보류`) instead of a grade, with the reason |

### 4.4 Report generation

| Code | Requirement |
| --- | --- |
| F-40 | The report is generated in Korean. Structure: one summary paragraph → per-resource verdict cards → per-workload analysis → purchase notes → evidence data |
| F-41 | The summary and per-resource explanations are written by on-device AI (§6), given only the rule engine's result. When AI is unavailable, template sentences are used instead, and the user should not notice a difference |
| F-42 | Purchase notes are presented as two lists: "upgrading this would make a big felt difference" and "this can stay at the current level". No specific model names or prices |
| F-43 | The evidence section draws, with Swift Charts, the time distribution of memory pressure levels, P-core saturation time, and throttling counts and durations |
| F-44 | Reports are viewed inside the app, and past reports are kept as a list |

### 4.5 Export and sharing

| Code | Requirement |
| --- | --- |
| F-50 | Report card: a single PNG (1200×1600px) for community posts. Includes machine model, chip and RAM, checkup period, per-resource grades and top 3 workloads. No personal data such as user name or file names |
| F-51 | Full report PDF export |
| F-52 | Report JSON export (with schema version). Load another machine's JSON and show them side by side on a comparison screen |
| F-53 | Raw sample CSV export (optional) |

### 4.6 UI

| Code | Requirement |
| --- | --- |
| F-60 | A single resident menu bar icon. Clicking shows checkup progress (days elapsed/target days), session start/end, open report, settings |
| F-61 | No live graphs in the menu bar (does not compete with existing monitor apps) |
| F-62 | Main window: onboarding (disclosure of collected items and consent) → progress screen → report screen → report list |
| F-63 | The checkup can be paused, resumed and reset from the menu bar |
| F-64 | Korean by default, English resources prepared (report prose generation is Korean only in the first release) |

## 5. Rule engine verdict criteria (draft)

The denominator is active time with idle removed, and each resource is graded by "the share of
active time covered by its limit signal". The thresholds below are initial values and are tuned in
the bundled JSON (F-32).

| Resource | Limit signal definition | Ample | Watch | Limit |
| --- | --- | --- | --- | --- |
| Memory | Memory pressure "warning" or above, or swap-out growth > 1MB per second. Swap used serves only as a supporting number (§14.3a) | < 5% | 5 to 20% | > 20% |
| Memory (strong) | Memory pressure "critical" | 0% | < 2% | ≥ 2% |
| CPU | Average P-core utilization ≥ 90% sustained for 30 seconds or more | < 10% | 10 to 30% | > 30% |
| GPU | GPU utilization ≥ 90% sustained for 30 seconds or more | < 10% | 10 to 30% | > 30% |
| Thermal | Throttling (frequency drops 20% or more below rated & temperature rises) | 0 times | 1 to 3 times a week | 4 or more times a week, or a single event of 10 minutes or more |
| Disk | I/O wait ≥ 30% for 30 seconds or more, or free space < 15% | < 5% | 5 to 15% | > 15% or low on space |

Auxiliary verdict rules:

- Even if CPU is at "limit", if the workload at the time is one that is meant to run at full load,
  such as rendering, compiling or exporting, mark it "intended full load" and lower the grade by one
  step. Full load in itself is normal operation, not a bottleneck.
- If a memory "limit" and disk I/O wait overlap in the same time window, group them as "disk load
  caused by swap" and attribute it to memory.
- CPU and thermal signals that occurred only in battery mode are marked separately and judged again
  on data from AC power.
- If the strong memory signal ("memory (strong)") is at limit, the overall verdict is "limit"
  regardless of other items. On Apple Silicon RAM is the only resource that cannot be upgraded after
  purchase, so it is viewed most conservatively.
- The overall verdict follows the worst per-resource grade, but the evidence sentence states which
  resource caused it.

Purchase note mapping (F-42):

| Verdict | Purchase note (gist) |
| --- | --- |
| Memory limit | Make one step up in RAM the top priority on the next machine |
| Memory watch | Current capacity works, but consider more if the workload is expected to grow |
| CPU limit (not intended full load) | Step up to a chip tier with more cores |
| CPU limit (intended full load) | A chip upgrade shortens that task, but is not required |
| GPU limit | Step up to a chip tier with more GPU cores |
| Thermal limit | Consider a form factor with a fan (MacBook Pro, Mac mini, Mac Studio) |
| Disk low on space | More storage or an external SSD |

## 6. On-device AI requirements

AI uses Apple's Foundation Models framework (macOS 26 or later, Apple Intelligence enabled), and its
role is limited to polishing the rule engine's result into Korean prose.

| Code | Requirement |
| --- | --- |
| A-01 | Check availability with `SystemLanguageModel.default.availability`, and show the reason it is unavailable (device not supported, Apple Intelligence off, model downloading) on the settings screen |
| A-02 | Pass only the rule engine's structured result (per-resource grades, supporting numbers, top workloads and processes). Do not pass raw samples, the full process list or file paths |
| A-03 | Receive output as a `@Generable` struct: summary (3 sentences or fewer), per-resource explanations (2 sentences or fewer each), purchase note sentences. Never put free text into the report as is |
| A-04 | Instruct the prompt not to change grades and numbers, and in a verification step after generation check that the input numbers appear unchanged in the output. On mismatch, fall back to template sentences |
| A-05 | Considering the context limit (about 4,000 tokens), split calls by resource item. No more than 6 calls per report |
| A-06 | Target generation time is 10 seconds or less (on M1). If exceeded, show the template report first and fill in the AI sentences later |
| A-07 | When Foundation Models is unavailable, the fallback is template sentences. Whether the fallback was used is noted in one line at the bottom of the report |
| A-08 | Do not adopt approaches that bundle a model, such as llama.cpp or MLX. App size and heat create the "measuring tool creates load" problem |
| A-09 | Entering the user's own API key is out of scope for the first release (keeps the zero cost and zero network principle) |

Prompt design principles: polite explanatory Korean prose, cite evidence instead of asserting (for
example `~한 시간이 전체의 23%였습니다`, "time spent ~ was 23% of the total"), no exaggerated
vocabulary, no mention of model names or prices.

## 7. Data model and storage

All data is stored in one SQLite file under `~/Library/Application Support/<앱이름>/` (`<앱이름>`
is the app name placeholder), and this path is stated in the uninstall guidance.

| Table | Main columns | Note |
| --- | --- | --- |
| `sample` | ts, mem\_used, mem\_compressed, swap\_used, swap\_in, swap\_out, mem\_pressure(0/1/2), cpu\_total, cpu\_p, cpu\_e, cpu\_freq, gpu\_util, gpu\_mem, disk\_read, disk\_write, io\_wait, temp\_cpu, temp\_gpu, fan\_rpm, throttled(bool), on\_battery(bool), idle(bool), front\_app | 5-second interval, 14 days ≈ 240,000 rows, about 40MB |
| `top_process` | sample\_ts, name, cpu, mem | 5 rows per sample |
| `session` | id, name, started\_at, ended\_at, interval\_sec | Manual session metadata |
| `session_sample` | session\_id + same columns as `sample` | 1-second interval |
| `checkup` | id, started\_at, ended\_at, target\_days, status | One checkup = one row |
| `report` | id, checkup\_id, created\_at, verdict\_json, text\_json, schema\_version | Verdict and prose stored separately |
| `app_category` | bundle\_id, category, user\_overridden | Built-in mapping + user overrides |

- After a checkup ends and the report is generated, raw `sample` rows are condensed into a summary
  (hourly aggregates) and the originals are deleted after 30 days. The user can keep them as CSV.
- The report JSON schema carries `schema_version` so the comparison feature (F-52) can check
  compatibility.
- The stored file is not encrypted (nothing is sent out, and it contains no information about the
  user's files).

## 8. Non-functional requirements

| Area | Requirement |
| --- | --- |
| Resource use | While collecting, CPU averages under 1%, resident memory under 50MB, disk writes under 5MB a day. Energy impact shows as "Low" in Activity Monitor's Energy tab |
| Privacy | Zero network requests (except the update check). No collection of file names, window titles, URLs or document contents. Onboarding lists every collected item and asks for consent |
| Compatibility | Minimum macOS 14 (collection, rule engine, template report). AI prose generation needs macOS 26 or later + Apple Silicon + Apple Intelligence enabled. Intel Macs work without the P/E-core and frequency items |
| Robustness | Sensor read failures, denied permissions and clock jumps during sleep do not stop collection; only the affected sample is marked missing |
| Correctness | The rule engine is unit tested against a fixed sample set. Same input, same verdict |
| Accessibility | The report body must be readable with VoiceOver. Grades are shown as text, not by color alone |
| Security | No administrator privileges (root helper) required. No write actions such as fan control |
| Language | Korean first for UI and report. English UI resources are prepared, but report prose generation is Korean only in the first release |

## 9. Technology stack

Everything is built from Apple's own frameworks and free open source; no paid or server-dependent
libraries are used.

| Area | Choice | Reason |
| --- | --- | --- |
| Language and UI | Swift 6, SwiftUI, AppKit (menu bar `NSStatusItem`) | Native, no extra cost |
| Collection | Mach/BSD APIs (`host_statistics64`, `sysctl`), IOKit, IOReport (private, frequency and power) | Reachable without a sandbox. IOReport is a private API that can break on OS updates, hence a design that tolerates missing data |
| Temperature and fans | SMC reads (referencing the SMC code of the open source Stats app, MIT) | On Apple Silicon, via IOHIDFamily |
| Storage | SQLite (GRDB.swift, MIT) | Lightweight, convenient for aggregate queries |
| Charts | Swift Charts | Shared by the report and PDF rendering |
| Report rendering | SwiftUI `ImageRenderer` (PNG card), `NSPrintOperation` or ImageRenderer (PDF) | No external library needed |
| AI | Foundation Models framework | See §6 |
| Launch at login | `SMAppService` | Login item, requires user consent |
| Updates | Sparkle 2 (MIT), self-generated EdDSA key, appcast hosted on GitHub Pages | No developer enrollment needed |
| Build and distribution | Xcode, release zip built with GitHub Actions (free tier) | See §10 |
| Tests | XCTest, fixed sample fixtures for the rule engine | Verifies determinism |

## 10. Distribution

The zip is distributed directly through GitHub Releases. With no developer enrollment, the core
distribution challenge is guiding users to get past the Gatekeeper warning themselves.

### 10.1 Constraints created by not enrolling

| Constraint | Impact | Response |
| --- | --- | --- |
| No Developer ID signing or notarization | "Unidentified developer" warning on first launch. From macOS 15 the right-click → Open workaround is gone, and the user must press `그래도 열기` ("Open Anyway") in `시스템 설정 → 개인정보 보호 및 보안` (System Settings → Privacy & Security) | Installation guide with screenshots in README and release notes. Also give the terminal alternative `xattr -d com.apple.quarantine <앱경로>` |
| No signature = no app integrity guarantee | Users cannot check whether the distributed file was tampered with | Publish a SHA-256 checksum with every release. Always sign (an unsigned binary is refused outright on Apple Silicon). The released build is signed with a self-signed certificate (`JinMac Self-Signed`) that pins the designated requirement across versions, and a development build without the certificate uses ad-hoc signing (`codesign -s -`). The certificate does not remove the Gatekeeper warning (§14.5a) |
| No paid-account-only features such as iCloud, push or App Groups | This app does not use them | No impact |
| No App Store distribution | No search exposure | Communities (such as `맥쓰사`, a Korean Mac user community) and GitHub are the only channels. The report card serves as promotion |
| Use of Foundation Models | No special entitlement needed. Whether it works in an ad-hoc signed app needs verification on a real machine | Recorded as a risk in §12 |

### 10.2 Release procedure

1. Push a tag `vX.Y.Z` on the `main` branch
2. GitHub Actions (macOS runner, free tier) runs a Release build → ad-hoc signing → zip → SHA-256
3. Update appcast.xml with Sparkle `generate_appcast` and commit it to GitHub Pages
4. Create a GitHub Release with the zip, checksum and release notes (changes + link to install guide)
5. Do the first release by hand to validate the procedure, then automate

### 10.3 Repository layout

- License: MIT (keep the copyright notice if referencing Stats' SMC code)
- README: one line on the question the app answers, an example report card image, install guide
  (Gatekeeper workaround screenshots), full list of collected items, how to uninstall
- Issue template: for reporting verdict errors (asks for the report JSON to be attached)
- The app category mapping JSON (F-21) accepts contributions through PRs in the repository

## 11. Out of scope

The following are deliberately not built. They overlap existing apps, go against the cost and
server principles, or could undermine trust in the verdict.

- Live graphs and gauges in the menu bar (the territory of iStat Menus and Stats)
- Anything that writes to the system, such as fan control, force-quitting processes or memory
  cleaning
- A server aggregating data across users, anonymous statistics, automatic crash report submission
- Recommending specific Mac models or prices ("buy an M4 Pro with 24GB")
- Cloud LLM calls, user API key entry
- Bundling model files (llama.cpp, MLX)
- App Store distribution, sandbox support
- Game FPS measurement (MacPulse's territory, needs separate hooking)
- Windows and Linux support

## 12. Risks and open questions

The biggest risks are install abandonment due to the Gatekeeper warning and loss of trust due to
verdict errors.

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Users give up installing because of the Gatekeeper warning | Failure to gain users | Invest in the quality of the install guide. Build trust in communities before distributing |
| Foundation Models may not work in an ad-hoc signed app | All AI prose falls back | Verify early on a real machine. If it does not work, shift effort into template report quality |
| Private APIs such as IOReport break on OS updates | Frequency and throttling items go missing | Design that tolerates missing data (F-06). Prepare a temperature-based substitute verdict |
| Misconfigured thresholds cause wrong verdicts | "RAM is enough" wrong answer → bad purchase | Initially only the memory verdict may reach "limit"; other resources go up to "watch" only. Calibrate thresholds from community feedback |
| Incomplete app category mapping | Inaccurate workload analysis | Allow user overrides (F-21), PR contributions |
| Existing apps (MacPulse and others) add features | Differentiation weakens | Focus on Korean, community and the purchase verdict frame. Do not compete on features |

Open questions:

- [ ] Confirm on a real M1-or-later machine whether Foundation Models works in an ad-hoc signed app
- [ ] Obtain the temperature and frequency sensor key lists for each Apple Silicon generation (M1 to
  M5)
- [ ] App name and report card design
- [ ] Decide the default checkup period, 7 days vs 14 days (enough data vs user patience)
- [ ] Decide the scope of Intel Mac support (a test machine is needed if supported)

## 13. Development stages

The MVP is to carry a single memory verdict all the way through (collection → verdict → Korean
report → PNG card). Before adding more resource types, verify that one resource's verdict and prose
can be trusted.

| Stage | Scope | Done when |
| --- | --- | --- |
| 0. Verification | Calling Foundation Models, reading SMC temperatures and reading IOReport frequency from an ad-hoc signed app | Whether each of the three works is confirmed on a real machine |
| 1. MVP | Menu bar app, memory and CPU collection (F-02, F-03, F-08), SQLite storage, memory rule verdict, Korean template report, PNG card, manual GitHub Release | After a 7-day checkup on my own machine a report comes out, and the card can be posted to a community |
| 2. Richer interpretation | Foundation Models prose generation + verification (A-01\~A-07), workload tagging (F-20\~F-23), CPU, GPU and thermal verdicts, manual sessions | The report shows "under which work" the limit was reached |
| 3. Sharing and comparison | JSON export, import and comparison (F-52), PDF, Sparkle auto-update, automated Actions release | A new machine's report can be compared side by side with the previous one |
| 4. Calibration | Tune thresholds and category mapping from community feedback, handle verdict error issues | The verdict error report rate falls |

Each stage ends with one GitHub Release tag, and before starting the next stage it is shown to the
community once to gauge the response. The tags are `v0.1.0` for stage 1, `v0.2.0` for stage 2,
`v0.3.0` for stage 3 and `v0.4.0` for stage 4. Stage 0 is not distributed to users, so it gets no
tag, and a fix release between stages bumps the patch number, as in `v0.1.1`. The conditions for
`v1.0.0` are written once the acceptance criteria are defined (§14.5e).

The done-when of every stage includes passing its acceptance criteria. An acceptance criterion pairs
a fixed sample fixture with an expected verdict, and is defined before that verdict is implemented
(§14.3d).

---

## 14. Decisions and review notes (2026-09-17)

§1 through §13 are verbatim from the draft. This chapter records the decisions made while building
the project skeleton (§14.1) and the review notes from checking the draft against the APIs macOS
actually provides (§14.2\~§14.5).

Every review note starts **awaiting decision**. When one is adopted, the affected section of the body is
edited and the note's status becomes `채택 (날짜)` ("adopted (date)"). When one is rejected, one line
of reasoning is left. Items marked "confirmed on this machine" were checked with ordinary user
privileges on Apple M5, macOS 27.2 and Xcode 27.0.

### 14.1 Decisions

| Item | Decision | Relation to the draft |
| --- | --- | --- |
| App name | JinMac. Bundle ID `dev.liampark.jinmac` | Settles the app name among the open questions in §12. The report card design is still open |
| Data path | `~/Library/Application Support/JinMac/jinmac.sqlite` | Fills in the `<앱이름>` placeholder in §7 |
| SQLite access | Use the system SQLite3 directly instead of GRDB | Changes the storage row of §9. With 7 tables and mostly batch inserts and aggregate queries, a thin wrapper is enough. This brings third-party dependencies to zero. Sparkle, the only candidate, is deferred under the Automatic updates row below |
| Code structure | XcodeGen `project.yml` and a local SwiftPM package `CoreKit`. Eight modules inside the package, with the dependency direction enforcing design constraints | Supplements §9. The module layout is in the table below |
| Collection loop location (2026-09-22) | Periodic execution, batch buffering and checkup state transitions live in a new CoreKit module `Recorder`, not in the app. The app keeps only the context reads that need AppKit (F-08) | Supplements §9. This lets the state transitions and buffering be verified with `swift test` without launching the app. The module count goes from seven to eight |
| Initial grade caps | `rules.json` has a per-resource `max_grade`: only memory is `limit`, the rest are `watch` | The mitigation wording in §12 appears neither in the §5 table nor in F-32, so it moves into the rule file |
| Minimum OS and AI | Deployment target is macOS 14, and Foundation Models is weak-linked | Follows the compatibility row of §8. Confirmed in an actual build that it links as `LC_LOAD_WEAK_DYLIB` |
| Repository | Public GitHub repository | Using the Actions macOS runner of §10.2 at no extra cost requires a public repository |
| Automatic updates (2026-09-19) | Defer adopting Sparkle until after paid Apple Developer Program enrollment. Until then, new versions ship only as a zip the user downloads from GitHub Releases to replace the app, and the app never checks for new versions | Removes Sparkle from the updates row of §9, step 3 of §10.2 and the scope of stage 3 in §13. The draft's `"개발자 등록 불필요"` ("no developer enrollment needed") in §9 does not hold for this app's signing setup. An app ad-hoc signed with Hardened Runtime on cannot load `Sparkle.framework`, which has no Team ID, because of Library Validation; avoiding that needs the `com.apple.security.cs.disable-library-validation` exception. Moja reached the same conclusion on 2026-09-18. While deferred, the app opens no network connection at all, so the `"업데이트 확인 제외"` ("except update checks") carve-out in §2 and §8 does not apply |
| Default checkup period (2026-09-20) | Keep the draft's 14 days. The user picks 7/14/30 days, and can request a report mid-period once active time passes 10 hours (F-30, F-34) | Settles the default period among the open questions in §12. F-01 does not change. The costliest verdict error is the "RAM is enough" wrong answer (§12), so the choice favours the side less likely to miss heavy work done only now and then. The 7-day checkup in the stage 1 done-when of §13 is the developer picking 7 days |
| Intel Macs (2026-09-20) | Unofficial support. Build Universal and let it work up to the memory verdict, but with no test machine the README says it is unverified. Items Intel cannot provide (P/E cores, frequency and so on) go missing, and verdicts relying on them are withheld (F-34) | Settles the scope of Intel support among the open questions in §12. Follows the compatibility row of §8, "Intel Macs work without the P/E-core and frequency items", without guaranteeing that it works |

Modules and dependency direction:

| Module | Depends on | Requirements covered | Constraint kept |
| --- | --- | --- | --- |
| `Model` | nothing | Shared value types | An unread metric is `nil`, never 0 |
| `Collector` | Model | F-01\~F-11 | IOKit and private APIs are used here only |
| `Store` | Model | §7 | System SQLite3 only |
| `Recorder` | Model, Collector, Store | F-01, F-63 | Takes time as an argument, and no verdict-side module imports it |
| `Workload` | Model | F-20, F-21 | The mapping is bundled JSON |
| `Verdict` | Model, Workload | F-30\~F-34, §5 | No clock, no randomness, no unordered iteration, and no import of Collector, Store or Recorder |
| `Report` | Model, Verdict | The non-UI parts of F-40\~F-44, F-50\~F-53 | Encodes with sorted keys, so the same report is the same bytes |
| `Narrator` | Report | §6 | The only place that imports Foundation Models, and it takes only the verdict as input |

### 14.2 Review notes: collection

Collection methods named in §4.1 and §4.2 that do not match the metrics macOS actually provides.

### 14.2a F-02: read the memory pressure level on every sample

- Draft: F-02 names `dispatch_source` memory pressure events as the source of the pressure level.
- Problem: the event fires only at the moment the level **changes**. That does not fit sampling that
  records "the level right now" every 5 seconds, and once the app misses one event it has no way to
  know the current level.
- Proposal: read `sysctl kern.memorystatus_vm_pressure_level` on every sample. The values are 1
  (normal), 2 (warning) and 4 (critical), stored as the 0/1/2 of §7. Confirmed on this machine that
  it is readable with ordinary privileges. Keep `dispatch_source` as an auxiliary means of recording
  the moment the level changed more precisely than the sample interval.
- Status: adopted (2026-09-20). Only the `sysctl` polling is adopted; the `dispatch_source` auxiliary is not kept. Verdicts are computed as a share of sample time, so a change time more precise than the sample interval has no use, and §7 has no column to hold it

### 14.2b F-05: macOS has no I/O wait metric

- Draft: F-05 and the disk row of §5 use an "I/O wait ratio".
- Problem: I/O wait (iowait) is a category the Linux kernel splits CPU time into. On macOS
  `host_processor_info` gives only user, system, idle and nice. Implemented as written, this metric
  is always missing.
- Proposal: use the cumulative `Total Time (Read)`, `Total Time (Write)` and `Latency Time` that
  `IOBlockStorageDriver` reports in `Statistics`. Divide the increment over each interval by the
  sample interval and redefine the metric as "the share of time the disk was busy serving requests".
  Overlapping requests can push it above 1, so cap it. Confirmed on this machine that these keys are
  readable through public IOKit. Revise the signal definition in the disk row of §5 and the meaning
  of the `io_wait` column in §7 together.
- Status: awaiting decision

### 14.2c F-06: throttling cannot be judged from frequency and temperature alone

- Draft: F-06 collects throttling state, and the thermal row of §5 defines throttling as "frequency
  drops 20% or more below rated & temperature rises".
- Problem: Apple Silicon offers no separate value saying whether it is throttling. CPU frequency also
  drops normally when load falls and when work moves to E-cores, so frequency and temperature alone
  cannot tell "slowed by heat" from "less work to do".
- Proposal: use the public API `ProcessInfo.thermalState` (nominal, fair, serious, critical) as the
  primary signal, and count each span at `serious` or above as one throttling event. Use IOReport
  frequency only as supporting evidence that "P-core utilization is high yet frequency dropped". On
  Apple Silicon temperatures go through the private `IOHIDEventSystemClient`, so treat them, like
  IOReport, as allowed to be missing.
- Status: awaiting decision

### 14.2d F-09, F-23: usage of processes owned by other accounts may be unreadable with ordinary privileges

- Draft: F-09 collects the top 5 processes on every sample, and F-23 shows background load such as
  indexing and backup separately. §8 requires no administrator privileges (root helper).
- Problem: `ps` and `top` show every process's usage because both tools are installed setuid root
  (the permission bits were confirmed on this machine). An app with ordinary privileges calling
  `proc_pid_rusage` on a process owned by another account is likely to be refused. Yet Spotlight's
  `mds` and Time Machine's `backupd` are owned by root, and `mds_stores` by the `_mds_stores`
  account (confirmed on this machine). The very load F-23 wants to show separately may come out
  blank.
- Proposal: add this to stage 0 verification. If refused, show the remainder of overall CPU
  utilization minus the sum of readable processes as `시스템 프로세스(개별 측정 불가)` ("system
  processes (not individually measurable)"). Do not run `ps` every 5 seconds: the process spawn cost
  eats into the F-10 budget.
- Status: awaiting decision

### 14.2e F-04: find GPU statistics through the parent class IOAccelerator

- Draft: F-04 names IOKit `AGXAccelerator` statistics.
- Problem: the actual class name changes with each chip generation. On this machine (M5) it was
  `AGXAcceleratorG17G`. Hardcoding the name means the metric goes missing with every new chip.
- Proposal: match on the parent class `IOAccelerator` and read `Device Utilization %` and
  `In use system memory` from `PerformanceStatistics`. Confirmed on this machine that both values
  are readable through public IOKit.
- Status: awaiting decision

### 14.2f F-23: do not drop work left running while away from the machine

- Draft: F-23 removes time with no input for 5 minutes or more, or with the screen locked, from the
  verdict denominator.
- Problem: video exports, 3D renders and long builds are often started and left while the user steps
  away. As written, the heaviest time falls out of the verdict, and a machine that actually hit its
  limit can be graded "ample".
- Proposal: when CPU or GPU utilization is high, classify the time as `무인 작업` ("unattended
  work") rather than idle, even with no input, and keep it in the denominator. The utilization
  threshold goes into `rules.json`.
- Status: adopted (2026-09-20). The initial threshold is overall CPU utilization or GPU utilization of 50% or more. Background work such as Spotlight indexing usually stays below it and is filtered out, while builds and renders stay in the denominator

### 14.3 Review notes: verdict criteria

Notes on the verdict criteria of §5 and the completion criteria of §13.

### 14.3a §5 memory signal: look at swap growth instead of swap used

- Draft: the memory limit signal includes "swap used > 1GB".
- Problem: pages sent out to swap stay there after pressure eases, until they are read back or their
  process exits. If swap crosses 1GB once in the morning, the limit signal counts as on for the rest
  of the day and the share is inflated.
- Proposal: count as a signal only the samples where the increment of the cumulative `swap_out`
  exceeds a threshold. Keep swap used itself in the report as a supporting number.
- Status: adopted (2026-09-20). The initial threshold is 1MB per second. The increment over a sample interval is divided by the actual elapsed time before comparing, so 1-second sessions and 5-second samples share one threshold and a sleep gap never becomes a signal. Recalibrate after the 7-day checkup

### 14.3b §5 auxiliary rule: do not judge intended full load from the frontmost app alone

- Draft: if the workload is "one meant to run at full load, such as rendering, compiling or
  exporting", lower the CPU grade by one step.
- Problem: workloads are classified by the frontmost app (F-08, F-20). Start a build and look at a
  browser, and the frontmost category is `브라우징·문서` ("browsing and documents"), so the full load
  is not recognized as intended. Conversely, with an IDE open, an unrelated process hogging the CPU is
  recognized.
- Proposal: look at the top processes of that sample (F-09) as well as the frontmost category. Keep a
  list of process names for which full load is normal, such as `swift-frontend`, `clang` and
  `ffmpeg`, in `app-categories.json`.
- Status: awaiting decision

### 14.3c §5 thermal row: normalize the counts by active time

- Draft: thermal grades are set by "1 to 3 times a week" and "4 or more times a week".
- Problem: the checkup period is picked from 7/14/30 days (F-01), and daily usage varies from person
  to person. Dividing by calendar weeks favors whoever used the Mac less.
- Proposal: treat a fixed amount of active time as one week (for example, count per 40 active hours)
  so the denominator is active time. The reference hours go into `rules.json`.
- Status: awaiting decision

### 14.3d §13: there are no verifiable acceptance criteria

- Draft: the completion criteria of §13 are qualitative sentences such as "a report comes out" and
  "is shown".
- Problem: verdict errors are the biggest way this app loses trust (§12). Without a definition of
  what passes, there is no way to notice a regression that flips an earlier verdict when the §5
  thresholds are edited.
- Proposal: before starting stage 1, define acceptance criteria that pair fixed sample fixtures with
  expected verdicts. For example: "a 14-day fixture where memory pressure warning covers 21% of
  active time is judged memory limit". When a new identifier family is created, add it to
  `SYM_PREFIXES` in `scripts/kb.swift`.
- Status: adopted (2026-09-20). The criteria are defined not before stage 1 starts but right before the memory verdict is implemented. What they protect is the verdict, and the collection and storage work ahead of it does not touch the verdict. The identifier family (`AC-01` form) is added to `SYM_PREFIXES` when the acceptance criteria document is created

### 14.4 Review notes: on-device AI

Notes on §6 and §4.4.

### 14.4a A-04: the app inserts the numbers, not the model

- Draft: A-04 checks after generation that the input numbers appear unchanged in the output, and
  falls back to templates otherwise.
- Problem: this check fails in both directions. If the model rewrites `23%` as `23퍼센트` or `1.5GB`
  as `1,536MB`, a correct sentence is thrown away as a mismatch. Conversely, a sentence that invents
  and adds a number not in the input passes a check that only asks "are the input numbers present?".
- Proposal: have the model write only placeholders such as `{memory_limit_ratio}` instead of numbers,
  and have the app substitute them deterministically. Change the check to "the output contains no
  digits at all, and every placeholder is a name present in the input". Changing a number then
  becomes structurally impossible for the model.
- Status: awaiting decision

### 14.4b F-41, A-06, A-07: decide whether to reveal the fallback to the user

- Draft: F-41 says that when AI is unavailable "the user should not notice a difference", A-06 shows
  the template report first and fills in the AI prose afterwards, and A-07 notes the fallback at the
  bottom of the report.
- Problem: the three requirements conflict. Under A-06 the sentences change in front of the user,
  and under A-07 the difference is announced on purpose.
- Proposal: settle on one. The recommendation is to announce the fallback rather than hide it
  (A-07). That fits the evidence-first principle (§2), and when a verdict error is reported it shows
  which path produced the prose. In that case F-41 becomes "template sentences carry the same
  information".
- Status: awaiting decision

### 14.4c A-01: check Korean support separately

- Draft: A-01 lists device not supported, Apple Intelligence off and model downloading as reasons it
  is unavailable.
- Problem: report prose is produced only in Korean (F-64). Even when the model is available,
  generation fails if it does not support Korean.
- Proposal: check Korean support with `SystemLanguageModel.supportsLocale`, and add `한국어 미지원`
  ("Korean not supported") to the reasons.
- Status: awaiting decision. The skeleton's `NarratorAvailability` already performs this check

### 14.5 Review notes: distribution and non-functional

Notes on §8, §10 and §13.

### 14.5a F-11: with ad-hoc signing the login item can come undone after an update

- Draft: F-11 registers the login item with `SMAppService.mainApp`, and §10.1 distributes with ad-hoc
  signing.
- Problem: an `SMAppService` registration is tied to the app's code signature. An ad-hoc signature
  changes with every build, so replacing the app with an update can silently turn launch at login
  off. The developer guide of Moja, which ships the same way, records this caveat. If that happens
  mid-checkup, data is missing after the next reboot, and the user does not find out until the
  report arrives.
- Proposal: check the registration on every launch, and say so in the menu when it has come undone.
  Once Sparkle is adopted (§14.1), postpone installing an update while a checkup is in progress until
  the checkup ends.
- Status: adopted with a different method (2026-09-20). Checking and notifying leaves the cause in place, so, as Moja does, the released build is signed with a self-signed certificate (`JinMac Self-Signed`). The designated requirement then becomes `identifier "dev.liampark.jinmac" and certificate leaf H"..."` instead of a cdhash, and stays the same across versions. Moja confirmed on 2026-09-18 that the login item registration survived replacing the installed app, and `SMAppService` worked even though the certificate's root is untrusted. The proposal to check the registration on every launch and say so in the menu is kept too, against a lost certificate or an installed ad-hoc build. The stage 0 Foundation Models check is also done with this release signature. The certificate does not remove the Gatekeeper warning and carries no Team ID, so the Sparkle deferral in §14.1 is unchanged. The proposal to postpone updates during a checkup is revisited when Sparkle is adopted

### 14.5b §8: recording `top_process` easily pushes disk writes past 5MB a day

- Draft: §8 keeps disk writes under 5MB a day, §7 estimates `sample` at about 40MB for 14 days, and
  `top_process` has 5 rows per sample.
- Problem: `sample` alone is about 2.9MB a day. `top_process` reaches about 1.21 million rows in 14
  days, and each row carries a timestamp, a name, two numbers and an index entry, adding several MB a
  day. Pages rewritten by WAL checkpoints also count as writes.
- Proposal: record top processes only for samples where a limit signal is on, or cut them to once
  every 60 seconds. Measure the actual daily writes in stage 1 before settling this item.
- Status: awaiting decision

### 14.5c F-10, F-22: decide whether 1-second sessions count against the resource budget

- Draft: F-10 and §8 require the collector to average under 1% CPU, and F-22 records manual sessions
  at a 1-second interval.
- Problem: a 1-second interval costs five times the reads of a 5-second interval. Whether the 1%
  budget must hold during a session is not specified.
- Proposal: state a separate session budget. The user turned the session on to measure heavy work, so
  measure in stage 0 the level at which collection overhead does not blur the result.
- Status: awaiting decision

### 14.5d §10.2: state the Actions free-tier condition and SDK version

- Draft: §10.2 uses the GitHub Actions macOS runner on the free tier.
- Problem: using macOS runners at no extra cost requires a public repository. Compiling Foundation
  Models also requires the runner image to have an Xcode with a macOS 26 or later SDK.
- Proposal: state both conditions in §10.2. The repository has been made public (§14.1).
- Status: awaiting decision

### 14.5e §13: pair development stages with version numbers

- Draft: §13 says each stage ends with one GitHub Release tag, but does not set the tag numbers.
- Proposal: stage 1 is `v0.1.0`, stage 2 `v0.2.0`, stage 3 `v0.3.0` and stage 4 `v0.4.0`. Stage 0 is
  not distributed to users, so it gets no tag. `MARKETING_VERSION` in `project.yml` starts at `0.1.0`
  to match the stage 1 goal. The conditions for `v1.0.0` are written after the acceptance criteria
  proposed in §14.3d are defined.
- Status: adopted (2026-09-20). A fix release between stages bumps the patch number, as in `v0.1.1`
