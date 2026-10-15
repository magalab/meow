import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

struct CalculatorTests {
    @Test
    func evaluatesOperatorPrecedenceAndParentheses() {
        let calculator = CalculatorEvaluator()

        #expect(calculator.evaluate("1 + 2 * 3") == Decimal(7))
        #expect(calculator.evaluate("(1 + 2) * 3") == Decimal(9))
        #expect(calculator.evaluate("-5.5 * 2") == Decimal(-11))
    }

    @Test
    func evaluatesPercentagesAndRejectsInvalidExpressions() {
        let calculator = CalculatorEvaluator()

        #expect(calculator.evaluate("20%") == Decimal(string: "0.2"))
        #expect(calculator.evaluate("50 * 20%") == Decimal(10))
        #expect(calculator.evaluate("1 / 3") != nil)
        #expect(calculator.evaluate("1 / 0") == nil)
        #expect(calculator.evaluate("(1 + 2") == nil)
        #expect(calculator.evaluate("1 + two") == nil)
        let largeNumber = String(repeating: "9", count: 100)
        #expect(calculator.evaluate("\(largeNumber) * \(largeNumber)") == nil)
    }
}
