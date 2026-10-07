import Cocoa
import Carbon.HIToolbox

// Italian if the Mac is set to Italian, English otherwise.
private let italian = Locale.preferredLanguages.first?.hasPrefix("it") ?? false
private func L(_ en: String, _ it: String) -> String { italian ? it : en }

// ─── Carbon hotkey callback ───────────────────────────────────────────────
private func hotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event:   EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = userData else { return noErr }
    Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue().startCapture()
    return noErr
}

// ─── ClickCatchView — cattura i click sull'overlay (fuori dal panel) ───────
private final class ClickCatchView: NSView {
    var onTap: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onTap?() }
    override var acceptsFirstResponder: Bool { false }
}

// ─── DimOverlay — schermo intero blur + dim, blocca click-through mouse ────
final class DimOverlay: NSPanel {
    var onTap: (() -> Void)?

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        hasShadow = false; alphaValue = 0; ignoresMouseEvents = false
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let vev = NSVisualEffectView()
        vev.material = .popover
        vev.blendingMode = .behindWindow
        vev.state = .active
        vev.appearance = NSAppearance(named: .darkAqua)
        vev.autoresizingMask = [.width, .height]
        contentView = vev

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.52).cgColor
        tint.autoresizingMask = [.width, .height]
        vev.addSubview(tint)

        let catchView = ClickCatchView()
        catchView.onTap = { [weak self] in self?.onTap?() }
        catchView.autoresizingMask = [.width, .height]
        vev.addSubview(catchView)
    }

    func show(on screen: NSScreen) {
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }
    }

    func hide(completion: @escaping () -> Void = {}) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { self.orderOut(nil); completion() })
    }
}

// ─── ScreenshotCard — screenshot che vola dal centro al thumbnail ──────────
final class ScreenshotCard: NSPanel {
    private let imgView = NSImageView()

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        hasShadow = true; alphaValue = 0; ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 12
        imgView.layer?.masksToBounds = true
        contentView = imgView
    }

    func animate(image: NSImage, screen: NSScreen, toThumb thumbRect: NSRect,
                 completion: @escaping () -> Void) {
        imgView.image = image
        let aspect = image.size.width / max(image.size.height, 1)
        let sw = min(screen.frame.width * 0.40, 540.0)
        let sh = sw / max(aspect, 0.1)
        let startFrame = NSRect(x: screen.frame.midX - sw / 2,
                                y: screen.frame.midY - sh / 2,
                                width: sw, height: sh)
        setFrame(startFrame, display: false); alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.48
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.10, 1.0)
                self.animator().alphaValue = 0.4
                self.animator().setFrame(thumbRect, display: true)
            }, completionHandler: {
                self.orderOut(nil)
                completion()
            })
        }
    }
}

