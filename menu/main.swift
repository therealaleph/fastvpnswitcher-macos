import AppKit
import Foundation

private let watcherLabel = "com.shin.fastvpnswitcher.watcher"
private let menuLabel = "com.shin.fastvpnswitcher.menu"
private let notificationName = Notification.Name("com.shin.fastvpnswitcher.notify")
private let fm = FileManager.default

private struct CommandResult {
    let status: Int32
    let output: String
}

@discardableResult
private func run(_ executable: String, _ arguments: [String] = []) -> CommandResult {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return CommandResult(status: process.terminationStatus, output: output)
    } catch {
        return CommandResult(status: 127, output: error.localizedDescription)
    }
}

private func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private func handleCommandLineMode() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        return
    }

    if args[1] == "--post-notification" {
        let subtitle = args.count >= 3 ? args[2] : "FastVPN Switcher"
        let body = args.count >= 4 ? args.dropFirst(3).joined(separator: " ") : ""
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: ["subtitle": subtitle, "body": body],
            deliverImmediately: true
        )
        exit(0)
    }

    guard args[1] == "--notify" else {
        return
    }

    let subtitle = args.count >= 3 ? args[2] : "FastVPN Switcher"
    let body = args.count >= 4 ? args.dropFirst(3).joined(separator: " ") : ""
    deliverNotification(subtitle: subtitle, body: body)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))
    exit(0)
}

