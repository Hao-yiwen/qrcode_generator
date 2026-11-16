//
//  qrcode_generatorApp.swift
//  qrcode_generator
//
//  Created by 郝宜文 on 2024/11/5.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit
import Carbon.HIToolbox // 用于处理快捷键

private enum AppColors {
    /// 二维码图案区域需保持高对比白底，便于扫描识别。
    static let qrCodeSurface = Color.white
    static let chromeBackground = Color(nsColor: .windowBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleBorder = Color.primary.opacity(0.12)
}

@MainActor
final class MenuBarExtraCoordinator {
    static let shared = MenuBarExtraCoordinator()
    static let windowIdentifier = NSUserInterfaceItemIdentifier("qrcode.menuBarExtra")

    weak var menuBarWindow: NSWindow?

    private init() {}

    func registerWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = Self.windowIdentifier
        menuBarWindow = window
    }

    /// 优先走状态栏按钮点击，让 SwiftUI 自己维护开关状态。
    /// 只有找不到 status item 时，才按已登记窗口显隐。
    func togglePanel() {
        activateApp()
        if clickMenuBarStatusItem() {
            return
        }

        guard let window = resolvedMenuBarWindow() else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func resolvedMenuBarWindow() -> NSWindow? {
        if let menuBarWindow {
            return menuBarWindow
        }
        return NSApp.windows.first { $0.identifier == Self.windowIdentifier }
    }

    /// 仅查询实现了 `statusItem` 的窗口，避免对其余窗口 KVC 抛出未定义键异常。
    private func clickMenuBarStatusItem() -> Bool {
        let selector = NSSelectorFromString("statusItem")
        for window in NSApp.windows where window.responds(to: selector) {
            guard let statusItem = window.value(forKey: "statusItem") as? NSStatusItem else { continue }
            statusItem.button?.performClick(nil)
            return true
        }
        return false
    }
}

private final class MenuBarWindowProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let window = self.window
        Task { @MainActor in
            MenuBarExtraCoordinator.shared.registerWindow(window)
        }
    }
}

private struct MenuBarWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MenuBarWindowProbeView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // MenuBarExtra / .window 均自 macOS 13.0 可用，与当前 deployment target 一致
        MenuBarExtra("QR Code Generator", systemImage: "qrcode") {
            ContentView()
                .frame(width: 500, height: 600)
                .background(MenuBarWindowAccessor())
        }
        .menuBarExtraStyle(.window)
    }
}

struct QRCodeGenerator {
    static func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}

// 状态管理器
@MainActor
final class AppStateManager: ObservableObject {
    static let shared = AppStateManager()

    @Published var qrCodes: [QRCodeItem] = []

    private init() {
        loadQRCodes()
    }

    func loadQRCodes() {
        guard let data = UserDefaults.standard.data(forKey: "qrcodes") else { return }

        do {
            let decoded = try JSONDecoder().decode([QRCodeItem].self, from: data)
            qrCodes = decoded
        } catch {
            print("Failed to decode QR codes: \(error)")
        }
    }

    func saveQRCodes() {
        do {
            let encoded = try JSONEncoder().encode(qrCodes)
            UserDefaults.standard.set(encoded, forKey: "qrcodes")
        } catch {
            print("Failed to encode QR codes: \(error)")
        }
    }

    func addQRCode(_ content: String) {
        let newItem = QRCodeItem(content: content)
        qrCodes.insert(newItem, at: 0)
        saveQRCodes()
    }

    func deleteQRCode(_ item: QRCodeItem) {
        qrCodes.removeAll { $0.id == item.id }
        saveQRCodes()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupGlobalHotkey()
    }

    func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
        guard let event else { return noErr }

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

