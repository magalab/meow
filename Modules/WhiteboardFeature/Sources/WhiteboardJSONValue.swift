import Foundation

enum WhiteboardJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([WhiteboardJSONValue])
    case object([String: WhiteboardJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WhiteboardJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: WhiteboardJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(WhiteboardJSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(WhiteboardJSONValue.init(any:)))
        default:
            self = .null
        }
    }

    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(value): return value
        case let .number(value): return value
        case let .string(value): return value
        case let .array(value): return value.map(\.anyValue)
        case let .object(value): return value.mapValues(\.anyValue)
        }
    }
}
