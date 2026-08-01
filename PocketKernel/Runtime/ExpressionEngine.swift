import Foundation

enum ExpressionError: LocalizedError, Equatable {
    case tooLong, tooDeep, tooManyOperations, invalidToken(Int), unexpected(String), unknownBinding(String), typeMismatch(String), invalidFunction(String), divisionByZero, arrayLimit
    var errorDescription: String? {
        switch self {
        case .tooLong: "Expression exceeds 2,000 characters."
        case .tooDeep: "Expression exceeds the maximum parse depth."
        case .tooManyOperations: "Expression exceeded its operation budget."
        case .invalidToken(let offset): "Invalid token at character \(offset)."
        case .unexpected(let token): "Unexpected token: \(token)."
        case .unknownBinding(let path): "Unknown binding: \(path)."
        case .typeMismatch(let operation): "Invalid value type for \(operation)."
        case .invalidFunction(let name): "Unsupported function: \(name)."
        case .divisionByZero: "Division by zero."
        case .arrayLimit: "Expression array exceeds 5,000 values."
        }
    }
}

private enum ExpressionToken: Equatable {
    case number(Double), string(String), identifier(String), bool(Bool), null
    case leftParen, rightParen, comma, operation(String), end
}

private struct ExpressionLexer {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) throws {
        guard source.count <= PocketLimits.expressionCharacters else { throw ExpressionError.tooLong }
        characters = Array(source)
    }

    mutating func tokenize() throws -> [ExpressionToken] {
        var tokens: [ExpressionToken] = []
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character == "(" { tokens.append(.leftParen); index += 1; continue }
            if character == ")" { tokens.append(.rightParen); index += 1; continue }
            if character == "," { tokens.append(.comma); index += 1; continue }
            if character == "\"" { tokens.append(.string(try readString())); continue }
            if character.isNumber || (character == "." && peek()?.isNumber == true) { tokens.append(.number(try readNumber())); continue }
            if character.isLetter || character == "_" { tokens.append(keyword(readIdentifier())); continue }
            if let operation = readOperation() { tokens.append(.operation(operation)); continue }
            throw ExpressionError.invalidToken(index)
        }
        tokens.append(.end)
        return tokens
    }

    private mutating func readString() throws -> String {
        index += 1; var output = ""
        while index < characters.count {
            let character = characters[index]; index += 1
            if character == "\"" { return output }
            if character == "\\" {
                guard index < characters.count else { throw ExpressionError.invalidToken(index) }
                let escaped = characters[index]; index += 1
                switch escaped { case "n": output.append("\n"); case "t": output.append("\t"); case "\"", "\\": output.append(escaped); default: throw ExpressionError.invalidToken(index - 1) }
            } else { output.append(character) }
        }
        throw ExpressionError.unexpected("unterminated string")
    }

    private mutating func readNumber() throws -> Double {
        let start = index; var hasDot = false
        while index < characters.count {
            let character = characters[index]
            if character == "." { if hasDot { break }; hasDot = true; index += 1 }
            else if character.isNumber { index += 1 } else { break }
        }
        guard let value = Double(String(characters[start..<index])) else { throw ExpressionError.invalidToken(start) }
        return value
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber || character == "_" || character == "." else { break }
            index += 1
        }
        return String(characters[start..<index])
    }

    private mutating func readOperation() -> String? {
        for candidate in ["==", "!=", ">=", "<=", ">", "<", "+", "-", "*", "/"] {
            let end = index + candidate.count
            if end <= characters.count, String(characters[index..<end]) == candidate { index = end; return candidate }
        }
        return nil
    }

    private func peek() -> Character? { index + 1 < characters.count ? characters[index + 1] : nil }
    private func keyword(_ value: String) -> ExpressionToken {
        switch value { case "true": .bool(true); case "false": .bool(false); case "null": .null; case "and", "or", "not": .operation(value); default: .identifier(value) }
    }
}

private indirect enum ExpressionNode: Sendable {
    case value(PocketValue), binding(String), unary(String, ExpressionNode), binary(String, ExpressionNode, ExpressionNode), function(String, [ExpressionNode])
}

private struct ExpressionParser {
    private let tokens: [ExpressionToken]
    private var index = 0
    init(tokens: [ExpressionToken]) { self.tokens = tokens }

    mutating func parse() throws -> ExpressionNode {
        let result = try parseOr(depth: 1)
        guard current == .end else { throw ExpressionError.unexpected(description(current)) }
        return result
    }

