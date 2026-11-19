# DateComponents reader slice

The observed open AppIntents loader imports require real DateComponents metadata:
`_$s10Foundation14DateComponentsVMa` and `_$s10Foundation14DateComponentsVMn`.
This slice compiles the original value implementation from swift-foundation
`swift-6.3.1-RELEASE`, revision `c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`.
`sources.json` pins its complete source digest; original notices and the full
Apache license with Swift exception are preserved.

The optional integer/boolean/calendar/time-zone fields, accessors, nil/Int.max
conversion, value semantics, equality, reflection and real Codable remain.
An inherited Hashable defect is fixed: equality equates an unset leap-month
flag with false, so hashing now combines `_isLeapMonth ?? false`. The original
candidate failed that Set test on M1; both failure receipts are retained.

The newer Objective-C bridging extension is excluded because the retained
NSDateComponents exposes only eight scalar fields. No successful bridge is
invented. `CalendarValues.swift` supplies a bounded real value adapter using
CoreFoundation calendars and immutable retained CFTimeZone objects, not dummy
calendar values. Compose/decompose use the exact existing open vector API
declarations in `include/SFCalendarRuntime`. Calendar values keep their settings
independently and create a private CFCalendar for each conversion.

Supported conversion scope is Gregorian and ISO calendars, fixed-offset time
zones and fields implemented by the retained CoreFoundation. Unsupported calendar
identifiers/autoupdating modes are rejected during decoding. Repeated-day
conversion policy is unavailable. The M1 lacks the IANA time-zone database, so
named-zone lookup returns nil; no named-zone/DST support is claimed. This is not
the full Foundation Calendar/TimeZone API or NSDateComponents bridge.

Prepare in a new owned directory and compile its two Swift sources in the
existing coherent Foundation, adding its `include` directory to the compiler
search path:

```sh
python3 integrations/siliconforest/finch/Preview/DateComponents/prepare.py \
  --source /path/to/pinned/swift-foundation \
  --output /path/to/fresh/owned/date-sources
```

The helper verifies the pin before writing, rejects an existing output, applies
the exact patch without fuzz, and copies the full license. No Data or prior
decoder/encoder source is edited. The preceding NSError conformance alias must
remain on the link.

## Measured M1 result

Private coherent library:
`runs/preview/app-private/calendar-values/build/libswiftFoundation.dylib`.
SHA-256:
`9d75adcf56def3473129eca719bf66df6d9178ae186172124a393010f1ac3f67`.
All 1,806 preceding exports remain (2,018 total); both required metadata symbols
and valid thin arm64 signatures are present.

Separate-client probe PID 2944 exits 0 for optional/scalar fields, independent
copies, Hashable equality, JSON encode/decode with calendar/time zone, epoch and
fixed-offset conversion, 2024 leap day, invalid 2023 leap day, invalid nanoseconds,
weekday/day-of-year and the ISO boundary 2016-01-01 = week 53 of 2015. IANA lookup
reports unavailable. The six unchanged error/Data/encoder/decoder/UUID/URL probes
also exit 0. All ten packet hashes, protected QTP Foundation, owner guards and
compositor PID 125 are unchanged under gui.lock. Receipt:
`runs/preview/app-private/evidence/calendar-values-20261119T071924Z.json`.
Static report: `app-private/calendar-values/linked-static-final.json`.

The changed tested provider advances a single standalone AppIntents `dlopen`
(PID 2978, exit 1) to `_$s10Foundation16AttributedStringVMa`. Packet and protected
hashes stay exact. Receipt:
`runs/preview/app-private/evidence/appintents-calendar-20261119T072036Z.json`.
REA host-wrapper capture:
`ev_e24f5d2ae68bf53e62fd111c141d0b5ff40ca7ede33877e7e2f2dae28fedb432`.
The remote receipt carries native PID/dyld/hash evidence; REA does not trace the
remote inferior directly. No Preview executable, window/input action, shared
install or active app-prefix change occurred.