        guard status == noErr else { return noErr }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MenuBarExtraCoordinator.shared.togglePanel()
            }
        }
        return noErr
    }

    func setupGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("QRCD".utf8.reduce(0, { $0 << 8 + OSType($1) }))
        hotKeyID.id = 1

        let modifiers = UInt32(cmdKey | controlKey)
        let keyCode = UInt32(kVK_ANSI_Q)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            print("Failed to register hotkey: \(status)")
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                return appDelegate.hotKeyHandler(nextHandler: nil, event: eventRef, userData: userData)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
    @State private var searchText: String = ""
    @State private var showingGeneratedQR: Bool = false
    @State private var showingMenu: Bool = false
    @State private var showingQRDetail: Bool = false
    @State private var showingDonateView: Bool = false
    @State private var currentQRImage: NSImage? = nil
    
    private var filteredHistory: [QRCodeItem] {
        if searchText.isEmpty {
            return stateManager.qrCodes
        } else {
            return stateManager.qrCodes.filter {
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
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
                        .foregroundStyle(.secondary)
                    Text("二维码生成器")
                        .font(.system(size: 13, weight: .medium))
                }
                
                Spacer()
                
                Text("⌘⌃Q")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppColors.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help("全局快捷键：显示/隐藏窗口")
                
                Button(action: {
                    if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                        // 清除当前状态
                        inputText = ""
                        showingGeneratedQR = false
                        currentQRImage = nil
                        window.close()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭窗口")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.chromeBackground)
            
            Divider()
            
            // 主要内容区域
            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    // 输入区域
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextEditor(text: $inputText)
                                .frame(height: 80)
                                .font(.system(.body))
                                .scrollContentBackground(.hidden)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(AppColors.subtleBorder, lineWidth: 1)
                                )
                            
                            // 按钮组垂直排列
                            VStack(spacing: 4) {
                                // 清除按钮
                                Button(action: {
                                    inputText = ""
                                    showingGeneratedQR = false
                                    currentQRImage = nil
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.borderless)
                                .background(AppColors.controlBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .help("清除内容")
                                .disabled(inputText.isEmpty)
                                
                                // 粘贴按钮
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
                                .background(AppColors.controlBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .help("从剪贴板粘贴")
                                .disabled(NSPasteboard.general.string(forType: .string) == nil)
                            }
                        }
                        
                        Button(action: {
                            if !inputText.isEmpty {
                                currentQRImage = QRCodeGenerator.generateQRCode(from: inputText)
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
                        if showingGeneratedQR, let qrImage = currentQRImage {
                            VStack {
                                Image(nsImage: qrImage)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: 120, height: 120)
                                    .background(AppColors.qrCodeSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 1)
                                    .onTapGesture {
                                        showingQRDetail = true
                                    }
                                    .popover(isPresented: $showingQRDetail, arrowEdge: .trailing) {
                                        QRCodeDetailView(qrImage: qrImage, content: inputText)
                                    }
                                
                                HStack(spacing: 16) {
                                    Button(action: {
                                        copyQRCodeToClipboard(qrImage)
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
                            .background(AppColors.controlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    // 历史记录标题
                    HStack {
                        Text("历史记录")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    // 搜索框
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                        
                        TextField("搜索历史记录", text: $searchText)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(AppColors.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 12)
                
                Divider()
                
                // 历史记录列表
               if filteredHistory.isEmpty {
                   VStack(spacing: 8) {
                       Image(systemName: "doc.text.magnifyingglass")
                           .font(.system(size: 24))
                           .foregroundStyle(.secondary)
                       Text(searchText.isEmpty ? "暂无历史记录" : "没有找到匹配的记录")
                           .font(.system(size: 13))
                           .foregroundStyle(.secondary)
                   }
                   .frame(maxWidth: .infinity, minHeight: 100)
                   .background(AppColors.controlBackground)
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
                   .background(AppColors.controlBackground)
               }
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // 添加这个
            .scrollDisabled(false)  // 确保可以滚动
            
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
            .background(AppColors.chromeBackground)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            // 确保每次视图出现时重置状态
            inputText = ""
            showingGeneratedQR = false
            currentQRImage = nil
        }
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
                    .lineLimit(2)
                    .font(.system(.body))
                
                Text(formatDate(item.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 二维码图片
            if let qrImage = QRCodeGenerator.generateQRCode(from: item.content) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 50, height: 50)
                    .background(AppColors.qrCodeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    .foregroundStyle(.red)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppColors.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .background(AppColors.qrCodeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .background(AppColors.qrCodeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
            
            Text("扫描上方二维码向我打赏")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300, height: 400)
    }
}
