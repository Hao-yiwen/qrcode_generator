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
import Carbon.HIToolbox // 用于处理快捷键

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
    
    // 添加编码键
    private enum CodingKeys: String, CodingKey {
        case id, content, timestamp
    }
    
    // 自定义编码方法
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    // 自定义解码方法
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}

// 主应用程序
@main
struct qrcode_generatorApp: App {
    var body: some Scene {
        MenuBarExtra("QR Code Generator", systemImage: "qrcode") {
            ContentView()
                .frame(width: 500, height: 600)
        }
        .menuBarExtraStyle(.window)
    }
}

struct QRCodeGenerator {
    static func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
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
        if let data = UserDefaults.standard.data(forKey: "qrcodes") {
            do {
                let decoder = JSONDecoder()
                let decoded = try decoder.decode([QRCodeItem].self, from: data)
                DispatchQueue.main.async {
                    self.qrCodes = decoded
                }
            } catch {
                print("Failed to decode QR codes: \(error)")
            }
        }
    }
    
    func saveQRCodes() {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(qrCodes)
            UserDefaults.standard.set(encoded, forKey: "qrcodes")
        } catch {
            print("Failed to encode QR codes: \(error)")
        }
    }
    
    func addQRCode(_ content: String) {
        let newItem = QRCodeItem(content: content)
        DispatchQueue.main.async {
            self.qrCodes.insert(newItem, at: 0)
            self.saveQRCodes()
        }
    }
    
    func deleteQRCode(_ item: QRCodeItem) {
        DispatchQueue.main.async {
            self.qrCodes.removeAll { $0.id == item.id }
            self.saveQRCodes()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupGlobalHotkey()
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "qrcode", accessibilityDescription: "QR Code Generator")
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView())
        
        // 添加点击外部关闭 popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, let popover = strongSelf.popover, popover.isShown {
                strongSelf.closePopover()
            }
        }
    }
    
    // 定义全局的事件处理函数
    func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
            guard let event = event else { return noErr }
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if status == noErr {
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async {
                    appDelegate.togglePopover()
                }
            }
            return noErr
        }
    
    // 设置全局快捷键
    func setupGlobalHotkey() {
            // 创建唯一的快捷键标识
            var hotKeyID = EventHotKeyID()
            hotKeyID.signature = OSType("QRCD".utf8.reduce(0, { $0 << 8 + OSType($1) }))
            hotKeyID.id = 1
            
            // 设置快捷键组合: Command + Control + Q
            let modifiers = UInt32(cmdKey | controlKey)
            let keyCode = UInt32(kVK_ANSI_Q)  // 使用 Q 键
            
            // 注册快捷键
            let status = RegisterEventHotKey(
                keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            
            if status != noErr {
                print("Failed to register hotkey: \(status)")
                return
            }
            
            // 设置事件处理
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            
            // 安装事件处理器
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, eventRef, userData) -> OSStatus in
                    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                    return appDelegate.hotKeyHandler(nextHandler: nextHandler, event: eventRef, userData: userData)
                },
                1,
                &eventType,
                selfPtr,
                nil
            )
        }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if let popover = popover {
                if popover.isShown {
                    closePopover()
                } else {
                    showPopover(button)
                }
            }
        }
    }
    
    func showPopover(_ sender: NSView) {
        if let popover = popover {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func closePopover() {
        popover?.performClose(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
    
    // 防止应用程序在没有窗口时终止
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
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
    @State private var searchText: String = ""  // 新增搜索文本状态
    @State private var showingGeneratedQR: Bool = false
    @State private var showingMenu: Bool = false
    @State private var showingQRDetail: Bool = false
    @State private var showingDonateView: Bool = false
    
    private var filteredHistory: [QRCodeItem] {
        if searchText.isEmpty {
            return stateManager.qrCodes
        } else {
            return stateManager.qrCodes.filter {
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    func showDetailView(qrImage: NSImage, content: String) {
        let detailView = QRCodeDetailView(qrImage: qrImage, content: content)
        let controller = NSHostingController(rootView: detailView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 350),
            styleMask: [.titled, .fullSizeContentView], // 移除关闭按钮，只保留标题栏
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true // 允许通过背景拖动窗口
        window.titlebarAppearsTransparent = true // 标题栏透明
        window.titleVisibility = .hidden // 隐藏标题
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    private func copyQRCodeToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "qrcode")
                        .foregroundColor(.secondary)
                    Text("二维码生成器")
                        .font(.system(size: 13, weight: .medium))
                }
                
                Spacer()
                
                Text("⌘⌃Q")  // 修改为正确的快捷键
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                
                Button(action: {
                    if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                        window.close()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭窗口")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 主要内容区域
            ScrollView {
                VStack(spacing: 16) {
                    // 输入区域
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextEditor(text: $inputText)
                                .frame(height: 80)
                                .font(.system(.body))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            
                            Button(action: {
                                if let clipboardString = NSPasteboard.general.string(forType: .string) {
                                    inputText = clipboardString
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 14))
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .disabled(NSPasteboard.general.string(forType: .string) == nil)
                        }
                        
                        Button(action: {
                            if !inputText.isEmpty {
                                stateManager.addQRCode(inputText)
                                showingGeneratedQR = true
                            }
                        }) {
                            Text("生成二维码")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(inputText.isEmpty)
                        
                        // 显示刚生成的二维码
                        if showingGeneratedQR && !inputText.isEmpty {
                                VStack {
                                    if let qrImage = QRCodeGenerator.generateQRCode(from: inputText) {
                                        Image(nsImage: qrImage)
                                            .resizable()
                                            .interpolation(.none)
                                            .frame(width: 120, height: 120)
                                            .background(Color.white)
                                            .cornerRadius(8)
                                            .shadow(radius: 1)
                                            .onTapGesture {
                                                showingQRDetail = true
                                            }
                                            .popover(isPresented: $showingQRDetail, arrowEdge: .trailing) {
                                                QRCodeDetailView(qrImage: qrImage, content: inputText)
                                            }
                                    }
                                    
                                    HStack(spacing: 16) {
                                        Button(action: {
                                            if let qrImage = QRCodeGenerator.generateQRCode(from: inputText) {
                                                copyQRCodeToClipboard(qrImage)
                                            }
                                        }) {
                                            Label("复制图片", systemImage: "doc.on.doc")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(inputText, forType: .string)
                                        }) {
                                            Label("复制文本", systemImage: "doc.text")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 8)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    // 历史记录标题
                    HStack {
                        Text("历史记录")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    // 搜索框
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        
                        TextField("搜索历史记录", text: $searchText)
                            .font(.system(size: 12))
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .padding(.horizontal, 12)
                
                Divider()
                
                // 历史记录列表
               if filteredHistory.isEmpty {
                   VStack(spacing: 8) {
                       Image(systemName: "doc.text.magnifyingglass")
                           .font(.system(size: 24))
                           .foregroundColor(.secondary)
                       Text(searchText.isEmpty ? "暂无历史记录" : "没有找到匹配的记录")
                           .font(.system(size: 13))
                           .foregroundColor(.secondary)
                   }
                   .frame(maxWidth: .infinity, minHeight: 100)
                   .background(Color(NSColor.controlBackgroundColor))
               } else {
                   LazyVStack(spacing: 0) {
                       ForEach(filteredHistory) { item in
                           HistoryItemView(item: item) {
                               stateManager.deleteQRCode(item)
                           }
                           if item.id != filteredHistory.last?.id {
                               Divider()
                           }
                       }
                   }
                   .background(Color(NSColor.controlBackgroundColor))
               }
            }
            
            Divider()
            
            // 底部菜单
            HStack {
                Spacer()
                Button(action: { showingMenu.toggle() }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingMenu, arrowEdge: .bottom) {
                    VStack(spacing: 8) {
                        Button(action: {
                            showingDonateView = true
                            showingMenu = false  // 关闭菜单
                        }) {
                            Label("请我喝咖啡", systemImage: "cup.and.saucer.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        
                        Divider()
                        
                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            Label("退出应用", systemImage: "power")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .padding(4)
                    .frame(width: 200)
                }
                .popover(isPresented: $showingDonateView, arrowEdge: .bottom) {
                    DonateView()
                }
                .padding(8)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 600)
    }
}

struct HistoryItemView: View {
    let item: QRCodeItem
    let onDelete: () -> Void
    @State private var showPopover: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 内容部分
            VStack(alignment: .leading, spacing: 4) {
                Text(item.content)
                    .lineLimit(3)
                    .font(.system(.body))
                
                Text(formatDate(item.timestamp))
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
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
            
            ScrollView {
                Text(content)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding(.horizontal)
            }
            .frame(height: 60)
            
            HStack(spacing: 12) {
                Button(action: {
                    copyQRCodeToClipboard(qrImage)
                }) {
                    Label("复制图片", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }) {
                    Label("复制文本", systemImage: "doc.text")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(width: 300, height: 350)
    }
    
    private func copyQRCodeToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

struct DonateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("感谢您的支持！")
                .font(.headline)
            
            Image("alipay-qr")  // 将您的支付宝收款码图片添加到项目的 Assets.xcassets 中
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 200, height: 300)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 2)
            
            Text("扫描上方二维码向我打赏")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300, height: 400)
    }
}
