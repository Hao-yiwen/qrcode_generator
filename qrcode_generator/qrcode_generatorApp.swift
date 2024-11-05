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
}

// 主应用程序
@main
struct qrcode_generatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
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
                
                Text("⌘⇧Space")  // 更新快捷键提示
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("退出应用")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // 主要内容区域
            VStack(spacing: 16) {
                // 输入区域
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("输入文本生成二维码", text: $inputText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(height: 28)
                        
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
                            stateManager.addQRCode(content: inputText)
                            inputText = ""
                        }
                    }) {
                        Text("生成二维码")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(inputText.isEmpty)
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
                .padding(.horizontal, 12)
                
                Divider()
                
                // 历史记录列表
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stateManager.qrCodes) { item in
                            HistoryItemView(item: item) {
                                stateManager.deleteQRCode(item: item)
                            }
                            if item.id != stateManager.qrCodes.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 300, height: 400)
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
