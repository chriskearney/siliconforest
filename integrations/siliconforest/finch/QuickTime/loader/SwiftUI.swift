// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// SwiftUI, binding subset. This is NOT a SwiftUI implementation: there is no attribute
// graph, no layout and no hosting view. It declares, with the real Swift compiler and
// library evolution, the part of SwiftUI's public interface that an application binary
// names at load time when it contains one small view built from Text, Image, Button,
// a frame modifier and an if/else. dyld can then bind such a binary; a program that
// actually asks this module to render a view stops with a diagnostic instead of
// drawing something wrong.
//
// Written from SwiftUI's public API documentation. The frozen types carry the stored
// properties their public interface declares, so a client that copies or destroys a
// value inline does so with a layout of the right shape. The whole of SwiftUI
// (OpenSwiftUI, as the Finch project builds it) is the intended replacement.
import Foundation

@usableFromInline
internal func _unavailable(_ what: StaticString) -> Never {
  fatalError("SwiftUI binding subset: \(what) needs a SwiftUI renderer, which SiliconForest does not have yet")
}

// MARK: graph plumbing named by the View protocol's hidden requirements

public struct _GraphValue<Value> {
  internal var identifier: UInt32
}
public struct _ViewInputs {
  internal var reserved: Int
}
public struct _ViewOutputs {
  internal var reserved: Int
}
public struct _ViewListInputs {
  internal var reserved: Int
}
public struct _ViewListOutputs {
  internal var reserved: Int
}
public struct _ViewListCountInputs {
  internal var reserved: Int
}

// MARK: View

public protocol View {
  static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
  static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
  static func _viewListCount(inputs: _ViewListCountInputs) -> Int?
  associatedtype Body: View
  var body: Self.Body { get }
}

extension View {
  public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
    _unavailable("View._makeView")
  }
  public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
    _unavailable("View._makeViewList")
  }
  public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
    nil
  }
}

extension Never: View {
  public typealias Body = Never
  public var body: Never {
    switch self {}
  }
}

// MARK: ViewModifier

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
  internal var reserved: Int
}
extension _ViewModifier_Content: View {
  public typealias Body = Never
  public var body: Never { _unavailable("_ViewModifier_Content.body") }
}

public protocol ViewModifier {
  associatedtype Body: View
  func body(content: Self.Content) -> Self.Body
  typealias Content = _ViewModifier_Content<Self>
}

extension ViewModifier where Self.Body == Never {
  public func body(content: Self.Content) -> Never {
    _unavailable("ViewModifier.body(content:)")
  }
}

@frozen public struct ModifiedContent<Content, Modifier> {
  public typealias Body = Never
  public var content: Content
  public var modifier: Modifier
  @inlinable public init(content: Content, modifier: Modifier) {
    self.content = content
    self.modifier = modifier
  }
}
extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
  public var body: Never { _unavailable("ModifiedContent.body") }
}

// MARK: alignment, insets and the frame modifier

@frozen public struct HorizontalAlignment: Equatable {
  @usableFromInline internal let key: UInt
  @usableFromInline internal init(key: UInt) { self.key = key }
  public static var leading: HorizontalAlignment { HorizontalAlignment(key: 2) }
  public static var center: HorizontalAlignment { HorizontalAlignment(key: 4) }
  public static var trailing: HorizontalAlignment { HorizontalAlignment(key: 6) }
}
@frozen public struct VerticalAlignment: Equatable {
  @usableFromInline internal let key: UInt
  @usableFromInline internal init(key: UInt) { self.key = key }
  public static var top: VerticalAlignment { VerticalAlignment(key: 3) }
  public static var center: VerticalAlignment { VerticalAlignment(key: 5) }
  public static var bottom: VerticalAlignment { VerticalAlignment(key: 7) }
}
@frozen public struct Alignment: Equatable {
  public var horizontal: HorizontalAlignment
  public var vertical: VerticalAlignment
  @inlinable public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
    self.horizontal = horizontal
    self.vertical = vertical
  }
  public static var center: Alignment { Alignment(horizontal: .center, vertical: .center) }
}

