import Foundation
import SwiftUI
import UIKit

// MARK: - CCBI Binary Scene Graph Model

enum CCBIPropValue {
    case pos(x: CGFloat, y: CGFloat, refCorner: Int, xUnit: Int, yUnit: Int, c: Int)
    case size(w: CGFloat, h: CGFloat, wUnit: Int, hUnit: Int, c: Int)
    case point(CGFloat, CGFloat)
    case scale(sx: CGFloat, sy: CGFloat, type: Int)
    case float(CGFloat)
    case int(Int)
    case uint(Int)
    case bool(Bool)
    case byte(UInt8)
    case str(String)
    case strBool(String, Bool)
    case strInt(String, Int)
    case str2Int(String, Int, Int)
    case fltInt(CGFloat, Int)
    case fltBool(CGFloat, Bool)
    case rgba(r: Double, g: Double, b: Double, a: Double)
    case spriteFrame(sheet: String, frame: String)
    case strList([String])
    case other
}

final class CCBINode: Identifiable {
    let id = UUID()
    let cls: String
    let base: String
    let varName: String
    var props: [String: CCBIPropValue]
    var children: [CCBINode]

    init(cls: String, base: String, varName: String, props: [String: CCBIPropValue], children: [CCBINode]) {
        self.cls = cls
        self.base = base
        self.varName = varName
        self.props = props
        self.children = children
    }

    func clone() -> CCBINode {
        CCBINode(cls: cls, base: base, varName: varName, props: props, children: children.map { $0.clone() })
    }
}

// MARK: - Native .ccbi Binary Decoder (v19..v22 compatible, 327/327 verified)

final class CCBIBinaryReader {
    private let data: [UInt8]
    private var pos: Int = 0
    private var ver: Int = 0
    private var strs: [String] = []

    init(data: Data) {
        self.data = [UInt8](data)
    }

    private func readU8() -> UInt8 {
        guard pos < data.count else { return 0 }
        let v = data[pos]
        pos += 1
        return v
    }

    private func readEliasGamma() -> Int {
        var bp = pos
        var bitp = 0
        var zeros = -1
        while bp < data.count {
            let bit = (Int(data[bp]) >> bitp) & 1
            bitp += 1
            if bitp >= 8 { bitp = 0; bp += 1 }
            zeros += 1
            if bit == 1 { break }
        }
        var val = 0
        var rem = zeros + 1
        while rem > 1 && bp < data.count {
            let bit = (Int(data[bp]) >> bitp) & 1
            bitp += 1
            if bitp >= 8 { bitp = 0; bp += 1 }
            val |= (bit << (rem - 2))
            rem -= 1
        }
        if bitp > 0 { bp += 1 }
        pos = bp
        return ((1 << zeros) | val) - 1
    }

    private func readInt(signed: Bool = false) -> Int {
        var res: UInt64 = 0
        var shift: UInt64 = 0
        while pos < data.count {
            let b = UInt64(data[pos])
            pos += 1
            res |= (b & 0x7f) << shift
            if (b & 0x80) == 0 { break }
            shift += 7
        }
        if !signed {
            return Int(truncatingIfNeeded: res)
        }
        if (res & 1) != 0 {
            let mag = (res >> 1) + 1
            return -Int(truncatingIfNeeded: mag)
        } else {
            return Int(truncatingIfNeeded: res >> 1)
        }
    }

    private func readUTF8() -> String {
        guard pos + 1 < data.count else { return "" }
        let len = (Int(data[pos]) << 8) | Int(data[pos + 1])
        pos += 2
        let end = min(pos + len, data.count)
        let sub = data[pos..<end]
        pos = end
        return String(bytes: sub, encoding: .utf8) ?? ""
    }

    private func readStr() -> String {
        let idx = readInt(signed: false)
        return (idx >= 0 && idx < strs.count) ? strs[idx] : ""
    }

    private func readFloat() -> CGFloat {
        let t = readU8()
        switch t {
        case 0: return 0.0
        case 1: return 1.0
        case 2: return -1.0
        case 3: return 0.5
        case 4: return CGFloat(readInt(signed: true))
        default:
            guard pos + 4 <= data.count else { return 0.0 }
            let bits = UInt32(data[pos])
                | (UInt32(data[pos + 1]) << 8)
                | (UInt32(data[pos + 2]) << 16)
                | (UInt32(data[pos + 3]) << 24)
            pos += 4
            return CGFloat(Float(bitPattern: bits))
        }
    }

    private func readPropVal(_ pt: Int) -> CCBIPropValue {
        switch pt {
        case 0:
            let x = readFloat(); let y = readFloat()
            let t = Int(readU8()); let a = Int(readU8()); let b = Int(readU8())
            let c = ver >= 14 ? Int(readU8()) : 0
            return .pos(x: x, y: y, refCorner: t, xUnit: a, yUnit: b, c: c)
        case 1:
            let w = readFloat(); let h = readFloat()
            let a = Int(readU8()); let b = Int(readU8())
            let c = ver >= 14 ? Int(readU8()) : 0
            return .size(w: w, h: h, wUnit: a, hUnit: b, c: c)
        case 2, 3, 27:
            return .point(readFloat(), readFloat())
        case 4:
            return .scale(sx: readFloat(), sy: readFloat(), type: Int(readU8()))
        case 5, 7:
            return .float(readFloat())
        case 6, 20:
            return .int(readInt(signed: true))
        case 8:
            _ = readFloat(); _ = readFloat()
            return .other
        case 9:
            return .bool(readU8() != 0)
        case 10, 11, 19, 23, 33, 34, 36, 37, 38, 39, 41:
            return .str(readStr())
        case 12:
            return .byte(readU8())
        case 13, 28, 42:
            let r = Double(readFloat()); let g = Double(readFloat())
            let b = Double(readFloat()); let a = Double(readFloat())
            return .rgba(r: r, g: g, b: b, a: a)
        case 14:
            for _ in 0..<8 { _ = readFloat() }
            return .other
        case 15:
            _ = readU8(); _ = readU8()
            return .other
        case 16:
            _ = readInt(signed: false); _ = readInt(signed: false)
            return .other
        case 18, 24:
            return .strBool(readStr(), readU8() != 0)
        case 21:
            return .strInt(readStr(), readInt(signed: false))
        case 22:
            return .spriteFrame(sheet: readStr(), frame: readStr())
        case 25:
            return .str2Int(readStr(), readInt(signed: false), readInt(signed: false))
        case 26:
            return .fltInt(readFloat(), readInt(signed: false))
        case 30:
            return .fltBool(readFloat(), readU8() != 0)
        case 31:
            return .uint(readInt(signed: false))
        case 40:
            let cnt = readInt(signed: false)
            return .strList((0..<cnt).map { _ in readStr() })
        case 43:
            let cnt = readInt(signed: false)
            for _ in 0..<cnt { _ = readPropVal(readInt(signed: false)) }
            return .other
        case 44:
            let cnt = readInt(signed: false)
            for _ in 0..<cnt {
                _ = readStr()
                _ = readPropVal(readInt(signed: false))
            }
            return .other
        default:
            return .other
        }
    }

