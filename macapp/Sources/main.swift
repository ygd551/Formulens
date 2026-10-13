import AppKit
import Carbon
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    static var shared: AppDelegate!

    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyOK = false
    private var keyMonitor: Any?
    private var capturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMainMenu()
        setupStatusItem()
        registerHotKey()
        installPasteMonitor()
        model.onServerStateChange = { [weak self] in self?.updateStatusIcon() }
        model.onLanguageChange = { [weak self] in
            self?.setupMainMenu()
            self?.updateStatusIcon()
        }
        model.startServer()
        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.server.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: 菜单栏图标

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let base = model.busy || capturing ? "∑…" : "∑"
        button.title = model.serverState == .ready ? base : base + "·"
        button.toolTip = "Formulens — " + model.serverState.title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 快捷键被其他应用占用时，在菜单里说明，避免用户以为软件没反应
        let cap = NSMenuItem(title: hotKeyOK ? L("Snip & Recognize") : L("Snip & Recognize (⌃⌘M is used by another app)"),
                             action: #selector(captureAction), keyEquivalent: hotKeyOK ? "m" : "")
        cap.keyEquivalentModifierMask = [.control, .command]
        cap.target = self
        menu.addItem(cap)
        menu.addItem(makeItem(L("Recognize Image from Clipboard"), #selector(pasteAction)))
        menu.addItem(makeItem(L("Show Window"), #selector(showWindowAction)))
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for mode in RecognizeMode.allCases {
            let it = makeItem(mode.title, #selector(setMode(_:)))
            it.representedObject = mode.rawValue
            it.state = model.mode == mode ? .on : .off
            modeMenu.addItem(it)
        }
        let modeItem = NSMenuItem(title: L("Recognition Mode"), action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let copyMenu = NSMenu()
        for fmt in CopyFormat.allCases {
            let it = makeItem(fmt.title, #selector(setCopyFormat(_:)))
            it.representedObject = fmt.rawValue
            it.state = model.copyFormat == fmt ? .on : .off
            copyMenu.addItem(it)
        }
        let copyItem = NSMenuItem(title: L("Copy Format"), action: nil, keyEquivalent: "")
        copyItem.submenu = copyMenu
        menu.addItem(copyItem)

        let langMenu = NSMenu()
        for lang in AppLanguage.allCases {
            let it = makeItem(lang.title, #selector(setLanguage(_:)))
            it.representedObject = lang.rawValue
            it.state = model.language == lang ? .on : .off
            langMenu.addItem(it)
        }
        // 菜单标题同时显示英文，看不懂当前语言时也能找到
        let langTitle = L("Language")
        let langItem = NSMenuItem(title: langTitle == "Language" ? langTitle : langTitle + " / Language",
                                  action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())
        let login = makeItem(L("Launch at Login"), #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let status = NSMenuItem(title: model.serverState.title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if model.serverState == .failed {
            menu.addItem(makeItem(L("Restart Model Service"), #selector(restartServer)))
        }
        menu.addItem(.separator())
        menu.addItem(makeItem(L("Restart Formulens"), #selector(relaunchAction)))
        let quit = makeItem(L("Quit Formulens"), #selector(quitAction))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = RecognizeMode(rawValue: raw) { model.mode = m }
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) { model.setLanguage(lang) }
    }

    @objc private func setCopyFormat(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let f = CopyFormat(rawValue: raw) { model.copyFormat = f }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showWindow()
            model.showToast(L("Failed to update Launch at Login: %@", error.localizedDescription))
        }
    }

    @objc private func restartServer() { model.startServer() }
    @objc private func showWindowAction() { showWindow() }
    @objc private func quitAction() { NSApp.terminate(nil) }
    @objc private func relaunchAction() { relaunch() }

    @objc private func pasteAction() {
        if let data = ImagePrep.pngFromPasteboard(.general) {
            showWindow()
            model.recognize(imageData: data)
        } else {
            showWindow()
            model.showToast(L("No image on the clipboard"))
        }
    }

    // MARK: 应用菜单（让 ⌘C / ⌘V / ⌘A / ⌘Z / ⌘W 在窗口中可用）

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: L("Quit Formulens"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Edit"))
        edit.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    /// 窗口中按 ⌘V 且剪贴板里是图片（而不是文字）时，直接识别
    private func installPasteMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v"
            else { return event }
            let pb = NSPasteboard.general
            if pb.string(forType: .string) == nil, let data = ImagePrep.pngFromPasteboard(pb) {
                self.model.recognize(imageData: data)
                return nil
            }
            return event
        }
    }

    // MARK: 全局快捷键 ⌃⌘M（Carbon 热键，无需辅助功能权限）

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { AppDelegate.shared.capture() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x464D_4C4E), id: 1)  // 'FMLN'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | controlKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyOK = status == noErr
        if !hotKeyOK {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.model.showToast(L("The ⌃⌘M shortcut is used by another app. Use the ∑ menu bar icon to snip."))
            }
        }
    }

    // MARK: 截图

    @objc private func captureAction() { capture() }

    func capture() {
        guard !capturing, !model.busy else { return }
        // 截图需要「录屏与系统录音」权限；授权只在应用重启后生效
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()  // 让 Formulens 出现在系统设置的列表中
            askForScreenCapturePermission()
            return
        }
        capturing = true
        updateStatusIcon()
        DispatchQueue.global(qos: .userInitiated).async {
            let path = NSTemporaryDirectory() + "formulens-\(UUID().uuidString).png"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", path]  // -i 拉框选择，Esc 取消
            var data: Data?
            if (try? p.run()) != nil {
                p.waitUntilExit()
                data = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
            try? FileManager.default.removeItem(atPath: path)
            DispatchQueue.main.async {
                self.capturing = false
                if let data, !data.isEmpty {
                    self.showWindow()
                    self.model.recognize(imageData: data)
                }
                self.updateStatusIcon()
            }
        }
    }

    private func askForScreenCapturePermission() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Screen Recording permission required")
        alert.informativeText = L("Turn on Formulens in System Settings → Privacy & Security → Screen & System Audio Recording, then click “Restart Formulens”.\n\nIf it is already on, the permission belongs to an older build: select Formulens, remove it with “−”, add it again, turn it on, and restart.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Restart Formulens"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: 主窗口

    func showWindow() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Formulens"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ContentView().environmentObject(model))
            w.center()
            w.setFrameAutosaveName("FormulensMainWindow")
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
