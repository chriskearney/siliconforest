import SwiftUI
@main struct LegacyProof {
  static func main() {
    precondition(LocalizedStringKey("Preview") == LocalizedStringKey(stringLiteral: "Preview"))
    precondition(Text(verbatim: "Preview") == Text(verbatim: "Preview"))
    precondition(Text(verbatim: "Preview") != Text(verbatim: "Other"))
    let image = Image(systemName: "doc"); let copiedImage = image
    precondition(image == copiedImage)
    precondition(image != Image(systemName: "other"))
    precondition(Alignment.center.horizontal == .center)
    precondition(Alignment.center.vertical == .center)
    precondition(EdgeInsets() == EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    print("Legacy SwiftUI subset value clients PASS keys/text/image/alignment/insets; no renderer claim")
  }
}