    private func skipKeyframe(_ pt: Int) {
        _ = readFloat()
        let e = readInt(signed: false)
        if e <= 19 && (((1 << e) & 0xe00fc) != 0) {
            _ = readFloat()
        }
        switch pt {
        case 13: for _ in 0..<4 { _ = readFloat() }
        case 12, 9: _ = readU8()
        case 5, 7: _ = readFloat()
        case 0, 1, 4, 27: _ = readFloat(); _ = readFloat()
        case 10, 18, 38: _ = readStr()
        default: break
        }
    }

    private func skipChannel(hasThree: Bool) {
        let n = readInt(signed: false)
        for _ in 0..<n {
            _ = readFloat(); _ = readStr()
            if hasThree { _ = readFloat(); _ = readFloat() }
            else { _ = readInt(signed: false) }
        }
    }

    private func readNode() -> CCBINode {
        let cls = readStr()
        let base = ver >= 12 ? readStr() : ""
        let at = readInt(signed: false)
        let an = at != 0 ? readStr() : ""

        let nsp = readInt(signed: false)
        for _ in 0..<nsp {
            _ = readInt(signed: false)
            let np = readInt(signed: false)
            for _ in 0..<np {
                _ = readStr()
                let pt = readInt(signed: false)
                let nk = readInt(signed: false)
                for _ in 0..<nk { skipKeyframe(pt) }
            }
        }
        if ver >= 13 {
            let nc = readInt(signed: false)
            for _ in 0..<nc {
                _ = readStr()
                let nv = ver >= 22 ? readInt(signed: false) : 1
                if ver >= 22 {
                    for _ in 0..<nv { _ = readStr() }
                }
            }
        }
        _ = readInt(signed: false) // uuid
        let np1 = readInt(signed: false)
        let np2 = readInt(signed: false)

        var props: [String: CCBIPropValue] = [:]
        props.reserveCapacity(np1 + np2)
        for _ in 0..<np1 {
            let pt = readInt(signed: false)
            let pn = readStr()
            props[pn] = readPropVal(pt)
        }
        if cls == "CCBFile" || base == "CCBFile" {
            let nOv = readInt(signed: false)
            for _ in 0..<nOv {
                let targetProp = readStr()
                let pt = readInt(signed: false)
                let varTarget = readStr()
                props["override:\(varTarget):\(targetProp)"] = readPropVal(pt)
                if ver >= 17 { _ = readU8() }
            }
        }
        for _ in 0..<np2 {
            let pt = readInt(signed: false)
            let pn = readStr()
            props[pn] = readPropVal(pt)
        }
        if ver <= 17 { _ = readU8() }
        let nch = readInt(signed: false)
        let children = (0..<nch).map { _ in readNode() }
        return CCBINode(cls: cls, base: base, varName: an, props: props, children: children)
    }

    func parseRoot() -> CCBINode? {
        guard data.count > 8,
              data[0] == 0x69, data[1] == 0x62, data[2] == 0x63, data[3] == 0x63 else { // "ibcc"
            return nil
        }
        pos = 4
        ver = readEliasGamma()
        let strCount = readInt(signed: false)
        strs = (0..<strCount).map { _ in readUTF8() }
        let nSeq = readInt(signed: false)
        if ver <= 17 { pos += 2 }
        for _ in 0..<nSeq {
            _ = readFloat(); _ = readStr(); _ = readInt(signed: false); _ = readInt(signed: true)
            skipChannel(hasThree: false)
            skipChannel(hasThree: true)
        }
        _ = readInt(signed: true)
        if 11 <= ver && ver <= 20 {
            _ = readInt(signed: false)
            _ = readInt(signed: false)
        }
        if ver >= 15 {
            let c1 = readInt(signed: false)
            for _ in 0..<c1 { _ = readStr(); _ = readInt(signed: false) }
            let c2 = readInt(signed: false)
            for _ in 0..<c2 {
                _ = readInt(signed: false)
                let c3 = readInt(signed: false)
                for _ in 0..<c3 {
                    let pt = readInt(signed: false)
                    _ = readStr()
                    _ = readPropVal(pt)
                }
            }
        }
        if ver >= 13 {
            let c4 = readInt(signed: false)
            for _ in 0..<c4 {
                _ = readStr()
                let pt = readInt(signed: false)
                _ = readInt(signed: false)
                _ = readPropVal(pt)
                if 16 <= ver && ver <= 21 && readU8() != 0 {
                    _ = readStr()
                }
            }
        }
        return readNode()
    }
}

// MARK: - Texture Atlas, Sprite, MCFS 9-Slice, and Localization Cache

struct CCBISpriteEntry {
    let image: UIImage
    let designSize: CGSize
    let pixelScale: CGFloat
}

struct CCBIMCFSEntry {
    let image: UIImage
    let capInsets: EdgeInsets
    let cgImage: CGImage
    let pixelScale: CGFloat
    let leftF: CGFloat
    let rightF: CGFloat
    let topF: CGFloat
    let bottomF: CGFloat

    func uiImageAndInsets(forUIScale uiScale: CGFloat) -> (UIImage, EdgeInsets) {
        let effScale = max(0.25, pixelScale / max(0.5, uiScale))
        let img = UIImage(cgImage: cgImage, scale: effScale, orientation: .up)
        let sz = img.size
        let hSum = leftF + rightF
        let vSum = topF + bottomF
        let hScale = hSum > 0.96 ? (0.96 / hSum) : 1.0
        let vScale = vSum > 0.96 ? (0.96 / vSum) : 1.0
        let insets = EdgeInsets(
            top: sz.height * topF * vScale,
            leading: sz.width * leftF * hScale,
            bottom: sz.height * bottomF * vScale,
            trailing: sz.width * rightF * hScale
        )
        return (img, insets)
    }
}

private struct AtlasFrameMeta {
    let frameRect: CGRect
    let sourceColorRect: CGRect
    let sourceSize: CGSize
    let rotated: Bool
}

private final class LoadedAtlas {
    let sheetName: String
    let cgImage: CGImage
    let pixelScale: CGFloat
    let frames: [String: AtlasFrameMeta]

    init(sheetName: String, cgImage: CGImage, pixelScale: CGFloat, frames: [String: AtlasFrameMeta]) {
        self.sheetName = sheetName
        self.cgImage = cgImage
        self.pixelScale = pixelScale
        self.frames = frames
    }
}

final class CCBIAtlasStore: @unchecked Sendable {
    static let shared = CCBIAtlasStore()

    private let lock = NSLock()
    private var ccbiCache: [String: CCBINode] = [:]
    private var atlases: [String: LoadedAtlas] = [:]
    private var atlasesLoaded = false
    private var spriteCache: [String: CCBISpriteEntry] = [:]
    private var mcfsCache: [String: CCBIMCFSEntry] = [:]
    private var localizedStrings: [String: String]?

    private init() {}

    func atlasPixelScale(for sheet: String) -> CGFloat {
        // Measured directly across agarskins.ipa base vs -ipadhd sheets:
        // Controls was authored at 2.0x; all UI sheets were authored at 32/9 (~3.5556x).
        return sheet == "Controls" ? 2.0 : (32.0 / 9.0)
    }