// ─── AirplanePanel — aeroplanino che vola verso Claude Desktop ─────────────
final class AirplanePanel: NSPanel {
    // Mantenuto in vita durante l'animazione
    private static var _retain: AirplanePanel?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 72, height: 72),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        hasShadow = false; alphaValue = 0; ignoresMouseEvents = true
        // Livello massimo — sopra a tutto, incluso il DimOverlay
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: 72, height: 72))
        let cfg = NSImage.SymbolConfiguration(pointSize: 48, weight: .bold)
        iv.image = NSImage(systemSymbolName: "paperplane.fill",
                           accessibilityDescription: nil)?
                   .withSymbolConfiguration(cfg)
        // Arancione Claude
        iv.contentTintColor = NSColor(red: 0.88, green: 0.52, blue: 0.18, alpha: 1.0)
        iv.imageScaling = .scaleProportionallyUpOrDown
        contentView = iv
    }

    // Animazione 60fps su bezier cubica:
    // lancio in alto → arco → picchiata verso la Dock, rimpicciolisce, ruota, poi svanisce
    func launch(from origin: NSPoint, screen: NSScreen) {
        AirplanePanel._retain = self

        let dockBandTop = screen.visibleFrame.minY
        let dockMidY    = Double((screen.frame.minY + dockBandTop) / 2)
        let dockX       = Double(screen.frame.midX - 60)

        let sx = Double(origin.x), sy = Double(origin.y)

        // Bezier cubica: slancio su-destra → curva → arrivo dall'alto alla Dock
        let p0 = (x: sx,          y: sy)
        let p1 = (x: sx + 80,     y: sy + 190)    // picco dell'arco
        let p2 = (x: dockX + 110, y: dockMidY + 190) // approccio dall'alto
        let p3 = (x: dockX,       y: dockMidY)

        func bez(_ t: Double) -> (x: Double, y: Double) {
            let u = 1 - t
            return (u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                    u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
        }
        func bezTan(_ t: Double) -> (x: Double, y: Double) {
            let u = 1 - t
            return (3*(u*u*(p1.x-p0.x) + 2*u*t*(p2.x-p1.x) + t*t*(p3.x-p2.x)),
                    3*(u*u*(p1.y-p0.y) + 2*u*t*(p2.y-p1.y) + t*t*(p3.y-p2.y)))
        }

        contentView?.wantsLayer = true
        let startSz: CGFloat = 72, endSz: CGFloat = 18
        let totalDuration = 1.2
        let startTime = Date()

        // Posizione iniziale
        let initSz = startSz
        setFrame(NSRect(x: origin.x - initSz/2, y: origin.y - initSz/2,
                        width: initSz, height: initSz), display: false)
        alphaValue = 1.0
        orderFrontRegardless()

        func tick() {
            let raw = min(Date().timeIntervalSince(startTime) / totalDuration, 1.0)
            // smoothstep
            let t = raw * raw * (3 - 2 * raw)

            let pos = bez(t)
            let tan = bezTan(t)
            let sz  = startSz + (endSz - startSz) * CGFloat(t)

            // Rotazione: paperplane.fill punta a ~45° di default
            let angle = atan2(tan.y, tan.x) - .pi / 4
            contentView?.layer?.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(angle)))

            // Svanisce solo nell'ultimo 25%
            alphaValue = raw < 0.75 ? 1.0 : CGFloat(max(0, 1 - (raw - 0.75) / 0.25))

            setFrame(NSRect(x: pos.x - Double(sz)/2, y: pos.y - Double(sz)/2,
                            width: Double(sz), height: Double(sz)), display: false)

            if raw < 1.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0/60.0, execute: tick)
            } else {
                orderOut(nil)
                AirplanePanel._retain = nil
            }
        }

        tick()
    }
}

// ─── FeedbackBezel ────────────────────────────────────────────────────────
final class FeedbackBezel: NSPanel {
    private let icon  = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 180, height: 86),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true; alphaValue = 0; hasShadow = true

        let cv = contentView!
        cv.wantsLayer = true
        cv.layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.94).cgColor
        cv.layer?.cornerRadius = 22; cv.layer?.masksToBounds = true
        cv.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        cv.layer?.borderWidth = 0.6

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.isBordered = false; label.drawsBackground = false; label.isEditable = false
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.95); label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            stack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
        ])
    }

    func show(symbol: String, text: String, duration: TimeInterval = 1.2) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideTimer?.invalidate()
            let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            self.icon.image = NSImage(systemSymbolName: symbol,
                                      accessibilityDescription: nil)?
                              .withSymbolConfiguration(cfg)
            self.label.stringValue = text
            guard let screen = NSScreen.main else { return }
            let sf = screen.frame; let bw = self.frame.width; let bh = self.frame.height
            let menuH = NSStatusBar.system.thickness
            let cx = sf.midX - bw / 2
            let finalY = sf.maxY - menuH - bh - 6
            let startY = sf.maxY - bh / 2
            self.setFrameOrigin(NSPoint(x: cx, y: startY))
            self.alphaValue = 0; self.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
                self.animator().setFrameOrigin(NSPoint(x: cx, y: finalY))
            }
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
                [weak self] _ in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22; ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.animator().alphaValue = 0
                    self.animator().setFrameOrigin(NSPoint(x: cx, y: startY))
                }, completionHandler: { self.orderOut(nil) })
            }
        }
    }
}

