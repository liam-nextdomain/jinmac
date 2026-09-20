---
id: probe-results
title: "Stage 0 probe results: sensors and permissions"
type: measurement
version: "1.0"
date: "2026-09-20"
parents:
  - id: requirements
    version: "1.2"
    sections: ["12", "13", "14.2c", "14.2d"]
    note: "answers, by measurement on a real machine, what ch. 13 lists for stage 0 verification and what ch. 12 leaves open. §14.2c and §14.2d stay awaiting decision; this only adds evidence to judge them by"
entities:
  - name: smc-thermal-keys
    type: api
    definition: "reading temperature and fan keys through the AppleSMC user client. it opens without administrator privileges and the key names are the sensor list itself, so a new chip generation means checking the key list again"
    code: [scripts/probes/probe-smc.swift]
  - name: hid-temperature-sensors
    type: api
    definition: "the private path that reads Apple Silicon temperatures through IOHIDEventSystemClient. sensor names are human-readable strings, easier to interpret than four-character SMC keys, but some sensors return values outside any temperature range"
    code: [scripts/probes/probe-smc.swift]
  - name: ioreport-frequency
    type: api
    definition: "the two-step path to CPU frequency. IOReport gives residency per DVFS state and the IORegistry pmgr node turns a state into a frequency; if either one shifts, the frequency goes missing"
    code: [scripts/probes/probe-ioreport.swift]
  - name: unmeasurable-system-cpu
    type: concept
    definition: "CPU time spent by processes owned by other accounts, whose usage cannot be read individually. it is knowable only as the remainder of total usage minus the sum that could be read, and that remainder grows the more idle the machine is"
    code: [scripts/probes/probe-rusage.swift]
tags: ["measurement", "probe", "collector", "apple-silicon", "private-api"]
---

# Stage 0 probe results: sensors and permissions

> Raw: [2026-09-20-thermal-sensors.md](../../raw/probes/2026-09-20-thermal-sensors.md)
> Raw: [2026-09-20-ioreport-cpu.md](../../raw/probes/2026-09-20-ioreport-cpu.md)
> Raw: [2026-09-20-proc-rusage.md](../../raw/probes/2026-09-20-proc-rusage.md)

This is what a real machine says about the sensor and permission items among the three things
requirements §13 asks stage 0 to verify. The Foundation Models check needs a distribution
signature, so it runs separately.

The machine is one Mac17,2 (Apple M5, macOS 27.2), and everything ran as an ordinary user with no
administrator privileges. The scripts are in `scripts/probes/` and the verbatim output is the three
raw documents above.

## 1. Summary of results

| What was checked | Result | Requirement |
|---|---|---|
| Can SMC temperature and fan keys be read with ordinary privileges | Yes. Of 2906 keys, 176 temperature keys and 24 fan keys | F-06 |
| Can Apple Silicon temperatures be read through IOHIDEventSystem | Yes. 46 of 47 temperature sensors returned a value | F-06 |
| Can the IOReport CPU frequency channels be read with ordinary privileges | Yes, though the library is not where convention says it is | F-03 |
| Can the usage of processes owned by other accounts be read | **No.** It is `EPERM`, without exception | F-09, F-23 |
| Per-generation sensor key lists for M1\~M4 | Not obtained. There is only one machine, an M5 | requirements §12 |

Three items work and one is blocked. The blocked one is what requirements §14.2d already expected,
and this document does not decide that review note. It only adds the numbers to decide it with.

## 2. Temperature and fans (F-06)

### 2.1 Both paths open

The `AppleSMC` user client opened without administrator privileges and reported 2906 registered
keys. Of the 176 temperature keys, those starting with `T`, 160 are of type `flt `, whose value is
degrees Celsius directly. Core die temperatures (`Tp00`\~`Tp1E`), the GPU family (`Tg04`\~`Tg1s`)
and the battery (`TB0T`\~`TB2T`) all came out.

`IOHIDEventSystemClient` was likewise created without administrator privileges. Of 47 services
matched as temperature sensors, 46 returned a value, and the sensor names are human-readable strings
such as `PMU tdie1` and `NAND CH0 temp`, which makes their meaning easier to place than a
four-character SMC key.

