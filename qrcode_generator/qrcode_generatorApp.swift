//
//  qrcode_generatorApp.swift
//  qrcode_generator
//
//  Created by 郝宜文 on 2024/11/5.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UserNotifications
import AppKit

// QR Code 数据模型
struct QRCodeItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let timestamp: Date
    
    init(content: String) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
    }
}

// 主应用程序
@main
struct qrcode_generatorApp: App {
    var body: some Scene {
        MenuBarExtra("QR Code Generator", systemImage: "qrcode") {
            ContentView()
                .frame(width: 300, height: 400)
        }
        .menuBarExtraStyle(.window) // 设置样式为窗口模式
    }
}

struct QRCodeGenerator {
    static func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext(options: [CIContextOption.useSoftwareRenderer: true])
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}

// 状态管理器
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published var qrCodes: [QRCodeItem] = []
    
    private init() {
        loadQRCodes()
    }
    
    func loadQRCodes() {
        if let data = UserDefaults.standard.data(forKey: "qrcodes"),
           let decoded = try? JSONDecoder().decode([QRCodeItem].self, from: data) {
            DispatchQueue.main.async {
                self.qrCodes = decoded
            }
        }
    }
    
    func saveQRCodes() {
        if let encoded = try? JSONEncoder().encode(qrCodes) {
            UserDefaults.standard.set(encoded, forKey: "qrcodes")
        }
    }
    
    func addQRCode( content: String) {
        DispatchQueue.main.async {
            let newItem = QRCodeItem(content: content)
            self.qrCodes.insert(newItem, at: 0)
            self.saveQRCodes()
        }
    }
    
    func deleteQRCode( item: QRCodeItem) {
        DispatchQueue.main.async {
            self.qrCodes.removeAll { $0.id == item.id }
            self.saveQRCodes()
        }
    }
}

// 应用委托
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    func applicationDidFinishLaunching( notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "qrcode", accessibilityDescription: "QR Code Generator")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView())
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if let popover = popover {
                if popover.isShown {
                    popover.performClose(nil)
                } else {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
            }
        }
    }
    
    // 防止应用程序在没有窗口时终止
    func applicationShouldTerminateAfterLastWindowClosed( sender: NSApplication) -> Bool {
        return false
    }
}

//
//  QRCodeGeneratorView.swift
//  qrcode_generator
//
//  Created by 郝宜文 on 2024/11/5.
//

// QR码生成器视图
struct QRCodeGeneratorView: View {
    let content: String
    
    var body: some View {
        if let qrImage = generateQRCode(from: content) {
            Image(nsImage: qrImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        }
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext(options: [CIContextOption.useSoftwareRenderer: true])
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}
//
//  ContentView.swift
//  qrcode_generator
//
//  Created by 郝宜文 on 2024/11/5.
//


// 主视图
struct ContentView: View {
    @StateObject private var stateManager = AppStateManager.shared
    @State private var inputText: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // 输入区域
            VStack(spacing: 8) {
                TextField("输入文本生成二维码", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(height: 24)
                
                Button(action: {
                    if !inputText.isEmpty {
                        stateManager.addQRCode(content: inputText)
                        inputText = ""
                    }
                }) {
                    Text("生成")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.isEmpty)
            }
            .padding([.horizontal, .top])
            
            Divider()
            
            // 历史记录区域
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(stateManager.qrCodes) { item in
                        HistoryItemView(item: item) {
                            stateManager.deleteQRCode(item: item)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 300, height: 400, alignment: .top)
        .padding(.bottom)
    }
}

struct HistoryItemView: View {
    let item: QRCodeItem
    let onDelete: () -> Void
    
    // 使用 showPopover 替代 showDetail
    @State private var showPopover: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 内容部分
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .lineLimit(1)
                    .font(.system(.body))
                Text(item.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // 二维码图片
            if let qrImage = QRCodeGenerator.generateQRCode(from: item.content) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 50, height: 50)
                    .background(Color.white)
                    .cornerRadius(4)
                    // 使用 popover 而不是 sheet
                    .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                        QRCodeDetailView(qrImage: qrImage, content: item.content)
                    }
                    .onTapGesture {
                        showPopover = true
                    }
            }
            
            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct QRCodeDetailView: View {
    let qrImage: NSImage
    let content: String
    
    var body: some View {
        VStack(spacing: 16) {
            Text("二维码详情")
                .font(.headline)
            
            Image(nsImage: qrImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 200, height: 200)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 2)
            
            Text(content)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // 添加复制按钮
            HStack(spacing: 12) {
                Button(action: {
                    copyQRCodeToClipboard(qrImage)
                }) {
                    Label("复制图片", systemImage: "doc.on.doc")
                }
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }) {
                    Label("复制文本", systemImage: "doc.text")
                }
            }
        }
        .padding()
        .frame(width: 300, height: 350)
    }
    
    // 复制图片到剪贴板
    private func copyQRCodeToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
