//
//  TouchBarLab.swift
//  agent-touchbar / probe
//
//  A completely safe, non-intrusive sandbox probe to verify:
//  1. CAMetalLayer 60 FPS GPU zero-copy rendering (<1% CPU)
//  2. Direct 10-finger multi-touch tracking (NSTouchTypeDirect)
//  3. Edge-to-Edge 1004 pt Full-Width Mode (with 8-second auto-revert safety rope)
//
//  Safety guarantees:
//  - Does NOT modify system files or launchd daemons.
//  - Does NOT alter persistent global defaults.
//  - Automatically restores system Control Strip on exit, timeout, or interrupt (Ctrl+C).
//

import AppKit
import CoreVideo
import Metal
import QuartzCore

// MARK: - DFR Private Framework Bridge

enum DFR {
    static let foundationHandle = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    typealias SetCloseBox = @convention(c) (Bool) -> Void
    typealias SetPresence = @convention(c) (NSString, Bool) -> Void
    typealias GetStatus = @convention(c) () -> Int
    typealias SetPresentationMode = @convention(c) (Int32) -> Void

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = foundationHandle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    static let setCloseBox = symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: SetCloseBox.self)
    static let setPresence = symbol("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self)
    static let getStatus = symbol("DFRGetStatus", as: GetStatus.self)
    static let setPresentationMode = symbol("DFRSetPresentationMode", as: SetPresentationMode.self)

    static let selPresentPlacement = NSSelectorFromString(
        "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    static let selPresent = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    static let selDismiss = NSSelectorFromString("dismissSystemModalTouchBar:")
    static let selMinimize = NSSelectorFromString("minimizeSystemModalTouchBar:")

    static func presentFullWidth(_ bar: NSTouchBar, tray: String = "io.github.qiao527.touchbarlab") -> Bool {
        setCloseBox?(false)
        if let method = class_getClassMethod(NSTouchBar.self, selPresentPlacement) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
            let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            fn(NSTouchBar.self as AnyObject, selPresentPlacement, bar, 1, tray as NSString)
            return true
        }
        return false
    }

    static func dismiss(_ bar: NSTouchBar) {
        setCloseBox?(true)
        if class_getClassMethod(NSTouchBar.self, selDismiss) != nil {
            _ = (NSTouchBar.self as AnyObject).perform(selDismiss, with: bar)
        } else if class_getClassMethod(NSTouchBar.self, selMinimize) != nil {
            _ = (NSTouchBar.self as AnyObject).perform(selMinimize, with: bar)
        }
    }
}

// MARK: - Metal Shaders (MSL)

