import Foundation
import Combine

struct CommanderPreferences {
    let isEnabled: Bool
    let calculatorEnabled: Bool
    let textToolsEnabled: Bool
    let chatActionsEnabled: Bool
    let chatInfoEnabled: Bool
    let funGamesEnabled: Bool
}

enum CommanderResult: Equatable {
    case local(String)
    case pin(Bool)
    case archive(Bool)
}

@MainActor
final class CommanderStore: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { persist(isEnabled, for: Keys.enabled) }
    }
    @Published var calculatorEnabled: Bool {
        didSet { persist(calculatorEnabled, for: Keys.calculator) }
    }
    @Published var textToolsEnabled: Bool {
        didSet { persist(textToolsEnabled, for: Keys.textTools) }
    }
    @Published var chatActionsEnabled: Bool {
        didSet { persist(chatActionsEnabled, for: Keys.chatActions) }
    }
    @Published var chatInfoEnabled: Bool {
        didSet { persist(chatInfoEnabled, for: Keys.chatInfo) }
    }
    @Published var funGamesEnabled: Bool {
        didSet { persist(funGamesEnabled, for: Keys.funGames) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "krochat.commander.enabled.v1"
        static let calculator = "krochat.commander.calculator.v1"
        static let textTools = "krochat.commander.textTools.v1"
        static let chatActions = "krochat.commander.chatActions.v1"
        static let chatInfo = "krochat.commander.chatInfo.v1"
        static let funGames = "krochat.commander.funGames.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        calculatorEnabled = defaults.object(forKey: Keys.calculator) as? Bool ?? true
        textToolsEnabled = defaults.object(forKey: Keys.textTools) as? Bool ?? true
        chatActionsEnabled = defaults.object(forKey: Keys.chatActions) as? Bool ?? true
        chatInfoEnabled = defaults.object(forKey: Keys.chatInfo) as? Bool ?? true
        funGamesEnabled = defaults.object(forKey: Keys.funGames) as? Bool ?? true
    }

    var preferences: CommanderPreferences {
        CommanderPreferences(
            isEnabled: isEnabled,
            calculatorEnabled: calculatorEnabled,
            textToolsEnabled: textToolsEnabled,
            chatActionsEnabled: chatActionsEnabled,
            chatInfoEnabled: chatInfoEnabled,
            funGamesEnabled: funGamesEnabled
        )
    }

    private func persist(_ value: Bool, for key: String) {
        defaults.set(value, forKey: key)
    }
}

enum CommanderCommandEngine {
    static func execute(
        _ input: String,
        chat: Chat,
        preferences: CommanderPreferences,
        now: Date = .now
    ) -> CommanderResult? {
        guard preferences.isEnabled else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "/" else { return nil }

        let commandAndArgument = trimmed.dropFirst().split(
            maxSplits: 1,
            whereSeparator: \.isWhitespace
        )
        guard let commandToken = commandAndArgument.first else { return nil }
        let command = commandToken.lowercased()
        let argument = commandAndArgument.count > 1 ? String(commandAndArgument[1]) : ""

        switch command {
        case "help":
            return .local(helpText(preferences: preferences))
        case "id" where preferences.chatInfoEnabled:
            return .local(String(format: L("commander.result.chatID"), "\(chat.id)"))
        case "time" where preferences.chatInfoEnabled:
            return .local(String(
                format: L("commander.result.time"),
                now.formatted(date: .abbreviated, time: .shortened)
            ))
        case "calc" where preferences.calculatorEnabled:
            guard !argument.isEmpty else { return .local(L("commander.error.calcUsage")) }
            do {
                let value = try ArithmeticExpression.evaluate(argument)
                let formatted = value.formatted(.number.precision(.fractionLength(0...8)))
                return .local(String(format: L("commander.result.calculation"), formatted))
            } catch {
                return .local(L("commander.error.calculation"))
            }
        case "upper" where preferences.textToolsEnabled:
            return textResult(argument, transform: { $0.uppercased() })
        case "lower" where preferences.textToolsEnabled:
            return textResult(argument, transform: { $0.lowercased() })
        case "reverse" where preferences.textToolsEnabled:
            return textResult(argument) { String($0.reversed()) }
        case "coin" where preferences.funGamesEnabled && argument.isEmpty:
            return .local(L(Bool.random() ? "commander.game.coin.heads" : "commander.game.coin.tails"))
        case "dice" where preferences.funGamesEnabled:
            let sides: Int
            if argument.isEmpty {
                sides = 6
            } else if let parsedSides = Int(argument), (2...1_000).contains(parsedSides) {
                sides = parsedSides
            } else {
                return .local(L("commander.error.diceUsage"))
            }
            let roll = Int.random(in: 1...sides)
            return .local(String(format: L("commander.game.dice"), roll, sides))
        case "8ball" where preferences.funGamesEnabled:
            guard !argument.isEmpty else { return .local(L("commander.error.eightBallUsage")) }
            let answers = (1...5).map { L("commander.game.eightBall.\($0)") }
            return .local(answers.randomElement() ?? L("commander.game.eightBall.1"))
        case "rps" where preferences.funGamesEnabled:
            let choices = ["rock", "paper", "scissors"]
            let player = argument.lowercased()
            guard choices.contains(player) else { return .local(L("commander.error.rpsUsage")) }
            let opponent = choices[Int.random(in: choices.indices)]
            let playerName = L("commander.game.rps.\(player)")
            let opponentName = L("commander.game.rps.\(opponent)")
            let outcome: String
            if player == opponent {
                outcome = L("commander.game.rps.draw")
            } else if (player == "rock" && opponent == "scissors")
                        || (player == "paper" && opponent == "rock")
                        || (player == "scissors" && opponent == "paper") {
                outcome = L("commander.game.rps.win")
            } else {
                outcome = L("commander.game.rps.loss")
            }
            return .local(String(format: outcome, playerName, opponentName))
        case "pin" where preferences.chatActionsEnabled && argument.isEmpty:
            return .pin(true)
        case "unpin" where preferences.chatActionsEnabled && argument.isEmpty:
            return .pin(false)
        case "archive" where preferences.chatActionsEnabled && argument.isEmpty:
            return .archive(true)
        case "unarchive" where preferences.chatActionsEnabled && argument.isEmpty:
            return .archive(false)
        default:
            return nil
        }
    }

