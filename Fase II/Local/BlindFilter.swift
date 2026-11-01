import Foundation

/// Filtro Ciego Local de Fase I.
///
/// Detecta datos personales en el texto antes de que algo salga del equipo:
/// tarjetas con validación Luhn, CLABE con dígito verificador, RFC, CURP,
/// correos y teléfonos. Las mismas reglas existen en el backend como segunda barrera.
nonisolated enum BlindFilter {
    enum Kind: String, CaseIterable, Sendable {
        case tarjeta, clabe, rfc, curp, correo, telefono

        var token: String { "[\(rawValue.uppercased())]" }
    }

    struct Finding: Sendable {
        let kind: Kind
        let range: Range<String.Index>
    }

    struct Result: Sendable {
        let masked: String
        let counts: [Kind: Int]
        var total: Int { counts.values.reduce(0, +) }
    }

    private static let curp = try! NSRegularExpression(pattern: #"\b[A-Z][AEIOUX][A-Z]{2}\d{6}[HMX][A-Z]{5}[A-Z0-9]\d\b"#, options: [.caseInsensitive])
    private static let rfc = try! NSRegularExpression(pattern: #"\b[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\b"#, options: [.caseInsensitive])
    private static let email = try! NSRegularExpression(pattern: #"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"#)
    private static let digits = try! NSRegularExpression(pattern: #"(?<![\w])\+?\d[\d \-.]{8,24}\d(?![\w])"#)

    static func findings(in text: String) -> [Finding] {
        var result: [Finding] = []
        let whole = NSRange(text.startIndex..., in: text)

        func overlaps(_ r: Range<String.Index>) -> Bool {
            result.contains { $0.range.overlaps(r) }
        }

        for (regex, kind) in [(curp, Kind.curp), (rfc, .rfc), (email, .correo)] {
            for match in regex.matches(in: text, range: whole) {
                guard let r = Range(match.range, in: text), !overlaps(r) else { continue }
                result.append(Finding(kind: kind, range: r))
            }
        }

        for match in digits.matches(in: text, range: whole) {
            guard let r = Range(match.range, in: text), !overlaps(r) else { continue }
            let onlyDigits = text[r].filter(\.isNumber)
            if (13...19).contains(onlyDigits.count), luhnIsValid(onlyDigits) {
                result.append(Finding(kind: .tarjeta, range: r))
            } else if clabeIsValid(onlyDigits) {
                result.append(Finding(kind: .clabe, range: r))
            } else if onlyDigits.count == 10 || (onlyDigits.count == 12 && onlyDigits.hasPrefix("52")) {
                result.append(Finding(kind: .telefono, range: r))
            }
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func mask(_ text: String) -> Result {
        let found = findings(in: text)
        var masked = text
        var counts: [Kind: Int] = [:]
        for f in found.reversed() {
            masked.replaceSubrange(f.range, with: f.kind.token)
            counts[f.kind, default: 0] += 1
        }
        return Result(masked: masked, counts: counts)
    }

    static func luhnIsValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, !values.isEmpty else { return false }
        let parity = values.count % 2
        let sum = values.enumerated().reduce(0) { acc, item in
            var d = item.element
            if item.offset % 2 == parity {
                d *= 2
                if d > 9 { d -= 9 }
            }
            return acc + d
        }
        return sum % 10 == 0
    }

    static func clabeIsValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 18 else { return false }
        let weights = [3, 7, 1]
        let sum = (0..<17).reduce(0) { $0 + (values[$1] * weights[$1 % 3]) % 10 }
        return (10 - sum % 10) % 10 == values[17]
    }
}