private func deliverNotification(subtitle: String, body: String) {
    let notification = NSUserNotification()
    notification.title = "FastVPN Switcher"
    notification.subtitle = subtitle
    notification.informativeText = body
    NSUserNotificationCenter.default.deliver(notification)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSUserNotificationCenterDelegate {
    private let uid = getuid()
    private let home = NSHomeDirectory()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?

    private var watcherRunning = false
    private var watcherStartup = false
    private var menuStartup = false
    private var vpnConnected = false
    private var notificationsOn = true
    private var vpnSummary = "VPN: checking..."
    private var lastAction = ""

    private var launchAgentsDir: String { "\(home)/Library/LaunchAgents" }
    private var scriptsDir: String { "\(home)/Library/Scripts" }
    private var logDir: String { "\(home)/Library/Logs" }
    private var watcherScriptPath: String { "\(scriptsDir)/fastvpn-switcher.sh" }
    private var watcherPlistPath: String { "\(launchAgentsDir)/\(watcherLabel).plist" }
    private var menuPlistPath: String { "\(launchAgentsDir)/\(menuLabel).plist" }
    private var logPath: String { "\(logDir)/fastvpn-switcher.log" }
    private var launchDomain: String { "gui/\(uid)" }
    private var bundledWatcherScriptPath: String? {
        Bundle.main.url(forResource: "fastvpn-switcher", withExtension: "sh")?.path
    }
    private var activeWatcherScriptPath: String {
        if fm.fileExists(atPath: watcherScriptPath) {
            return watcherScriptPath
        }
        return bundledWatcherScriptPath ?? watcherScriptPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSUserNotificationCenter.default.delegate = self
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: notificationName,
            object: nil
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "FastVPN Switcher"
        statusItem.button?.imagePosition = .imageOnly

        menu.delegate = self
        statusItem.menu = menu

        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        true
    }

    @objc private func handleDistributedNotification(_ notification: Notification) {
        let subtitle = notification.userInfo?["subtitle"] as? String ?? "FastVPN Switcher"
        let body = notification.userInfo?["body"] as? String ?? ""
        deliverNotification(subtitle: subtitle, body: body)
    }

    private func refreshStatus() {
        watcherRunning = isServiceRunning(watcherLabel)
        watcherStartup = isStartupEnabled(label: watcherLabel, plistPath: watcherPlistPath)
        menuStartup = fm.fileExists(atPath: menuPlistPath) && !isServiceDisabled(menuLabel)
        vpnSummary = detectVPN()
        vpnConnected = hasConnectedVPN()
        notificationsOn = notificationsEnabled()
        updateIcon()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let title = NSMenuItem(title: "FastVPN Switcher", action: nil, keyEquivalent: "")
        title.isEnabled = false
        title.attributedTitle = NSAttributedString(
            string: "FastVPN Switcher",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        menu.addItem(title)

        menu.addItem(disabledItem(watcherRunning ? "Watcher: running" : "Watcher: stopped"))
        menu.addItem(disabledItem(vpnSummary))

        if !lastAction.isEmpty {
            menu.addItem(disabledItem(lastAction))
        }

        menu.addItem(.separator())

        let toggleWatcher = NSMenuItem(
            title: watcherRunning ? "Stop Watcher Now" : "Start Watcher Now",
            action: #selector(toggleWatcherNow),
            keyEquivalent: ""
        )
        toggleWatcher.target = self
        menu.addItem(toggleWatcher)

        let reconnect = NSMenuItem(title: "Reconnect Current VPN", action: #selector(reconnectCurrentVPN), keyEquivalent: "")
        reconnect.target = self
        reconnect.isEnabled = vpnConnected
        menu.addItem(reconnect)

        let install = NSMenuItem(title: "Install / Update Watcher", action: #selector(installWatcherFromMenu), keyEquivalent: "")
        install.target = self
        menu.addItem(install)

        menu.addItem(.separator())

        let watcherLogin = NSMenuItem(title: "Start Watcher at Login", action: #selector(toggleWatcherStartup), keyEquivalent: "")
        watcherLogin.target = self
        watcherLogin.state = watcherStartup ? .on : .off
        menu.addItem(watcherLogin)

        let menuLogin = NSMenuItem(title: "Show V Icon at Login", action: #selector(toggleMenuStartup), keyEquivalent: "")
        menuLogin.target = self
        menuLogin.state = menuStartup ? .on : .off
        menu.addItem(menuLogin)

        let notifications = NSMenuItem(title: "Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        notifications.target = self
        notifications.state = notificationsOn ? .on : .off
        menu.addItem(notifications)

        menu.addItem(.separator())

        let openLog = NSMenuItem(title: "Open Log", action: #selector(openLogFile), keyEquivalent: "")
        openLog.target = self
        menu.addItem(openLog)

        let reveal = NSMenuItem(title: "Reveal Installed Script", action: #selector(revealScript), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About", action: nil, keyEquivalent: "")
        let aboutMenu = NSMenu()
        aboutMenu.addItem(linkItem(title: "GitHub", action: #selector(openGitHub)))
        aboutMenu.addItem(linkItem(title: "Website", action: #selector(openWebsite)))
        aboutMenu.addItem(linkItem(title: "Donate", action: #selector(openDonate)))
        about.submenu = aboutMenu
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit FastVPN Switcher", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func linkItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func updateIcon() {
        statusItem.button?.image = makeIcon(running: watcherRunning, connected: vpnConnected)
        statusItem.button?.toolTip = "\(watcherRunning ? "Watcher running" : "Watcher stopped")\n\(vpnSummary)"
    }

    private func makeIcon(running: Bool, connected: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 2.5, y: 2.5, width: 17, height: 17)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5.5, yRadius: 5.5)

        if running {
            if connected {
                NSGradient(colors: [
                    NSColor(calibratedRed: 0.02, green: 0.63, blue: 0.88, alpha: 1),
                    NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.62, alpha: 1)
                ])?.draw(in: path, angle: 35)
            } else {
                NSGradient(colors: [
                    NSColor(calibratedRed: 0.24, green: 0.48, blue: 0.90, alpha: 1),
                    NSColor(calibratedRed: 0.44, green: 0.37, blue: 0.94, alpha: 1)
                ])?.draw(in: path, angle: 35)
            }
        } else {
            NSColor(calibratedWhite: 0.50, alpha: 0.85).setFill()
            path.fill()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .black),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        NSString(string: "V").draw(in: NSRect(x: 2, y: 3.2, width: 18, height: 16), withAttributes: attrs)

        if !running {
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let slash = NSBezierPath()
            slash.lineWidth = 1.7
            slash.move(to: NSPoint(x: 6, y: 5.7))
            slash.line(to: NSPoint(x: 16, y: 16.3))
            slash.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func isServiceRunning(_ label: String) -> Bool {
        let result = run("/bin/launchctl", ["print", "\(launchDomain)/\(label)"])
        return result.status == 0 && result.output.contains("state = running")
    }

    private func isServiceDisabled(_ label: String) -> Bool {
        let result = run("/bin/launchctl", ["print-disabled", launchDomain])
        let pattern = "\"\(label)\" => true"
        return result.output.contains(pattern)
    }

    private func isStartupEnabled(label: String, plistPath: String) -> Bool {
        fm.fileExists(atPath: plistPath) && !isServiceDisabled(label)
    }

    private func runWatcherScript(_ arguments: [String]) -> CommandResult {
        run("/bin/bash", [activeWatcherScriptPath] + arguments)
    }

    private func detectVPN() -> String {
        let result = runWatcherScript(["--status-human"])
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "VPN: none connected" : output
    }

    private func hasConnectedVPN() -> Bool {
        let result = runWatcherScript(["--status"])
        return result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func notificationsEnabled() -> Bool {
        runWatcherScript(["--notifications-status"]).output.trimmingCharacters(in: .whitespacesAndNewlines) != "off"
    }

    @objc private func toggleWatcherNow() {
        if watcherRunning {
            stopWatcher()
        } else {
            startWatcher()
        }
        refreshStatus()
    }

    @objc private func installWatcherFromMenu() {
        installWatcher(startAfterInstall: true)
        refreshStatus()
    }

    @objc private func toggleWatcherStartup() {
        if watcherStartup {
            run("/bin/launchctl", ["disable", "\(launchDomain)/\(watcherLabel)"])
            lastAction = "Watcher login startup: off"
        } else {
            ensureWatcherFiles()
            run("/bin/launchctl", ["enable", "\(launchDomain)/\(watcherLabel)"])
            lastAction = "Watcher login startup: on"
        }
        refreshStatus()
    }

    @objc private func toggleMenuStartup() {
        if menuStartup {
            run("/bin/launchctl", ["disable", "\(launchDomain)/\(menuLabel)"])
            try? fm.removeItem(atPath: menuPlistPath)
            lastAction = "V icon login startup: off"
        } else {
            writeMenuPlist()
            run("/bin/launchctl", ["enable", "\(launchDomain)/\(menuLabel)"])
            lastAction = "V icon login startup: on"
        }
        refreshStatus()
    }

    @objc private func toggleNotifications() {
        let newValue = notificationsOn ? "off" : "on"
        let result = runWatcherScript(["--notifications", newValue])
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        lastAction = "Notifications: \(value.isEmpty ? newValue : value)"
        refreshStatus()
    }

    @objc private func reconnectCurrentVPN() {
        let result = runWatcherScript(["--reconnect-current"])
        lastAction = result.status == 0 ? "Reconnect requested" : "Reconnect unavailable"
        refreshStatus()
    }

    @objc private func openGitHub() {
        openURL("https://github.com/therealaleph/fastvpnswitcher-macos")
    }

    @objc private func openWebsite() {
        openURL("https://sh1n.org")
    }

    @objc private func openDonate() {
        openURL("https://sh1n.org/donate")
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openLogFile() {
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: Data(), attributes: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func revealScript() {
        if fm.fileExists(atPath: watcherScriptPath) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: watcherScriptPath)])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: scriptsDir)])
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startWatcher() {
        let restoreDisabled = isServiceDisabled(watcherLabel)
        ensureWatcherFiles()
        if restoreDisabled {
            run("/bin/launchctl", ["enable", "\(launchDomain)/\(watcherLabel)"])
        }
        run("/bin/launchctl", ["bootstrap", launchDomain, watcherPlistPath])
        run("/bin/launchctl", ["kickstart", "-k", "\(launchDomain)/\(watcherLabel)"])
        if restoreDisabled {
            run("/bin/launchctl", ["disable", "\(launchDomain)/\(watcherLabel)"])
        }
        lastAction = "Watcher started"
    }

    private func stopWatcher() {
        run("/bin/launchctl", ["bootout", launchDomain, watcherPlistPath])
        lastAction = "Watcher stopped"
    }

    private func installWatcher(startAfterInstall: Bool) {
        ensureWatcherFiles()
        run("/bin/launchctl", ["bootout", launchDomain, watcherPlistPath])
        run("/bin/launchctl", ["enable", "\(launchDomain)/\(watcherLabel)"])

        if startAfterInstall {
            run("/bin/launchctl", ["bootstrap", launchDomain, watcherPlistPath])
            run("/bin/launchctl", ["kickstart", "-k", "\(launchDomain)/\(watcherLabel)"])
        }

        lastAction = startAfterInstall ? "Watcher installed and started" : "Watcher installed"
    }

    private func ensureWatcherFiles() {
        try? fm.createDirectory(atPath: scriptsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        if let bundled = Bundle.main.url(forResource: "fastvpn-switcher", withExtension: "sh") {
            try? fm.removeItem(atPath: watcherScriptPath)
            try? fm.copyItem(at: bundled, to: URL(fileURLWithPath: watcherScriptPath))
        }

        chmod(watcherScriptPath, 0o755)
        writeWatcherPlist()
    }

    private func writeWatcherPlist() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(watcherLabel)</string>

          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscape(watcherScriptPath))</string>
          </array>

          <key>EnvironmentVariables</key>
          <dict>
            <key>PATH</key>
            <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
            <key>TAILSCALE_BE_CLI</key>
            <string>1</string>
            <key>FASTVPN_NOTIFIER</key>
            <string>\(xmlEscape(Bundle.main.executableURL?.path ?? ""))</string>
          </dict>

          <key>RunAtLoad</key>
          <true/>

          <key>KeepAlive</key>
          <true/>

          <key>StandardOutPath</key>
          <string>\(xmlEscape(home))/Library/Logs/fastvpn-switcher.launchd.out.log</string>

          <key>StandardErrorPath</key>
          <string>\(xmlEscape(home))/Library/Logs/fastvpn-switcher.launchd.err.log</string>
        </dict>
        </plist>
        """

        try? plist.write(toFile: watcherPlistPath, atomically: true, encoding: .utf8)
    }

    private func writeMenuPlist() {
        let bundlePath = Bundle.main.bundlePath
        try? fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(menuLabel)</string>

          <key>ProgramArguments</key>
          <array>
            <string>/usr/bin/open</string>
            <string>-g</string>
            <string>\(xmlEscape(bundlePath))</string>
          </array>

          <key>RunAtLoad</key>
          <true/>

          <key>KeepAlive</key>
          <false/>

          <key>StandardOutPath</key>
          <string>\(xmlEscape(home))/Library/Logs/fastvpn-switcher-menu.out.log</string>

          <key>StandardErrorPath</key>
          <string>\(xmlEscape(home))/Library/Logs/fastvpn-switcher-menu.err.log</string>
        </dict>
        </plist>
        """

        try? plist.write(toFile: menuPlistPath, atomically: true, encoding: .utf8)
    }
}

handleCommandLineMode()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
