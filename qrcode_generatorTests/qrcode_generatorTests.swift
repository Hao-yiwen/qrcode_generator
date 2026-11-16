//
//  qrcode_generatorTests.swift
//  qrcode_generatorTests
//
//  Created by 郝宜文 on 2024/11/5.
//

import Testing
@testable import qrcode_generator

struct qrcode_generatorTests {

    @Test func qrCodeItemCodableRoundTrip() throws {
        let item = QRCodeItem(content: "https://example.com")
        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([QRCodeItem].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == item.id)
        #expect(decoded[0].content == item.content)
        #expect(decoded[0].timestamp == item.timestamp)
    }

    @Test func qrCodeGeneratorCreatesImageOnSupportedPlatform() {
        #if os(macOS)
        let image = QRCodeGenerator.generateQRCode(from: "https://example.com")
        #expect(image != nil)
        #expect(image?.size.width ?? 0 > 0)
        #else
        #expect(Bool(true))
        #endif
    }

    @Test @MainActor func appStateManagerPersistsNewItem() {
        let manager = AppStateManager.shared
        let marker = "unit-test-\(UUID().uuidString)"
        let initialCount = manager.qrCodes.count

        manager.addQRCode(marker)
        #expect(manager.qrCodes.count == initialCount + 1)
        #expect(manager.qrCodes.first?.content == marker)

        if let created = manager.qrCodes.first(where: { $0.content == marker }) {
            manager.deleteQRCode(created)
        }
        #expect(manager.qrCodes.contains { $0.content == marker } == false)
    }

}