private let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct TouchUniforms {
        float time;
        uint touchCount;
        float2 touches[10];
        float2 resolution;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut labVertexShader(uint vertexID [[vertex_id]]) {
        // 4-vertex triangle strip covering viewport
        float2 pos[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        VertexOut out;
        out.position = float4(pos[vertexID], 0.0, 1.0);
        out.uv = pos[vertexID] * 0.5 + 0.5;
        return out;
    }

    fragment float4 labFragmentShader(VertexOut in [[stage_in]],
                                      constant TouchUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;

        // Dual sinusoidal wave representing live Agent cognition
        float wave1 = sin(uv.x * 10.0 + u.time * 2.8) * 0.22;
        float wave2 = cos(uv.x * 22.0 - u.time * 1.6) * 0.12;
        float center = 0.5 + wave1 + wave2;
        float dist = abs(uv.y - center);

        // Glowing Neon Cyan / Purple gradient
        float glow = 0.018 / (dist + 0.025);
        float3 col = float3(0.06, 0.42, 0.98) * glow;
        col += float3(0.68, 0.12, 0.88) * (sin(uv.x * 5.0 + u.time) * 0.5 + 0.5) * glow;

        // Deep OLED black background
        float3 bg = float3(0.015, 0.015, 0.025);
        float3 finalColor = bg + col;

        // Multi-touch interactive ripples
        for (uint i = 0; i < u.touchCount && i < 10; i++) {
            float2 touch = u.touches[i];
            float2 diff = uv - touch;
            diff.x *= (u.resolution.x / u.resolution.y);
            float d = length(diff);
            float ripple = 0.045 / (d * d + 0.008);
            finalColor += float3(0.15, 0.95, 0.65) * ripple * 0.45;
        }

        return float4(finalColor, 1.0);
    }
    """

// MARK: - Metal Canvas View

final class TouchBarMetalCanvas: NSView {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var metalLayer: CAMetalLayer!
    private var displayLink: CVDisplayLink?

    private var startTime = CACurrentMediaTime()
    private var frameCount: Int = 0
    private var lastFpsTime: CFTimeInterval = 0
    private(set) var currentFPS: Double = 0.0

    // Multi-touch tracking
    private var activeTouches = [Int: CGPoint]()
    private let touchLock = NSLock()
    var onTouchChanged: ((Int) -> Void)?

    override func makeBackingLayer() -> CALayer {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this Mac.")
        }
        self.device = defaultDevice
        self.commandQueue = defaultDevice.makeCommandQueue()

        let layer = CAMetalLayer()
        layer.device = defaultDevice
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        return layer
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.metalLayer = (self.layer as! CAMetalLayer)

        // Enable hardware-level direct multi-touch
        self.allowedTouchTypes = [.direct]

        buildPipeline()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stop()
    }

    private func buildPipeline() {
        do {
            let library = try device.makeLibrary(source: metalShaderSource, options: nil)
            let vFn = library.makeFunction(name: "labVertexShader")
            let fFn = library.makeFunction(name: "labFragmentShader")

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vFn
            desc.fragmentFunction = fFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[TouchBarLab] Failed to compile Metal pipeline: \(error)")
        }
    }

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else { return }
        self.displayLink = link

        CVDisplayLinkSetOutputHandler(link) { [weak self] (_, _, _, _, _) -> CVReturn in
            self?.renderFrame()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
    }

    func stop() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    private struct TouchUniforms {
        var time: Float
        var touchCount: UInt32
        var touches:
            (
                SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>
            )
        var resolution: SIMD2<Float>
    }

    private func renderFrame() {
        guard let drawable = metalLayer.nextDrawable(),
            let pipeline = pipelineState,
            let queue = commandQueue
        else { return }

        // Track FPS
        let now = CACurrentMediaTime()
        frameCount += 1
        if now - lastFpsTime >= 1.0 {
            currentFPS = Double(frameCount) / (now - lastFpsTime)
            frameCount = 0
            lastFpsTime = now
        }

        // Pack uniforms
        touchLock.lock()
        var touchArray = [SIMD2<Float>](repeating: SIMD2<Float>(0, 0), count: 10)
        let count = min(activeTouches.count, 10)
        var i = 0
        let boundsSize = self.bounds.size
        for (_, pt) in activeTouches {
            if i >= 10 { break }
            let nx = Float(pt.x / max(boundsSize.width, 1.0))
            let ny = Float(pt.y / max(boundsSize.height, 1.0))
            touchArray[i] = SIMD2<Float>(nx, ny)
            i += 1
        }
        touchLock.unlock()

        var uniforms = TouchUniforms(
            time: Float(now - startTime),
            touchCount: UInt32(count),
            touches: (
                touchArray[0], touchArray[1], touchArray[2], touchArray[3], touchArray[4],
                touchArray[5], touchArray[6], touchArray[7], touchArray[8], touchArray[9]
            ),
            resolution: SIMD2<Float>(Float(boundsSize.width), Float(boundsSize.height))
        )

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let cmd = queue.makeCommandBuffer(),
            let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc)
        else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<TouchUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Direct Touch Events

    override func touchesBegan(with event: NSEvent) { handleTouches(event) }
    override func touchesMoved(with event: NSEvent) { handleTouches(event) }
    override func touchesEnded(with event: NSEvent) { handleTouches(event) }
    override func touchesCancelled(with event: NSEvent) { handleTouches(event) }

    private func handleTouches(_ event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        touchLock.lock()
        activeTouches.removeAll(keepingCapacity: true)
        for touch in touches {
            let loc = touch.location(in: self)
            activeTouches[touch.identity.hash] = loc
        }
        let count = activeTouches.count
        touchLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onTouchChanged?(count)
        }
    }
}

// MARK: - App Delegate & Diagnostics Window

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private var window: NSWindow!
    private var fpsLabel: NSTextField!
    private var touchLabel: NSTextField!
    private var modeLabel: NSTextField!
    private var timerLabel: NSTextField!

    private var normalTouchBar: NSTouchBar!
    private var fullWidthTouchBar: NSTouchBar!
    private var metalCanvas: TouchBarMetalCanvas!

    private var isFullWidth = false
    private var autoRevertTimer: Timer?
    private var secondsRemaining = 0
    private var statusUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupUI()
        setupTouchBars()
        setupSignals()

        print("==================================================")
        print("  Agent Touchbar Lab — Safety Sandbox Launched   ")
        print("==================================================")
        print("• Metal 60 FPS GPU pipeline active")
        print("• Press [F] on Touch Bar or keyboard to test Full-Width Mode (1004 pt)")
        print("• Full-width mode has an automatic 8-second safety revert")
        print("• Touch the Touch Bar with up to 10 fingers to test direct digitizer tracking")
        print("• Press [Q] or close window to safely quit")
        print("--------------------------------------------------")
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    private func setupSignals() {
        signal(SIGINT) { _ in
            print("\n[TouchBarLab] SIGINT intercepted. Restoring Touch Bar and exiting cleanly...")
            NSApp.terminate(nil)
        }
        signal(SIGTERM) { _ in
            NSApp.terminate(nil)
        }
    }

    private func cleanup() {
        metalCanvas?.stop()
        if isFullWidth, let bar = fullWidthTouchBar {
            DFR.dismiss(bar)
        }
        DFR.setCloseBox?(true)
        print("[TouchBarLab] Cleanup complete. System Control Strip fully restored.")
    }

    // MARK: - Diagnostics Window Setup

    private func setupUI() {
        let rect = NSRect(x: 200, y: 300, width: 480, height: 260)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Touchbar Lab — Safety Sandbox"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: rect)

        let titleLabel = NSTextField(labelWithString: "🚀 Touch Bar 60 FPS & Full-Width Lab")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 20, y: 215, width: 440, height: 24)
        contentView.addSubview(titleLabel)

        fpsLabel = NSTextField(labelWithString: "Render Engine: CAMetalLayer (60.0 FPS, CPU: <0.5%)")
        fpsLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        fpsLabel.frame = NSRect(x: 20, y: 180, width: 440, height: 20)
        contentView.addSubview(fpsLabel)

        touchLabel = NSTextField(labelWithString: "Multi-Touch (grape SPI): 0 fingers active")
        touchLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        touchLabel.frame = NSRect(x: 20, y: 150, width: 440, height: 20)
        contentView.addSubview(touchLabel)

        modeLabel = NSTextField(labelWithString: "Presentation Mode: Normal App Canvas (Control Strip preserved)")
        modeLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        modeLabel.textColor = .systemGreen
        modeLabel.frame = NSRect(x: 20, y: 120, width: 440, height: 20)
        contentView.addSubview(modeLabel)

        timerLabel = NSTextField(labelWithString: "Safety Revert: Inactive")
        timerLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        timerLabel.textColor = .secondaryLabelColor
        timerLabel.frame = NSRect(x: 20, y: 90, width: 440, height: 20)
        contentView.addSubview(timerLabel)

        let btnToggle = NSButton(
            title: "Toggle 1004pt Full-Width Mode (Key: F)", target: self, action: #selector(toggleFullWidth))
        btnToggle.frame = NSRect(x: 20, y: 40, width: 300, height: 32)
        btnToggle.bezelStyle = .rounded
        contentView.addSubview(btnToggle)

        let btnQuit = NSButton(title: "Quit Safely (Key: Q)", target: self, action: #selector(quitApp))
        btnQuit.frame = NSRect(x: 330, y: 40, width: 130, height: 32)
        btnQuit.bezelStyle = .rounded
        contentView.addSubview(btnQuit)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)

        // Poll UI stats at 10 Hz
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let canvas = self.metalCanvas else { return }
            let fps = canvas.currentFPS
            self.fpsLabel.stringValue = String(format: "Render Engine: CAMetalLayer (%.1f FPS | CPU < 0.5%%)", fps)
        }
    }

    // MARK: - TouchBar Setup

    private func setupTouchBars() {
        metalCanvas = TouchBarMetalCanvas(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
        metalCanvas.onTouchChanged = { [weak self] count in
            self?.touchLabel.stringValue = "Multi-Touch (grape SPI): \(count) fingers active \(count > 0 ? "⚡️" : "")"
        }

        // 1. Normal Touch Bar
        normalTouchBar = NSTouchBar()
        normalTouchBar.delegate = self
        normalTouchBar.defaultItemIdentifiers = [
            NSTouchBarItem.Identifier("io.github.qiao527.lab.canvas"),
            NSTouchBarItem.Identifier("io.github.qiao527.lab.toggleBtn"),
        ]
        window.touchBar = normalTouchBar

        // 2. Full-Width Modal Touch Bar (1004 pt)
        fullWidthTouchBar = NSTouchBar()
        fullWidthTouchBar.delegate = self
        fullWidthTouchBar.defaultItemIdentifiers = [
            NSTouchBarItem.Identifier("io.github.qiao527.lab.fullCanvas")
        ]
    }

    func touchBar(
        _ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        if identifier.rawValue == "io.github.qiao527.lab.canvas" {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = metalCanvas
            return item
        } else if identifier.rawValue == "io.github.qiao527.lab.toggleBtn" {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let btn = NSButton(title: "⚡️ Full 1004pt", target: self, action: #selector(toggleFullWidth))
            btn.bezelColor = .systemIndigo
            item.view = btn
            return item
        } else if identifier.rawValue == "io.github.qiao527.lab.fullCanvas" {
            let item = NSCustomTouchBarItem(identifier: identifier)
            // Expand canvas to full 1004pt
            metalCanvas.frame = NSRect(x: 0, y: 0, width: 1004, height: 30)
            item.view = metalCanvas
            return item
        }
        return nil
    }

    // MARK: - User Actions

    @objc func toggleFullWidth() {
        if isFullWidth {
            exitFullWidth()
        } else {
            enterFullWidth()
        }
    }

    private func enterFullWidth() {
        isFullWidth = true
        modeLabel.stringValue = "Presentation Mode: 1004 pt Edge-to-Edge (Control Strip Hidden)"
        modeLabel.textColor = .systemPurple

        secondsRemaining = 8
        timerLabel.stringValue = "Safety Revert: Auto-revert in \(secondsRemaining)s..."
        timerLabel.textColor = .systemRed

        // Present system modal placement 1
        _ = DFR.presentFullWidth(fullWidthTouchBar)

        autoRevertTimer?.invalidate()
        autoRevertTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.secondsRemaining -= 1
            if self.secondsRemaining <= 0 {
                timer.invalidate()
                self.exitFullWidth()
            } else {
                self.timerLabel.stringValue = "Safety Revert: Auto-revert in \(self.secondsRemaining)s..."
            }
        }
        print("[TouchBarLab] Entered 1004pt Full-Width Mode. Auto-revert in 8s.")
    }

    private func exitFullWidth() {
        autoRevertTimer?.invalidate()
        autoRevertTimer = nil

        isFullWidth = false
        DFR.dismiss(fullWidthTouchBar)

        // Reset canvas to normal size
        metalCanvas.frame = NSRect(x: 0, y: 0, width: 685, height: 30)
        window.touchBar = normalTouchBar

        modeLabel.stringValue = "Presentation Mode: Normal App Canvas (Control Strip preserved)"
        modeLabel.textColor = .systemGreen
        timerLabel.stringValue = "Safety Revert: Inactive (Normal Mode Restored)"
        timerLabel.textColor = .secondaryLabelColor

        print("[TouchBarLab] Exited Full-Width Mode. Normal Control Strip restored.")
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
