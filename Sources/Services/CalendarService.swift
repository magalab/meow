import Foundation

struct MonthDayInfo: Identifiable {
    let id: String
    let date: Date
    let day: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let lunarDay: String
    let lunarMonth: String?
    let solarTerm: String?
    let holiday: String?
    let isWeekend: Bool
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    let solarTermNames: [String] = [
        "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
        "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
        "立冬", "小雪", "大雪", "冬至", "小寒", "大寒",
    ]

    private let solarTermNamesEN: [String] = [
        "Beginning of Spring", "Rain Water", "Awakening of Insects", "Spring Equinox",
        "Clear and Bright", "Grain Rain", "Beginning of Summer", "Grain Buds",
        "Grain in Ear", "Summer Solstice", "Minor Heat", "Major Heat",
        "Beginning of Autumn", "End of Heat", "White Dew", "Autumn Equinox",
        "Cold Dew", "Frost Descent", "Beginning of Winter", "Minor Snow",
        "Major Snow", "Winter Solstice", "Minor Cold", "Major Cold",
    ]

    private let lunarDayNames: [Int: String] = [
        1: "初一", 2: "初二", 3: "初三", 4: "初四", 5: "初五",
        6: "初六", 7: "初七", 8: "初八", 9: "初九", 10: "初十",
        11: "十一", 12: "十二", 13: "十三", 14: "十四", 15: "十五",
        16: "十六", 17: "十七", 18: "十八", 19: "十九", 20: "二十",
        21: "廿一", 22: "廿二", 23: "廿三", 24: "廿四", 25: "廿五",
        26: "廿六", 27: "廿七", 28: "廿八", 29: "廿九", 30: "三十",
    ]

    private let lunarDayNamesEN: [Int: String] = [
        1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 5: "5th",
        6: "6th", 7: "7th", 8: "8th", 9: "9th", 10: "10th",
        11: "11th", 12: "12th", 13: "13th", 14: "14th", 15: "15th",
        16: "16th", 17: "17th", 18: "18th", 19: "19th", 20: "20th",
        21: "21st", 22: "22nd", 23: "23rd", 24: "24th", 25: "25th",
        26: "26th", 27: "27th", 28: "28th", 29: "29th", 30: "30th",
    ]

    private let lunarMonthNames: [Int: String] = [
        1: "正月", 2: "二月", 3: "三月", 4: "四月", 5: "五月", 6: "六月",
        7: "七月", 8: "八月", 9: "九月", 10: "十月", 11: "冬月", 12: "腊月",
    ]

    private let lunarMonthNamesEN: [Int: String] = [
        1: "1st Month", 2: "2nd Month", 3: "3rd Month", 4: "4th Month",
        5: "5th Month", 6: "6th Month", 7: "7th Month", 8: "8th Month",
        9: "9th Month", 10: "10th Month", 11: "11th Month", 12: "12th Month",
    ]

    private let solarTerms: [String: [String]]

    private let chineseCalendar: Calendar = {
        var cal = Calendar(identifier: .chinese)
        cal.locale = Locale(identifier: "zh-Hans")
        return cal
    }()

