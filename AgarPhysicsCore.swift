import Foundation
import CoreGraphics

/// Clean-room port of `SoftBodyCellView` deformation + `GameArena` physics rules from `agar.io`.
enum AgarPhysicsCore {

    // MARK: - Cell Speed & Movement (`GameArena` exact formula)

    @inline(__always)
    static func speed(forSolidRadius solidRadius: CGFloat) -> CGFloat {
        let r = Double(max(solidRadius, 10.0))
        return CGFloat(OriginalGameplay.velocityMultiplier * pow(r, OriginalGameplay.inputFactorPow) * OriginalGameplay.baseVelocityCompensation)
    }

    @inline(__always)
    static func mergeDuration(forNewCellMass mass: CGFloat) -> Double {
        return 30.0 + Double(mass) * 0.02
    }

    /// Wall squash clamp (`0x10004C888`): `[0.4 * r, worldSize - 0.4 * r]`.
    @inline(__always)
    static func clampSquashPosition(_ pos: CGPoint, radius: CGFloat, worldSize: CGFloat) -> CGPoint {
        let margin = OriginalGameplay.percentageOfCellToSquash * radius
        let maxPos = max(margin, worldSize - margin)
        return CGPoint(x: min(maxPos, max(margin, pos.x)), y: min(maxPos, max(margin, pos.y)))
    }

    @inline(__always)
    static func clampSquashCoordinate(_ value: Double, radius: Double, worldSize: Double) -> Double {
        let margin = Double(OriginalGameplay.percentageOfCellToSquash) * radius
        let maxPos = max(margin, worldSize - margin)
        return min(maxPos, max(margin, value))
    }

    /// Recursive binary-split mass partition (`sub_10004F308` / `0x10004e404`) up to `maxSplits` (cap 16).
    static func calculateVirusSplitMass(mass: Double, maxSplits: Int) -> [Double] {
        guard mass > 0, maxSplits >= 2 else { return [mass] }
        let cap = min(maxSplits, 16)
        let minSplitMass = OriginalGameplay.minSplitMass
        var pieces: [Double] = [mass]
        while pieces.count < cap {
            guard let maxIdx = pieces.indices.max(by: { pieces[$0] < pieces[$1] }),
                  pieces[maxIdx] >= minSplitMass else { break }
            let half = pieces[maxIdx] * 0.5
            pieces[maxIdx] = half
            pieces.append(half)
        }
        pieces.sort(by: >)
        return pieces
    }

    static func calculateVirusSplitMass(mass: CGFloat, maxSplits: Int) -> [CGFloat] {
        calculateVirusSplitMass(mass: Double(mass), maxSplits: maxSplits).map { CGFloat($0) }
    }

    /// Computes `agar.io.bin` inputDistance & world cursor reach (`inputDistance / arenaZoom`).
    static func worldCursorReach(cells: [PlayerCell], viewportSize: CGSize) -> (inputDist: CGFloat, worldReach: CGFloat) {
        let totalRadius = cells.reduce(CGFloat(0)) { $0 + $1.cachedSolidRadius }
        let inputDist = OriginalGameplay.inputDistance(for: viewportSize)
        let arenaZoom = OriginalGameplay.arenaZoomForInput(
            totalRadius: max(totalRadius, CGFloat(OriginalGameplay.baseRadius)),
            cellCount: max(cells.count, 1),
            viewportSize: viewportSize
        )
        return (inputDist, inputDist / max(arenaZoom, 0.05))
    }

    /// Computes world cursor along `directionNorm` at `worldReach` (`0x10004ff70`).
    static func steerTarget(
        flockCenter: CGPoint,
        directionNorm: CGSize,
        cells: [PlayerCell],
        viewportSize: CGSize
    ) -> CGPoint? {
        let mag = hypot(directionNorm.width, directionNorm.height)
        guard mag > 0.001 else { return nil }
        let reach = worldCursorReach(cells: cells, viewportSize: viewportSize).worldReach
        return CGPoint(
            x: flockCenter.x + directionNorm.width * reach,
            y: flockCenter.y + directionNorm.height * reach
        )
    }

    // MARK: - Offline Adapted Mass Decay (`Offline Mode - Settings`)

