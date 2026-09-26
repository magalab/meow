import Foundation

/// A small, dependency-free SentencePiece tokenizer for the MOSS tokenizer
/// asset. It uses the scores embedded in the model file to choose a
/// segmentation and supports byte-fallback pieces.
public struct MossTTSNanoTokenizer: Sendable {
    private let pieces: [SentencePieceModel.Piece]
    private let pieceToID: [String: Int]
    private let maxPieceLength: Int
    private let byteToID: [UInt8: Int]
    private let unknownScore: Float

    public init(modelData: Data) throws {
        let parsed = try SentencePieceModel.parse(modelData)
        guard !parsed.isEmpty else {
            throw MossTTSNanoTokenizerError.emptyVocabulary
        }
        pieces = parsed
        pieceToID = Dictionary(uniqueKeysWithValues: parsed.enumerated().map { ($0.element.text, $0.offset) })
        maxPieceLength = parsed.map { $0.text.unicodeScalars.count }.max() ?? 1
        unknownScore = (parsed.map(\.score).min() ?? -10) - 10
        byteToID = Dictionary(uniqueKeysWithValues: parsed.enumerated().compactMap { index, piece in
            guard piece.text.count == 6,
                  piece.text.hasPrefix("<0x"),
                  piece.text.hasSuffix(">"),
                  let value = UInt8(piece.text.dropFirst(3).dropLast(), radix: 16)
            else { return nil }
            return (value, index)
        })
    }

    public func encode(_ text: String) -> [Int32] {
        guard !text.isEmpty else { return [] }
        let normalized = "\u{2581}" + text.replacingOccurrences(of: " ", with: "\u{2581}")
        let scalars = Array(normalized.unicodeScalars)
        let count = scalars.count
        var bestScore = [Float](repeating: -.infinity, count: count + 1)
        var bestPiece = [(id: Int, start: Int)](repeating: (-1, 0), count: count + 1)
        bestScore[0] = 0

        for start in 0..<count {
            guard bestScore[start].isFinite else { continue }
            var coversScalar = false
            let upperBound = min(maxPieceLength, count - start)
            for length in 1...upperBound {
                let end = start + length
                let candidate = String(String.UnicodeScalarView(scalars[start..<end]))
                guard let id = pieceToID[candidate] else { continue }
                coversScalar = coversScalar || length == 1
                let score = bestScore[start] + pieces[id].score
                if score > bestScore[end] {
                    bestScore[end] = score
                    bestPiece[end] = (id, start)
                }
            }
            if !coversScalar {
                let score = bestScore[start] + unknownScore
                if score > bestScore[start + 1] {
                    bestScore[start + 1] = score
                    bestPiece[start + 1] = (-1, start)
                }
            }
        }

        var result: [Int32] = []
        var end = count
        while end > 0 {
            let piece = bestPiece[end]
            guard piece.start < end else { break }
            if piece.id >= 0 {
                result.append(Int32(piece.id))
            } else {
                result.append(contentsOf: byteFallbackIDs(for: scalars[piece.start]).reversed())
            }
            end = piece.start
        }
        return result.reversed()
    }

    private func byteFallbackIDs(for scalar: Unicode.Scalar) -> [Int32] {
        var result: [Int32] = []
        for byte in String(scalar).utf8 {
            guard let id = byteToID[byte] else { return [] }
            result.append(Int32(id))
        }
        return result
    }
}

public enum MossTTSNanoTokenizerError: Error, LocalizedError, Sendable, Equatable {
    case emptyVocabulary
    case invalidModel
    case invalidUTF8
    case unexpectedEnd

    public var errorDescription: String? {
        switch self {
        case .emptyVocabulary:
            return "MOSS-TTS-Nano tokenizer vocabulary is empty."
        case .invalidModel:
            return "MOSS-TTS-Nano tokenizer model is invalid."
        case .invalidUTF8:
            return "MOSS-TTS-Nano tokenizer contains invalid UTF-8."
        case .unexpectedEnd:
            return "MOSS-TTS-Nano tokenizer ended unexpectedly."
        }
    }
}

private struct SentencePieceModel {
    struct Piece {
        let text: String
        let score: Float
    }

    static func parse(_ data: Data) throws -> [Piece] {
        let bytes = Array(data)
        var offset = 0
        var pieces: [Piece] = []
        while offset < bytes.count {
            let (field, wire) = try readTag(bytes, count: bytes.count, offset: &offset)
            switch wire {
            case 0:
                _ = try readVarint(bytes, count: bytes.count, offset: &offset)
            case 1:
                offset += 8
            case 2:
                let length = try readVarint(bytes, count: bytes.count, offset: &offset)
                let end = offset + Int(length)
                guard end <= bytes.count else { throw MossTTSNanoTokenizerError.unexpectedEnd }
                if field == 1 {
                    pieces.append(try parsePiece(bytes, start: offset, end: end))
                }
                offset = end
            case 5:
                offset += 4
            default:
                throw MossTTSNanoTokenizerError.invalidModel
            }
            guard offset <= bytes.count else { throw MossTTSNanoTokenizerError.unexpectedEnd }
        }
        return pieces
    }

    private static func parsePiece(_ bytes: [UInt8], start: Int, end: Int) throws -> Piece {
        var offset = start
        var text = ""
        var score: Float = 0
        while offset < end {
            let (field, wire) = try readTag(bytes, count: end, offset: &offset)
            switch wire {
            case 0:
                _ = try readVarint(bytes, count: end, offset: &offset)
            case 1:
                offset += 8
            case 2:
                let length = try readVarint(bytes, count: end, offset: &offset)
                let fieldEnd = offset + Int(length)
                guard fieldEnd <= end else { throw MossTTSNanoTokenizerError.unexpectedEnd }
                if field == 1 {
                    guard let value = String(bytes: bytes[offset..<fieldEnd], encoding: .utf8) else {
                        throw MossTTSNanoTokenizerError.invalidUTF8
                    }
                    text = value
                }
                offset = fieldEnd
            case 5:
                guard offset + 4 <= end else { throw MossTTSNanoTokenizerError.unexpectedEnd }
                if field == 2 {
                    let bits = UInt32(bytes[offset])
                        | UInt32(bytes[offset + 1]) << 8
                        | UInt32(bytes[offset + 2]) << 16
                        | UInt32(bytes[offset + 3]) << 24
                    score = Float(bitPattern: bits)
                }
                offset += 4
            default:
                throw MossTTSNanoTokenizerError.invalidModel
            }
        }
        return Piece(text: text, score: score)
    }

    private static func readTag(
        _ bytes: [UInt8],
        count: Int,
        offset: inout Int
    ) throws -> (Int, Int) {
        let tag = try readVarint(bytes, count: count, offset: &offset)
        return (Int(tag >> 3), Int(tag & 0x07))
    }

    private static func readVarint(
        _ bytes: [UInt8],
        count: Int,
        offset: inout Int
    ) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while offset < count {
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift >= 64 { throw MossTTSNanoTokenizerError.invalidModel }
        }
        throw MossTTSNanoTokenizerError.unexpectedEnd
    }
}
