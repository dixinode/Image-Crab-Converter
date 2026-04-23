import Foundation

public enum RenamePatternValidationError: Equatable, Sendable {
    case unexpectedClosingBrace
    case unclosedToken
    case emptyToken
    case invalidNumberPadding(String)
    case unknownToken(String)

    public var message: String {
        switch self {
        case .unexpectedClosingBrace:
            return "Rename pattern has an unexpected `}`."
        case .unclosedToken:
            return "Rename pattern has an unclosed `{...}` token."
        case .emptyToken:
            return "Rename pattern contains an empty token `{}`."
        case let .invalidNumberPadding(token):
            return "Invalid rename tag `{\(token)}`. Use `{n:3}` style padding."
        case let .unknownToken(token):
            return "Unknown rename tag `{\(token)}`."
        }
    }
}

public struct FileRenamer: Sendable {
    private let supportedTokens: Set<String> = ["n", "name", "date", "time", "datetime", "ext", "width", "height"]

    public init() {}

    public func validationError(for pattern: String) -> RenamePatternValidationError? {
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let character = pattern[index]

            if character == "}" {
                return .unexpectedClosingBrace
            }

            guard character == "{" else {
                index = pattern.index(after: index)
                continue
            }

            guard let closingBrace = pattern[index...].firstIndex(of: "}") else {
                return .unclosedToken
            }

            let tokenStart = pattern.index(after: index)
            let token = String(pattern[tokenStart..<closingBrace])

            if token.isEmpty {
                return .emptyToken
            }

            if supportedTokens.contains(token) {
                index = pattern.index(after: closingBrace)
                continue
            }

            if token.hasPrefix("n:") {
                let padding = String(token.dropFirst(2))
                if !padding.isEmpty && padding.allSatisfy({ $0.isNumber }) {
                    index = pattern.index(after: closingBrace)
                    continue
                }
                return .invalidNumberPadding(token)
            }

            return .unknownToken(token)
        }

        return nil
    }

    public func renderBaseName(
        pattern: String,
        file: ImageDocument,
        index: Int,
        date: Date,
        renderedExtension: String? = nil
    ) -> String {
        var result = pattern

        let number = max(0, index)
        result = replacePaddedNumberTokens(in: result, number: number)
        result = result.replacingOccurrences(of: "{n}", with: String(format: "%03d", number))

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "HHmmss"
        let timeString = dateFormatter.string(from: date)

        result = result.replacingOccurrences(of: "{date}", with: dateString)
        result = result.replacingOccurrences(of: "{time}", with: timeString)
        result = result.replacingOccurrences(of: "{datetime}", with: "\(dateString)_\(timeString)")
        result = result.replacingOccurrences(of: "{name}", with: file.nameWithoutExtension)
        result = result.replacingOccurrences(of: "{ext}", with: renderedExtension ?? file.fileExtension)
        result = result.replacingOccurrences(of: "{width}", with: String(file.width))
        result = result.replacingOccurrences(of: "{height}", with: String(file.height))

        return sanitizeFilename(result, fallback: file.nameWithoutExtension)
    }

    public func applyPattern(
        _ pattern: String,
        to file: ImageDocument,
        index: Int,
        date: Date,
        finalExtension: String
    ) -> String {
        let ext = finalExtension.lowercased()
        let normalized = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        let base = renderBaseName(
            pattern: pattern,
            file: file,
            index: index,
            date: date,
            renderedExtension: normalized
        )
        if base.lowercased().hasSuffix(".\(normalized)") {
            return base
        }
        return "\(base).\(normalized)"
    }

    public func preview(
        pattern: String,
        files: [ImageDocument],
        startNumber: Int,
        date: Date,
        finalExtension: String,
        limit: Int = 3
    ) -> [String] {
        files.prefix(limit).enumerated().map { offset, file in
            applyPattern(
                pattern,
                to: file,
                index: startNumber + offset,
                date: date,
                finalExtension: finalExtension
            )
        }
    }

    private func replacePaddedNumberTokens(in string: String, number: Int) -> String {
        let regexPattern = #"\{n:(\d+)\}"#
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return string
        }

        let fullRange = NSRange(location: 0, length: string.utf16.count)
        let matches = regex.matches(in: string, range: fullRange).reversed()
        var result = string

        for match in matches {
            guard match.numberOfRanges > 1,
                  let digitRange = Range(match.range(at: 1), in: result),
                  let fullMatchRange = Range(match.range(at: 0), in: result),
                  let padding = Int(result[digitRange]) else {
                continue
            }
            let replacement = String(format: "%0\(padding)d", number)
            result.replaceSubrange(fullMatchRange, with: replacement)
        }

        return result
    }

    private func sanitizeFilename(_ raw: String, fallback: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let meaningful = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "_- "))

        if meaningful.isEmpty {
            return fallback
        }

        return trimmed
    }
}