    static func applyOfflineMassDecay(mass: CGFloat, isPlayer: Bool, dt: CGFloat) -> CGFloat {
        // `sub_10004B844` + `sub_10004BFC8`: linear rate interpolation over
        // [baseRadiusForAdaptedDecay (200), maxCellRadius (1500)] with radiusDecayMultiplier = 50.
        let r = Double(max(mass, 1.0)).squareRoot() * 10.0
        guard r > 200.0 else { return mass }
        let t = max(0.0, r - 200.0) / (1500.0 - 200.0)
        let maxRate = isPlayer ? 0.99922 : 1.0
        let rate = 0.99998 + (maxRate - 0.99998) * t
        let factor = pow(rate, 2.0 * 50.0 * Double(dt))
        return max(CGFloat(10.0), mass * CGFloat(factor))
    }

    // MARK: - Pairwise Eat / Merge / Self-Collision (`Arena_canEat` & `Arena_selfCollision`)

    @inline(__always)
    static func canEat(eaterMass: CGFloat, eaterRadius: CGFloat, victimMass: CGFloat, dx: CGFloat, dy: CGFloat) -> Bool {
        guard eaterMass > victimMass * CGFloat(OriginalGameplay.eatMassRatio), eaterRadius > 0 else { return false }
        if dx < -eaterRadius || dx > eaterRadius || dy < -eaterRadius || dy > eaterRadius { return false }
        return (dx * dx + dy * dy) <= (eaterRadius * eaterRadius)
    }

    @inline(__always)
    static func canMerge(bigRadius: CGFloat, dx: CGFloat, dy: CGFloat) -> Bool {
        guard bigRadius > 0 else { return false }
        if dx < -bigRadius || dx > bigRadius || dy < -bigRadius || dy > bigRadius { return false }
        return (dx * dx + dy * dy) <= (bigRadius * bigRadius)
    }

    /// `Arena_selfCollision` (`0x10004e5e0` + `0x10004bf14`): 2-pass simultaneous Jacobi
    /// accumulation using `cachedSolidRadius` + wall squash clamp `[0.4 * r, worldSize - 0.4 * r]`.
    static func resolveSelfCollisions(cells: inout [PlayerCell], worldSize: CGFloat = OriginalGameplay.offlineArenaSideLength) {
        guard cells.count > 1 else { return }
        var groups: [UUID: [Int]] = [:]
        var radii = [CGFloat](repeating: 0, count: cells.count)
        groups.reserveCapacity(min(cells.count, 64))
        for i in cells.indices {
            groups[cells[i].ownerID, default: []].append(i)
            radii[i] = cells[i].cachedSolidRadius
        }

        let squashFactor = OriginalGameplay.percentageOfCellToSquash
        for (_, indices) in groups {
            let groupCount = indices.count
            guard groupCount > 1 else { continue }
            var pushX = [CGFloat](repeating: 0, count: groupCount)
            var pushY = [CGFloat](repeating: 0, count: groupCount)

            for _ in 0..<2 {
                var anyOverlap = false
                for i in 0..<groupCount {
                    pushX[i] = 0
                    pushY[i] = 0
                }
                for i in 0..<(groupCount - 1) {
                    let idxA = indices[i]
                    if cells[idxA].isMerging { continue }
                    let rA = radii[idxA]
                    for j in (i + 1)..<groupCount {
                        let idxB = indices[j]
                        if cells[idxB].isMerging { continue }
                        guard cells[idxA].mergeTimer > 0 || cells[idxB].mergeTimer > 0 else { continue }
                        if cells[idxA].immuneToCellID == cells[idxB].id || cells[idxB].immuneToCellID == cells[idxA].id {
                            continue
                        }

                        let rB = radii[idxB]
                        let totalRadius = rA + rB
                        let dx = cells[idxA].position.x - cells[idxB].position.x
                        if dx < -totalRadius || dx > totalRadius { continue }
                        let dy = cells[idxA].position.y - cells[idxB].position.y
                        if dy < -totalRadius || dy > totalRadius { continue }

                        let distSq = dx * dx + dy * dy
                        guard distSq < (totalRadius * totalRadius) else { continue }

                        var dist = sqrt(distSq)
                        var nx: CGFloat
                        var ny: CGFloat
                        if dist < 0.0001 {
                            let theta = Double((idxA * 73 + idxB * 137) % 360) * .pi / 180.0
                            nx = CGFloat(cos(theta))
                            ny = CGFloat(sin(theta))
                            dist = 0.1
                        } else {
                            nx = dx / dist
                            ny = dy / dist
                        }

                        let overlap = totalRadius - dist
                        let rA2 = rA * rA
                        let rB2 = rB * rB
                        let denom = rA2 + rB2
                        guard denom > 0 else { continue }
                        let pushA = overlap * (rB2 / denom)
                        let pushB = overlap * (rA2 / denom)

                        pushX[i] += nx * pushA
                        pushY[i] += ny * pushA
                        pushX[j] -= nx * pushB
                        pushY[j] -= ny * pushB
                        anyOverlap = true
                    }
                }
                if !anyOverlap { break }
                for i in 0..<groupCount {
                    let idx = indices[i]
                    if pushX[i] != 0 || pushY[i] != 0 {
                        let minPos = squashFactor * radii[idx]
                        let maxPos = max(minPos, worldSize - minPos)
                        cells[idx].position.x = min(maxPos, max(minPos, cells[idx].position.x + pushX[i]))
                        cells[idx].position.y = min(maxPos, max(minPos, cells[idx].position.y + pushY[i]))
                    }
                }
            }
        }
    }