Since both work, F-06's temperature collection is feasible. Neither is a public API, though, so the
premise that both paths can disappear at any time still holds.

### 2.2 A successful read is not necessarily a temperature

The `PMU tdev1` sensor returned `-9202.86`. The read succeeded and raised no error. Storing such a
value as it is makes the rule engine compute a nonsense average temperature.

So temperature cannot be judged by read success alone. The value's range must be checked too, and a
value outside it left as missing. Alongside "missing is not zero", this calls for "success is not
valid".

### 2.3 A stopped fan and an unread fan are different

This machine's fan keys were `FNum` 1, `F0Ac` (current RPM) 0, `F0Mn` 2317 and `F0Mx` 6550. The fan
really was stopped at the time of measurement, and 0 is the correct value.

Writing a failed read as 0 makes it indistinguishable from this. Fan RPM must keep missing and 0
apart in storage.

### 2.4 Byte order differs by data type

`flt `, `si32` and `ioft` had to be read little-endian for the values to make sense. `ioft` is an
8-byte fixed-point (48.16) type, used by the GPU temperature family (`TG0B`, `TG0V`).

One `ui16` key (`F0CR`) has raw bytes `9600`, which is 38400 big-endian and 150 little-endian. Which
one it is was not settled. It is not a key any verdict uses, so it stays open. The raw bytes are kept
in the raw document, so it can be worked out later.

### 2.5 Per-generation key lists remain open

What requirements §12 lists as "obtain the temperature and frequency sensor key lists for each generation, M1
to M5" is filled in for M5 only. There is no machine of another generation, so there is no way to
check the rest.

Hardcoding key names makes the metric go silently missing on a generation nobody checked. In stage 2,
where thermal collection is actually built, keeping the key list in bundled JSON and filling it from
user reports should be considered alongside.

## 3. CPU frequency (F-03)

### 3.1 IOReport is not where the framework should be

`/System/Library/PrivateFrameworks/IOReport.framework/IOReport` does not exist on this machine. Most
published sample code hardcodes that path, and on macOS 27.2 `dlopen` fails on it.

`/usr/lib/libIOReport.dylib` opens. All 11 symbols were found, and no administrator privileges were
needed. Only an implementation that tries several candidate paths in turn will survive an OS
upgrade.

### 3.2 Bridging the channel dictionary to a Swift dictionary kills the process

`IOReportStateGetNameForIndex` **writes the resolved state name back into** the channel dictionary it
was passed. Hand it a dictionary bridged to Swift's `[String: Any]` and the process dies with
`unrecognized selector`.

Channels must be taken out of a sample with `CFDictionaryGetValue` and `CFArrayGetValueAtIndex`, so
that the original objects are passed through. Making this mistake on a path the collector runs every
5 seconds means the app dies on a schedule.

### 3.3 Frequency needs two sources to line up

What IOReport gives is not a frequency but residency per DVFS state. The table that turns a state
name (`V0P7`, `V3P15`) into a frequency lives in the IORegistry at `IODeviceTree:/arm-io/pmgr`.

The correspondence confirmed on this machine is:

| Cluster | IOReport channel | Frequency table | States | Range |
|---|---|---|---|---|
| Efficiency cores | `ECPU`, `ECPU0`\~`ECPU5` | `voltage-states1-sram` | 8 | 972\~3048MHz |
| Performance cores | `PCPU`, `PCPU0`\~`PCPU3` | `voltage-states5-sram` | 19 | 1308\~4608MHz |

The table's unit cannot be told from its name. `voltage-states1-sram` is in kHz while
`voltage-states9-sram` is in Hz, and `voltage-states1` and `voltage-states5` are not frequencies at
all but period values. Deciding the unit from the magnitude of the largest value in the table is
safer than trusting the name.

That frequency needs two paths to line up points the same way as the concern raised in
requirements §14.2c, which argues against making frequency a primary verdict signal. That review
note is still awaiting decision.

