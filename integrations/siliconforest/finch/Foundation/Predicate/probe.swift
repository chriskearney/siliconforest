// SPDX-License-Identifier: MIT OR Apache-2.0
// Headless evaluation of the Predicate expressions Preview imports.
// Builds Equal, Comparison, Value, KeyPath, Variable, and the two string
// expressions, then evaluates them. Diacritic folding is printed and is not
// a pass condition: this NSString header has no diacritic or width flag.
import Foundation
import Darwin

struct Row: Codable, Sendable {
    var score: Int
    var label: String
}

@main
struct Probe {
    static func main() throws {
        func say(_ line: String) {
            print(line)
            fflush(stdout)
        }
        func check(_ value: Bool, _ name: String) {
            if !value {
                say("FAIL \(name)")
                exit(1)
            }
            say("PASS \(name)")
        }
        func raw(_ result: ComparisonResult) -> Int {
            result.rawValue
        }

        let empty = PredicateBindings()
        let constant = PredicateExpressions.Value(true)
        check(constant.evaluate(empty), "value true")

        let three = PredicateExpressions.build_Arg(3)
        let again = PredicateExpressions.build_Arg(three)
        check(three.evaluate(empty) == 3, "build_Arg value")
        check(again.evaluate(empty) == 3, "build_Arg expression")

        let equal = Predicate<String> { text in
            PredicateExpressions.build_Equal(
                lhs: text,
                rhs: PredicateExpressions.build_Arg("tip")
            )
        }
        check(try equal.evaluate("tip"), "equal true")
        check(try equal.evaluate("Tip") == false, "equal false")

        let score = PredicateExpressions.Variable<Int>()
        let atLeast = PredicateExpressions.build_Comparison(
            lhs: score,
            rhs: PredicateExpressions.build_Arg(10),
            op: .greaterThanOrEqual
        )
        check(try atLeast.evaluate(PredicateBindings((score, 10))), "greaterThanOrEqual equal")
        check(try atLeast.evaluate(PredicateBindings((score, 11))), "greaterThanOrEqual above")
        check(try atLeast.evaluate(PredicateBindings((score, 9))) == false, "greaterThanOrEqual below")

        let left = PredicateExpressions.Variable<Int>()
        let less = PredicateExpressions.build_Comparison(
            lhs: left,
            rhs: PredicateExpressions.build_Arg(2),
            op: .lessThan
        )
        let lessOrEqual = PredicateExpressions.build_Comparison(
            lhs: left,
            rhs: PredicateExpressions.build_Arg(2),
            op: .lessThanOrEqual
        )
        let greater = PredicateExpressions.build_Comparison(
            lhs: left,
            rhs: PredicateExpressions.build_Arg(2),
            op: .greaterThan
        )
        check(try less.evaluate(PredicateBindings((left, 1))), "lessThan")
        check(try less.evaluate(PredicateBindings((left, 2))) == false, "lessThan false")
        check(try lessOrEqual.evaluate(PredicateBindings((left, 2))), "lessThanOrEqual")
        check(try greater.evaluate(PredicateBindings((left, 3))), "greaterThan")
        check(try greater.evaluate(PredicateBindings((left, 2))) == false, "greaterThan false")

        say("OBS equality start")
        check(PredicateError.undefinedVariable == .undefinedVariable, "undefinedVariable equals itself")
        check(PredicateError.undefinedVariable != .invalidInput, "undefinedVariable is not invalidInput")
        check(PredicateError.forceUnwrapFailure == .forceUnwrapFailure, "forceUnwrapFailure equals itself")
        check(PredicateError.forceCastFailure == .forceCastFailure, "forceCastFailure equals itself")
        check(PredicateError.invalidInput == .invalidInput, "invalidInput equals itself")
        check(PredicateError.invalidInput != .forceCastFailure, "invalidInput is not forceCastFailure")

        say("OBS throw start")
        do {
            throw PredicateError.undefinedVariable
        } catch let error as PredicateError {
            check(error == .undefinedVariable, "thrown undefinedVariable")
            check(error.debugDescription == "Encountered an undefined variable", "undefinedVariable description")
        }

        let missing = PredicateExpressions.Variable<Int>()
        let unbound = PredicateExpressions.build_Equal(
            lhs: missing,
            rhs: PredicateExpressions.build_Arg(1)
        )
        do {
            _ = try unbound.evaluate(empty)
            say("FAIL undefined returned a value")
            exit(1)
        } catch let error as PredicateError {
            check(error == .undefinedVariable, "undefined variable")
            say("OBS undefined \(error.debugDescription)")
        }
        let other = PredicateExpressions.Variable<Int>()
        do {
            _ = try atLeast.evaluate(PredicateBindings((other, 10)))
            say("FAIL wrong variable returned a value")
            exit(1)
        } catch let error as PredicateError {
            check(error == .undefinedVariable, "wrong variable is undefined")
        }

        let name = PredicateExpressions.Variable<String>()
        let folded = PredicateExpressions.build_caseInsensitiveCompare(
            name,
            PredicateExpressions.build_Arg("cafe")
        )
        check(raw(try folded.evaluate(PredicateBindings((name, "Cafe")))) == 0, "case insensitive same")
        check(raw(try folded.evaluate(PredicateBindings((name, "CAB")))) == -1, "case insensitive CAB precedes cafe")
        check(raw(try folded.evaluate(PredicateBindings((name, "caff")))) == 1, "case insensitive caff follows cafe")

        let ordered = PredicateExpressions.build_localizedCompare(
            PredicateExpressions.build_Arg("a"),
            PredicateExpressions.build_Arg("b")
        )
        check(raw(try ordered.evaluate(empty)) == -1, "localizedCompare ascending")
        let sameOrder = PredicateExpressions.build_localizedCompare(
            PredicateExpressions.build_Arg("a"),
            PredicateExpressions.build_Arg("a")
        )
        check(raw(try sameOrder.evaluate(empty)) == 0, "localizedCompare same")

        let hay = PredicateExpressions.Variable<String>()
        let containsELL = PredicateExpressions.build_localizedStandardContains(
            hay,
            PredicateExpressions.build_Arg("ELL")
        )
        let containsXYZ = PredicateExpressions.build_localizedStandardContains(
            hay,
            PredicateExpressions.build_Arg("xyz")
        )
        let helloELL = try containsELL.evaluate(PredicateBindings((hay, "Hello")))
        check(helloELL, "localizedStandardContains Hello/ELL")
        check(helloELL == "Hello".localizedStandardContains("ELL"), "contains expression matches method")
        check(try containsXYZ.evaluate(PredicateBindings((hay, "Hello"))) == false, "localizedStandardContains absent")
        check(try PredicateExpressions.build_localizedStandardContains(
            hay,
            PredicateExpressions.build_Arg("ell")
        ).evaluate(PredicateBindings((hay, "Hello"))), "localizedStandardContains exact ASCII")

        let cafe = "Caf\u{00E9}"
        let cafeFold = cafe.localizedStandardContains("cafe")
        let cafeExact = cafe.localizedStandardContains("f\u{00E9}")
        let cafeCase = try PredicateExpressions.build_caseInsensitiveCompare(
            PredicateExpressions.build_Arg(cafe),
            PredicateExpressions.build_Arg("caf\u{00E9}")
        ).evaluate(empty)
        say("OBS diacritic scalars \(cafe.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",")) contains-cafe \(cafeFold) contains-fe \(cafeExact) case-raw \(raw(cafeCase))")
        check(cafeExact, "localizedStandardContains exact accented substring")

        say("OBS keypath start")
        let ranked = Predicate<Row> { row in
            PredicateExpressions.build_Comparison(
                lhs: PredicateExpressions.build_KeyPath(root: row, keyPath: \Row.score),
                rhs: PredicateExpressions.build_Arg(10),
                op: .greaterThanOrEqual
            )
        }
        check(try ranked.evaluate(Row(score: 10, label: "open")), "keypath greaterThanOrEqual")
        check(try ranked.evaluate(Row(score: 9, label: "open")) == false, "keypath below")
        let labeled = Predicate<Row> { row in
            PredicateExpressions.build_Equal(
                lhs: PredicateExpressions.build_KeyPath(root: row, keyPath: \Row.label),
                rhs: PredicateExpressions.build_Arg("open")
            )
        }
        check(try labeled.evaluate(Row(score: 1, label: "open")), "keypath equal")
        check(try labeled.evaluate(Row(score: 1, label: "closed")) == false, "keypath equal false")
        say("PREDICATE PROBE PASS")
    }
}