    // MARK: - Soft-Body Vertex Spring Solver (`SoftBodyCellView::calcDisplacements` & `updateCellRadius`)

    private static func resampleRing(_ values: [CGFloat], to count: Int) -> [CGFloat] {
        let oldCount = values.count
        guard oldCount > 0, count > 0 else {
            return [CGFloat](repeating: 0, count: max(0, count))
        }
        if oldCount == count { return values }
        var out = [CGFloat](repeating: 0, count: count)
        let ratio = CGFloat(oldCount) / CGFloat(count)
        for k in 0..<count {
            let src = CGFloat(k) * ratio
            let i0 = Int(floor(src)) % oldCount
            let i1 = (i0 + 1) % oldCount
            let frac = src - floor(src)
            out[k] = values[i0] + (values[i1] - values[i0]) * frac
        }
        return out
    }

    static func deformVertices(
        cells: inout [PlayerCell],
        neighborsByOwner: Bool,
        visibleWorldRect: CGRect,
        worldSize: CGFloat,
        dt: CGFloat,
        cocosZoom: CGFloat = 1.0,
        massManager: EjectedMassManager? = nil
    ) {
        let count = cells.count
        guard count > 0 else { return }
        let stepScale = min(CGFloat(1.5), max(CGFloat(0.25), dt * 60.0))
        let wobbleDecay = pow(CGFloat(0.7), stepScale)
        let visRect = visibleWorldRect

        for i in cells.indices {
            let pos = cells[i].position
            let visualRadius = cells[i].cachedVisualRadius

            if !visRect.isEmpty && !visRect.intersects(
                CGRect(x: pos.x - visualRadius, y: pos.y - visualRadius, width: visualRadius * 2, height: visualRadius * 2)
            ) {
                if !cells[i].deformedVertices.isEmpty {
                    cells[i].deformedVertices.removeAll(keepingCapacity: false)
                    cells[i].vertexDisplacements.removeAll(keepingCapacity: false)
                    cells[i].vertexRadii.removeAll(keepingCapacity: false)
                }
                continue
            }

            let cellVertexCount = max(24, min(72, (Int(floor(max(1.0, visualRadius * cocosZoom))) & ~1)))
            let trig = SoftBodyTrigCache.get(count: cellVertexCount)

            if cells[i].deformedVertices.count != cellVertexCount ||
               cells[i].vertexDisplacements.count != cellVertexCount ||
               cells[i].vertexRadii.count != cellVertexCount {
                let prevDisp = cells[i].vertexDisplacements
                let prevRadii = cells[i].vertexRadii
                cells[i].deformedVertices = [CGPoint](repeating: .zero, count: cellVertexCount)
                if prevDisp.count >= 8 && prevRadii.count == prevDisp.count {
                    // Resample existing spring state instead of snapping back to a circle when zoom/radius crosses an even int.
                    cells[i].vertexDisplacements = resampleRing(prevDisp, to: cellVertexCount)
                    cells[i].vertexRadii = resampleRing(prevRadii, to: cellVertexCount)
                } else {
                    cells[i].vertexDisplacements = [CGFloat](repeating: 0, count: cellVertexCount)
                    cells[i].vertexRadii = [CGFloat](repeating: visualRadius, count: cellVertexCount)
                }
                for k in 0..<cellVertexCount {
                    let r = cells[i].vertexRadii[k]
                    cells[i].deformedVertices[k] = CGPoint(x: trig[k].cos * r, y: trig[k].sin * r)
                }
                if prevDisp.count < 8 { continue }
            }

            let nearWall = (pos.x - visualRadius) < 0 || (pos.y - visualRadius) < 0
                || (pos.x + visualRadius) > worldSize || (pos.y + visualRadius) > worldSize

            var nearbyMass: [EjectedMass] = []
            var siblingNeighbors: [(pos: CGPoint, radius: CGFloat)] = []
            if let mm = massManager {
                let sr = visualRadius + 100
                nearbyMass = mm.getLimitedVisibleMassesArray(
                    in: CGRect(x: pos.x - sr, y: pos.y - sr, width: sr * 2, height: sr * 2),
                    limit: 12
                )
            }
            if neighborsByOwner {
                let owner = cells[i].ownerID
                for j in cells.indices where j != i && !cells[j].isMerging {
                    let jr = cells[j].cachedSolidRadius
                    if cells[j].ownerID != owner && jr > visualRadius { continue }
                    let sumR = visualRadius + jr + 6.0
                    let ndx = pos.x - cells[j].position.x
                    let ndy = pos.y - cells[j].position.y
                    if ndx * ndx + ndy * ndy < sumR * sumR {
                        siblingNeighbors.append((cells[j].position, jr))
                    }
                }
            }

            // 1. SoftBodyCellView::calcDisplacements (`0x1003a5c34`): random jelly impulse + 0.7 damping + 3-tap smooth
            var rawDisp = cells[i].vertexDisplacements
            let noiseAmp: CGFloat = visualRadius > 18.0 ? 0.5 : 0.15
            for k in 0..<cellVertexCount {
                let jitter = (CGFloat.random(in: -0.5...0.5) * noiseAmp) * stepScale
                let next = min(CGFloat(10.0), max(CGFloat(-10.0), rawDisp[k] + jitter)) * wobbleDecay
                rawDisp[k] = next
            }
            var disp = rawDisp
            for k in 0..<cellVertexCount {
                let prev = rawDisp[(k - 1 + cellVertexCount) % cellVertexCount]
                let nxt = rawDisp[(k + 1) % cellVertexCount]
                disp[k] = (8.0 * rawDisp[k] + prev + nxt) / 10.0
            }

            // 2. Boundary & cell-to-cell squash when radius > 18
            let massRad = OriginalGameplay.shotMassBaseRadiusCGFloat
            let minR = visualRadius * 0.45
            var radialTarget = [CGFloat](repeating: visualRadius, count: cellVertexCount)
            if visualRadius > 18.0 && (nearWall || !nearbyMass.isEmpty || !siblingNeighbors.isEmpty) {
                for k in 0..<cellVertexCount {
                    let c = trig[k].cos
                    let s = trig[k].sin
                    let baseR = max(minR, cells[i].vertexRadii[k] + disp[k])
                    let wx = pos.x + c * baseR
                    let wy = pos.y + s * baseR
                    var overlap: CGFloat = 0

                    for m in nearbyMass {
                        let dx = wx - m.position.x
                        let dy = wy - m.position.y
                        let d2 = dx * dx + dy * dy
                        if d2 < massRad * massRad {
                            overlap = max(overlap, massRad - sqrt(d2))
                        }
                    }
                    for nb in siblingNeighbors {
                        let dx = wx - nb.pos.x
                        let dy = wy - nb.pos.y
                        let d2 = dx * dx + dy * dy
                        if d2 < nb.radius * nb.radius {
                            overlap = max(overlap, (nb.radius - sqrt(d2)) * 0.55)
                        }
                    }
                    if nearWall {
                        if wx < 0 { overlap = max(overlap, -wx) }
                        else if wx > worldSize { overlap = max(overlap, wx - worldSize) }
                        if wy < 0 { overlap = max(overlap, -wy) }
                        else if wy > worldSize { overlap = max(overlap, wy - worldSize) }
                    }
                    if overlap > 0 {
                        let push = min(1.0, overlap / 6.0 + 0.5)
                        disp[k] = (disp[k] > 0 ? -1.0 : (disp[k] - 1.0)) * push
                        radialTarget[k] = max(minR, baseR - overlap * 0.8)
                    }
                }
            }
            cells[i].vertexDisplacements = disp

            // 3. SoftBodyCellView::updateCellRadius (`0x1003a5a0c`): 3-tap radial spring
            let prevR = cells[i].vertexRadii
            var nextR = prevR
            let blend = min(1.0, stepScale)
            for k in 0..<cellVertexCount {
                let candidate = max(minR, prevR[k] + disp[k])
                let tgt = min(visualRadius * 1.12, min(radialTarget[k], candidate))
                let driven = (12.0 * tgt + visualRadius) / 13.0
                let pPrev = prevR[(k - 1 + cellVertexCount) % cellVertexCount]
                let pNext = prevR[(k + 1) % cellVertexCount]
                let smoothed = (8.0 * driven + pPrev + pNext) / 10.0
                nextR[k] = prevR[k] + (smoothed - prevR[k]) * blend
                cells[i].deformedVertices[k] = CGPoint(x: trig[k].cos * nextR[k], y: trig[k].sin * nextR[k])
            }
            cells[i].vertexRadii = nextR
        }
    }

