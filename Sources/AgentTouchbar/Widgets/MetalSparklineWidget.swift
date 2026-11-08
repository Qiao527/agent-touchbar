//
//  MetalSparklineWidget.swift
//  agent-touchbar
//
//  A 60 FPS GPU-accelerated real-time sparkline graph for Apple Touch Bar.
//  Subclasses MetalCanvasView to render live scrolling CPU & Memory wave curves
//  with smooth neon gradient fills and zero CPU overhead.
//

import AgentTouchbarCore
import AppKit
import Metal
import QuartzCore

// MARK: - Metal Shader Pipeline for Sparkline

private let sparklineShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SparklineUniforms {
        float time;
        float currentVal;
        uint sampleCount;
        float samples[32];
        float scrollOffset;
        float2 resolution;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut sparklineVertexShader(uint vertexID [[vertex_id]]) {
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

    fragment float4 sparklineFragmentShader(VertexOut in [[stage_in]],
                                            constant SparklineUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;

        // Smooth horizontal mapping with sub-sample scroll
        float xPos = uv.x * float(u.sampleCount - 1) + u.scrollOffset;
        int idx0 = clamp(int(floor(xPos)), 0, int(u.sampleCount - 1));
        int idx1 = clamp(idx0 + 1, 0, int(u.sampleCount - 1));
        float t = xPos - float(idx0);

        // Cosine smoothing interpolation between adjacent history points
        float val0 = u.samples[idx0];
        float val1 = u.samples[idx1];
        float lineY = mix(val0, val1, (1.0 - cos(t * 3.14159265)) * 0.5);

        // Padding (10% bottom to 90% top)
        lineY = clamp(lineY * 0.78 + 0.11, 0.05, 0.95);

        // Curve line crest with glow
        float dist = abs(uv.y - lineY);
        float lineGlow = 0.016 / (dist + 0.014);

        // Metric load-adaptive neon colors:
        // Low: Neon Cyan (0.08, 0.75, 0.95)
        // Mid: Cyber Violet (0.68, 0.22, 0.95)
        // High: Fiery Amber (0.98, 0.32, 0.12)
        float load = u.currentVal;
        float3 colLow = float3(0.08, 0.75, 0.95);
        float3 colMid = float3(0.68, 0.22, 0.95);
        float3 colHigh = float3(0.98, 0.32, 0.12);

        float3 lineColor = mix(colLow, colMid, smoothstep(0.25, 0.60, load));
        lineColor = mix(lineColor, colHigh, smoothstep(0.60, 0.85, load));

        // Under-curve gradient fill
        float area = step(uv.y, lineY) * pow(uv.y / max(lineY, 0.001), 1.6) * 0.40;
        float3 areaColor = lineColor * area;

        // Subtle edge fade on left and right for seamless Touch Bar blending
        float edgeFade = smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x);
        float3 finalColor = (areaColor + lineColor * lineGlow) * edgeFade;

        // Subtle dark OLED background
        finalColor += float3(0.012, 0.012, 0.020);

        return float4(finalColor, 1.0);
    }
    """

// MARK: - Specialized Sparkline Canvas View

@MainActor
final class MetalSparklineCanvasView: MetalCanvasView {
    private var pipelineState: MTLRenderPipelineState?
    private var history = [Float](repeating: 0.1, count: 32)
    private var currentValue: Float = 0.0
    private var scrollOffset: Float = 0.0

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
            let lib = try device.makeLibrary(source: sparklineShaderSource, options: nil)
            let vFn = lib.makeFunction(name: "sparklineVertexShader")
            let fFn = lib.makeFunction(name: "sparklineFragmentShader")

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vFn
            desc.fragmentFunction = fFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[MetalSparklineWidget] Shader compile error: \(error)")
        }
    }

    /// Appends a new data sample (0.0 to 1.0).
    func pushSample(_ val: Float) {
        let clamped = max(0.0, min(1.0, val))
        currentValue = clamped
        history.removeFirst()
        history.append(clamped)
        scrollOffset = 0.0
    }

    private struct SparklineUniforms {
        var time: Float
        var currentVal: Float
        var sampleCount: UInt32
        var samples:
            (
                Float, Float, Float, Float, Float, Float, Float, Float,
                Float, Float, Float, Float, Float, Float, Float, Float,
                Float, Float, Float, Float, Float, Float, Float, Float,
                Float, Float, Float, Float, Float, Float, Float, Float
            )
        var scrollOffset: Float
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

        // Smooth sub-sample scroll advance
        scrollOffset = min(scrollOffset + 0.015, 1.0)

        let s = (
            history[0], history[1], history[2], history[3], history[4], history[5], history[6], history[7],
            history[8], history[9], history[10], history[11], history[12], history[13], history[14], history[15],
            history[16], history[17], history[18], history[19], history[20], history[21], history[22], history[23],
            history[24], history[25], history[26], history[27], history[28], history[29], history[30], history[31]
        )

        var uniforms = SparklineUniforms(
            time: time,
            currentVal: currentValue,
            sampleCount: 32,
            samples: s,
            scrollOffset: scrollOffset,
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
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<SparklineUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    override func touchesEnded(with event: NSEvent) {
        super.touchesEnded(with: event)
        onTapped?()
    }
}

// MARK: - MetalSparklineWidget

final class MetalSparklineWidget: Widget {
    private var canvas: MetalSparklineCanvasView!
    private var label: NSTextField!
    private var metric: String = "cpu"  // "cpu" or "memory"

    override var refreshInterval: TimeInterval? { 1 }

    required init(config: WidgetConfig, env: Env) {
        super.init(config: config, env: env)
        metric = options.string("metric", default: "cpu") ?? "cpu"
        let width = CGFloat(options.int("width", default: 95))

        canvas = MetalSparklineCanvasView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.widthAnchor.constraint(equalToConstant: width).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: 30).isActive = true

        label = UI.label("", size: 11, weight: .bold)

        canvas.onTapped = { [weak self] in
            self?.showDetailsOverlay()
        }
    }

    override func refresh() {
        let value: Double
        let title: String

        if metric == "memory" || metric == "ram" {
            value = env.stats.memory
            title = String(format: "RAM %d%%", Int(value * 100))
        } else {
            value = env.stats.cpu
            title = String(format: "CPU %d%%", Int(value * 100))
        }

        canvas.pushSample(Float(value))
        label.stringValue = title

        // Color coding the label to match curve intensity
        if value > 0.80 {
            label.textColor = .systemRed
        } else if value > 0.50 {
            label.textColor = .systemPurple
        } else {
            label.textColor = .systemTeal
        }

        if stack.views.isEmpty {
            let row = UI.row([label, canvas], spacing: 4)
            setContent([row])
        }
    }

    private func showDetailsOverlay() {
        let cpuPct = Int(env.stats.cpu * 100)
        let memPct = Int(env.stats.memory * 100)

        let labelInfo = UI.label("⚡️ CPU: \(cpuPct)%   |   🧠 RAM: \(memPct)%")
        let btnActivity = ActionButton(title: "Activity Monitor", icon: Icon.image("sf:chart.bar.xaxis")) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }

        env.showOverlay("System Performance", [labelInfo, btnActivity])
    }
}
