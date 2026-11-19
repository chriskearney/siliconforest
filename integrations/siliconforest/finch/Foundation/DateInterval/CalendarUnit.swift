// SPDX-License-Identifier: MIT
extension NSCalendar {
    public typealias Unit = NSCalendarUnit
}

extension NSCalendarUnit {
    public static var era: Self { .calendarUnitEra }
    public static var year: Self { .calendarUnitYear }
    public static var month: Self { .calendarUnitMonth }
    public static var day: Self { .calendarUnitDay }
    public static var hour: Self { .calendarUnitHour }
    public static var minute: Self { .calendarUnitMinute }
    public static var second: Self { .calendarUnitSecond }
    public static var weekday: Self { .calendarUnitWeekday }
}