    static func suggestions(for input: String, preferences: CommanderPreferences) -> [String] {
        guard preferences.isEnabled,
              input.first == "/",
              !input.contains(where: \.isWhitespace) else { return [] }
        let commands = [
            "/help",
            preferences.chatInfoEnabled ? "/id" : nil,
            preferences.chatInfoEnabled ? "/time" : nil,
            preferences.calculatorEnabled ? "/calc " : nil,
            preferences.textToolsEnabled ? "/upper " : nil,
            preferences.textToolsEnabled ? "/lower " : nil,
            preferences.textToolsEnabled ? "/reverse " : nil,
            preferences.funGamesEnabled ? "/coin" : nil,
            preferences.funGamesEnabled ? "/dice" : nil,
            preferences.funGamesEnabled ? "/8ball " : nil,
            preferences.funGamesEnabled ? "/rps " : nil,
            preferences.chatActionsEnabled ? "/pin" : nil,
            preferences.chatActionsEnabled ? "/unpin" : nil,
            preferences.chatActionsEnabled ? "/archive" : nil,
            preferences.chatActionsEnabled ? "/unarchive" : nil
        ].compactMap { $0 }
        let query = input.lowercased()
        return commands.filter { $0.lowercased().hasPrefix(query) }.prefix(5).map { $0 }
    }

    private static func textResult(
        _ text: String,
        transform: (String) -> String
    ) -> CommanderResult {
        guard !text.isEmpty else { return .local(L("commander.error.textUsage")) }
        guard text.count <= 2_000 else { return .local(L("commander.error.textTooLong")) }
        return .local(transform(text))
    }

    private static func helpText(preferences: CommanderPreferences) -> String {
        var commands = [L("commander.help.help")]
        if preferences.chatInfoEnabled {
            commands += [L("commander.help.id"), L("commander.help.time")]
        }
        if preferences.calculatorEnabled {
            commands.append(L("commander.help.calc"))
        }
        if preferences.textToolsEnabled {
            commands += [
                L("commander.help.upper"),
                L("commander.help.lower"),
                L("commander.help.reverse")
            ]
        }
        if preferences.funGamesEnabled {
            commands += [
                L("commander.help.coin"),
                L("commander.help.dice"),
                L("commander.help.eightBall"),
                L("commander.help.rps")
            ]
        }
        if preferences.chatActionsEnabled {
            commands += [
                L("commander.help.pin"),
                L("commander.help.archive")
            ]
        }
        return ([L("commander.help.title")] + commands).joined(separator: "\n")
    }
}

private enum ArithmeticExpression {
    static func evaluate(_ input: String) throws -> Double {
        guard input.count <= 160 else { throw ArithmeticError.invalid }
        var parser = Parser(input)
        let result = try parser.parseExpression()
        parser.skipWhitespace()
        guard parser.isAtEnd, result.isFinite else { throw ArithmeticError.invalid }
        return result
    }

    private enum ArithmeticError: Error {
        case invalid
        case divisionByZero
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0
        private var nesting = 0

        init(_ input: String) {
            characters = Array(input)
        }

        var isAtEnd: Bool { index == characters.count }

        mutating func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                skipWhitespace()
                if consume("+") {
                    value += try parseTerm()
                } else if consume("-") {
                    value -= try parseTerm()
                } else {
                    return value
                }
                guard value.isFinite else { throw ArithmeticError.invalid }
            }
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parsePower()
            while true {
                skipWhitespace()
                if consume("*") {
                    value *= try parsePower()
                } else if consume("/") {
                    let divisor = try parsePower()
                    guard divisor != 0 else { throw ArithmeticError.divisionByZero }
                    value /= divisor
                } else if consume("%") {
                    let divisor = try parsePower()
                    guard divisor != 0 else { throw ArithmeticError.divisionByZero }
                    value.formTruncatingRemainder(dividingBy: divisor)
                } else {
                    return value
                }
                guard value.isFinite else { throw ArithmeticError.invalid }
            }
        }

        private mutating func parsePower() throws -> Double {
            var value = try parseUnary()
            skipWhitespace()
            if consume("^") {
                let exponent = try parsePower()
                value = pow(value, exponent)
                guard value.isFinite else { throw ArithmeticError.invalid }
            }
            return value
        }

        private mutating func parseUnary() throws -> Double {
            skipWhitespace()
            if consume("+") { return try parseUnary() }
            if consume("-") { return -(try parseUnary()) }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            if consume("(") {
                nesting += 1
                guard nesting <= 24 else { throw ArithmeticError.invalid }
                let value = try parseExpression()
                skipWhitespace()
                guard consume(")") else { throw ArithmeticError.invalid }
                nesting -= 1
                return value
            }

            let start = index
            var hasDigit = false
            var hasDecimal = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    hasDigit = true
                    index += 1
                } else if character == ".", !hasDecimal {
                    hasDecimal = true
                    index += 1
                } else {
                    break
                }
            }
            guard hasDigit,
                  let value = Double(String(characters[start..<index])),
                  value.isFinite else {
                throw ArithmeticError.invalid
            }
            return value
        }

        private mutating func consume(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }
    }
}