    func localize(_ key: String, localizedFlag: Bool = true) -> String {
        let shouldLookup = localizedFlag || (key.contains("_") && !key.contains(" ") && !key.contains("\n"))
        guard shouldLookup else {
            return key.replacingOccurrences(of: "\\n", with: "\n")
        }
        lock.lock()
        if localizedStrings == nil {
            var dict: [String: String] = [:]
            if let url = Bundle.main.url(forResource: "en_text", withExtension: "json", subdirectory: "AgarAssets"),
               let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = obj["texts"] as? [[String: Any]] {
                dict.reserveCapacity(rows.count)
                for row in rows {
                    if let k = row["k"] as? String, let v = row["v"] as? String {
                        dict[k] = v.replacingOccurrences(of: "\\n", with: "\n")
                    }
                }
            }
            localizedStrings = dict
        }
        let found = localizedStrings?[key]
        lock.unlock()
        return found ?? key.replacingOccurrences(of: "\\n", with: "\n")
    }

    func loadCCBI(named rawName: String) -> CCBINode? {
        let stem = URL(fileURLWithPath: rawName)
            .deletingPathExtension()
            .lastPathComponent
        lock.lock()
        if let cached = ccbiCache[stem] {
            lock.unlock()
            return cached.clone()
        }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: stem, withExtension: "ccbi", subdirectory: "AgarAssets/ccbi"),
              let data = try? Data(contentsOf: url),
              let root = CCBIBinaryReader(data: data).parseRoot() else {
            return nil
        }

        lock.lock()
        ccbiCache[stem] = root
        lock.unlock()
        return root.clone()
    }

    private func ensureAtlasesLoadedLocked() {
        guard !atlasesLoaded else { return }
        atlasesLoaded = true
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "plist", subdirectory: "AgarAssets/atlases") else {
            return
        }
        for plistURL in urls {
            let file = plistURL.lastPathComponent
            let sheet = file.replacingOccurrences(of: "-ipadhd.plist", with: "")
            let pngURL = plistURL.deletingPathExtension().appendingPathExtension("png")
            guard let uiImg = UIImage(contentsOfFile: pngURL.path),
                  let cgImg = uiImg.cgImage,
                  let data = try? Data(contentsOf: plistURL),
                  let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let rawFrames = raw["frames"] as? [String: [String: Any]] else {
                continue
            }
            var parsedFrames: [String: AtlasFrameMeta] = [:]
            parsedFrames.reserveCapacity(rawFrames.count)
            for (fname, fdict) in rawFrames {
                let frameStr = (fdict["frame"] as? String) ?? "{{0,0},{0,0}}"
                let srcSizeStr = (fdict["sourceSize"] as? String) ?? "{0,0}"
                let rotated = (fdict["rotated"] as? Bool) ?? false
                let fRect = NSCoder.cgRect(for: frameStr)
                let sSize = NSCoder.cgSize(for: srcSizeStr)
                let cRect: CGRect = {
                    if let rawCR = fdict["sourceColorRect"] as? String {
                        return NSCoder.cgRect(for: rawCR)
                    }
                    let off = NSCoder.cgPoint(for: (fdict["offset"] as? String) ?? "{0,0}")
                    return CGRect(
                        x: (sSize.width - fRect.width) * 0.5 + off.x,
                        y: (sSize.height - fRect.height) * 0.5 - off.y,
                        width: fRect.width,
                        height: fRect.height
                    )
                }()
                if fRect.width > 0 && fRect.height > 0 && sSize.width > 0 && sSize.height > 0 {
                    parsedFrames[fname] = AtlasFrameMeta(frameRect: fRect, sourceColorRect: cRect, sourceSize: sSize, rotated: rotated)
                }
            }
            atlases[sheet] = LoadedAtlas(sheetName: sheet, cgImage: cgImg, pixelScale: atlasPixelScale(for: sheet), frames: parsedFrames)
        }
    }

    func sprite(for rawPath: String, explicitSheet: String = "") -> CCBISpriteEntry? {
        guard !rawPath.isEmpty else { return nil }
        let cacheKey = "\(explicitSheet)|\(rawPath)"
        lock.lock()
        if let hit = spriteCache[cacheKey] {
            lock.unlock()
            return hit
        }
        ensureAtlasesLoadedLocked()

        // Parse "GeneratedAssets/spritesheets/Bundle/All/<sheet>/<frame>"
        var targetSheet = explicitSheet.replacingOccurrences(of: ".plist", with: "")
        var targetFrame = URL(fileURLWithPath: rawPath).lastPathComponent
        if targetSheet.isEmpty {
            let parts = rawPath.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "All"), idx + 2 < parts.count {
                targetSheet = parts[idx + 1]
                targetFrame = parts[(idx + 2)...].joined(separator: "/")
            }
        }

        var foundAtlas: LoadedAtlas?
        var foundMeta: AtlasFrameMeta?
        if !targetSheet.isEmpty, let atlas = atlases[targetSheet], let meta = atlas.frames[targetFrame] {
            foundAtlas = atlas
            foundMeta = meta
        } else {
            let shortName = URL(fileURLWithPath: targetFrame).lastPathComponent
            for atlas in atlases.values {
                if let meta = atlas.frames[targetFrame] ?? atlas.frames[shortName] {
                    foundAtlas = atlas
                    foundMeta = meta
                    break
                }
            }
        }
        lock.unlock()

        if let atlas = foundAtlas, let meta = foundMeta {
            let w = meta.frameRect.width
            let h = meta.frameRect.height
            let cropRect = meta.rotated
                ? CGRect(x: meta.frameRect.minX, y: meta.frameRect.minY, width: h, height: w)
                : meta.frameRect
            if let cropped = atlas.cgImage.cropping(to: cropRect) {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0
                format.opaque = false
                let outSize = meta.sourceSize
                let rendered = UIGraphicsImageRenderer(size: outSize, format: format).image { ctx in
                    let cg = ctx.cgContext
                    let dest = meta.sourceColorRect
                    if meta.rotated {
                        cg.saveGState()
                        cg.translateBy(x: dest.minX, y: dest.minY + dest.height)
                        cg.rotate(by: -.pi / 2)
                        UIImage(cgImage: cropped, scale: 1.0, orientation: .up)
                            .draw(in: CGRect(x: 0, y: 0, width: dest.height, height: dest.width))
                        cg.restoreGState()
                    } else {
                        UIImage(cgImage: cropped, scale: 1.0, orientation: .up).draw(in: dest)
                    }
                }
                if let renderedCG = rendered.cgImage {
                    let designSize = CGSize(width: outSize.width / atlas.pixelScale, height: outSize.height / atlas.pixelScale)
                    let finalUI = UIImage(cgImage: renderedCG, scale: atlas.pixelScale, orientation: .up)
                    let entry = CCBISpriteEntry(image: finalUI, designSize: designSize, pixelScale: atlas.pixelScale)
                    lock.lock()
                    spriteCache[cacheKey] = entry
                    lock.unlock()
                    return entry
                }
            }
        }

        // Fallback: standalone sprite in AgarAssets/sprites/
        let shortFile = URL(fileURLWithPath: rawPath).lastPathComponent
        let stem = (shortFile as NSString).deletingPathExtension
        let ext = (shortFile as NSString).pathExtension.isEmpty ? "png" : (shortFile as NSString).pathExtension
        if let spURL = Bundle.main.url(forResource: stem, withExtension: ext, subdirectory: "AgarAssets/sprites"),
           let rawUI = UIImage(contentsOfFile: spURL.path),
           let rawCG = rawUI.cgImage {
            let pxScale: CGFloat = (32.0 / 9.0)
            let designSize = CGSize(width: CGFloat(rawCG.width) / pxScale, height: CGFloat(rawCG.height) / pxScale)
            let finalUI = UIImage(cgImage: rawCG, scale: pxScale, orientation: .up)
            let entry = CCBISpriteEntry(image: finalUI, designSize: designSize, pixelScale: pxScale)
            lock.lock()
            spriteCache[cacheKey] = entry
            lock.unlock()
            return entry
        }
        return nil
    }

    func mcfs(for descriptionName: String) -> CCBIMCFSEntry? {
        guard !descriptionName.isEmpty else { return nil }
        let fileName = URL(fileURLWithPath: descriptionName).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        lock.lock()
        if let hit = mcfsCache[stem] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: stem, withExtension: "plist", subdirectory: "AgarAssets/mcfs"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let sheet = dict["Sprite_Sheet"] as? String,
              let sourceFrame = dict["Source_Frame"] as? String,
              let entry = sprite(for: sourceFrame, explicitSheet: sheet),
              let cg = entry.image.cgImage else {
            return nil
        }

        let leftF = CGFloat((dict["Left_Margin"] as? NSNumber)?.doubleValue ?? 0.4)
        let rightF = CGFloat((dict["Right_Margin"] as? NSNumber)?.doubleValue ?? 0.4)
        let topF = CGFloat((dict["Top_Margin"] as? NSNumber)?.doubleValue ?? 0.4)
        let bottomF = CGFloat((dict["Bottom_Margin"] as? NSNumber)?.doubleValue ?? 0.4)

        let hSum = leftF + rightF
        let vSum = topF + bottomF
        let hScale = hSum > 0.96 ? (0.96 / hSum) : 1.0
        let vScale = vSum > 0.96 ? (0.96 / vSum) : 1.0

        let ptSize = entry.image.size
        let insets = EdgeInsets(
            top: ptSize.height * topF * vScale,
            leading: ptSize.width * leftF * hScale,
            bottom: ptSize.height * bottomF * vScale,
            trailing: ptSize.width * rightF * hScale
        )
        let res = CCBIMCFSEntry(
            image: entry.image,
            capInsets: insets,
            cgImage: cg,
            pixelScale: entry.pixelScale,
            leftF: leftF,
            rightF: rightF,
            topF: topF,
            bottomF: bottomF
        )
        lock.lock()
        mcfsCache[stem] = res
        lock.unlock()
        return res
    }
}