### 3.4 Residency is counted in 24MHz ticks

Summing one channel's residency across all states over a 1-second interval gives about 24,180,000.
That is ticks of the 24MHz timer. Two things follow from it.

- Active share: the whole minus the `IDLE` state.
- Average frequency: a weighted mean over the frequency table, weighted by residency in the active
  states.

While idle at the time of measurement, the efficiency cluster was 29.9% active at an average of
1497MHz, and the performance cluster 11.7% active at 2136MHz. If the collector uses this calculation as is,
F-03's "current frequency" becomes the average over the sample interval rather than an instantaneous
value. At a 5-second interval that is the more representative of the two.

## 4. Processes owned by other accounts (F-09, F-23)

### 4.1 Only usage is blocked; names and owners are readable

Of 863 processes, the 527 owned by my account all succeeded on `proc_pid_rusage`, and the remaining
336 all failed with `EPERM`. `mds`, `mds_stores` and `backupd`, named by requirements §14.2d, are
all in that group, as are `kernel_task`, `launchd` and `WindowServer`. There was not a single
exception.

What is blocked, though, is only usage. `proc_pidinfo` with `PROC_PIDTBSDINFO` is refused on the same
336, but the short form, `PROC_PIDT_SHORTBSDINFO`, succeeds on all 863. That is: which account runs
how many processes under what name is knowable, and only how much CPU they used is not.

The short form's name is truncated at 15 characters. Matching processes by name has to account for
that limit.

`ps` and `top` show every process because both are setuid root. Their permission bits were `4755` and
`4555`. Exactly as requirements §14.2d describes.

### 4.2 The unmeasured share grows the more idle the machine is

The remainder of total CPU busy time minus the sum over readable processes was measured under two
conditions.

| Interval | Mean CPU utilization | Total busy time | Sum read | Remainder |
|---|---|---|---|---|
| Idle | 5.1% | 0.510s | 0.217s | 57.4% |
| Loaded | 46.3% | 4.630s | 4.568s | 1.3% |

The load is the probe spinning cores itself, so it is owned by my account and therefore readable.

While the user is actually working, the remainder stays at 1 to 2%. The remainder grows while the
machine is idle, and what runs then is exactly Spotlight indexing and backup. That is, the very load
requirements §14.2d wants shown separately sits on the unmeasurable side.

Both numbers come from a single run on one machine, and the idle figure swings widely with whatever
happened to be running. Take the direction rather than the ratio: under load almost everything is
measured, while idle more than half of it drops out.

### 4.3 rusage times are not in nanoseconds

`rusage_info_v4`'s `ri_user_time` and `ri_system_time` are in mach absolute time units, not
nanoseconds. On Apple Silicon the two units differ by a factor of 41.67.

Building the probe walked straight into this trap. An interval that spent 5.03 seconds spinning 5
cores for a second came out as 0.120 seconds, and the remainder came out as a wrong 97.7%. Only after
converting through `mach_timebase_info` did it become 1.5%.

Code that handles CPU time must go through `mach_timebase_info`. The mistake raises no error and
merely divides the value by 42, so it is worth making a wrong unit conversion something a test can
catch.

## 5. What this hands to implementation

| What the probe established | Where it goes |
|---|---|
| Open IOReport by trying several candidate paths in turn | Stage 2 frequency collection |
| Handle channel dictionaries at the CoreFoundation level | Stage 2 frequency collection |
| Range-check temperature values and leave outliers missing | Stage 2 thermal collection |
| Keep fan RPM's missing and 0 apart | Stage 2 thermal collection |
| Convert CPU time through `mach_timebase_info` | Stage 1 CPU collection (F-03), top-process collection |
| Group the remainder that cannot be measured individually | After requirements §14.2d is decided |

## 6. Open questions

- The temperature sensor key lists for M1\~M4. They need either the machines or user reports
  (requirements §12).
- The byte order of the SMC `ui16` type. No verdict uses such a key, so it is not urgent.
- requirements §14.2c and requirements §14.2d are not decided by this document either. They are
  decided when stage 2 begins.
