import Testing
import Foundation
@testable import ClaudeAgentsMonitor

@Suite("CronExpression")
struct CronExpressionTests {
    @Test("@daily alias parses to midnight")
    func dailyAlias() {
        let cron = CronExpression("@daily")
        #expect(cron != nil)
        #expect(cron?.minutes == [0])
        #expect(cron?.hours == [0])
    }

    @Test("Every 15 minutes step")
    func every15min() {
        let cron = CronExpression("*/15 * * * *")
        #expect(cron?.minutes == [0, 15, 30, 45])
    }

    @Test("Weekdays 9am")
    func weekdays9am() {
        let cron = CronExpression("0 9 * * 1-5")
        #expect(cron?.minutes == [0])
        #expect(cron?.hours == [9])
        #expect(cron?.weekdays == [1, 2, 3, 4, 5])
    }

    @Test("Invalid expressions")
    func invalid() {
        #expect(CronExpression("bogus") == nil)
        #expect(CronExpression("0 25 * * *") == nil)
        #expect(CronExpression("0 0 0 * *") == nil)
    }

    @Test("Matches specific timestamp")
    func matches() {
        let cron = CronExpression("30 14 * * *")!
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        c.hour = 14; c.minute = 30
        #expect(cron.matches(Calendar.current.date(from: c)!))
    }

    @Test("Next date after now")
    func nextDateAfter() {
        let cron = CronExpression("0 9 * * *")!
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        c.hour = 10; c.minute = 0
        let date = Calendar.current.date(from: c)!
        let next = cron.nextDate(after: date)
        #expect(next != nil)
        let comps = Calendar.current.dateComponents([.day, .hour, .minute], from: next!)
        #expect(comps.day == 12)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
    }
}