// ─── PromptPanel ──────────────────────────────────────────────────────────
// IMPORTANTE: niente .nonactivatingPanel — il panel DEVE catturare la tastiera.
// NIENTE globalMonitor — osserva ma non consuma eventi → il testo finiva anche
// nelle app in background (es. barra di ricerca Google).
final class PromptPanel: NSPanel, NSTextFieldDelegate, NSWindowDelegate {

    private let thumbView = NSImageView()
    private let textField = NSTextField()
    private var completion: ((String?) -> Void)?

    let pw: CGFloat = 600
    let ph: CGFloat = 70

    // Senza questo override macOS può rifiutare di rendere il panel key window
    // quando alphaValue=0 oppure è borderless — causando: niente click sull'input, niente Esc
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 70),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        hasShadow = true; alphaValue = 0
        delegate = self

        let cv = contentView!
        cv.wantsLayer = true
        cv.layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.97).cgColor
        cv.layer?.cornerRadius = 18; cv.layer?.masksToBounds = true
        cv.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        cv.layer?.borderWidth = 0.7

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 7
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        thumbView.layer?.borderWidth = 0.6
        thumbView.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: L("⏎ send  ·  esc cancel", "⏎ invia  ·  esc annulla"))
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.28)
        hint.translatesAutoresizingMaskIntoConstraints = false

        textField.isBordered = false; textField.drawsBackground = false
        textField.textColor = .white; textField.font = .systemFont(ofSize: 15)
        textField.focusRingType = .none
        textField.placeholderAttributedString = NSAttributedString(
            string: L("Add a message... (optional)", "Aggiungi un messaggio... (opzionale)"),
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.28),
                         .font: NSFont.systemFont(ofSize: 15)])
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(thumbView); cv.addSubview(hint); cv.addSubview(textField)
        NSLayoutConstraint.activate([
            thumbView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            thumbView.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 62),
            thumbView.heightAnchor.constraint(equalToConstant: 46),
            hint.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -14),
            hint.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: hint.leadingAnchor, constant: -10),
            textField.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func present(screenshot: NSImage?, dimOverlay: DimOverlay,
                 completion: @escaping (String?) -> Void) {
        self.completion = completion
        textField.stringValue = ""

        if let img = screenshot {
            thumbView.image = img; thumbView.contentTintColor = nil
        } else {
            let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            thumbView.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                      accessibilityDescription: nil)?
                              .withSymbolConfiguration(cfg)
            thumbView.contentTintColor = NSColor(red: 0.30, green: 0.85, blue: 0.50, alpha: 0.85)
        }

        guard let screen = NSScreen.main else { completion(nil); return }
        let sf = screen.frame
        let finalCX = sf.midX - pw / 2
        let finalCY = sf.midY + 50

        let s: CGFloat = 0.88
        let startFrame = NSRect(x: finalCX + pw*(1-s)/2, y: finalCY + ph*(1-s)/2,
                                width: pw*s, height: ph*s)
        let endFrame   = NSRect(x: finalCX, y: finalCY, width: pw, height: ph)

        setFrame(startFrame, display: false); alphaValue = 0.01  // >0 perché macOS ignora makeKeyAndOrderFront su finestre completamente invisibili
        dimOverlay.onTap = { [weak self] in self?.dismiss(sending: false) }

        // Attiva l'app e ruba il focus dalla app precedente
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(textField)

        // Retry a 100ms e a 300ms — copre il race condition post-screencapture
        for delay in [0.10, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.completion != nil else { return }
                if !self.isKeyWindow {
                    NSApp.activate(ignoringOtherApps: true)
                    self.makeKeyAndOrderFront(nil)
                    self.makeFirstResponder(self.textField)
                }
            }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            animator().alphaValue = 1.0
            animator().setFrame(endFrame, display: true)
        }
    }

    func dismiss(sending: Bool) {
        guard let cb = completion else { return }
        completion = nil
        let result: String? = sending ? textField.stringValue : nil

        if sending, let screen = NSScreen.main {
            // ── Animazione "impacchettamento" ──────────────────────────────
            // Il panel si stringe verso il proprio centro (come se si arrotolasse),
            // poi scompare e al suo posto compare l'aereo che vola verso la Dock.
            let cx = frame.midX; let cy = frame.midY
            let tiny: CGFloat = 52
            let tinyFrame = NSRect(x: cx - tiny/2, y: cy - tiny/2, width: tiny, height: tiny)

            // Aumenta il corner radius per dare l'idea di "paletta che si arrotola"
            contentView?.layer?.cornerRadius = 26
            // Flash leggero del bordo
            contentView?.layer?.borderColor =
                NSColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 0.9).cgColor

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.45, 1.0)
                self.animator().setFrame(tinyFrame, display: true)
                self.animator().alphaValue = 0.75
            }, completionHandler: {
                self.orderOut(nil)
                // L'aereo parte esattamente da dove il panel si è "compresso"
                let ap = AirplanePanel()
                ap.launch(from: NSPoint(x: cx, y: cy), screen: screen)
            })

            // Il flusso di consegna parte mentre l'aereo è ancora in volo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { cb(result) }

        } else {
            // Annulla: fade + ritiro verso il centro
            let cx = frame.origin.x; let cy = frame.origin.y
            let w = frame.width;     let h  = frame.height
            let exitFrame = NSRect(x: cx + w*0.06, y: cy + h*0.06,
                                   width: w*0.88, height: h*0.88)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
                self.animator().setFrame(exitFrame, display: true)
            }, completionHandler: {
                self.orderOut(nil)
                cb(result)
            })
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss(sending: false) }

    // Se perdiamo il focus mentre il panel è aperto, lo riprendiamo subito.
    // Questo impedisce che la tastiera vada a Chrome o altre app in background.
    func windowDidResignKey(_ notification: Notification) {
        guard completion != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.completion != nil else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            self.makeFirstResponder(self.textField)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        makeFirstResponder(textField)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:))   { dismiss(sending: true);  return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { dismiss(sending: false); return true }
        return false
    }
}


