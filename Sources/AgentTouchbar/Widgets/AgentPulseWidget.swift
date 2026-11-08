//
//  AgentPulseWidget.swift
//  agent-touchbar
//
//  A 60 FPS GPU-accelerated Metal pulse waveform representing live AI Agent cognition.
//  Subclasses MetalCanvasView with direct multi-touch support and zero CPU overhead.
//

import AgentTouchbarCore
import AppKit
import Metal
import QuartzCore

// MARK: - Metal Shader Pipeline for Agent Pulse

private let pulseShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct PulseUniforms {
        float time;
        float activity;       // 0.0 (calm idle) to 1.0 (busy reasoning)
        uint touchCount;
        float2 touches[10];
        float2 resolution;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut pulseVertexShader(uint vertexID [[vertex_id]]) {
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

    fragment float4 pulseFragmentShader(VertexOut in [[stage_in]],
                                        constant PulseUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;

        // Harmonic multi-frequency waves
        float speed = 1.8 + u.activity * 2.5;
        float w1 = sin(uv.x * (8.0 + u.activity * 6.0) + u.time * speed) * (0.15 + u.activity * 0.12);
        float w2 = cos(uv.x * 16.0 - u.time * (speed * 0.7)) * (0.08 + u.activity * 0.08);
        float center = 0.5 + w1 + w2;
        float dist = abs(uv.y - center);

        // Dynamic color gradient based on Agent activity
        float glow = (0.012 + u.activity * 0.010) / (dist + 0.022);
        float3 idleColor = float3(0.08, 0.45, 0.85);   // Cool cyan / deep blue
        float3 busyColor = float3(0.75, 0.15, 0.95);   // High-energy neon purple / magenta
        float3 baseColor = mix(idleColor, busyColor, u.activity) * glow;

        // Subtle edge fade for seamless blending into Touch Bar
        float edgeFade = smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x);
        float3 finalColor = baseColor * edgeFade;

        // Direct multi-touch ripple interactions
        for (uint i = 0; i < u.touchCount && i < 10; i++) {
            float2 touch = u.touches[i];
            float2 diff = uv - touch;
            diff.x *= (u.resolution.x / u.resolution.y);
            float d = length(diff);
            float ripple = 0.04 / (d * d + 0.008);
            finalColor += float3(0.2, 0.95, 0.7) * ripple * 0.5;
        }

        return float4(finalColor, 1.0);
    }
    """

// MARK: - Specialized Canvas View

@MainActor
final class AgentPulseCanvasView: MetalCanvasView {
    private var pipelineState: MTLRenderPipelineState?
    var activityLevel: Float = 0.0  // 0.0 (idle) to 1.0 (active reasoning)
    var onTapped: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildPipeline()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildPipeline()
    }

    private func buildPipeline() {
        guard let device = self.device else { return }
        do {
            let lib = try device.makeLibrary(source: pulseShaderSource, options: nil)
            let vFn = lib.makeFunction(name: "pulseVertexShader")
            let fFn = lib.makeFunction(name: "pulseFragmentShader")

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vFn
            desc.fragmentFunction = fFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[AgentPulseWidget] Pipeline compile error: \(error)")
        }
    }

    private struct PulseUniforms {
        var time: Float
        var activity: Float
        var touchCount: UInt32
        var touches:
            (
                SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>
            )
        var resolution: SIMD2<Float>
    }

    override func render(
        drawable: CAMetalDrawable,
        commandQueue: MTLCommandQueue,
        time: Float,
        bounds: CGSize,
        touches: [Int: CGPoint]
    ) {
        guard let pipeline = pipelineState else {
            super.render(drawable: drawable, commandQueue: commandQueue, time: time, bounds: bounds, touches: touches)
            return
        }

        var touchArray = [SIMD2<Float>](repeating: SIMD2<Float>(0, 0), count: 10)
        let count = min(touches.count, 10)
        var i = 0
        for (_, pt) in touches {
            if i >= 10 { break }
            let nx = Float(pt.x / max(bounds.width, 1.0))
            let ny = Float(pt.y / max(bounds.height, 1.0))
            touchArray[i] = SIMD2<Float>(nx, ny)
            i += 1
        }

        var uniforms = PulseUniforms(
            time: time,
            activity: activityLevel,
            touchCount: UInt32(count),
            touches: (
                touchArray[0], touchArray[1], touchArray[2], touchArray[3], touchArray[4],
                touchArray[5], touchArray[6], touchArray[7], touchArray[8], touchArray[9]
            ),
            resolution: SIMD2<Float>(Float(bounds.width), Float(bounds.height))
        )

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let cmd = commandQueue.makeCommandBuffer(),
            let enc = cmd.makeRenderCommandEncoder(descriptor: passDesc)
        else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<PulseUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    override func touchesEnded(with event: NSEvent) {
        super.touchesEnded(with: event)
        // Single tap opens agent detail overlay
        onTapped?()
    }
}

// MARK: - AgentPulseWidget

final class AgentPulseWidget: Widget {
    private var canvas: AgentPulseCanvasView!
    private var statusLabel: NSTextField?

    override var refreshInterval: TimeInterval? { 1 }

    required init(config: WidgetConfig, env: Env) {
        super.init(config: config, env: env)
        let width = CGFloat(options.int("width", default: 120))
        canvas = AgentPulseCanvasView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.widthAnchor.constraint(equalToConstant: width).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: 30).isActive = true

        canvas.onTapped = { [weak self] in
            self?.showAgentOverlay()
        }
    }

    override func refresh() {
        let activeSessions = env.agents.active.filter { $0.state != .ended }
        let hasActive = !activeSessions.isEmpty

        // Smooth activity level transition
        canvas.activityLevel = hasActive ? 1.0 : 0.0

        if stack.views.isEmpty {
            let views: [NSView] = [canvas]
            setContent(views)
        }
    }

    private func showAgentOverlay() {
        let sessions = env.agents.active.filter { $0.state != .ended }
        guard !sessions.isEmpty else {
            env.showOverlay(L("AI Agents"), [UI.label(L("No agents currently running"), color: .secondaryLabelColor)])
            return
        }

        let buttons = sessions.map { session in
            let status = session.state == .running ? "⚡️" : "⏳"
            let proj = session.project ?? session.id
            return ActionButton(
                title: "\(status) \(session.displayName) (\(proj))"
            ) { [weak self] in
                self?.env.hideOverlay()
            }
        }
        env.showOverlay(L("Active Agents ({0})", sessions.count), buttons)
    }
}
