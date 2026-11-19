// SPDX-License-Identifier: MIT
import Foundation
import Darwin

private func require(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
    if !condition() {
        let message = "PersonNameComponents FAIL line \(line)\n"
        message.withCString { _ = fputs($0, stderr) }
        exit(1)
    }
}

@main struct Probe {
    static func main() throws {
        let empty = PersonNameComponents()
        require(empty.namePrefix == nil && empty.givenName == nil && empty.middleName == nil)
        require(empty.familyName == nil && empty.nameSuffix == nil && empty.nickname == nil)
        require(empty.phoneticRepresentation == nil)
        require(empty == PersonNameComponents() && Set([empty, PersonNameComponents()]).count == 1)

        var full = PersonNameComponents()
        full.namePrefix = "Dr."
        full.givenName = "Johnathan"
        full.middleName = "Maple"
        full.familyName = "Appleseed"
        full.nameSuffix = "Esq."
        full.nickname = "Johnny"
        var copy = full
        copy.givenName = "Jane"
        require(full.givenName == "Johnathan" && copy.givenName == "Jane")
        require(full == full && Set([full, full]).count == 1)

        var otherMiddle = full
        otherMiddle.middleName = "Other"
        require(full != otherMiddle && Set([full, otherMiddle]).count == 2)

        var phonetic = PersonNameComponents()
        phonetic.givenName = "JAN"
        phonetic.familyName = "APULSEED"
        full.phoneticRepresentation = phonetic
        require(full.phoneticRepresentation?.givenName == "JAN")
        require(full.phoneticRepresentation?.familyName == "APULSEED")
        require(full != otherMiddle)
        var fullCopy = full
        require(full == fullCopy && Set([full, fullCopy]).count == 1)
        fullCopy.phoneticRepresentation = nil
        require(full != fullCopy)

        let bridged = full._bridgeToObjectiveC()
        require(bridged.givenName == "Johnathan" && bridged.familyName == "Appleseed")
        require(bridged.namePrefix == "Dr." && bridged.middleName == "Maple")
        require(bridged.nameSuffix == "Esq." && bridged.nickname == "Johnny")
        require(bridged.phoneticRepresentation?.givenName == "JAN")
        full.givenName = "Changed"
        require(bridged.givenName == "Johnathan")

        let roundTrip = PersonNameComponents._unconditionallyBridgeFromObjectiveC(bridged)
        require(roundTrip.givenName == "Johnathan" && roundTrip.nickname == "Johnny")
        require(roundTrip.phoneticRepresentation?.familyName == "APULSEED")
        bridged.givenName = "Mutated"
        require(roundTrip.givenName == "Johnathan")

        let encoded = try JSONEncoder().encode(roundTrip)
        let decoded = try JSONDecoder().decode(PersonNameComponents.self, from: encoded)
        require(decoded.namePrefix == "Dr." && decoded.givenName == "Johnathan")
        require(decoded.middleName == "Maple" && decoded.familyName == "Appleseed")
        require(decoded.nameSuffix == "Esq." && decoded.nickname == "Johnny")
        require(decoded.phoneticRepresentation == nil)
        print("overlay Codable omits phoneticRepresentation")

        var unicode = PersonNameComponents()
        unicode.givenName = "山田"
        unicode.familyName = "太郎"
        require(unicode._bridgeToObjectiveC().givenName == "山田")
        let unicodeDecoded = try JSONDecoder().decode(PersonNameComponents.self, from: JSONEncoder().encode(unicode))
        require(unicodeDecoded == unicode)

        let partial = try JSONDecoder().decode(PersonNameComponents.self, from: Data(#"{"givenName":"Ada","familyName":"Lovelace"}"#.utf8))
        require(partial.givenName == "Ada" && partial.familyName == "Lovelace" && partial.nickname == nil)
        var blank = PersonNameComponents()
        blank.givenName = ""
        require(blank != PersonNameComponents())
        require(NSClassFromString("NSPersonNameComponents") != nil)
        require(NSClassFromString("NSPersonNameComponentsFormatter") != nil)
        require(String(reflecting: PersonNameComponents.self) == "Foundation.PersonNameComponents")
        print("PersonNameComponents PASS storage/copy/equality/hash/bridge/Codable unicode partial-json retained-class")
    }
}
