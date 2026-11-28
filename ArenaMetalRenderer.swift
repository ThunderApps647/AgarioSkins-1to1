import Foundation
import Metal
import MetalKit
import SwiftUI
import UIKit
import CoreText
import simd

// MARK: - POD Shader Structs (Must Match ArenaShaders.metal Layout)

private struct GridUniforms {
    var viewportSize: SIMD2<Float>
    var cameraPos: SIMD2<Float>
    var zoom: Float
    var cellSize: Float
    var gridGray: Float
    var lineWidthPx: Float
    var bgColor: SIMD4<Float>
}

private struct BoundaryUniforms {
    var viewportSize: SIMD2<Float>
    var cameraPos: SIMD2<Float>
    var arenaMin: SIMD2<Float>
    var arenaMax: SIMD2<Float>
    var zoom: Float
    var fadeWidth: Float
    var minAlpha: Float
    var borderLineWidth: Float
    var easePower: Float
    var blendMode: Int32
    var _pad: SIMD2<Float> = .zero
    var fillColor: SIMD4<Float>
    var lineColor: SIMD4<Float>
}

private struct SolidVertex {
    var pixelPos: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct TexVertex {
    var pixelPos: SIMD2<Float>
    var texCoord: SIMD2<Float>
    var tint: SIMD4<Float>
}

// MARK: - Snapshot Passed Into MTKView

final class ArenaRenderBox {
    var worldSize: CGFloat = OriginalGameplay.arenaSideLengthCGFloat
    var cameraPos: CGPoint = .zero
    var zoom: CGFloat = 1.0
    /// `[BaseArenaView zoom]`: fixed soft-body ring resolution factor.
    var softBodyZoom: Float = 0.7
    var darkMode: Bool = false
    var showGrid: Bool = true
    var showSkins: Bool = true
    var showMassText: Bool = true
    var showBoundaryOverlay: Bool = false
    var tokens: [Token] = []
    var foodManager: FoodManager?
    var massManager: EjectedMassManager?
    var viruses: [Virus] = []
    var playerCells: [PlayerCell] = []
    var botCells: [PlayerCell] = []
    var animatingEatenCells: [PlayerCell] = []
    var teammateOwnerID: UUID?
    var teammateOwnerIDs: Set<UUID> = []
    var localPlayerInParty: Bool = false
    var dualSkinSwapShowingSince: TimeInterval? = nil
    var dualSkinSwapShowingSinceByOwner: [UUID: TimeInterval] = [:]
    var ownerLevels: [UUID: Int] = [:]
    var consumeAnimations: [ConsumedPickupAnimation] = []
    var activeEmoteAsset: String? = nil
    var activeEmoteStartedAt: TimeInterval = 0
    var activeEmoteExpiresAt: TimeInterval = 0
}

// MARK: - Texture & Label Cache

private final class ArenaTextureCache {
    private let device: MTLDevice
    private var imageTextures: [String: MTLTexture] = [:]
    private var labelTextures: [LabelCacheKey: (texture: MTLTexture, size: CGSize, fontSize: CGFloat)] = [:]
    private var labelOrder: [LabelCacheKey] = []
    private var width30Cache: [String: Float] = [:]
    private lazy var font30: UIFont = {
        MyFont.requireCustomFont(named: "OpenSans-Bold", size: 30)
    }()
    private let maxLabelCache = 280

    func widthAt30pt(for text: String) -> Float {
        if let hit = width30Cache[text] { return hit }
        let w = Float((text as NSString).size(withAttributes: [.font: font30]).width)
        if width30Cache.count > 256 { width30Cache.removeAll(keepingCapacity: true) }
        width30Cache[text] = w
        return w
    }

    struct LabelCacheKey: Hashable {
        let text: String
        let bucketPx: Int
        let strokeKey: Int
        let strokeRGBA: UInt32
    }

    init(device: MTLDevice) {
        self.device = device
    }

    func texture(named name: String) -> MTLTexture? {
        if let hit = imageTextures[name] { return hit }
        let uiImage: UIImage? = {
            if let img = UIImage(named: name) { return img }
            if let entry = CCBIAtlasStore.shared.sprite(for: name) { return entry.image }
            return nil
        }()
        guard let img = uiImage, let tex = uploadImage(img) else { return nil }
        imageTextures[name] = tex
        return tex
    }

    func skinTexture(name: String, isAlternate: Bool = false) -> MTLTexture? {
        let resolvedName = SkinSelectorPreview.resolvedAssetName(for: name)
        let key = "skin:\(resolvedName):\(isAlternate ? 1 : 0)"
        if let hit = imageTextures[key] { return hit }
        guard let img = SkinSelectorPreview.bundledImage(resolvedName) else {
            return nil
        }
        let sourceImg: UIImage = {
            if let cg = img.cgImage,
               (DualSkinCatalog.shared.isDual(name) || DualSkinCatalog.shared.isDual(resolvedName) || cg.width >= Int(CGFloat(cg.height) * 1.5)) {
                let halfW = cg.width / 2
                let cropRect = isAlternate
                    ? CGRect(x: halfW, y: 0, width: cg.width - halfW, height: cg.height)
                    : CGRect(x: 0, y: 0, width: halfW, height: cg.height)
                if let subCG = cg.cropping(to: cropRect) {
                    return UIImage(cgImage: subCG, scale: img.scale, orientation: img.imageOrientation)
                }
            }
            return img
        }()
        if let tex = uploadCircularSkinImage(sourceImg) {
            imageTextures[key] = tex
            return tex
        }
        return nil
    }

    private func rgbaKey(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(255, Int((r * 255).rounded()))))
        let gi = UInt32(max(0, min(255, Int((g * 255).rounded()))))
        let bi = UInt32(max(0, min(255, Int((b * 255).rounded()))))
        let ai = UInt32(max(0, min(255, Int((a * 255).rounded()))))
        return (ri << 24) | (gi << 16) | (bi << 8) | ai
    }

    func labelTexture(text: String, pixelHeight: CGFloat, strokeWidthPct: CGFloat = -6.7, strokeColor: UIColor = .black) -> (texture: MTLTexture, size: CGSize, fontSize: CGFloat)? {
        guard !text.isEmpty else { return nil }
        let quantized = max(12, min(140, Int((pixelHeight / 6.0).rounded() * 6.0)))
        let key = LabelCacheKey(text: text, bucketPx: quantized, strokeKey: Int((strokeWidthPct * 10).rounded()), strokeRGBA: rgbaKey(strokeColor))
        if let hit = labelTextures[key] {
            return hit
        }

        let fontSize = CGFloat(quantized)
        let uiFont = MyFont.requireCustomFont(named: "OpenSans-Bold", size: fontSize)

        let strokeAttrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: UIColor.clear,
            .strokeColor: strokeColor,
            .strokeWidth: abs(strokeWidthPct) * 2.0
        ]
        let fillAttrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: UIColor.white
        ]
        let strokeStr = NSAttributedString(string: text, attributes: strokeAttrs)
        let fillStr = NSAttributedString(string: text, attributes: fillAttrs)
        let bounds = strokeStr.boundingRect(with: CGSize(width: 1024, height: 256),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            context: nil).integral
        let pad: CGFloat = ceil(fontSize * 0.22)
        let w = max(8, Int(bounds.width + pad * 2))
        let h = max(8, Int(bounds.height + pad * 2))
        let size = CGSize(width: w, height: h)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.setLineJoin(.round)
            ctx.cgContext.setLineCap(.round)
            let drawRect = CGRect(x: pad - bounds.minX,
                                  y: pad - bounds.minY,
                                  width: bounds.width + 4,
                                  height: bounds.height + 4)
            strokeStr.draw(in: drawRect)
            fillStr.draw(in: drawRect)
        }
        guard let tex = uploadImage(rendered) else { return nil }

        if labelOrder.count >= maxLabelCache {
            let old = labelOrder.removeFirst()
            labelTextures.removeValue(forKey: old)
        }
        labelOrder.append(key)
        let res = (tex, size, fontSize)
        labelTextures[key] = res
        return res
    }

    private func uploadCircularSkinImage(_ image: UIImage) -> MTLTexture? {
        guard let cg = image.cgImage else { return nil }
        let side = min(max(cg.width, cg.height), 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        // Preserve native perimeter texels unclipped so MTLSamplerAddressMode.clampToEdge
        // stretches edge pixels cleanly on deforming/shrinking SoftBodyCellView skins.
        let unclipped = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return uploadImage(unclipped)
    }

    private func uploadImage(_ image: UIImage) -> MTLTexture? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        guard w > 0 && h > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        let bytesPerRow = w * 4
        var raw = [UInt8](repeating: 0, count: bytesPerRow * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &raw,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: raw, bytesPerRow: bytesPerRow)
        return tex
    }
}

