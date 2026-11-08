//
//  MetalSliderWidget.swift
//  agent-touchbar
//
//  A 60 FPS GPU-accelerated continuous touch slider for Apple Touch Bar.
//  Uses hardware NSTouchTypeDirect for sub-pixel accuracy and zero-latency
//  volume, brightness, or parameter adjustments with glowing neon finger trails.
//

import AgentTouchbarCore
import AppKit
import Metal
import QuartzCore

// MARK: - Metal Shader Pipeline for Slider

private let sliderShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SliderUniforms {
        float time;
        float value;        // 0.0 to 1.0
        float isTouching;   // 1.0 if touching, 0.0 otherwise
        float touchX;       // touch normalized x
        float2 resolution;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut sliderVertexShader(uint vertexID [[vertex_id]]) {
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

    fragment float4 sliderFragmentShader(VertexOut in [[stage_in]],
                                         constant SliderUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;

        // Track bounds (vertical padding)
        float trackHeight = 0.50; // half height of Touch Bar
        float trackY = abs(uv.y - 0.5);
        bool inTrack = trackY < (trackHeight * 0.5);

        // Background track color (dark translucent slate)
        float3 trackBg = float3(0.08, 0.08, 0.12);

        // Active fill gradient: Vibrant cyan to magenta
        float3 fillGradient = mix(float3(0.12, 0.55, 0.95), float3(0.72, 0.18, 0.98), uv.x);

        // Thumb indicator position
        float distToThumb = abs(uv.x - u.value);
        float thumbGlow = 0.012 / (distToThumb + 0.015);
        float3 thumbColor = float3(1.0, 1.0, 1.0) * thumbGlow;

        float3 col = float3(0.01, 0.01, 0.02);
        if (inTrack) {
            if (uv.x <= u.value) {
                col = fillGradient;
            } else {
                col = trackBg;
            }
            float rim = smoothstep(0.20, 0.25, trackY);
            col += float3(0.1, 0.1, 0.15) * rim;
        }

        col += thumbColor * (inTrack ? 1.0 : 0.6);

        // Touch feedback halo directly under finger
        if (u.isTouching > 0.5) {
            float2 touchPos = float2(u.touchX, 0.5);
            float2 diff = (uv - touchPos);
            diff.x *= (u.resolution.x / u.resolution.y);
            float d = length(diff);
            float touchHalo = 0.035 / (d * d + 0.008);
            col += float3(0.2, 0.95, 0.7) * touchHalo * 0.45;
        }

        // Corner smoothing on ends
        float edgeFade = smoothstep(0.0, 0.03, uv.x) * smoothstep(1.0, 0.97, uv.x);
        return float4(col * edgeFade, 1.0);
    }
    """

// MARK: - Specialized Slider Canvas View

@MainActor
final class MetalSliderCanvasView: MetalCanvasView {
    private var pipelineState: MTLRenderPipelineState?
    var value: Float = 0.5 {  // 0.0 to 1.0
        didSet { value = max(0.0, min(1.0, value)) }
    }
    private var isTouching = false
    private var touchX: Float = 0.5

    var onValueChanged: ((Float) -> Void)?

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
            let lib = try device.makeLibrary(source: sliderShaderSource, options: nil)
            let vFn = lib.makeFunction(name: "sliderVertexShader")
            let fFn = lib.makeFunction(name: "sliderFragmentShader")

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vFn
            desc.fragmentFunction = fFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[MetalSliderWidget] Shader compile error: \(error)")
        }
    }

    private struct SliderUniforms {
        var time: Float
        var value: Float
        var isTouching: Float
        var touchX: Float
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

        var uniforms = SliderUniforms(
            time: time,
            value: value,
            isTouching: isTouching ? 1.0 : 0.0,
            touchX: touchX,
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
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<SliderUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Direct Continuous Touch Tracking

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        updateValueFromTouch(event)
    }

    override func touchesMoved(with event: NSEvent) {
        super.touchesMoved(with: event)
        updateValueFromTouch(event)
    }

    override func touchesEnded(with event: NSEvent) {
        super.touchesEnded(with: event)
        isTouching = false
    }

    override func touchesCancelled(with event: NSEvent) {
        super.touchesCancelled(with: event)
        isTouching = false
    }

    private func updateValueFromTouch(_ event: NSEvent) {
        guard let touch = event.touches(matching: .touching, in: self).first else { return }
        let loc = touch.location(in: self)
        let normalized = Float(loc.x / max(self.bounds.width, 1.0))
        value = max(0.0, min(1.0, normalized))
        touchX = value
        isTouching = true
        onValueChanged?(value)
    }
}

// MARK: - MetalSliderWidget

final class MetalSliderWidget: Widget {
    private var canvas: MetalSliderCanvasView!
    private var iconBtn: ActionButton!
    private var mode: String = "volume"  // "volume" or "brightness"
    private var lastUserInteraction = Date.distantPast

    override var refreshInterval: TimeInterval? { 3 }

    required init(config: WidgetConfig, env: Env) {
        super.init(config: config, env: env)
        mode = options.string("mode", default: "volume") ?? "volume"
        let width = CGFloat(options.int("width", default: 110))

        canvas = MetalSliderCanvasView(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.widthAnchor.constraint(equalToConstant: width).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: 30).isActive = true

        iconBtn = ActionButton(title: "", icon: Icon.image("sf:speaker.wave.2.fill")) { [weak self] in
            self?.handleIconTap()
        }
        iconBtn.isBordered = false

        canvas.onValueChanged = { [weak self] val in
            self?.handleSliderMoved(val)
        }
    }

    override func refresh() {
        if stack.views.isEmpty {
            setContent([iconBtn, canvas])
        }

        // Avoid overwriting slider position right while user is sliding
        guard Date().timeIntervalSince(lastUserInteraction) > 2.0 else { return }

        if mode == "volume" {
            Audio.volume { [weak self] vol, muted in
                guard let self = self else { return }
                if let vol = vol {
                    self.canvas.value = Float(vol) / 100.0
                }
                let iconName =
                    muted || vol == 0
                    ? "sf:speaker.slash.fill" : (vol ?? 50) < 50 ? "sf:speaker.wave.1.fill" : "sf:speaker.wave.2.fill"
                self.iconBtn.image = Icon.image(iconName)
            }
        }
    }

    private func handleSliderMoved(_ val: Float) {
        lastUserInteraction = Date()
        if mode == "volume" {
            let intVol = Int(val * 100)
            Audio.setVolume(intVol)
            let iconName =
                intVol == 0
                ? "sf:speaker.slash.fill" : intVol < 50 ? "sf:speaker.wave.1.fill" : "sf:speaker.wave.2.fill"
            iconBtn.image = Icon.image(iconName)
        }
    }

    private func handleIconTap() {
        if mode == "volume" {
            Audio.toggleMute()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.refresh()
            }
        }
    }
}
