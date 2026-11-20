// SPDX-License-Identifier: MIT
import CoreTransferable
import Darwin
import Foundation
import UniformTypeIdentifiers

struct Record: Codable, Equatable, Transferable {
    let count: Int
    let label: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: Self.self, contentType: .data)
    }
}

@main struct Probe {
    static func main() async throws {
        let input = Record(count: 42, label: "Résumé")
        precondition(Record.exportedContentTypes() == [.data])
        let record = try await input.withExportedFile(contentType: .data) { file in
            try await Record(importing: file, contentType: .data)
        }
        precondition(input == record)

        let text = try await String(importing: Data("日本語".utf8), contentType: UTType("public.utf8-plain-text"))
        precondition(text == "日本語")
        do {
            _ = try await String(importing: Data([0xff, 0xfe]), contentType: UTType("public.utf8-plain-text"))
            preconditionFailure("Invalid UTF-8 was accepted")
        } catch {}

        let url = try await URL(importing: Data("https://example.invalid/file".utf8), contentType: UTType("public.url"))
        precondition(url.absoluteString == "https://example.invalid/file")
        print("CoreTransferable PASS for Codable file round trip and strict UTF-8 and URL import")
    }
}
