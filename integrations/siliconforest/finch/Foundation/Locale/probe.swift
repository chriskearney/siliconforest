import Foundation

@main
struct Probe {
    static func main() {
        let traditional = Locale(identifier: "zh_TW").language
        precondition(traditional.languageCode?.identifier == "zh")
        precondition(traditional.maximalIdentifier == "zh-Hant-TW")
        let english = Locale(identifier: "en").language
        precondition(english.maximalIdentifier == "en-Latn-US")
        let turkish = "istanbul izmir".capitalized(with: Locale(identifier: "tr"))
        precondition(turkish == "İstanbul İzmir")
        print("Locale language maximization and Turkish title case PASS")
    }
}