// ─── AppDelegate ──────────────────────────────────────────────────────────
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem:     NSStatusItem!
    private var hotKeyRef:      EventHotKeyRef?
    private var handlerRef:     EventHandlerRef?
    private var bezel:          FeedbackBezel!
    private var dimOverlay:     DimOverlay!
    private var promptPanel:    PromptPanel!
    private var screenshotCard: ScreenshotCard!
    private var capturing       = false

    func applicationDidFinishLaunching(_ _: Notification) {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if running.count > 1 { NSApp.terminate(nil); return }

        NSApp.setActivationPolicy(.accessory)
        bezel          = FeedbackBezel()
        dimOverlay     = DimOverlay()
        promptPanel    = PromptPanel()
        screenshotCard = ScreenshotCard()

        buildMenuBar()
        registerHotKey()

        let axOpts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                     as CFDictionary
        if !AXIsProcessTrustedWithOptions(axOpts) {
            bezel.show(symbol: "exclamationmark.triangle",
                       text: L("Allow Accessibility", "Concedi Accessibility"), duration: 4.0)
        } else {
            bezel.show(symbol: "checkmark.circle.fill", text: L("ClaudeShot ready", "ClaudeShot pronto"), duration: 2.0)
        }
    }

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "camera.viewfinder",
                                accessibilityDescription: "ClaudeShot")
            btn.image?.isTemplate = true
        }
        let menu = NSMenu()
        let cap = NSMenuItem(title: L("Capture → Claude  ⌘⇧Space", "Cattura → Claude  ⌘⇧Space"),
                             action: #selector(menuCapture), keyEquivalent: "")
        cap.target = self; menu.addItem(cap)
        let testItem = NSMenuItem(title: L("Test the animation 🛫", "Test aereo 🛫"),
                                  action: #selector(testAirplane), keyEquivalent: "")
        testItem.target = self; menu.addItem(testItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit ClaudeShot", "Esci"),
                                action: #selector(NSApp.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind:  UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyCallback, 1, &spec, selfPtr, &handlerRef)
        let id = EventHotKeyID(signature: 0x434C5348, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: – Flusso principale

    func startCapture() {
        guard !capturing else { return }
        capturing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 1. screencapture interattivo — l'utente seleziona l'area con il mouse
            let sc = Process()
            sc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            sc.arguments = ["-i", "-c"]
            guard (try? sc.run()) != nil else { self.capturing = false; return }
            sc.waitUntilExit()

            guard sc.terminationStatus == 0 else {
                self.capturing = false   // Esc durante selezione: uscita silenziosa
                return
            }

            // 2. Leggi immagine dalla clipboard (per thumbnail e animazione card)
            let screenshot: NSImage? = NSPasteboard.general
                .readObjects(forClasses: [NSImage.self], options: nil)?
                .first as? NSImage

            Thread.sleep(forTimeInterval: 0.08)

            DispatchQueue.main.async {
                guard let screen = NSScreen.main else { self.capturing = false; return }

                // 3. Overlay blur immediatamente
                self.dimOverlay.show(on: screen)

                // Rettangolo destinazione thumbnail nel panel (per traiettoria card)
                let pw = self.promptPanel.pw
                let ph = self.promptPanel.ph
                let thumbRect = NSRect(
                    x: screen.frame.midX - pw / 2 + 12,
                    y: screen.frame.midY + 50 + (ph - 46) / 2,
                    width: 62, height: 46)

                let showPanel = {
                    self.promptPanel.present(
                        screenshot: screenshot,
                        dimOverlay: self.dimOverlay) { [weak self] result in
                        guard let self else { return }
                        self.dimOverlay.hide {
                            NSApp.setActivationPolicy(.accessory)
                            // NON chiamare NSApp.hide(nil) — nasconderebbe l'aereo in volo!
                            self.capturing = false
                            guard let userText = result else { return }
                            DispatchQueue.global(qos: .userInitiated).async {
                                self.pasteToClaudeDesktop(promptText: userText)
                            }
                        }
                    }
                }

                // 4. Screenshot card vola verso il thumbnail, poi mostra il panel
                if let img = screenshot {
                    self.screenshotCard.animate(
                        image: img, screen: screen, toThumb: thumbRect) {
                        showPanel()
                    }
                } else {
                    showPanel()
                }
            }
        }
    }

    @objc private func menuCapture() { startCapture() }

    @objc private func testAirplane() {
        guard let screen = NSScreen.main else { return }
        let center = NSPoint(x: screen.frame.midX, y: screen.frame.midY + 50)
        let ap = AirplanePanel()
        ap.launch(from: center, screen: screen)
    }

    // MARK: – Incolla in Claude Desktop

    private func pasteToClaudeDesktop(promptText: String) {
        let bundleID = "com.anthropic.claudefordesktop"
        let alreadyRunning = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }

        DispatchQueue.main.async {
            if let app = alreadyRunning {
                app.activate(options: [])
            } else if let url = NSWorkspace.shared.urlForApplication(
                                    withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
            }
        }

        let waitMax: TimeInterval = alreadyRunning != nil ? 1.2 : 3.5
        var waited = 0.0
        while waited < waitMax {
            Thread.sleep(forTimeInterval: 0.15); waited += 0.15
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { break }
        }
        Thread.sleep(forTimeInterval: 0.40)

        guard let pid = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.processIdentifier
        else { return }

        if AXIsProcessTrusted() {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand; vUp?.flags = .maskCommand
            vDown?.postToPid(pid); Thread.sleep(forTimeInterval: 0.08); vUp?.postToPid(pid)
            if !promptText.isEmpty {
                Thread.sleep(forTimeInterval: 0.20)
                typeText(promptText, toPid: pid)
            }
        } else {
            runOsascript(
                "tell application \"System Events\" to keystroke \"v\" using {command down}")
            if !promptText.isEmpty {
                Thread.sleep(forTimeInterval: 0.25)
                let escaped = promptText
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                runOsascript(
                    "tell application \"System Events\" to keystroke \"\(escaped)\"")
            }
        }
    }

    private func runOsascript(_ source: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        try? proc.run(); proc.waitUntilExit()
    }

    private func typeText(_ text: String, toPid pid: pid_t) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            var ch = UniChar(scalar.value & 0xFFFF)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            down?.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.010)
            up?.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.010)
        }
    }
}

// ─── Entry point ───────────────────────────────────────────────────────────
let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
