# Date intervals and calendar-unit aliases

The private Swift Foundation build uses the upstream DateInterval value
type from swift-foundation commit
`c20150400269a6afffe5b3a9f9fa8bbd51d69e1a`. Run `prepare.sh` against
that checkout and include its output and `CalendarUnit.swift` in the
Foundation build. The script verifies the source digest and leaves out the
NSDateInterval bridge because the installed Objective-C runtime lacks that
class. Calendar-unit names share the existing NSCalendarUnit bit values.

The M1 client checks closed interval boundaries, intersection, and
calendar-unit flag composition.