@frozen public struct EdgeInsets: Equatable {
  public var top: CGFloat
  public var leading: CGFloat
  public var bottom: CGFloat
  public var trailing: CGFloat
  @inlinable public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }
  @inlinable public init() {
    self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
  }
}

@frozen public struct _FrameLayout {
  @usableFromInline internal let width: CGFloat?
  @usableFromInline internal let height: CGFloat?
  @usableFromInline internal let alignment: Alignment
  @usableFromInline internal init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
    self.width = width
    self.height = height
    self.alignment = alignment
  }
  public typealias Body = Never
}
extension _FrameLayout: ViewModifier {}

// MARK: conditional content

@frozen public struct _ConditionalContent<TrueContent, FalseContent> {
  @frozen public enum Storage {
    case trueContent(TrueContent)
    case falseContent(FalseContent)
  }
  public let storage: Storage
}
extension _ConditionalContent: View where TrueContent: View, FalseContent: View {
  public typealias Body = Never
  @usableFromInline internal init(storage: Storage) {
    self.storage = storage
  }
  public var body: Never { _unavailable("_ConditionalContent.body") }
}

// MARK: text

@frozen public struct LocalizedStringKey: Equatable, ExpressibleByStringLiteral {
  internal var key: String
  internal var hasFormatting: Bool = false
  internal var arguments: [FormatArgument]
  public init(_ value: String) {
    self.key = value
    self.arguments = []
  }
  public init(stringLiteral value: String) {
    self.init(value)
  }
  @usableFromInline internal struct FormatArgument: Equatable {
    internal var value: String
  }
}

@usableFromInline internal class AnyTextStorage {
  internal let key: LocalizedStringKey
  internal let table: String?
  internal let bundle: Bundle?
  internal init(key: LocalizedStringKey, table: String?, bundle: Bundle?) {
    self.key = key
    self.table = table
    self.bundle = bundle
  }
}

@frozen public struct Text: Equatable {
  @usableFromInline @frozen internal enum Storage: Equatable {
    case verbatim(String)
    case anyTextStorage(AnyTextStorage)
    @usableFromInline internal static func == (lhs: Storage, rhs: Storage) -> Bool {
      switch (lhs, rhs) {
      case let (.verbatim(a), .verbatim(b)): return a == b
      case let (.anyTextStorage(a), .anyTextStorage(b)): return a === b
      default: return false
      }
    }
  }
  @usableFromInline @frozen internal enum Modifier: Equatable {
    case reserved(Int)
  }
  @usableFromInline internal var storage: Storage
  @usableFromInline internal var modifiers: [Modifier] = []

  public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
    self.storage = .anyTextStorage(AnyTextStorage(key: key, table: tableName, bundle: bundle))
  }
  public init(verbatim content: String) {
    self.storage = .verbatim(content)
  }
}
extension Text: View {
  public typealias Body = Never
  public var body: Never { _unavailable("Text.body") }
}

// MARK: image

@usableFromInline internal class AnyImageProviderBox {
  internal let systemName: String
  internal var capInsets = EdgeInsets()
  internal var resizingMode: Image.ResizingMode?
  internal init(systemName: String) {
    self.systemName = systemName
  }
}

@frozen public struct Image: Equatable {
  internal var provider: AnyImageProviderBox
  public init(systemName: String) {
    self.provider = AnyImageProviderBox(systemName: systemName)
  }
  public enum ResizingMode: Sendable {
    case tile
    case stretch
  }
  public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: Image.ResizingMode = .stretch) -> Image {
    let copy = AnyImageProviderBox(systemName: provider.systemName)
    copy.capInsets = capInsets
    copy.resizingMode = resizingMode
    var image = self
    image.provider = copy
    return image
  }
  public static func == (lhs: Image, rhs: Image) -> Bool {
    lhs.provider === rhs.provider
  }
}
extension Image: View {
  public typealias Body = Never
  public var body: Never { _unavailable("Image.body") }
}

// MARK: button

public struct Button<Label>: View where Label: View {
  internal var action: () -> Void
  internal var label: Label
  public init(action: @escaping () -> Void, label: () -> Label) {
    self.action = action
    self.label = label()
  }
  public typealias Body = Never
  public var body: Never { _unavailable("Button.body") }
}