    private mutating func parseOr(depth: Int) throws -> ExpressionNode {
        var node = try parseAnd(depth: depth + 1)
        while current == .operation("or") { advance(); node = .binary("or", node, try parseAnd(depth: depth + 1)) }
        return node
    }

    private mutating func parseAnd(depth: Int) throws -> ExpressionNode {
        var node = try parseComparison(depth: depth + 1)
        while current == .operation("and") { advance(); node = .binary("and", node, try parseComparison(depth: depth + 1)) }
        return node
    }

    private mutating func parseComparison(depth: Int) throws -> ExpressionNode {
        var node = try parseTerm(depth: depth + 1)
        while case .operation(let operation) = current, ["==", "!=", ">", ">=", "<", "<="].contains(operation) {
            advance(); node = .binary(operation, node, try parseTerm(depth: depth + 1))
        }
        return node
    }

    private mutating func parseTerm(depth: Int) throws -> ExpressionNode {
        var node = try parseFactor(depth: depth + 1)
        while case .operation(let operation) = current, ["+", "-"].contains(operation) {
            advance(); node = .binary(operation, node, try parseFactor(depth: depth + 1))
        }
        return node
    }

    private mutating func parseFactor(depth: Int) throws -> ExpressionNode {
        var node = try parseUnary(depth: depth + 1)
        while case .operation(let operation) = current, ["*", "/"].contains(operation) {
            advance(); node = .binary(operation, node, try parseUnary(depth: depth + 1))
        }
        return node
    }

    private mutating func parseUnary(depth: Int) throws -> ExpressionNode {
        try checkDepth(depth)
        if current == .operation("not") { advance(); return .unary("not", try parseUnary(depth: depth + 1)) }
        if current == .operation("-") { advance(); return .unary("-", try parseUnary(depth: depth + 1)) }
        return try parsePrimary(depth: depth + 1)
    }

    private mutating func parsePrimary(depth: Int) throws -> ExpressionNode {
        try checkDepth(depth)
        switch current {
        case .number(let value): advance(); return .value(.number(value))
        case .string(let value): advance(); return .value(.string(value))
        case .bool(let value): advance(); return .value(.bool(value))
        case .null: advance(); return .value(.null)
        case .identifier(let name):
            advance()
            guard current == .leftParen else { return .binding(name) }
            advance(); var arguments: [ExpressionNode] = []
            if current != .rightParen {
                repeat { arguments.append(try parseOr(depth: depth + 1)); if current != .comma { break }; advance() } while true
            }
            guard current == .rightParen else { throw ExpressionError.unexpected(description(current)) }
            advance(); return .function(name, arguments)
        case .leftParen:
            advance(); let node = try parseOr(depth: depth + 1)
            guard current == .rightParen else { throw ExpressionError.unexpected(description(current)) }
            advance(); return node
        default: throw ExpressionError.unexpected(description(current))
        }
    }

    private var current: ExpressionToken { tokens[min(index, tokens.count - 1)] }
    private mutating func advance() { index += 1 }
    private func checkDepth(_ depth: Int) throws { if depth > 20 { throw ExpressionError.tooDeep } }
    private func description(_ token: ExpressionToken) -> String { String(describing: token) }
}

struct BindingResolver: Sendable {
    func resolve(_ path: String, in root: [String: PocketValue]) throws -> PocketValue {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first, var value = root[first] else { throw ExpressionError.unknownBinding(path) }
        for part in parts.dropFirst() {
            guard case .object(let object) = value, let next = object[part] else { throw ExpressionError.unknownBinding(path) }
            value = next
        }
        return value
    }
}

struct ExpressionEvaluator: Sendable {
    func validateSyntax(_ source: String) throws {
        var lexer = try ExpressionLexer(source); var parser = ExpressionParser(tokens: try lexer.tokenize()); _ = try parser.parse()
    }

    func evaluate(_ source: String, context: [String: PocketValue]) throws -> PocketValue {
        var lexer = try ExpressionLexer(source); var parser = ExpressionParser(tokens: try lexer.tokenize())
        let node = try parser.parse(); var operations = 0
        return try evaluate(node, context: context, operations: &operations)
    }

