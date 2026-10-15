import Foundation

/// Evaluates the deliberately small expression language supported by the launcher.
/// It never evaluates arbitrary code or invokes a scripting runtime.
struct CalculatorEvaluator: Sendable {
    func evaluate(_ expression: String) -> Decimal? {
        var parser = Parser(Array(expression))
        return parser.parse()
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        init(_ characters: [Character]) {
            self.characters = characters
        }

        mutating func parse() -> Decimal? {
            skipWhitespace()
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            return index == characters.count ? value : nil
        }

        private mutating func parseExpression() -> Decimal? {
            guard var value = parseTerm() else { return nil }

            while true {
                skipWhitespace()
                guard let operation = currentCharacter, operation == "+" || operation == "-" else {
                    return value
                }
                index += 1
                guard let rhs = parseTerm() else { return nil }
                guard let nextValue = operation == "+" ? add(value, rhs) : subtract(value, rhs) else {
                    return nil
                }
                value = nextValue
            }
        }

        private mutating func parseTerm() -> Decimal? {
            guard var value = parseUnary() else { return nil }

            while true {
                skipWhitespace()
                guard let operation = currentCharacter, operation == "*" || operation == "/" else {
                    return value
                }
                index += 1
                guard let rhs = parseUnary() else { return nil }
                if operation == "/", rhs == 0 { return nil }
                guard let nextValue = operation == "*" ? multiply(value, rhs) : divide(value, rhs) else {
                    return nil
                }
                value = nextValue
            }
        }

        private mutating func parseUnary() -> Decimal? {
            skipWhitespace()
            guard let character = currentCharacter else { return nil }
            if character == "+" || character == "-" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return character == "-" ? negate(value) : value
            }
            return parsePostfix()
        }

        private mutating func parsePostfix() -> Decimal? {
            guard var value = parsePrimary() else { return nil }
            while true {
                skipWhitespace()
                guard currentCharacter == "%" else { return value }
                index += 1
                guard let percentage = divide(value, Decimal(100)) else { return nil }
                value = percentage
            }
        }

        private mutating func parsePrimary() -> Decimal? {
            skipWhitespace()
            if currentCharacter == "(" {
                index += 1
                guard let value = parseExpression() else { return nil }
                skipWhitespace()
                guard currentCharacter == ")" else { return nil }
                index += 1
                return value
            }

            let start = index
            var hasDigit = false
            var hasDecimalPoint = false
            while let character = currentCharacter {
                if character.isNumber {
                    hasDigit = true
                    index += 1
                } else if character == ".", !hasDecimalPoint {
                    hasDecimalPoint = true
                    index += 1
                } else {
                    break
                }
            }
            guard hasDigit else { return nil }
            return Decimal(string: String(characters[start..<index]))
        }

        private var currentCharacter: Character? {
            guard index < characters.count else { return nil }
            return characters[index]
        }

        private mutating func skipWhitespace() {
            while currentCharacter?.isWhitespace == true {
                index += 1
            }
        }

        private func add(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
            var result = Decimal.zero
            var lhs = lhs
            var rhs = rhs
            return acceptable(NSDecimalAdd(&result, &lhs, &rhs, .plain)) ? result : nil
        }

        private func subtract(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
            var result = Decimal.zero
            var lhs = lhs
            var rhs = rhs
            return acceptable(NSDecimalSubtract(&result, &lhs, &rhs, .plain)) ? result : nil
        }

        private func multiply(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
            var result = Decimal.zero
            var lhs = lhs
            var rhs = rhs
            return acceptable(NSDecimalMultiply(&result, &lhs, &rhs, .plain)) ? result : nil
        }

        private func divide(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
            guard rhs != 0 else { return nil }
            var result = Decimal.zero
            var lhs = lhs
            var rhs = rhs
            return acceptable(NSDecimalDivide(&result, &lhs, &rhs, .plain)) ? result : nil
        }

        private func negate(_ value: Decimal) -> Decimal? {
            var value = value
            var zero = Decimal.zero
            var result = Decimal.zero
            return acceptable(NSDecimalSubtract(&result, &zero, &value, .plain)) ? result : nil
        }

        private func acceptable(_ error: NSDecimalNumber.CalculationError) -> Bool {
            error == .noError || error == .lossOfPrecision
        }
    }
}