// MARK: - Exact Cocos2d-x FixedHeight Layout & Interactive Scene Renderer

struct CCBIBindingContext {
    var actions: [String: () -> Void] = [:]
    var tapVarActions: [String: () -> Void] = [:]
    var labelOverrides: [String: String] = [:]
    var labelColorOverrides: [String: Color] = [:]
    var visibilityOverrides: [String: Bool] = [:]
    var opacityOverrides: [String: Double] = [:]
    var slotViews: [String: AnyView] = [:]
    var replacingSlotViews: [String: AnyView] = [:]
    var designScaleModifier: ((CGSize) -> CGFloat)? = nil
    var ancestorVars: [String] = []

    func scopedLookup<T>(_ dict: [String: T], varName: String) -> T? {
        guard !varName.isEmpty else { return nil }
        for anc in ancestorVars.reversed() {
            if let hit = dict["\(anc).\(varName)"] { return hit }
        }
        return dict[varName]
    }
}

struct CCBISceneView: View {
    let ccbFile: String
    var centerRoot: Bool = false
    var context: CCBIBindingContext

    var body: some View {
        GeometryReader { geo in
            let scale = context.designScaleModifier?(geo.size) ?? OriginalGameplay.uiScale(for: geo.size)
            let designSize = CGSize(width: geo.size.width / scale, height: geo.size.height / scale)
            if let root = CCBIAtlasStore.shared.loadCCBI(named: ccbFile) {
                CCBINodeRenderer(
                    node: root,
                    parentDesignSize: designSize,
                    scaleFactor: scale,
                    context: context,
                    positionOverride: centerRoot ? (designSize.width * 0.5, designSize.height * 0.5) : nil,
                    anchorOverride: centerRoot ? CGPoint(x: 0.5, y: 0.5) : nil
                )
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

private struct CCBINodeRenderer: View {
    let node: CCBINode
    let parentDesignSize: CGSize
    let scaleFactor: CGFloat
    let context: CCBIBindingContext
    var positionOverride: (CGFloat, CGFloat)? = nil
    var anchorOverride: CGPoint? = nil

    private var childContext: CCBIBindingContext {
        if node.varName.isEmpty { return context }
        var copy = context
        copy.ancestorVars.append(node.varName)
        return copy
    }

    var body: some View {
        let isVisible = resolveVisible()
        if isVisible {
            let subFileRoot = loadSubCCBFileIfNeeded()
            let resolvedSize = resolveContentSize(node: node, parentSize: parentDesignSize, subRoot: subFileRoot)
            let anchor = effectiveAnchorPoint(node: node, subRoot: subFileRoot)
            let (posSX, posSY) = positionOverride ?? resolvePosition(node: node, parentSize: parentDesignSize)
            let (scaleX, scaleY) = resolveScale(node: node)
            let rotationDeg = resolveFloat("rotation", default: 0)
            let opacity: CGFloat = {
                if let ov = context.scopedLookup(context.opacityOverrides, varName: node.varName) {
                    return CGFloat(ov)
                }
                return resolveFloat("opacity", default: 1)
            }()

            let swiftAnchorX = anchor.x
            let swiftAnchorY = 1.0 - anchor.y

            let isZeroContainer = (resolvedSize.width <= 0 && resolvedSize.height <= 0)
            let isSlotReplaced = context.scopedLookup(context.replacingSlotViews, varName: node.varName) != nil
                || (context.scopedLookup(context.slotViews, varName: node.varName) != nil && (
                    node.varName == "_playerAvatar" ||
                    node.varName == "_rewardSprite" ||
                    node.varName == "_buttonIcon" ||
                    node.varName == "_skinsButtonSprite" ||
                    node.varName == "_staticPlayButtonsContainer"
                ))

            let visual = nodeContent(designSize: resolvedSize, subFileRoot: subFileRoot)
                .frame(width: max(0, resolvedSize.width * scaleFactor),
                       height: max(0, resolvedSize.height * scaleFactor),
                       alignment: isZeroContainer ? .center : .topLeading)
                .scaleEffect(x: isSlotReplaced ? 1.0 : scaleX,
                             y: isSlotReplaced ? 1.0 : scaleY,
                             anchor: UnitPoint(x: swiftAnchorX, y: swiftAnchorY))
                .rotationEffect(.degrees(Double(rotationDeg)), anchor: UnitPoint(x: swiftAnchorX, y: swiftAnchorY))
                .opacity(Double(max(0, min(1, opacity))))

            let varTapHandler = context.scopedLookup(context.tapVarActions, varName: node.varName)
            let blockHandler: (() -> Void)? = {
                if let blockName = resolveBlockSelector() {
                    return context.scopedLookup(context.actions, varName: blockName)
                        ?? context.scopedLookup(context.actions, varName: node.varName)
                        ?? context.actions[blockName]
                }
                return nil
            }()

            let targetPos = CGPoint(
                x: (posSX + (0.5 - swiftAnchorX) * resolvedSize.width) * scaleFactor,
                y: (posSY + (0.5 - swiftAnchorY) * resolvedSize.height) * scaleFactor
            )

            if let handler = blockHandler ?? varTapHandler {
                visual
                    .contentShape(Rectangle())
                    .onTapGesture {
                        SoundManager.shared.play(.menuClick)
                        handler()
                    }
                    .position(targetPos)
            } else {
                visual.position(targetPos)
            }
        }
    }

    private func loadSubCCBFileIfNeeded() -> CCBINode? {
        guard (node.cls == "CCBFile" || node.base == "CCBFile"),
              case let .str(ccb) = node.props["ccbFile"],
              let subRoot = CCBIAtlasStore.shared.loadCCBI(named: ccb) else {
            return nil
        }
        applyOverrides(from: node, to: subRoot)
        return subRoot
    }

    private func resolveBlockSelector() -> String? {
        if case let .strInt(sel, _) = node.props["block"], !sel.isEmpty {
            return sel
        }
        return nil
    }

    private func resolveVisible() -> Bool {
        if let ov = context.scopedLookup(context.visibilityOverrides, varName: node.varName) {
            return ov
        }
        if case let .bool(v) = node.props["visible"] { return v }
        return true
    }

    private func resolveFloat(_ key: String, default def: CGFloat) -> CGFloat {
        if case let .float(f) = node.props[key] { return f }
        if case let .byte(b) = node.props[key] { return CGFloat(b) / 255.0 }
        return def
    }

    private func effectiveAnchorPoint(node: CCBINode, subRoot: CCBINode?) -> CGPoint {
        if let ao = anchorOverride { return ao }
        if let subRoot, node.props["anchorPoint"] == nil, node.props["ignoreAnchorPointForPosition"] == nil {
            return resolveAnchorPoint(node: subRoot)
        }
        return resolveAnchorPoint(node: node)
    }

    private func resolveAnchorPoint(node: CCBINode) -> CGPoint {
        if case let .bool(ign) = node.props["ignoreAnchorPointForPosition"] {
            if ign { return .zero }
        } else if node.cls == "CCLayer" || node.base == "CCLayer" ||
                  node.cls == "CCNodeColor" || node.base == "CCNodeColor" ||
                  node.cls == "CCLayerColor" || node.base == "CCLayerColor" {
            return .zero
        }
        if case let .point(x, y) = node.props["anchorPoint"] {
            return CGPoint(x: x, y: y)
        }
        let isMenuItem = node.cls.contains("MenuItem") || node.base.contains("MenuItem")
        if !isMenuItem && (
            node.cls == "CCSprite" || node.base == "CCSprite" ||
            node.cls == "MCAutoScalableSprite" || node.base == "MCAutoScalableSprite" ||
            node.cls == "MCFramedSprite" || node.base == "MCFramedSprite" ||
            node.cls == "MCLabelTTF" || node.base == "MCLabelTTF" ||
            node.cls == "CCLabelTTF" ||
            node.cls == "CCHybridMenu" || node.base == "CCHybridMenu" ||
            node.cls == "CCMenu" || node.base == "CCMenu" ||
            node.cls == "MCAlignmentNode" || node.base == "MCAlignmentNode" ||
            node.cls == "MCAlignmentNodeStatic" || node.base == "MCAlignmentNodeStatic" ||
            node.cls == "MCSpineNode" || node.base == "MCSpineNode"
        ) {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return .zero
    }

    private func resolveScale(node: CCBINode) -> (CGFloat, CGFloat) {
        if case let .scale(sx, sy, _) = node.props["scale"] {
            return (sx, sy)
        }
        return (1.0, 1.0)
    }

    private func resolvePosition(node: CCBINode, parentSize: CGSize) -> (CGFloat, CGFloat) {
        guard case let .pos(rawX, rawY, refCorner, xUnit, yUnit, _) = node.props["position"] else {
            return (0, parentSize.height)
        }
        let px: CGFloat = (xUnit == 2) ? rawX * parentSize.width : rawX
        let py: CGFloat = (yUnit == 2) ? rawY * parentSize.height : rawY
        // Convert Cocos2d ReferenceCorner -> SwiftUI top-left coordinates (design points)
        switch refCorner {
        case 0: return (px, parentSize.height - py)
        case 1: return (px, py)
        case 2: return (parentSize.width - px, py)
        case 3: return (parentSize.width - px, parentSize.height - py)
        default: return (px, parentSize.height - py)
        }
    }

    private func spriteEntryForNode(_ n: CCBINode) -> CCBISpriteEntry? {
        if case let .str(path) = n.props["spriteFrame"], !path.isEmpty {
            return CCBIAtlasStore.shared.sprite(for: path)
        }
        if case let .spriteFrame(sh, fr) = n.props["spriteFrame"], !fr.isEmpty {
            return CCBIAtlasStore.shared.sprite(for: fr, explicitSheet: sh)
        }
        return nil
    }

    private func resolveContentSize(node: CCBINode, parentSize: CGSize, subRoot: CCBINode? = nil) -> CGSize {
        if let sub = subRoot {
            if case let .size(rw, rh, wu, hu, _) = node.props["contentSize"], (rw > 0 || rh > 0) {
                return CGSize(width: evalDim(rw, unit: wu, parent: parentSize.width),
                              height: evalDim(rh, unit: hu, parent: parentSize.height))
            }
            return resolveContentSize(node: sub, parentSize: parentSize, subRoot: nil)
        }
        if (node.cls == "CCBFile" || node.base == "CCBFile"),
           case let .str(ccb) = node.props["ccbFile"],
           let sub = CCBIAtlasStore.shared.loadCCBI(named: ccb) {
            applyOverrides(from: node, to: sub)
            if case let .size(rw, rh, wu, hu, _) = node.props["contentSize"], (rw > 0 || rh > 0) {
                return CGSize(width: evalDim(rw, unit: wu, parent: parentSize.width),
                              height: evalDim(rh, unit: hu, parent: parentSize.height))
            }
            return resolveContentSize(node: sub, parentSize: parentSize, subRoot: nil)
        }
        if let entry = spriteEntryForNode(node), node.props["contentSize"] == nil {
            if (node.cls == "MCAutoScalableSprite" || node.base == "MCAutoScalableSprite" || node.varName == "_defaultImage"),
               parentSize.width > 0 && parentSize.height > 0,
               (entry.designSize.width > parentSize.width || entry.designSize.height > parentSize.height) {
                let k = min(parentSize.width / entry.designSize.width, parentSize.height / entry.designSize.height)
                return CGSize(width: entry.designSize.width * k, height: entry.designSize.height * k)
            }
            return entry.designSize
        }
        if case let .size(rw, rh, wu, hu, _) = node.props["contentSize"] {
            let isSpine = (node.cls == "MCSpineNode" || node.base == "MCSpineNode")
            let effWU = (isSpine && wu == 2 && rw > 2.0) ? 0 : wu
            let effHU = (isSpine && hu == 2 && rh > 2.0) ? 0 : hu
            var w = evalDim(rw, unit: effWU, parent: parentSize.width)
            var h = evalDim(rh, unit: effHU, parent: parentSize.height)
            if w == 0 && h == 0, let entry = spriteEntryForNode(node) {
                w = entry.designSize.width
                h = entry.designSize.height
            }
            if w > 0 || h > 0 {
                return CGSize(width: w, height: h)
            }
        }
        if (node.cls.contains("MenuItem") || node.base.contains("MenuItem")),
           case let .int(normTag) = node.props["normalNodeTag"] {
            for c in node.children {
                if case let .int(tag) = c.props["name"], tag == normTag {
                    return resolveContentSize(node: c, parentSize: parentSize, subRoot: nil)
                }
            }
        }
        if node.cls == "MCAlignmentNode" || node.base == "MCAlignmentNode" ||
           node.cls == "MCAlignmentNodeStatic" || node.base == "MCAlignmentNodeStatic" {
            let gap = alignmentSpacing(node)
            let visibleChildren = node.children.filter { childIsVisible($0) }
            if !visibleChildren.isEmpty {
                let isVertical: Bool = {
                    if case let .int(d) = node.props["direction"], d == 1 { return true }
                    return false
                }()
                if isVertical {
                    var maxW: CGFloat = 0
                    var totalH: CGFloat = 0
                    for c in visibleChildren {
                        let cs = measureTightChildSize(child: c, parentSize: parentSize)
                        maxW = max(maxW, cs.width)
                        totalH += cs.height
                    }
                    totalH += gap * CGFloat(max(0, visibleChildren.count - 1))
                    return CGSize(width: maxW, height: totalH)
                } else {
                    var totalW: CGFloat = 0
                    var maxH: CGFloat = 0
                    for c in visibleChildren {
                        let cs = measureTightChildSize(child: c, parentSize: parentSize)
                        totalW += cs.width
                        maxH = max(maxH, cs.height)
                    }
                    totalW += gap * CGFloat(max(0, visibleChildren.count - 1))
                    return CGSize(width: totalW, height: maxH)
                }
            }
        }
        if node.cls == "MCLabelTTF" || node.base == "MCLabelTTF" || node.cls == "CCLabelTTF" {
            return measureLabelDesignSize(parentDesignSize: parentSize)
        }
        return .zero
    }

    private func alignmentSpacing(_ n: CCBINode) -> CGFloat {
        if case let .fltInt(sp, _) = n.props["spacing"] { return sp }
        if case let .float(sp) = n.props["spacing"] { return sp }
        return 0
    }

    private func childIsVisible(_ c: CCBINode) -> Bool {
        if let ov = childContext.scopedLookup(childContext.visibilityOverrides, varName: c.varName) {
            return ov
        }
        if case let .bool(v) = c.props["visible"] { return v }
        return true
    }

    private func evalDim(_ v: CGFloat, unit: Int, parent: CGFloat) -> CGFloat {
        switch unit {
        case 2: return v * parent
        case 3: return max(0, parent - v)
        default: return v
        }
    }

    private func applyOverrides(from owner: CCBINode, to subRoot: CCBINode) {
        for (k, v) in owner.props where k.hasPrefix("override:") {
            let comps = k.split(separator: ":", maxSplits: 2).map(String.init)
            if comps.count == 3 {
                setPropRecursive(node: subRoot, varTarget: comps[1], propName: comps[2], val: v)
            }
        }
    }

    private func setPropRecursive(node: CCBINode, varTarget: String, propName: String, val: CCBIPropValue) {
        if node.varName == varTarget || varTarget == "Content Size" || varTarget == "Button Size" {
            if propName == "contentSize" || propName == "visible" || propName == "descriptionName" || propName == "string" || propName == "color" || propName == "outlineColor" || propName == "fontColor" {
                node.props[propName] = val
                if varTarget != "Content Size" && varTarget != "Button Size" { return }
            }
        }
        for c in node.children {
            setPropRecursive(node: c, varTarget: varTarget, propName: propName, val: val)
        }
    }

    private func measureTightChildSize(child: CCBINode, parentSize: CGSize) -> CGSize {
        if child.cls == "MCLabelTTF" || child.base == "MCLabelTTF" || child.cls == "CCLabelTTF" {
            var rawText: String = {
                if let ov = childContext.scopedLookup(childContext.labelOverrides, varName: child.varName) {
                    return ov
                }
                if case let .strBool(s, loc) = child.props["string"] {
                    return CCBIAtlasStore.shared.localize(s, localizedFlag: loc)
                }
                if case let .str(s) = child.props["string"] {
                    return CCBIAtlasStore.shared.localize(s, localizedFlag: true)
                }
                return ""
            }()
            while rawText.hasSuffix("\n") || rawText.hasSuffix("\r") { rawText.removeLast() }
            if rawText.isEmpty { return .zero }

            let fontName: String = {
                if case let .str(fn) = child.props["fontName"], !fn.isEmpty {
                    let base = URL(fileURLWithPath: fn).deletingPathExtension().lastPathComponent
                    return base.lowercased() == "lato-heavy" ? "Lato-Heavy" : base
                }
                return "OpenSans-Bold"
            }()
            let fontSizeDesign: CGFloat = {
                if case let .fltInt(sz, _) = child.props["fontSize"] { return sz }
                if case let .float(sz) = child.props["fontSize"] { return sz }
                return 14.0
            }()
            var reqW: CGFloat = 0
            if case let .size(rw, _, wu, _, _) = child.props["requestedDimensions"] {
                let w = evalDim(rw, unit: wu, parent: parentSize.width)
                if w > 1.0 { reqW = w }
            }
            let uiFont = UIFont(name: fontName, size: max(7, fontSizeDesign))
                ?? UIFont.systemFont(ofSize: max(7, fontSizeDesign), weight: .bold)
            let rect = (rawText as NSString).boundingRect(
                with: CGSize(width: reqW > 0 ? reqW : 10000, height: 10000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: uiFont],
                context: nil
            )
            let w = reqW > 0 ? min(reqW, ceil(rect.width) + 2) : (ceil(rect.width) + 2)
            return CGSize(width: w, height: ceil(rect.height) + 2)
        }
        return resolveContentSize(node: child, parentSize: parentSize, subRoot: nil)
    }

    private func filteredNormalChildren(designSize: CGSize) -> [(node: CCBINode, posOverride: (CGFloat, CGFloat)?, anchorOverride: CGPoint?)] {
        if node.cls == "MCAlignmentNode" || node.base == "MCAlignmentNode" ||
           node.cls == "MCAlignmentNodeStatic" || node.base == "MCAlignmentNodeStatic" {
            let gap = alignmentSpacing(node)
            let visibleChildren = node.children.filter { childIsVisible($0) }
            guard !visibleChildren.isEmpty else { return [] }
            let sizes = visibleChildren.map { measureTightChildSize(child: $0, parentSize: designSize) }
            var out: [(CCBINode, (CGFloat, CGFloat)?, CGPoint?)] = []
            let isVertical: Bool = {
                if case let .int(d) = node.props["direction"], d == 1 { return true }
                return false
            }()
            if isVertical {
                let totalH = sizes.reduce(CGFloat(0)) { $0 + $1.height } + gap * CGFloat(max(0, visibleChildren.count - 1))
                var curY = max(CGFloat(0), (designSize.height - totalH) * 0.5)
                for (c, cs) in zip(visibleChildren, sizes) {
                    out.append((c, (designSize.width * 0.5, curY + cs.height * 0.5), CGPoint(x: 0.5, y: 0.5)))
                    curY += cs.height + gap
                }
            } else {
                let totalW = sizes.reduce(CGFloat(0)) { $0 + $1.width } + gap * CGFloat(max(0, visibleChildren.count - 1))
                var curX = max(CGFloat(0), (designSize.width - totalW) * 0.5)
                for (c, cs) in zip(visibleChildren, sizes) {
                    out.append((c, (curX + cs.width * 0.5, designSize.height * 0.5), CGPoint(x: 0.5, y: 0.5)))
                    curX += cs.width + gap
                }
            }
            return out
        }

        let normTag: Int? = {
            if case let .int(t) = node.props["normalNodeTag"] { return t }
            return nil
        }()
        let selTag: Int? = {
            if (node.cls.contains("MenuItem") || node.base.contains("MenuItem")),
               case let .int(t) = node.props["selectedNodeTag"], t != normTag {
                return t
            }
            return nil
        }()
        let disTag: Int? = {
            if (node.cls.contains("MenuItem") || node.base.contains("MenuItem")),
               case let .int(t) = node.props["disabledNodeTag"], t != normTag {
                return t
            }
            return nil
        }()

        return node.children.compactMap { c in
            if case let .int(tag) = c.props["name"], tag == selTag || tag == disTag {
                return nil
            }
            return (c, nil, nil)
        }
    }

    @ViewBuilder
    private func nodeContent(designSize: CGSize, subFileRoot: CCBINode?) -> some View {
        let wPx = max(0, designSize.width * scaleFactor)
        let hPx = max(0, designSize.height * scaleFactor)
        let replacingSlot = context.scopedLookup(context.replacingSlotViews, varName: node.varName)
        let customSlot = replacingSlot ?? context.scopedLookup(context.slotViews, varName: node.varName)
        let suppressDefaultsForSlot = (replacingSlot != nil) || (customSlot != nil && (
            node.varName == "_playerAvatar" ||
            node.varName == "_rewardSprite" ||
            node.varName == "_buttonIcon" ||
            node.varName == "_skinsButtonSprite" ||
            node.varName == "_staticPlayButtonsContainer"
        ))

        ZStack(alignment: (wPx == 0 && hPx == 0) ? .center : .topLeading) {
            if suppressDefaultsForSlot, let customSlot {
                customSlot.frame(width: wPx > 0 ? wPx : nil, height: hPx > 0 ? hPx : nil)
            } else if let subRoot = subFileRoot {
                let _ = {
                    subRoot.props["position"] = .pos(x: 0, y: 0, refCorner: 1, xUnit: 0, yUnit: 0, c: 0)
                    subRoot.props["anchorPoint"] = .point(0, 1)
                    subRoot.props["ignoreAnchorPointForPosition"] = .bool(false)
                    if designSize.width > 0 || designSize.height > 0 {
                        subRoot.props["contentSize"] = .size(w: designSize.width, h: designSize.height, wUnit: 0, hUnit: 0, c: 0)
                    }
                }()
                CCBINodeRenderer(
                    node: subRoot,
                    parentDesignSize: designSize,
                    scaleFactor: scaleFactor,
                    context: childContext
                )
            } else {
                // Background / Visual node body
                if node.cls == "CCNodeColor" || node.base == "CCNodeColor" {
                    if case let .rgba(r, g, b, a) = node.props["color"] {
                        let nr = r > 1.0 ? r / 255.0 : r
                        let ng = g > 1.0 ? g / 255.0 : g
                        let nb = b > 1.0 ? b / 255.0 : b
                        let na = a > 1.0 ? a / 255.0 : a
                        Rectangle().fill(Color(red: nr, green: ng, blue: nb, opacity: na))
                    } else {
                        Rectangle().fill(Color.white)
                    }
                } else if (node.cls == "MCFramedSprite" || node.base == "MCFramedSprite"),
                          case let .str(desc) = node.props["descriptionName"],
                          let mcfs = CCBIAtlasStore.shared.mcfs(for: desc) {
                    let pair = mcfs.uiImageAndInsets(forUIScale: scaleFactor)
                    Image(uiImage: pair.0)
                        .resizable(capInsets: pair.1, resizingMode: .stretch)
                        .frame(width: wPx, height: hPx)
                } else if let sp = spriteEntryForNode(node) {
                    let img = Image(uiImage: sp.image).resizable()
                    if node.varName == "_background" {
                        img.scaledToFill().frame(width: wPx, height: hPx).clipped()
                    } else if node.cls == "MCAutoScalableSprite" || node.base == "MCAutoScalableSprite" {
                        img.scaledToFit().frame(width: wPx > 0 ? wPx : nil, height: hPx > 0 ? hPx : nil)
                    } else {
                        img.frame(width: wPx, height: hPx)
                    }
                } else if node.cls == "MCLabelTTF" || node.base == "MCLabelTTF" || node.cls == "CCLabelTTF" {
                    buildLabelView(designSize: designSize)
                }

                // Child nodes
                ForEach(Array(filteredNormalChildren(designSize: designSize).enumerated()), id: \.element.node.id) { _, entry in
                    CCBINodeRenderer(
                        node: entry.node,
                        parentDesignSize: designSize,
                        scaleFactor: scaleFactor,
                        context: childContext,
                        positionOverride: entry.posOverride,
                        anchorOverride: entry.anchorOverride
                    )
                }
            }

            if !suppressDefaultsForSlot, let customSlot {
                customSlot.frame(width: wPx > 0 ? wPx : nil, height: hPx > 0 ? hPx : nil)
            }
        }
    }

    private func resolveLabelTextAndFont() -> (text: String, fontName: String, fontSizeDesign: CGFloat) {
        var rawKey: String = {
            if let ov = context.scopedLookup(context.labelOverrides, varName: node.varName) {
                return ov
            }
            if case let .strBool(s, loc) = node.props["string"] {
                return CCBIAtlasStore.shared.localize(s, localizedFlag: loc)
            }
            if case let .str(s) = node.props["string"] {
                return CCBIAtlasStore.shared.localize(s, localizedFlag: true)
            }
            return ""
        }()
        while rawKey.hasSuffix("\n") || rawKey.hasSuffix("\r") {
            rawKey.removeLast()
        }

        let fontName: String = {
            if case let .str(fn) = node.props["fontName"], !fn.isEmpty {
                let base = URL(fileURLWithPath: fn).deletingPathExtension().lastPathComponent
                if base.lowercased() == "lato-heavy" { return "Lato-Heavy" }
                return base
            }
            return "OpenSans-Bold"
        }()

        let fontSizeDesign: CGFloat = {
            if case let .fltInt(sz, _) = node.props["fontSize"] { return sz }
            if case let .float(sz) = node.props["fontSize"] { return sz }
            return 14.0
        }()

        return (rawKey, fontName, fontSizeDesign)
    }

    private func requestedLabelDimensions(parentDesignSize: CGSize) -> CGSize {
        if case let .size(rw, rh, wu, hu, _) = node.props["requestedDimensions"] {
            let w = evalDim(rw, unit: wu, parent: parentDesignSize.width)
            let h = evalDim(rh, unit: hu, parent: parentDesignSize.height)
            return CGSize(width: w > 1.0 ? w : 0, height: h > 1.0 ? h : 0)
        }
        return .zero
    }

    private func isSingleLineLabel() -> Bool {
        if case let .bool(sl) = node.props["forceSingleLine"] { return sl }
        return false
    }

    private func measureLabelDesignSize(parentDesignSize: CGSize) -> CGSize {
        let spec = resolveLabelTextAndFont()
        guard !spec.text.isEmpty else { return .zero }
        let uiFont = UIFont(name: spec.fontName, size: max(7, spec.fontSizeDesign))
            ?? UIFont.systemFont(ofSize: max(7, spec.fontSizeDesign), weight: .bold)
        let req = requestedLabelDimensions(parentDesignSize: parentDesignSize)
        let singleLine = isSingleLineLabel()
        if req.width > 1.0 && req.height > 1.0 && !singleLine {
            return req
        }
        let boundW: CGFloat = (singleLine && req.height <= 1.0) ? 10000 : (req.width > 0 ? req.width : 10000)
        let rect = (spec.text as NSString).boundingRect(
            with: CGSize(width: boundW, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uiFont],
            context: nil
        )
        if singleLine && req.height <= 1.0 {
            return CGSize(width: ceil(rect.width) + 2, height: ceil(rect.height) + 2)
        }
        let w = req.width > 0 ? min(req.width, ceil(rect.width) + 2) : (ceil(rect.width) + 2)
        return CGSize(width: w, height: ceil(rect.height) + 2)
    }

    private func normalizedRGBA(_ prop: CCBIPropValue?) -> (r: Double, g: Double, b: Double, a: Double) {
        guard case let .rgba(r, g, b, a) = prop else { return (1, 1, 1, 1) }
        let nr = r > 1.0 ? r / 255.0 : r
        let ng = g > 1.0 ? g / 255.0 : g
        let nb = b > 1.0 ? b / 255.0 : b
        let na = a > 1.0 ? a / 255.0 : a
        return (nr, ng, nb, na)
    }

    private func buildLabelView(designSize: CGSize) -> some View {
        let spec = resolveLabelTextAndFont()
        let fc = normalizedRGBA(node.props["fontColor"])
        let cc = normalizedRGBA(node.props["color"])
        let baseColor = Color(red: fc.r * cc.r, green: fc.g * cc.g, blue: fc.b * cc.b, opacity: fc.a * cc.a)
        let textColor = context.scopedLookup(context.labelColorOverrides, varName: node.varName) ?? baseColor

        var outlineColor: Color? = nil
        var outlinePx: CGFloat = 0
        if case let .bool(fx) = node.props["useFontEffects"], fx,
           let ocProp = node.props["outlineColor"] {
            let oc = normalizedRGBA(ocProp)
            outlineColor = Color(red: oc.r, green: oc.g, blue: oc.b, opacity: oc.a)
            let rawW: CGFloat = {
                if case let .fltInt(w, _) = node.props["outlineWidth"] { return w }
                if case let .float(w) = node.props["outlineWidth"] { return w }
                return 1.2
            }()
            outlinePx = max(0.8, rawW * scaleFactor * 0.85)
        }

        let align: TextAlignment = {
            if case let .int(h) = node.props["horizontalAlignment"] {
                if h == 0 { return .leading }
                if h == 2 { return .trailing }
                return .center
            }
            let ap = resolveAnchorPoint(node: node)
            if ap.x < 0.25 { return .leading }
            if ap.x > 0.75 { return .trailing }
            return .center
        }()

        let hAlign: HorizontalAlignment = {
            switch align {
            case .leading: return .leading
            case .trailing: return .trailing
            default: return .center
            }
        }()

        let vAlign: VerticalAlignment = {
            if case let .int(v) = node.props["verticalAlignment"] {
                if v == 0 { return .top }
                if v == 2 { return .bottom }
            }
            return .center
        }()

        let req = requestedLabelDimensions(parentDesignSize: parentDesignSize)
        let hasExplicitNewline = spec.text.contains("\n")
        let singleLine = !hasExplicitNewline && (isSingleLineLabel() || (req.width > 0 && req.height > 0 && spec.text.count <= 24))
        let autoShrink = (req.width > 1.0 && req.height > 1.0) || singleLine
        let constrainHeight = (req.width > 1.0 && req.height > 1.0 && !singleLine)
        return CCBILabelView(
            text: spec.text,
            fontName: spec.fontName,
            fontSize: max(7, spec.fontSizeDesign * scaleFactor),
            textColor: textColor,
            outlineColor: outlineColor,
            outlineWidth: outlinePx,
            alignment: align,
            constrainWidth: (req.width > 0 && !singleLine) || designSize.width > 0,
            constrainHeight: constrainHeight,
            singleLine: singleLine,
            autoShrink: autoShrink
        )
        .frame(
            width: designSize.width > 0 ? designSize.width * scaleFactor : nil,
            height: designSize.height > 0 ? designSize.height * scaleFactor : nil,
            alignment: Alignment(horizontal: hAlign, vertical: vAlign)
        )
    }
}

private struct CCBILabelView: View {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: Color
    let outlineColor: Color?
    let outlineWidth: CGFloat
    let alignment: TextAlignment
    let constrainWidth: Bool
    var constrainHeight: Bool = false
    var singleLine: Bool = false
    var autoShrink: Bool = false

    var body: some View {
        let base = Text(text)
            .font(.custom(fontName, size: fontSize))
            .multilineTextAlignment(alignment)
            .lineLimit(singleLine ? 1 : nil)
            .minimumScaleFactor(autoShrink ? 0.45 : 1.0)
            .allowsTightening(autoShrink)
            .fixedSize(horizontal: !constrainWidth, vertical: !constrainHeight)

        if let oc = outlineColor, outlineWidth > 0 {
            let d = outlineWidth
            ZStack {
                base.foregroundColor(oc).offset(x: -d, y: 0)
                base.foregroundColor(oc).offset(x: d, y: 0)
                base.foregroundColor(oc).offset(x: 0, y: -d)
                base.foregroundColor(oc).offset(x: 0, y: d)
                base.foregroundColor(oc).offset(x: -d * 0.7, y: -d * 0.7)
                base.foregroundColor(oc).offset(x: d * 0.7, y: -d * 0.7)
                base.foregroundColor(oc).offset(x: -d * 0.7, y: d * 0.7)
                base.foregroundColor(oc).offset(x: d * 0.7, y: d * 0.7)
                base.foregroundColor(textColor)
            }
        } else {
            base.foregroundColor(textColor)
        }
    }
}