    private func evaluate(_ node: ExpressionNode, context: [String: PocketValue], operations: inout Int) throws -> PocketValue {
        operations += 1; guard operations <= PocketLimits.expressionOperations else { throw ExpressionError.tooManyOperations }
        switch node {
        case .value(let value): return value
        case .binding(let path): return try BindingResolver().resolve(path, in: context)
        case .unary(let operation, let child):
            let value = try evaluate(child, context: context, operations: &operations)
            if operation == "not", case .bool(let bool) = value { return .bool(!bool) }
            if operation == "-", case .number(let number) = value { return .number(-number) }
            throw ExpressionError.typeMismatch(operation)
        case .binary(let operation, let leftNode, let rightNode):
            let left = try evaluate(leftNode, context: context, operations: &operations)
            if operation == "and", case .bool(false) = left { return .bool(false) }
            if operation == "or", case .bool(true) = left { return .bool(true) }
            let right = try evaluate(rightNode, context: context, operations: &operations)
            return try binary(operation, left, right)
        case .function(let name, let nodes):
            let values = try nodes.map { try evaluate($0, context: context, operations: &operations) }
            return try function(name, values)
        }
    }

    private func binary(_ operation: String, _ left: PocketValue, _ right: PocketValue) throws -> PocketValue {
        if operation == "==" { return .bool(left == right) }
        if operation == "!=" { return .bool(left != right) }
        if case .number(let lhs) = left, case .number(let rhs) = right {
            switch operation { case "+": return .number(lhs + rhs); case "-": return .number(lhs - rhs); case "*": return .number(lhs * rhs); case "/": guard rhs != 0 else { throw ExpressionError.divisionByZero }; return .number(lhs / rhs); case ">": return .bool(lhs > rhs); case ">=": return .bool(lhs >= rhs); case "<": return .bool(lhs < rhs); case "<=": return .bool(lhs <= rhs); default: break }
        }
        if case .string(let lhs) = left, case .string(let rhs) = right {
            switch operation { case "+": return .string(lhs + rhs); case ">": return .bool(lhs > rhs); case ">=": return .bool(lhs >= rhs); case "<": return .bool(lhs < rhs); case "<=": return .bool(lhs <= rhs); default: break }
        }
        if case .bool(let lhs) = left, case .bool(let rhs) = right, operation == "and" || operation == "or" { return .bool(operation == "and" ? lhs && rhs : lhs || rhs) }
        if case .date(let lhs) = left, case .date(let rhs) = right {
            switch operation { case ">": return .bool(lhs > rhs); case ">=": return .bool(lhs >= rhs); case "<": return .bool(lhs < rhs); case "<=": return .bool(lhs <= rhs); default: break }
        }
        throw ExpressionError.typeMismatch(operation)
    }

    private func function(_ name: String, _ values: [PocketValue]) throws -> PocketValue {
        switch name {
        case "contains", "startsWith", "endsWith":
            guard values.count == 2, case .string(let source) = values[0], case .string(let query) = values[1] else { throw ExpressionError.typeMismatch(name) }
            return .bool(name == "contains" ? source.contains(query) : name == "startsWith" ? source.hasPrefix(query) : source.hasSuffix(query))
        case "count":
            guard values.count == 1 else { throw ExpressionError.typeMismatch(name) }
            if case .array(let array) = values[0] { guard array.count <= PocketLimits.recordsPerCollection else { throw ExpressionError.arrayLimit }; return .number(Double(array.count)) }
            if case .string(let string) = values[0] { return .number(Double(string.count)) }
            throw ExpressionError.typeMismatch(name)
        case "sum", "min", "max":
            guard values.count == 1, case .array(let array) = values[0], array.count <= PocketLimits.recordsPerCollection else { throw ExpressionError.typeMismatch(name) }
            let numbers = try array.map { value -> Double in guard case .number(let number) = value else { throw ExpressionError.typeMismatch(name) }; return number }
            if name == "sum" { return .number(numbers.reduce(0, +)) }
            guard let result = name == "min" ? numbers.min() : numbers.max() else { return .null }
            return .number(result)
        case "coalesce": return values.first { $0 != .null } ?? .null
        case "formatNumber": guard let first = values.first, case .number(let number) = first else { throw ExpressionError.typeMismatch(name) }; return .string(number.formatted())
        case "formatDate": guard let first = values.first, case .date(let date) = first else { throw ExpressionError.typeMismatch(name) }; return .string(date.formatted(date: .abbreviated, time: .omitted))
        default: throw ExpressionError.invalidFunction(name)
        }
    }
}