    static func deformViruses(
        viruses: inout [Virus],
        visibleWorldRect: CGRect,
        worldSize: CGFloat,
        dt: CGFloat,
        cocosZoom: CGFloat = 1.0,
        massManager: EjectedMassManager? = nil
    ) {
        guard !viruses.isEmpty else { return }
        let stepScale = min(CGFloat(1.5), max(CGFloat(0.25), dt * 60.0))
        let wobbleDecay = pow(CGFloat(0.7), stepScale)
        let visRect = visibleWorldRect
        let massRad = OriginalGameplay.shotMassBaseRadiusCGFloat

        for i in viruses.indices {
            let pos = viruses[i].position
            let visualRadius = viruses[i].radius

            if !visRect.isEmpty && !visRect.intersects(
                CGRect(x: pos.x - visualRadius - 12, y: pos.y - visualRadius - 12,
                       width: visualRadius * 2 + 24, height: visualRadius * 2 + 24)
            ) {
                if !viruses[i].deformedVertices.isEmpty {
                    viruses[i].deformedVertices.removeAll(keepingCapacity: false)
                    viruses[i].vertexDisplacements.removeAll(keepingCapacity: false)
                    viruses[i].vertexRadii.removeAll(keepingCapacity: false)
                }
                continue
            }

            let vCount = min(120, max(30, (2 * Int(floor(max(1.0, visualRadius * cocosZoom)))) & ~1))
            let trig = SoftBodyTrigCache.get(count: vCount)

            if viruses[i].deformedVertices.count != vCount ||
               viruses[i].vertexDisplacements.count != vCount ||
               viruses[i].vertexRadii.count != vCount {
                let prevDisp = viruses[i].vertexDisplacements
                let prevRadii = viruses[i].vertexRadii
                viruses[i].deformedVertices = [CGPoint](repeating: .zero, count: vCount)
                if prevDisp.count >= 8 && prevRadii.count == prevDisp.count {
                    viruses[i].vertexDisplacements = resampleRing(prevDisp, to: vCount)
                    viruses[i].vertexRadii = resampleRing(prevRadii, to: vCount)
                } else {
                    viruses[i].vertexDisplacements = [CGFloat](repeating: 0, count: vCount)
                    viruses[i].vertexRadii = [CGFloat](repeating: visualRadius, count: vCount)
                }
                for k in 0..<vCount {
                    let r = viruses[i].vertexRadii[k]
                    viruses[i].deformedVertices[k] = CGPoint(x: trig[k].cos * r, y: trig[k].sin * r)
                }
                if prevDisp.count < 8 { continue }
            }

            var rawDisp = viruses[i].vertexDisplacements
            for k in 0..<vCount {
                let jitter = (CGFloat.random(in: -0.5...0.5) * 0.45) * stepScale
                rawDisp[k] = min(CGFloat(10.0), max(CGFloat(-10.0), rawDisp[k] + jitter)) * wobbleDecay
            }
            var disp = rawDisp
            for k in 0..<vCount {
                let prev = rawDisp[(k - 1 + vCount) % vCount]
                let nxt = rawDisp[(k + 1) % vCount]
                disp[k] = (8.0 * rawDisp[k] + prev + nxt) / 10.0
            }

            let nearWall = (pos.x - visualRadius) < 0 || (pos.y - visualRadius) < 0
                || (pos.x + visualRadius) > worldSize || (pos.y + visualRadius) > worldSize
            var nearbyMass: [EjectedMass] = []
            if let mm = massManager {
                let sr = visualRadius + 100
                nearbyMass = mm.getLimitedVisibleMassesArray(
                    in: CGRect(x: pos.x - sr, y: pos.y - sr, width: sr * 2, height: sr * 2),
                    limit: 12
                )
            }

            let minR = visualRadius * 0.45
            var radialTarget = [CGFloat](repeating: visualRadius, count: vCount)
            if nearWall || !nearbyMass.isEmpty {
                for k in 0..<vCount {
                    let baseR = max(minR, viruses[i].vertexRadii[k] + disp[k])
                    let wx = pos.x + trig[k].cos * baseR
                    let wy = pos.y + trig[k].sin * baseR
                    var overlap: CGFloat = 0
                    for m in nearbyMass {
                        let dx = wx - m.position.x
                        let dy = wy - m.position.y
                        let d2 = dx * dx + dy * dy
                        if d2 < massRad * massRad { overlap = max(overlap, massRad - sqrt(d2)) }
                    }
                    if nearWall {
                        if wx < 0 { overlap = max(overlap, -wx) }
                        else if wx > worldSize { overlap = max(overlap, wx - worldSize) }
                        if wy < 0 { overlap = max(overlap, -wy) }
                        else if wy > worldSize { overlap = max(overlap, wy - worldSize) }
                    }
                    if overlap > 0 {
                        let push = min(1.0, overlap / 6.0 + 0.5)
                        disp[k] = (disp[k] > 0 ? -1.0 : (disp[k] - 1.0)) * push
                        radialTarget[k] = max(minR, baseR - overlap * 0.8)
                    }
                }
            }
            viruses[i].vertexDisplacements = disp

            let prevR = viruses[i].vertexRadii
            var nextR = prevR
            let blend = min(1.0, stepScale)
            for k in 0..<vCount {
                let candidate = max(minR, prevR[k] + disp[k])
                let tgt = min(visualRadius * 1.12, min(radialTarget[k], candidate))
                let driven = (12.0 * tgt + visualRadius) / 13.0
                let pPrev = prevR[(k - 1 + vCount) % vCount]
                let pNext = prevR[(k + 1) % vCount]
                let smoothR = (8.0 * driven + pPrev + pNext) / 10.0
                nextR[k] = prevR[k] + (smoothR - prevR[k]) * blend
                viruses[i].deformedVertices[k] = CGPoint(x: trig[k].cos * nextR[k], y: trig[k].sin * nextR[k])
            }
            viruses[i].vertexRadii = nextR
        }
    }
}

private enum SoftBodyTrigCache {
    static var cache: [Int: [(cos: CGFloat, sin: CGFloat)]] = [:]
    static func get(count: Int) -> [(cos: CGFloat, sin: CGFloat)] {
        if let hit = cache[count] { return hit }
        var out: [(cos: CGFloat, sin: CGFloat)] = []
        out.reserveCapacity(count)
        let step = (2.0 * CGFloat.pi) / CGFloat(count)
        for k in 0..<count {
            let a = CGFloat(k) * step
            out.append((cos(a), sin(a)))
        }
        cache[count] = out
        return out
    }
}