// MARK: - SwiftUI Wrapper & MTKView Coordinator

struct ArenaMetalView: UIViewRepresentable {
    let box: ArenaRenderBox

    func makeCoordinator() -> ArenaMetalCoordinator {
        ArenaMetalCoordinator(box: box)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.isOpaque = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.box = box
    }
}

final class ArenaMetalCoordinator: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let gridPipeline: MTLRenderPipelineState
    private let boundaryAlphaPipeline: MTLRenderPipelineState
    private let boundaryMultiplyPipeline: MTLRenderPipelineState
    private let solidPipeline: MTLRenderPipelineState
    private let texPipeline: MTLRenderPipelineState
    private let texCache: ArenaTextureCache
    var box: ArenaRenderBox

    private var solidBuf: [SolidVertex] = []
    private var trigCache: [Int: [(cos: Float, sin: Float)]] = [:]
    /// `-[BaseArenaView createCell:updateRate:]` (0x1003736c4): a new cell is
    /// invisible for two update ticks, snaps to 0.1 scale, then CCEaseBackOut
    /// scales it to 1.0 over 0.5 s.  Keyed by cell UUID so splits replay it.
    private var cellSpawnTimes: [UUID: CFTimeInterval] = [:]
    /// Current cell spawn scale applied by the deformed-fan helpers.
    private var fanScale: Float = 1.0

    // Triple-buffered per-frame vertex rings to prevent CPU/GPU races and per-frame allocation flicker
    private let maxFramesInFlight = 3
    private lazy var inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
    private var frameRingIndex: Int = 0
    private var solidRingBuffers: [MTLBuffer] = []
    private var solidRingCursors: [Int] = [0, 0, 0]
    private var texRingBuffers: [MTLBuffer] = []
    private var texRingCursors: [Int] = [0, 0, 0]

    private func ensureRingBuffer(buffers: inout [MTLBuffer], frameIdx: Int, used: Int, neededEnd: Int) -> MTLBuffer? {
        while buffers.count < maxFramesInFlight {
            guard let b = device.makeBuffer(length: 256 * 1024, options: .storageModeShared) else { return nil }
            buffers.append(b)
        }
        if neededEnd > buffers[frameIdx].length {
            let newCap = max(neededEnd, buffers[frameIdx].length * 2)
            guard let grown = device.makeBuffer(length: newCap, options: .storageModeShared) else { return nil }
            if used > 0 {
                memcpy(grown.contents(), buffers[frameIdx].contents(), used)
            }
            buffers[frameIdx] = grown
        }
        return buffers[frameIdx]
    }

    init(box: ArenaRenderBox) {
        self.box = box
        guard let dev = MTLCreateSystemDefaultDevice(),
              let cq = dev.makeCommandQueue(),
              let lib = dev.makeDefaultLibrary() else {
            fatalError("Metal device or default library unavailable")
        }
        self.device = dev
        self.commandQueue = cq
        self.texCache = ArenaTextureCache(device: dev)

        let fullV = lib.makeFunction(name: "fullscreen_vertex")
        let gridF = lib.makeFunction(name: "grid_fragment")
        let boundF = lib.makeFunction(name: "boundary_fragment")
        let solidV = lib.makeFunction(name: "cell_solid_vertex")
        let solidF = lib.makeFunction(name: "cell_solid_fragment")
        let texV = lib.makeFunction(name: "cell_tex_vertex")
        let texF = lib.makeFunction(name: "cell_tex_fragment")

        func makePSO(v: MTLFunction?, f: MTLFunction?, blend: (MTLBlendFactor, MTLBlendFactor)?, rgbBlend: (MTLBlendFactor, MTLBlendFactor)? = nil) -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = v
            desc.fragmentFunction = f
            let att = desc.colorAttachments[0]!
            att.pixelFormat = .bgra8Unorm
            if let blend = blend {
                att.isBlendingEnabled = true
                att.sourceRGBBlendFactor = rgbBlend?.0 ?? blend.0
                att.destinationRGBBlendFactor = rgbBlend?.1 ?? blend.1
                att.rgbBlendOperation = .add
                att.sourceAlphaBlendFactor = blend.0
                att.destinationAlphaBlendFactor = blend.1
                att.alphaBlendOperation = .add
            }
            return try! dev.makeRenderPipelineState(descriptor: desc)
        }

        self.gridPipeline = makePSO(v: fullV, f: gridF, blend: nil)
        self.boundaryAlphaPipeline = makePSO(v: fullV, f: boundF, blend: (.sourceAlpha, .oneMinusSourceAlpha))
        self.boundaryMultiplyPipeline = makePSO(v: fullV, f: boundF, blend: (.one, .zero), rgbBlend: (.destinationColor, .zero))
        self.solidPipeline = makePSO(v: solidV, f: solidF, blend: (.sourceAlpha, .oneMinusSourceAlpha))
        self.texPipeline = makePSO(v: texV, f: texF, blend: (.one, .oneMinusSourceAlpha))

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func trigRing(count: Int) -> [(cos: Float, sin: Float)] {
        let n = max(8, count)
        if let hit = trigCache[n] { return hit }
        var arr: [(Float, Float)] = []
        arr.reserveCapacity(n)
        let step = Float(2.0 * Double.pi) / Float(n)
        for i in 0..<n {
            let a = Float(i) * step
            arr.append((cosf(a), sinf(a)))
        }
        trigCache[n] = arr
        return arr
    }

    private func rgba(_ color: Color, alphaMultiplier: Float = 1.0) -> SIMD4<Float> {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a) * alphaMultiplier)
        }
        return SIMD4<Float>(0.5, 0.5, 0.5, alphaMultiplier)
    }

    private func appendDiskFan(cx: Float, cy: Float, radius: Float, count: Int, color: SIMD4<Float>) {
        let ring = trigRing(count: count)
        let center = SolidVertex(pixelPos: SIMD2<Float>(cx, cy), color: color)
        for i in 0..<ring.count {
            let next = (i + 1) % ring.count
            let p1 = SIMD2<Float>(cx + ring[i].cos * radius, cy + ring[i].sin * radius)
            let p2 = SIMD2<Float>(cx + ring[next].cos * radius, cy + ring[next].sin * radius)
            solidBuf.append(center)
            solidBuf.append(SolidVertex(pixelPos: p1, color: color))
            solidBuf.append(SolidVertex(pixelPos: p2, color: color))
        }
    }

    private func appendDeformedFan(cx: Float, cy: Float, verts: [CGPoint], zoomPx: Float, radiusOffsetWorld: Float, isVirus: Bool, virusSpikeDeltaWorld: Float, color: SIMD4<Float>) {
        let n = verts.count
        guard n >= 6 else { return }
        let center = SolidVertex(pixelPos: SIMD2<Float>(cx, cy), color: color)
        var pts = [SIMD2<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            let v = verts[i]
            let vx = Float(v.x)
            let vy = Float(v.y)
            let len = max(0.0001, hypotf(vx, vy))
            let spike = (isVirus && (i & 1) == 0) ? virusSpikeDeltaWorld : 0.0
            let totalOffset = (radiusOffsetWorld + spike) * zoomPx
            pts[i] = SIMD2<Float>(cx + vx * zoomPx * fanScale + (vx / len) * totalOffset * fanScale,
                                  cy + vy * zoomPx * fanScale + (vy / len) * totalOffset * fanScale)
        }
        for i in 0..<n {
            let next = (i + 1) % n
            solidBuf.append(center)
            solidBuf.append(SolidVertex(pixelPos: pts[i], color: color))
            solidBuf.append(SolidVertex(pixelPos: pts[next], color: color))
        }
    }

    private func appendScaledFan(cx: Float, cy: Float, verts: [CGPoint], zoomPx: Float, scale: Float, color: SIMD4<Float>) {
        let n = verts.count
        guard n >= 6 else { return }
        let center = SolidVertex(pixelPos: SIMD2<Float>(cx, cy), color: color)
        var pts = [SIMD2<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            pts[i] = SIMD2<Float>(cx + Float(verts[i].x) * scale * zoomPx * fanScale,
                                  cy + Float(verts[i].y) * scale * zoomPx * fanScale)
        }
        for i in 0..<n {
            let next = (i + 1) % n
            solidBuf.append(center)
            solidBuf.append(SolidVertex(pixelPos: pts[i], color: color))
            solidBuf.append(SolidVertex(pixelPos: pts[next], color: color))
        }
    }

    /// drawFillingWithVertices on a virus: the spiked vertices are scaled uniformly by
    /// (r - 10) / r after calculateVirusEdgeRadiusDelta has been applied.
    private func appendScaledVirusFan(cx: Float, cy: Float, verts: [CGPoint], zoomPx: Float, scale: Float, spikeDeltaWorld: Float, color: SIMD4<Float>) {
        let n = verts.count
        guard n >= 6 else { return }
        let center = SolidVertex(pixelPos: SIMD2<Float>(cx, cy), color: color)
        var pts = [SIMD2<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            let v = verts[i]
            let vx = Float(v.x)
            let vy = Float(v.y)
            let len = max(0.0001, hypotf(vx, vy))
            let spike = (i & 1) == 0 ? spikeDeltaWorld : 0.0
            let rr = (len + spike) * scale * zoomPx * fanScale
            pts[i] = SIMD2<Float>(cx + (vx / len) * rr, cy + (vy / len) * rr)
        }
        for i in 0..<n {
            let next = (i + 1) % n
            solidBuf.append(center)
            solidBuf.append(SolidVertex(pixelPos: pts[i], color: color))
            solidBuf.append(SolidVertex(pixelPos: pts[next], color: color))
        }
    }

    private func appendVirusFan(cx: Float, cy: Float, radiusWorld: Float, zoomPx: Float, pointCount: Int, radiusOffsetWorld: Float, spikeDeltaWorld: Float, color: SIMD4<Float>) {
        let count = max(12, pointCount & ~1)
        let ring = trigRing(count: count)
        let center = SolidVertex(pixelPos: SIMD2<Float>(cx, cy), color: color)
        var pts = [SIMD2<Float>](repeating: .zero, count: count)
        for i in 0..<count {
            let spike = (i & 1) == 0 ? spikeDeltaWorld : 0.0
            let rPx = max(1.0, (radiusWorld + radiusOffsetWorld + spike) * zoomPx * fanScale)
            pts[i] = SIMD2<Float>(cx + ring[i].cos * rPx, cy + ring[i].sin * rPx)
        }
        for i in 0..<count {
            let next = (i + 1) % count
            solidBuf.append(center)
            solidBuf.append(SolidVertex(pixelPos: pts[i], color: color))
            solidBuf.append(SolidVertex(pixelPos: pts[next], color: color))
        }
    }

    private func flushSolid(enc: MTLRenderCommandEncoder, viewportSize: SIMD2<Float>) {
        guard !solidBuf.isEmpty else { return }
        var vp = viewportSize
        enc.setRenderPipelineState(solidPipeline)
        let byteLen = solidBuf.count * MemoryLayout<SolidVertex>.stride
        enc.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        if byteLen <= 4096 {
            enc.setVertexBytes(solidBuf, length: byteLen, index: 0)
        } else {
            let alignedOffset = (solidRingCursors[frameRingIndex] + 15) & ~15
            let neededEnd = alignedOffset + byteLen
            if let buf = ensureRingBuffer(buffers: &solidRingBuffers, frameIdx: frameRingIndex, used: solidRingCursors[frameRingIndex], neededEnd: neededEnd) {
                solidBuf.withUnsafeBytes { raw in
                    if let base = raw.baseAddress {
                        memcpy(buf.contents().advanced(by: alignedOffset), base, byteLen)
                    }
                }
                solidRingCursors[frameRingIndex] = neededEnd
                enc.setVertexBuffer(buf, offset: alignedOffset, index: 0)
            } else {
                solidBuf.removeAll(keepingCapacity: true)
                return
            }
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: solidBuf.count)
        solidBuf.removeAll(keepingCapacity: true)
    }

    private func drawTexturedFan(enc: MTLRenderCommandEncoder, texture: MTLTexture, cx: Float, cy: Float, verts: [CGPoint], zoomPx: Float, radiusOffsetWorld: Float, fallbackRadiusPx: Float, baseRadiusWorld: Float, vertexScale: Float = 1.0, alpha: Float, viewportSize: SIMD2<Float>) {
        var tv: [TexVertex] = []
        let tint = SIMD4<Float>(alpha, alpha, alpha, alpha) // premultiplied alpha
        if verts.count >= 8 && baseRadiusWorld > 1 {
            let n = verts.count
            tv.reserveCapacity(n * 3)
            let center = TexVertex(pixelPos: SIMD2<Float>(cx, cy), texCoord: SIMD2<Float>(0.5, 0.5), tint: tint)
            var pxPts = [SIMD2<Float>](repeating: .zero, count: n)
            var uvs = [SIMD2<Float>](repeating: .zero, count: n)
            // Mirrors SoftBodyCellView::calcTexCoordsInto:vertexArray: (0x1003a5354):
            // texCoord = vertex / (2 * radius) + 0.5.  The old (5/r + 1) factor sampled
            // outside the skin and relied on clampToEdge, visibly stretching every skin.
            let uvScale = 1.0 / max(0.0001, baseRadiusWorld)
            for i in 0..<n {
                let v = verts[i]
                let vx = Float(v.x)
                let vy = Float(v.y)
                let len = max(0.0001, hypotf(vx, vy))
                let rr = (radiusOffsetWorld + len) * vertexScale
                pxPts[i] = SIMD2<Float>(cx + (vx / len) * rr * zoomPx,
                                        cy + (vy / len) * rr * zoomPx)
                uvs[i] = SIMD2<Float>(0.5 + 0.5 * (vx * uvScale), 0.5 + 0.5 * (vy * uvScale))
            }
            for i in 0..<n {
                let next = (i + 1) % n
                tv.append(center)
                tv.append(TexVertex(pixelPos: pxPts[i], texCoord: uvs[i], tint: tint))
                tv.append(TexVertex(pixelPos: pxPts[next], texCoord: uvs[next], tint: tint))
            }
        } else {
            let ring = trigRing(count: 32)
            tv.reserveCapacity(ring.count * 3)
            let center = TexVertex(pixelPos: SIMD2<Float>(cx, cy), texCoord: SIMD2<Float>(0.5, 0.5), tint: tint)
            for i in 0..<ring.count {
                let next = (i + 1) % ring.count
                let c1 = ring[i]; let c2 = ring[next]
                tv.append(center)
                tv.append(TexVertex(pixelPos: SIMD2<Float>(cx + c1.cos * fallbackRadiusPx * vertexScale, cy + c1.sin * fallbackRadiusPx * vertexScale),
                                    texCoord: SIMD2<Float>(0.5 + 0.5 * c1.cos, 0.5 + 0.5 * c1.sin), tint: tint))
                tv.append(TexVertex(pixelPos: SIMD2<Float>(cx + c2.cos * fallbackRadiusPx * vertexScale, cy + c2.sin * fallbackRadiusPx * vertexScale),
                                    texCoord: SIMD2<Float>(0.5 + 0.5 * c2.cos, 0.5 + 0.5 * c2.sin), tint: tint))
            }
        }
        drawTexVertices(enc: enc, verts: tv, texture: texture, viewportSize: viewportSize)
    }

    private func drawQuad(enc: MTLRenderCommandEncoder, texture: MTLTexture, centerX: Float, centerY: Float, width: Float, height: Float, alpha: Float, viewportSize: SIMD2<Float>) {
        let hw = width * 0.5
        let hh = height * 0.5
        let t = SIMD4<Float>(alpha, alpha, alpha, alpha)
        let verts: [TexVertex] = [
            TexVertex(pixelPos: SIMD2<Float>(centerX - hw, centerY - hh), texCoord: SIMD2<Float>(0, 0), tint: t),
            TexVertex(pixelPos: SIMD2<Float>(centerX + hw, centerY - hh), texCoord: SIMD2<Float>(1, 0), tint: t),
            TexVertex(pixelPos: SIMD2<Float>(centerX - hw, centerY + hh), texCoord: SIMD2<Float>(0, 1), tint: t),
            TexVertex(pixelPos: SIMD2<Float>(centerX + hw, centerY - hh), texCoord: SIMD2<Float>(1, 0), tint: t),
            TexVertex(pixelPos: SIMD2<Float>(centerX + hw, centerY + hh), texCoord: SIMD2<Float>(1, 1), tint: t),
            TexVertex(pixelPos: SIMD2<Float>(centerX - hw, centerY + hh), texCoord: SIMD2<Float>(0, 1), tint: t)
        ]
        drawTexVertices(enc: enc, verts: verts, texture: texture, viewportSize: viewportSize)
    }

    private func drawTexVertices(enc: MTLRenderCommandEncoder, verts: [TexVertex], texture: MTLTexture, viewportSize: SIMD2<Float>) {
        guard !verts.isEmpty else { return }
        var vp = viewportSize
        enc.setRenderPipelineState(texPipeline)
        let byteLen = verts.count * MemoryLayout<TexVertex>.stride
        enc.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        if byteLen <= 4096 {
            enc.setVertexBytes(verts, length: byteLen, index: 0)
        } else {
            let alignedOffset = (texRingCursors[frameRingIndex] + 15) & ~15
            let neededEnd = alignedOffset + byteLen
            if let buf = ensureRingBuffer(buffers: &texRingBuffers, frameIdx: frameRingIndex, used: texRingCursors[frameRingIndex], neededEnd: neededEnd) {
                verts.withUnsafeBytes { raw in
                    if let base = raw.baseAddress {
                        memcpy(buf.contents().advanced(by: alignedOffset), base, byteLen)
                    }
                }
                texRingCursors[frameRingIndex] = neededEnd
                enc.setVertexBuffer(buf, offset: alignedOffset, index: 0)
            } else {
                return
            }
        }
        enc.setFragmentTexture(texture, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    /// CCEaseBackOut with the Cocos2d-x default 1.70158 overshoot.
    @inline(__always)
    private func backOut(_ t: Float) -> Float {
        let s: Float = 1.70158
        let u = t - 1.0
        return 1.0 + (s + 1.0) * u * u * u + s * u * u
    }

    private func spawnScale(id: UUID, now: CFTimeInterval) -> Float {
        guard let start = cellSpawnTimes[id] else { return 1.0 }
        let age = now - start
        // CCDelayTime(2 * updateRate) at the 60 Hz arena tick.
        let delay = 2.0 / 60.0
        guard age >= delay else { return 0.0 }
        let t = Float(min(1.0, max(0.0, (age - delay) / 0.5)))
        return 0.1 + 0.9 * backOut(t)
    }

    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        guard let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }
        let sem = inFlightSemaphore
        cmdBuf.addCompletedHandler { _ in sem.signal() }
        frameRingIndex = (frameRingIndex + 1) % maxFramesInFlight
        solidRingCursors[frameRingIndex] = 0
        texRingCursors[frameRingIndex] = 0
        guard renderFrame(
            passDesc: passDesc,
            drawableSize: view.drawableSize,
            boundsSize: view.bounds.size,
            contentScale: view.contentScaleFactor,
            commandBuffer: cmdBuf
        ) else {
            cmdBuf.commit()
            return
        }
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    func renderOffscreenSnapshot(size: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        #if targetEnvironment(simulator)
        desc.storageMode = .shared
        #endif
        guard let tex = device.makeTexture(descriptor: desc),
              let cmdBuf = commandQueue.makeCommandBuffer() else {
            return nil
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)

        solidRingCursors[frameRingIndex] = 0
        texRingCursors[frameRingIndex] = 0
        guard renderFrame(
            passDesc: pass,
            drawableSize: CGSize(width: w, height: h),
            boundsSize: size,
            contentScale: scale,
            commandBuffer: cmdBuf
        ) else {
            return nil
        }
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        let bpr = w * 4
        var bytes = [UInt8](repeating: 0, count: bpr * h)
        tex.getBytes(&bytes, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        // Swap BGRA -> RGBA for CGImage creation
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let b = bytes[i]
            bytes[i] = bytes[i + 2]
            bytes[i + 2] = b
            bytes[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(
                  width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr,
                  space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    @discardableResult
    private func renderFrame(
        passDesc: MTLRenderPassDescriptor,
        drawableSize: CGSize,
        boundsSize: CGSize,
        contentScale: CGFloat,
        commandBuffer cmdBuf: MTLCommandBuffer
    ) -> Bool {
        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return false
        }

        let drawW = Float(drawableSize.width)
        let drawH = Float(drawableSize.height)
        guard drawW > 0 && drawH > 0 else {
            enc.endEncoding(); cmdBuf.commit(); return false
        }
        let scale = max(Float(1.0), Float(contentScale))
        let ptZoom = Float(max(0.01, box.zoom))
        let zoomPx = ptZoom * scale
        let camX = Float(box.cameraPos.x)
        let camY = Float(box.cameraPos.y)
        let vpPx = SIMD2<Float>(drawW, drawH)

        let screenOffX = -camX * zoomPx + drawW * 0.5
        let screenOffY = -camY * zoomPx + drawH * 0.5
        let worldVisible = CGRect(
            x: Double(-screenOffX / zoomPx) - 180.0,
            y: Double(-screenOffY / zoomPx) - 180.0,
            width: Double(drawW / zoomPx) + 360.0,
            height: Double(drawH / zoomPx) + 360.0
        )

        // 1. Background + Infinite 50u Grid (`OptimizedArenaBackground::draw` 0x10030e108)
        let uiScale = Float(OriginalGameplay.arenaScreenScale(for: boundsSize))
        let cocosZoom = ptZoom / uiScale
        let intensity = min(Float(0.85), max(Float(0.10), (50.0 * 50.0 * cocosZoom * cocosZoom) / 5000.0 + 0.10))
        let gridGray = box.darkMode ? intensity : (1.0 - intensity)
        let bgCol = box.darkMode ? SIMD4<Float>(0, 0, 0, 1) : SIMD4<Float>(1, 1, 1, 1)
        var gridU = GridUniforms(
            viewportSize: vpPx,
            cameraPos: SIMD2<Float>(camX, camY),
            zoom: zoomPx,
            cellSize: 50.0,
            gridGray: box.showGrid ? gridGray : (box.darkMode ? 0.0 : 1.0),
            lineWidthPx: box.darkMode ? max(2.0, scale * 1.1) : max(1.0, scale * 0.65),
            bgColor: bgCol
        )
        var vpCopy = vpPx
        enc.setRenderPipelineState(gridPipeline)
        enc.setVertexBytes(&vpCopy, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        enc.setFragmentBytes(&gridU, length: MemoryLayout<GridUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // 2. ArenaBoundaryShaderEffect (only enabled in modes where GameConfiguration defines it)
        if box.showBoundaryOverlay {
            var boundU = BoundaryUniforms(
                viewportSize: vpPx,
                cameraPos: SIMD2<Float>(camX, camY),
                arenaMin: SIMD2<Float>(0, 0),
                arenaMax: SIMD2<Float>(Float(box.worldSize), Float(box.worldSize)),
                zoom: zoomPx,
                fadeWidth: 2.0 * Float(boundsSize.width) / max(0.01, ptZoom),
                minAlpha: 0.35,
                borderLineWidth: 5.0,
                easePower: 0.75,
                blendMode: box.darkMode ? 0 : 1,
                fillColor: box.darkMode
                    ? SIMD4<Float>(180.0 / 255.0, 180.0 / 255.0, 180.0 / 255.0, 0.863)
                    : SIMD4<Float>(90.0 / 255.0, 90.0 / 255.0, 90.0 / 255.0, 1.0),
                lineColor: SIMD4<Float>(208.0 / 255.0, 40.0 / 255.0, 60.0 / 255.0, 1.0)
            )
            enc.setRenderPipelineState(box.darkMode ? boundaryAlphaPipeline : boundaryMultiplyPipeline)
            enc.setVertexBytes(&vpCopy, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            enc.setFragmentBytes(&boundU, length: MemoryLayout<BoundaryUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // 3. Food Pellets (10-gon vertex fan per FoodCellView, 1 batched draw, zero modulo-skip flicker)
        let foodPxR = max(0.75 * scale, Float(Food.radius) * zoomPx)
        let foodSegs = foodPxR < 4.0 ? 8 : 10
        let paletteSIMD: [SIMD4<Float>] = Food.palette.map { rgba($0) }
        box.foodManager?.forEachVisibleFood(in: worldVisible, limit: 5000, everyNth: 1) { f in
            let sx = Float(f.position.x) * zoomPx + screenOffX
            let sy = Float(f.position.y) * zoomPx + screenOffY
            let col = f.colorIndex < paletteSIMD.count ? paletteSIMD[f.colorIndex] : SIMD4<Float>(1, 0, 0, 1)
            appendDiskFan(cx: sx, cy: sy, radius: foodPxR, count: foodSegs, color: col)
        }

        // 4. Consumed Pickup Slide Animations + Sorted Drawables by (int)radius z-order (`BaseArenaView::createCell` 0x1003736c4)
        let shotR = Float(OriginalGameplay.shotMassBaseRadiusCGFloat)
        for anim in box.consumeAnimations {
            let sx = Float(anim.position.x) * zoomPx + screenOffX
            let sy = Float(anim.position.y) * zoomPx + screenOffY
            let a = Float(anim.alpha)
            let sc = Float(anim.scale)
            switch anim.kind {
            case .food(let idx):
                let r = Float(Food.radius) * sc * zoomPx
                if r >= 0.6 && idx >= 0 && idx < paletteSIMD.count {
                    var c = paletteSIMD[idx]; c.w *= a
                    appendDiskFan(cx: sx, cy: sy, radius: r, count: 8, color: c)
                }
            case .ejected(let sid):
                if let st = box.massManager?.renderStyle(for: sid) {
                    let ro = (shotR + 5.0) * sc * zoomPx
                    let ri = max(1.0, (shotR * (shotR - 5.0) / (shotR + 5.0)) * sc * zoomPx)
                    let segs = max(7, min(1000, Int(floor(max(1, shotR * box.softBodyZoom)))))
                    appendDiskFan(cx: sx, cy: sy, radius: ro, count: segs, color: rgba(st.borderColor, alphaMultiplier: a))
                    appendDiskFan(cx: sx, cy: sy, radius: ri, count: segs, color: rgba(st.color, alphaMultiplier: a))
                }
            case .token:
                break
            }
        }
        flushSolid(enc: enc, viewportSize: vpPx)

        // 5. All Arena Entities Sorted by zOrder = Int(stateRadius) (Tokens, EjectedMass, Cells, Viruses)
        enum RenderEntity {
            case token(Token)
            case ejected(EjectedMass, style: EjectedMassStyle)
            case cell(PlayerCell, isLocal: Bool)
            case virus(Virus)
            var zOrder: Int {
                switch self {
                case .token: return 20
                case .ejected: return Int(OriginalGameplay.shotMassBaseRadiusCGFloat)
                case .cell(let c, _): return Int(c.cachedSolidRadius)
                case .virus(let v): return Int(v.radius)
                }
            }
            var tieOrder: Int {
                switch self {
                case .token: return 0
                case .ejected(let m, _): return m.zIndex
                case .cell(let c, _): return Int(c.mass * 100)
                case .virus: return 10000
                }
            }
        }

        let nowTS = CACurrentMediaTime()
        // Register first-seen cells for the original create-cell pop animation.
        var liveCellIDs = Set<UUID>()
        for c in box.playerCells { liveCellIDs.insert(c.id) }
        for c in box.botCells { liveCellIDs.insert(c.id) }
        cellSpawnTimes = cellSpawnTimes.filter { liveCellIDs.contains($0.key) || nowTS - $0.value < 2.0 }
        for id in liveCellIDs where cellSpawnTimes[id] == nil { cellSpawnTimes[id] = nowTS }
        let tokTex = texCache.texture(named: "token-snowflake") ?? texCache.texture(named: "token")
        let tokSide = Float(52.0) * zoomPx
        let rOutShot = (shotR + 5.0) * zoomPx
        let rInShot = max(1.0, (shotR * (shotR - 5.0) / (shotR + 5.0)) * zoomPx)
        let segsShot = max(7, min(1000, Int(floor(max(1, shotR * box.softBodyZoom)))))

        var drawables: [RenderEntity] = []
        drawables.reserveCapacity(box.tokens.count + box.playerCells.count + box.botCells.count + box.animatingEatenCells.count + box.viruses.count + 64)
        let myOwner = box.playerCells.first?.ownerID

        if tokTex != nil {
            for tok in box.tokens where worldVisible.contains(tok.position) {
                drawables.append(.token(tok))
            }
        }
        if let mm = box.massManager {
            mm.forEachVisibleMass(in: worldVisible) { m in
                if let st = mm.renderStyle(for: m.styleID) {
                    drawables.append(.ejected(m, style: st))
                }
            }
        }
        for c in box.animatingEatenCells {
            let r = c.cachedVisualRadius
            if worldVisible.intersects(CGRect(x: c.position.x - r, y: c.position.y - r, width: r * 2, height: r * 2)) {
                drawables.append(.cell(c, isLocal: c.ownerID == myOwner))
            }
        }
        for c in box.botCells {
            let r = c.cachedVisualRadius
            if worldVisible.intersects(CGRect(x: c.position.x - r, y: c.position.y - r, width: r * 2, height: r * 2)) {
                drawables.append(.cell(c, isLocal: false))
            }
        }
        for c in box.playerCells {
            let r = c.cachedVisualRadius
            if worldVisible.intersects(CGRect(x: c.position.x - r, y: c.position.y - r, width: r * 2, height: r * 2)) {
                drawables.append(.cell(c, isLocal: true))
            }
        }
        for v in box.viruses {
            let r = v.radius + 12
            if worldVisible.intersects(CGRect(x: v.position.x - r, y: v.position.y - r, width: r * 2, height: r * 2)) {
                drawables.append(.virus(v))
            }
        }
        drawables.sort {
            if $0.zOrder != $1.zOrder { return $0.zOrder < $1.zOrder }
            return $0.tieOrder < $1.tieOrder
        }

        let borderColVirus = SIMD4<Float>(0.0, 0.9, 0.0, 1.0)
        let fillColVirus = SIMD4<Float>(0.0, 1.0, 0.0, 1.0)
        // Default Settings - Party Mode: outer 0xFFC300, inner 0xF9F92F.
        let partyRingCol = SIMD4<Float>(1.0, 0xC3 / 255.0, 0.0, 1.0)
        let partyInnerCol = SIMD4<Float>(0xF9 / 255.0, 0xF9 / 255.0, 0x2F / 255.0, 1.0)

        for item in drawables {
            fanScale = 1.0
            switch item {
            case .token(let tok):
                if let tokTex {
                    flushSolid(enc: enc, viewportSize: vpPx)
                    let sx = Float(tok.position.x) * zoomPx + screenOffX
                    let sy = Float(tok.position.y) * zoomPx + screenOffY
                    drawQuad(enc: enc, texture: tokTex, centerX: sx, centerY: sy, width: tokSide * 0.9, height: tokSide, alpha: 1.0, viewportSize: vpPx)
                }

            case .ejected(let m, let st):
                let sx = Float(m.renderPosition.x) * zoomPx + screenOffX
                let sy = Float(m.renderPosition.y) * zoomPx + screenOffY
                appendDiskFan(cx: sx, cy: sy, radius: rOutShot, count: segsShot, color: rgba(st.borderColor))
                appendDiskFan(cx: sx, cy: sy, radius: rInShot, count: segsShot, color: rgba(st.color))

            case .virus(let v):
                let sx = Float(v.position.x) * zoomPx + screenOffX
                let sy = Float(v.position.y) * zoomPx + screenOffY
                let rW = Float(v.radius)
                // SoftBodyCellView::calculateVirusEdgeRadiusDelta (0x1003a49fc).
                // drawOutlineWithVertices scales by (r*zoom + 10)/(r*zoom), so the
                // 10 and 5 offsets are screen points, not world units.
                let spikeDelta = rW * Float(OriginalGameplay.virusEdgeRadiusMultiplier) + 5.0
                let borderOff = 10.0 / max(0.01, ptZoom)
                let bodyOff = 5.0 / max(0.01, ptZoom)
                let innerScale = max(0.0, 1.0 - 10.0 / max(0.001, rW * ptZoom))
                if v.deformedVertices.count >= 8 {
                    // calculateVirusEdgeRadiusDelta stores r*0.02 + 5; drawOutlineWithVertices
                    // then draws (r+10)/r and (r+5)/r, and drawFillingWithVertices adds the
                    // opaque (r-10)/r core from the same spiked vertices.
                    appendDeformedFan(cx: sx, cy: sy, verts: v.deformedVertices, zoomPx: zoomPx,
                                      radiusOffsetWorld: borderOff, isVirus: true, virusSpikeDeltaWorld: spikeDelta, color: borderColVirus)
                    appendDeformedFan(cx: sx, cy: sy, verts: v.deformedVertices, zoomPx: zoomPx,
                                      radiusOffsetWorld: bodyOff, isVirus: true, virusSpikeDeltaWorld: spikeDelta, color: fillColVirus)
                    appendScaledVirusFan(cx: sx, cy: sy, verts: v.deformedVertices, zoomPx: zoomPx,
                                         scale: innerScale, spikeDeltaWorld: spikeDelta, color: fillColVirus)
                } else {
                    // calcCellVertexCount: floor(radius * zoom), rounded even for viruses.
                    var rawCount = Int(floor(max(1, rW * box.softBodyZoom)))
                    rawCount += rawCount & 1
                    let vCount = max(30, min(1000, rawCount))
                    appendVirusFan(cx: sx, cy: sy, radiusWorld: rW, zoomPx: zoomPx, pointCount: vCount,
                                   radiusOffsetWorld: borderOff, spikeDeltaWorld: spikeDelta, color: borderColVirus)
                    appendVirusFan(cx: sx, cy: sy, radiusWorld: rW, zoomPx: zoomPx, pointCount: vCount,
                                   radiusOffsetWorld: bodyOff, spikeDeltaWorld: spikeDelta, color: fillColVirus)
                    appendVirusFan(cx: sx, cy: sy, radiusWorld: rW * innerScale, zoomPx: zoomPx, pointCount: vCount,
                                   radiusOffsetWorld: 0, spikeDeltaWorld: spikeDelta * innerScale, color: fillColVirus)
                }
                flushSolid(enc: enc, viewportSize: vpPx)

            case .cell(let c, let isLocal):
                let spawn = spawnScale(id: c.id, now: nowTS)
                if spawn <= 0.001 { continue }
                fanScale = spawn
                let sx = Float(c.position.x) * zoomPx + screenOffX
                let sy = Float(c.position.y) * zoomPx + screenOffY
                let baseRadius = Float(c.cachedVisualRadius)
                let rW = baseRadius * spawn
                // calcCellVertexCount fallback before the soft-body arrays exist.
                let minPoints = baseRadius <= 20.0 ? 7 : 10
                let segCount = max(minPoints, min(1000, Int(floor(max(1, baseRadius * box.softBodyZoom)))))
                // SoftBodyCellView::drawOutlineWithVertices (0x1003a5064):
                //   outline at (r + 10) / r, body fill at (r + 5) / r.
                // drawFillingWithVertices (0x1003a528c) then paints an inner disc at (r - 10) / r.
                let isSmall = baseRadius <= 18.0
                // (r*zoom + 10)/(r*zoom): 10 and 5 are fixed screen points.
                let borderOff = 10.0 / max(0.01, ptZoom)
                let bodyOff = 5.0 / max(0.01, ptZoom)
                let innerScale = max(0.0, 1.0 - 10.0 / max(0.001, baseRadius * ptZoom))
                let isTeammate = box.teammateOwnerID == c.ownerID || box.teammateOwnerIDs.contains(c.ownerID)
                let showPartyBorder = isTeammate || (isLocal && box.localPlayerInParty)
                let fillSIMD = rgba(c.color)
                let skinTex: MTLTexture? = {
                    guard box.showSkins, let sName = c.skinName else { return nil }
                    return texCache.skinTexture(name: sName)
                }()
                // Party cells use the dedicated branch in drawOutlineWithVertices:
                // an opaque partySkinOuterOutlineColor disc at r, then
                // partySkinInnerOutlineColor at r-5pt.  The skin is then shrunk by
                // 6pt, leaving the 5pt orange ring and a 1pt yellow seam.
                if showPartyBorder {
                    let outerCol = SIMD4<Float>(partyRingCol.x, partyRingCol.y, partyRingCol.z, fillSIMD.w)
                    let innerCol = SIMD4<Float>(partyInnerCol.x, partyInnerCol.y, partyInnerCol.z, fillSIMD.w)
                    let innerPartyScale = max(0.0, 1.0 - 5.0 / max(0.001, baseRadius * ptZoom))
                    if c.deformedVertices.count >= 8 {
                        appendDeformedFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                          radiusOffsetWorld: 0, isVirus: false, virusSpikeDeltaWorld: 0, color: outerCol)
                        appendScaledFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                        scale: innerPartyScale, color: innerCol)
                    } else {
                        appendDiskFan(cx: sx, cy: sy, radius: max(1.5, rW * zoomPx), count: segCount, color: outerCol)
                        appendDiskFan(cx: sx, cy: sy, radius: max(1.5, (rW - 5.0 / max(0.01, ptZoom) * spawn) * zoomPx),
                                      count: segCount, color: innerCol)
                    }
                    flushSolid(enc: enc, viewportSize: vpPx)
                } else if !(showPartyBorder && skinTex != nil) {
                    if isSmall {
                        if c.deformedVertices.count >= 8 {
                            appendDeformedFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                              radiusOffsetWorld: 0, isVirus: false, virusSpikeDeltaWorld: 0, color: fillSIMD)
                        } else {
                            appendDiskFan(cx: sx, cy: sy, radius: max(1.5, rW * zoomPx), count: segCount, color: fillSIMD)
                        }
                    } else {
                        let borderSIMD = SIMD4<Float>(rgba(c.borderColor).x, rgba(c.borderColor).y, rgba(c.borderColor).z, fillSIMD.w)
                        let bodyBandSIMD = SIMD4<Float>(fillSIMD.x, fillSIMD.y, fillSIMD.z, 0x83 / 255.0)
                        if c.deformedVertices.count >= 8 {
                            appendDeformedFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                              radiusOffsetWorld: borderOff, isVirus: false, virusSpikeDeltaWorld: 0,
                                              color: showPartyBorder ? partyRingCol : borderSIMD)
                            appendDeformedFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                              radiusOffsetWorld: bodyOff, isVirus: false, virusSpikeDeltaWorld: 0, color: bodyBandSIMD)
                        } else {
                            appendDiskFan(cx: sx, cy: sy, radius: (rW + borderOff * spawn) * zoomPx, count: segCount,
                                          color: showPartyBorder ? partyRingCol : borderSIMD)
                            appendDiskFan(cx: sx, cy: sy, radius: max(1.5, (rW + bodyOff * spawn) * zoomPx), count: segCount, color: bodyBandSIMD)
                        }
                    }
                    flushSolid(enc: enc, viewportSize: vpPx)
                }

                // drawBackgroundForTextureTransparency: (0x1003a56d0) runs before
                // the skin and paints an opaque white polygon only when the cell's
                // alpha is not fully opaque.
                if let skinTex, fillSIMD.x < 0.999 { // initialColor3b.r != 255
                    if c.deformedVertices.count >= 8 {
                        appendScaledFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                        scale: 1.0, color: SIMD4<Float>(1, 1, 1, 1))
                    } else {
                        appendDiskFan(cx: sx, cy: sy, radius: max(1.5, rW * zoomPx), count: segCount,
                                      color: SIMD4<Float>(1, 1, 1, 1))
                    }
                    flushSolid(enc: enc, viewportSize: vpPx)
                }

                // Skin is drawn on the full soft-body polygon.  shrinkGLForPartyCell
                // (0x1003a56f0) scales the party skin geometry by 1 - 6/(r*zoom),
                // but calcTexCoordsInto still uses the unscaled vertices.
                if let skinTex {
                    let vertexScale = (showPartyBorder
                        ? max(0.5, 1.0 - 6.0 / max(0.001, baseRadius * ptZoom))
                        : 1.0) * spawn
                    let rFallback = max(1.5, baseRadius * zoomPx)
                    drawTexturedFan(enc: enc, texture: skinTex, cx: sx, cy: sy,
                                    verts: c.deformedVertices, zoomPx: zoomPx,
                                    radiusOffsetWorld: 0, fallbackRadiusPx: rFallback,
                                    baseRadiusWorld: baseRadius, vertexScale: vertexScale,
                                    alpha: fillSIMD.w, viewportSize: vpPx)

                    let altSince: TimeInterval? = isLocal
                        ? box.dualSkinSwapShowingSince
                        : box.dualSkinSwapShowingSinceByOwner[c.ownerID]
                    if let since = altSince, let sName = c.skinName, DualSkinCatalog.shared.isDual(sName),
                       let altTex = texCache.skinTexture(name: sName, isAlternate: true) {
                        let age = nowTS - since
                        let fade = age < 0.14 ? Float(age / 0.14) : 1.0
                        drawTexturedFan(enc: enc, texture: altTex, cx: sx, cy: sy,
                                        verts: c.deformedVertices, zoomPx: zoomPx,
                                        radiusOffsetWorld: 0, fallbackRadiusPx: rFallback,
                                        baseRadiusWorld: baseRadius, vertexScale: vertexScale,
                                        alpha: min(fillSIMD.w, max(0.0, fade)), viewportSize: vpPx)
                    }
                }

                // drawFillingWithVertices (0x1003a528c):
                //   * player-owned cells draw 0xC0C0C0 at the FULL radius with
                //     alpha*0.75 (after the skin, so it is a translucent wash);
                //   * other unskinned cells draw the opaque (r-10)/r disc in their
                //     own colour.
                // Skinned non-player cells return before this pass in the client.
                if skinTex != nil {
                    // The skin already carries the cell artwork.  The client's 0xC0C0C0
                    // player-owned fill is a dimming wash only for the untextured body;
                    // painting it over a skin produced the grey veil seen in game.
                } else if isLocal {
                    let wash = SIMD4<Float>(0xC0 / 255.0, 0xC0 / 255.0, 0xC0 / 255.0, fillSIMD.w * 0.75)
                    if c.deformedVertices.count >= 8 {
                        appendScaledFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                        scale: 1.0, color: wash)
                    } else {
                        appendDiskFan(cx: sx, cy: sy, radius: max(1.5, rW * zoomPx), count: segCount, color: wash)
                    }
                    flushSolid(enc: enc, viewportSize: vpPx)
                } else {
                    // Unskinned cell: drawFillingWithVertices paints the opaque
                    // (r - 10pt)/r core in the cell's own colour.  Without this
                    // the banded body read as a see-through ring.
                    if c.deformedVertices.count >= 8 {
                        appendScaledFan(cx: sx, cy: sy, verts: c.deformedVertices, zoomPx: zoomPx,
                                        scale: innerScale, color: fillSIMD)
                    } else {
                        appendDiskFan(cx: sx, cy: sy, radius: max(1.5, rW * innerScale * zoomPx), count: segCount, color: fillSIMD)
                    }
                    flushSolid(enc: enc, viewportSize: vpPx)
                }

                // Emote bubble over local cells clipped to the cell polygon (`CellOverlayImage::drawWithVertices` 0x1002e2ae8)
                // Drawn BEFORE name/mass/badge labels (`SoftBodyCellView` z:2 child order) so text stays readable on top.
                if isLocal, let emoteName = box.activeEmoteAsset, nowTS < box.activeEmoteExpiresAt,
                   let emoteTex = texCache.texture(named: emoteName) {
                    let elapsed = nowTS - box.activeEmoteStartedAt
                    let remaining = box.activeEmoteExpiresAt - nowTS
                    let alpha = Float(min(1.0, min(elapsed / 0.12, remaining / 0.2)))
                    let rFallback = max(1.5, baseRadius * zoomPx)
                    if alpha > 0.01 && rFallback > 4 {
                        drawTexturedFan(enc: enc, texture: emoteTex, cx: sx, cy: sy,
                                        verts: c.deformedVertices, zoomPx: zoomPx,
                                        radiusOffsetWorld: 0, fallbackRadiusPx: rFallback,
                                        baseRadiusWorld: baseRadius, vertexScale: spawn,
                                        alpha: alpha, viewportSize: vpPx)
                    }
                }

                // Cell labels + League Badges + friend-pfp (SoftBodyCellView: OpenSans-Bold white w/ outline, z:2)
                let screenSolidR = Float(c.cachedSolidRadius) * spawn * zoomPx
                if screenSolidR > 12.0 * scale {
                    let level = box.ownerLevels[c.ownerID]
                    let rWFloat = Float(c.cachedSolidRadius) * spawn
                    let w30 = c.name.isEmpty ? Float(0) : texCache.widthAt30pt(for: c.name)
                    let nameScale = max(Float(0.8), (3.24 * rWFloat) / (w30 + 161.0))
                    let fontPx = max(8.0 * scale, 30.0 * nameScale * zoomPx)
                    let baseScale = c.name.isEmpty ? max(Float(1.0), ((rWFloat - 47.0) * 0.6) / 50.0 + 1.0) : nameScale
                    let h30: Float = 41.0
                    let targetMassScale = min(3.0 / max(cocosZoom, 0.05), (0.5 * rWFloat) / h30)
                    let massScale = min(2.0 * baseScale, targetMassScale)
                    let massPx = max(8.0 * scale, 30.0 * massScale * zoomPx * Float(c.massFontScale))
                    let centeredMassPx = max(8.0 * scale, 30.0 * min(2.0 * max(Float(1.0), baseScale), targetMassScale) * zoomPx * Float(c.massFontScale))
                    let massInt = max(10, Int(round(c.mass)))
                    let badgeAspect = Float(LeagueBadge.imageAspect)

                    func drawBadge(lvl: Int, cx: Float, cy: Float, hPx: Float) {
                        let asset = LeagueBadge.assetName(forLevel: lvl)
                        guard let bTex = texCache.texture(named: asset) else { return }
                        let wPx = hPx * badgeAspect
                        drawQuad(enc: enc, texture: bTex, centerX: cx, centerY: cy, width: wPx, height: hPx, alpha: 1.0, viewportSize: vpPx)
                        let clamped = LeagueBadge.clamp(lvl)
                        let digitPx = hPx * (clamped >= 100 ? 0.32 : 0.40)
                        let stCol = LeagueBadge.strokeColor(forAsset: asset)
                        if let dlbl = texCache.labelTexture(text: "\(clamped)", pixelHeight: CGFloat(digitPx), strokeWidthPct: -8.0, strokeColor: stCol) {
                            let sr = digitPx / Float(max(1.0, dlbl.fontSize))
                            let dW = Float(dlbl.size.width) * sr
                            let dH = Float(dlbl.size.height) * sr
                            drawQuad(enc: enc, texture: dlbl.texture, centerX: cx, centerY: cy, width: dW, height: dH, alpha: 1.0, viewportSize: vpPx)
                        }
                    }

                    func drawNameAndBadge(text: String, lvl: Int?, cx: Float, cy: Float, targetFontPx: Float) {
                        guard let lbl = texCache.labelTexture(text: text, pixelHeight: CGFloat(targetFontPx), strokeWidthPct: -6.7, strokeColor: .black) else {
                            if let lvl { drawBadge(lvl: lvl, cx: cx, cy: cy, hPx: screenSolidR * 1.3) }
                            return
                        }
                        let sr = targetFontPx / Float(max(1.0, lbl.fontSize))
                        let rawW = Float(lbl.size.width) * sr
                        let rawH = Float(lbl.size.height) * sr
                        let fitScale = rawW > screenSolidR * 2.15 ? (screenSolidR * 2.15 / max(1.0, rawW)) : 1.0
                        let textW = rawW * fitScale
                        let finalH = rawH * fitScale
                        if let lvl {
                            let bH = targetFontPx * 1.1475
                            let bW = bH * badgeAspect
                            let nameCX = cx + (bW - targetFontPx * 0.06) * 0.5
                            drawQuad(enc: enc, texture: lbl.texture, centerX: nameCX, centerY: cy, width: textW, height: finalH, alpha: 1.0, viewportSize: vpPx)
                            let badgeCX = nameCX - textW * 0.5 - bW * 0.5 + targetFontPx * 0.06
                            drawBadge(lvl: lvl, cx: badgeCX, cy: cy, hPx: bH)
                        } else {
                            drawQuad(enc: enc, texture: lbl.texture, centerX: cx, centerY: cy, width: textW, height: finalH, alpha: 1.0, viewportSize: vpPx)
                        }
                    }

                    func drawMassNumber(_ px: Float, cx: Float, cy: Float) {
                        guard let mlbl = texCache.labelTexture(text: "\(massInt)", pixelHeight: CGFloat(px), strokeWidthPct: -6.7, strokeColor: .black) else { return }
                        let sr = px / Float(max(1.0, mlbl.fontSize))
                        let w = Float(mlbl.size.width) * sr
                        let h = Float(mlbl.size.height) * sr
                        drawQuad(enc: enc, texture: mlbl.texture, centerX: cx, centerY: cy, width: w, height: h, alpha: 1.0, viewportSize: vpPx)
                    }

                    if isTeammate {
                        if let pfpTex = texCache.texture(named: "friend-pfp") {
                            let pfpSide = max(4.0 * scale, screenSolidR * 0.40) * 1.35
                            drawQuad(enc: enc, texture: pfpTex, centerX: sx, centerY: sy - screenSolidR * 0.40,
                                     width: pfpSide, height: pfpSide, alpha: 1.0, viewportSize: vpPx)
                        }
                        if !c.name.isEmpty {
                            drawNameAndBadge(text: c.name, lvl: level, cx: sx, cy: sy + screenSolidR * 0.28, targetFontPx: fontPx * 0.85)
                        } else if let level {
                            drawBadge(lvl: level, cx: sx, cy: sy + screenSolidR * 0.28, hPx: screenSolidR * 0.85)
                        }
                    } else if !isLocal {
                        if !c.name.isEmpty {
                            drawNameAndBadge(text: c.name, lvl: level, cx: sx, cy: sy, targetFontPx: fontPx)
                        } else if let level {
                            drawBadge(lvl: level, cx: sx, cy: sy, hPx: screenSolidR * 1.3)
                        }
                    } else if c.name.isEmpty {
                        if let level {
                            drawBadge(lvl: level, cx: sx, cy: sy, hPx: screenSolidR * 1.3)
                            if box.showMassText { drawMassNumber(massPx, cx: sx, cy: sy + screenSolidR * 0.65) }
                        } else if box.showMassText {
                            drawMassNumber(centeredMassPx, cx: sx, cy: sy)
                        }
                    } else {
                        let nameY = box.showMassText ? (sy - screenSolidR * 0.10) : sy
                        drawNameAndBadge(text: c.name, lvl: level, cx: sx, cy: nameY, targetFontPx: fontPx)
                        if box.showMassText { drawMassNumber(massPx, cx: sx, cy: sy + screenSolidR * 0.65) }
                    }
                }
            }
        }

        flushSolid(enc: enc, viewportSize: vpPx)
        enc.endEncoding()
        return true
    }
}