    private let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        return cal
    }()

    private init() {
        if let url = Bundle.module.url(forResource: "solar_terms", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]]
        {
            solarTerms = json
        } else {
            solarTerms = [:]
        }
    }

    func monthDays(year: Int, month: Int) -> [MonthDayInfo] {
        let components = DateComponents(year: year, month: month, day: 1)
        guard let firstOfMonth = gregorian.date(from: components) else { return [] }

        let weekday = gregorian.component(.weekday, from: firstOfMonth)
        let startDayOffset = (weekday - gregorian.firstWeekday + 7) % 7

        guard let startDate = gregorian.date(byAdding: .day, value: -startDayOffset, to: firstOfMonth) else {
            return []
        }

        let monthRange = gregorian.range(of: .day, in: .month, for: firstOfMonth)
        let daysInMonth = monthRange?.count ?? 31
        let totalDays = startDayOffset + daysInMonth > 35 ? 42 : 35
        let today = Date()
        let todayComponents = gregorian.dateComponents([.year, .month, .day], from: today)

        var result: [MonthDayInfo] = []
        let isChineseLang = isChineseLanguage

        for i in 0..<totalDays {
            guard let date = gregorian.date(byAdding: .day, value: i, to: startDate) else { continue }
            let dc = gregorian.dateComponents([.year, .month, .day], from: date)

            let isCurrentMonth = dc.month == month
            let isToday = dc.year == todayComponents.year && dc.month == todayComponents.month && dc.day == todayComponents.day
            let isWeekend = isWeekendDay(date)

            let lunarDC = chineseCalendar.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
            let lunarDay = lunarDayNames[lunarDC.day ?? 1] ?? "\(lunarDC.day ?? 1)"
            let lunarDayEN = lunarDayNamesEN[lunarDC.day ?? 1] ?? "\(lunarDC.day ?? 1)"

            var lunarMonth: String?
            if lunarDC.day == 1, let m = lunarDC.month {
                let baseName = isChineseLang
                    ? (lunarMonthNames[m] ?? "\(m)月")
                    : (lunarMonthNamesEN[m] ?? "\(m) Month")
                if lunarDC.isLeapMonth == true {
                    lunarMonth = isChineseLang ? "闰\(baseName)" : "Leap \(baseName)"
                } else {
                    lunarMonth = baseName
                }
            }

            let term = findSolarTerm(year: dc.year ?? year, month: dc.month ?? month, day: dc.day ?? 1)

            let holiday = findHoliday(
                solarYear: dc.year ?? year, solarMonth: dc.month ?? month, solarDay: dc.day ?? 1,
                lunarMonth: lunarDC.month, lunarDay: lunarDC.day, isLeap: lunarDC.isLeapMonth ?? false
            )

            let lunarLabel = isChineseLang ? lunarDay : lunarDayEN

            let id = "\(dc.year ?? 0)-\(dc.month ?? 0)-\(dc.day ?? 0)"
            result.append(MonthDayInfo(
                id: id,
                date: date,
                day: dc.day ?? i,
                isCurrentMonth: isCurrentMonth,
                isToday: isToday,
                lunarDay: lunarLabel,
                lunarMonth: lunarMonth,
                solarTerm: term,
                holiday: holiday,
                isWeekend: isWeekend
            ))
        }

        return result
    }

    func monthYearString(year: Int, month: Int) -> String {
        let isChinese = isChineseLanguage
        if isChinese {
            return "\(year)年\(month)月"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        if let date = gregorian.date(from: DateComponents(year: year, month: month, day: 1)) {
            return formatter.string(from: date)
        }
        return "\(month)/\(year)"
    }

    var weekdaySymbols: [String] {
        if isChineseLanguage {
            return ["日", "一", "二", "三", "四", "五", "六"]
        }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    var todayDateString: String {
        let now = Date()
        let dc = gregorian.dateComponents([.year, .month, .day, .weekday], from: now)
        let lunarDC = chineseCalendar.dateComponents([.month, .day, .isLeapMonth], from: now)
        let lunarDay = lunarDayNames[lunarDC.day ?? 1] ?? "\(lunarDC.day ?? 1)"
        let lunarMonth = lunarMonthNames[lunarDC.month ?? 1] ?? "\(lunarDC.month ?? 1)月"
        let leapStr = lunarDC.isLeapMonth == true ? "闰" : ""

        if isChineseLanguage {
            return "\(dc.year ?? 0)年\(dc.month ?? 0)月\(dc.day ?? 0)日  农历\(leapStr)\(lunarMonth)\(lunarDay)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: now)
    }

    // MARK: - Private

    private var isChineseLanguage: Bool {
        LanguageManager.shared.currentLanguageCode.hasPrefix("zh")
    }

    private func isWeekendDay(_ date: Date) -> Bool {
        let wd = gregorian.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    private func findSolarTerm(year: Int, month: Int, day: Int) -> String? {
        let mmdd = String(format: "%02d%02d", month, day)
        let lookupYear = month == 1 ? year - 1 : year
        let key = "\(lookupYear)"
        guard let terms = solarTerms[key], let index = terms.firstIndex(of: mmdd) else {
            return nil
        }
        if isChineseLanguage {
            return solarTermNames[index]
        } else {
            return solarTermNamesEN[index]
        }
    }

    private func findHoliday(
        solarYear: Int, solarMonth: Int, solarDay: Int,
        lunarMonth: Int?, lunarDay: Int?, isLeap: Bool
    ) -> String? {
        if solarMonth == 1, solarDay == 1 {
            return isChineseLanguage ? "元旦" : "New Year's Day"
        }
        if solarMonth == 5, solarDay == 1 {
            return isChineseLanguage ? "劳动节" : "Labour Day"
        }
        if solarMonth == 10, solarDay == 1 {
            return isChineseLanguage ? "国庆节" : "National Day"
        }
        if let term = findSolarTerm(year: solarYear, month: solarMonth, day: solarDay) {
            if (isChineseLanguage && term == "清明") || (!isChineseLanguage && term == "Clear and Bright") {
                return isChineseLanguage ? "清明节" : "Qingming Festival"
            }
        }
        if !isLeap, let lm = lunarMonth, let ld = lunarDay {
            if lm == 1, ld == 1 {
                return isChineseLanguage ? "春节" : "Spring Festival"
            }
            if lm == 5, ld == 5 {
                return isChineseLanguage ? "端午节" : "Dragon Boat Festival"
            }
            if lm == 8, ld == 15 {
                return isChineseLanguage ? "中秋节" : "Mid-Autumn Festival"
            }
        }
        return nil
    }
}
