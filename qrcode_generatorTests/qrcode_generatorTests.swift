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

}
