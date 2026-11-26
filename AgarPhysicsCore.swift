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

    /// Computes focal world cursor outside clusterExtent + 600/zoom so split packs converge cleanly without folding.
    static func steerTarget(
        flockCenter: CGPoint,
        directionNorm: CGSize,
        cells: [PlayerCell],
        zoom: CGFloat
    ) -> CGPoint? {
        guard hypot(directionNorm.width, directionNorm.height) > 0.001 else { return nil }
        let safeZoom = max(zoom, 0.05)
        let clusterExtent = cells.reduce(CGFloat(0)) { best, cell in
            max(best, hypot(cell.position.x - flockCenter.x, cell.position.y - flockCenter.y) + cell.cachedVisualRadius)
        }
        let focalDistance = max(clusterExtent + 600.0 / safeZoom, 800.0 / safeZoom)
        return CGPoint(
            x: flockCenter.x + directionNorm.width * focalDistance,
            y: flockCenter.y + directionNorm.height * focalDistance
        )
    }

    // MARK: - Offline Adapted Mass Decay (`Offline Mode - Settings`)

    static func applyOfflineMassDecay(mass: CGFloat, isPlayer: Bool, dt: CGFloat) -> CGFloat {
        // radiusDecayRate = 0.99998 (base), adapted with baseRadiusForAdaptedDecay = 200, maxDecayRateForPlayer = 0.99922
        let r = Double(max(mass, 1.0)).squareRoot() * 10.0
        guard r >= 200.0 else { return mass }
        let ratio = min(4.0, r / 200.0)
        let stepFactor = max(0.99922, pow(0.99998, ratio * 25.0))
        let decayPerFrame = isPlayer ? stepFactor : 0.99998
        let factor = pow(decayPerFrame, Double(dt * 60.0))
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

    /// `Arena_selfCollision` (`0x10004e5e0`): single-pass mass-ratio pushout `overlap * (rB^2 / (rA^2 + rB^2))`.
    static func resolveSelfCollisions(cells: inout [PlayerCell]) {
        guard cells.count > 1 else { return }
        var groups: [UUID: [Int]] = [:]
        var radii = [CGFloat](repeating: 0, count: cells.count)
        groups.reserveCapacity(min(cells.count, 64))
        for i in cells.indices {
            groups[cells[i].ownerID, default: []].append(i)
            radii[i] = cells[i].cachedVisualRadius
        }

        for (_, indices) in groups {
            guard indices.count > 1 else { continue }
            for i in 0..<indices.count {
                for j in (i + 1)..<indices.count {
                    let idx1 = indices[i]
                    let idx2 = indices[j]
                    guard cells[idx1].mergeTimer > 0 || cells[idx2].mergeTimer > 0 else { continue }
                    if cells[idx1].immuneToCellID == cells[idx2].id || cells[idx2].immuneToCellID == cells[idx1].id {
                        continue
                    }

                    let r1 = radii[idx1]
                    let r2 = radii[idx2]
                    let totalRadius = r1 + r2
                    let dx = cells[idx2].position.x - cells[idx1].position.x
                    if dx < -totalRadius || dx > totalRadius { continue }
                    let dy = cells[idx2].position.y - cells[idx1].position.y
                    if dy < -totalRadius || dy > totalRadius { continue }

                    let distSq = dx * dx + dy * dy
                    guard distSq < (totalRadius * totalRadius) else { continue }

                    var dist = sqrt(distSq)
                    var nx = dx
                    var ny = dy
                    if dist < 0.0001 {
                        dist = 1.0
                        nx = 1.0
                        ny = 0.0
                    } else {
                        nx /= dist
                        ny /= dist
                    }

                    let overlap = totalRadius - dist
                    let denom = r1 * r1 + r2 * r2
                    guard denom > 0 else { continue }
                    let push1 = overlap * ((r2 * r2) / denom)
                    let push2 = overlap * ((r1 * r1) / denom)

                    cells[idx1].position.x -= nx * push1
                    cells[idx1].position.y -= ny * push1
                    cells[idx2].position.x += nx * push2
                    cells[idx2].position.y += ny * push2
                }
            }
        }
    }

    // MARK: - Soft-Body Vertex Spring Solver (`SoftBodyCellView::updateCellVertices`)

    static func deformVertices(
        cells: inout [PlayerCell],
        neighborsByOwner: Bool,
        visibleWorldRect: CGRect,
        worldSize: CGFloat,
        dt: CGFloat,
        massManager: EjectedMassManager? = nil
    ) {
        let count = cells.count
        guard count > 0 else { return }
        let vertexCount = max(20, min(64, (128 / max(1, count)) & ~1))
        let trig = SoftBodyTrigCache.get(count: vertexCount)
        let relax = 1.0 - pow(CGFloat(0.04), dt)
        let visRect = visibleWorldRect

        for i in cells.indices {
            let pos = cells[i].position
            let visualRadius = cells[i].cachedVisualRadius

            if !visRect.isEmpty && !visRect.intersects(
                CGRect(x: pos.x - visualRadius, y: pos.y - visualRadius, width: visualRadius * 2, height: visualRadius * 2)
            ) {
                if !cells[i].deformedVertices.isEmpty {
                    cells[i].deformedVertices.removeAll(keepingCapacity: false)
                }
                continue
            }

            if cells[i].deformedVertices.count != vertexCount {
                cells[i].deformedVertices = [CGPoint](repeating: .zero, count: vertexCount)
                for k in 0..<vertexCount {
                    cells[i].deformedVertices[k] = CGPoint(x: trig[k].cos * visualRadius, y: trig[k].sin * visualRadius)
                }
                continue
            }

            let nearWall = (pos.x - visualRadius) < 0 || (pos.y - visualRadius) < 0
                || (pos.x + visualRadius) > worldSize || (pos.y + visualRadius) > worldSize

            var nearbyMass: [EjectedMass] = []
            var siblingNeighbors: [(pos: CGPoint, radius: CGFloat)] = []
            let doComplex = !cells[i].isBot && count <= 20
            if doComplex {
                if let mm = massManager {
                    let sr = visualRadius + 100
                    nearbyMass = mm.getLimitedVisibleMassesArray(
                        in: CGRect(x: pos.x - sr, y: pos.y - sr, width: sr * 2, height: sr * 2),
                        limit: 12
                    )
                }
                if neighborsByOwner {
                    let owner = cells[i].ownerID
                    for j in cells.indices where j != i && cells[j].ownerID == owner && !cells[j].isMerging {
                        let jr = cells[j].cachedSolidRadius
                        let sumR = visualRadius + jr + 6.0
                        let ndx = pos.x - cells[j].position.x
                        let ndy = pos.y - cells[j].position.y
                        if ndx * ndx + ndy * ndy < sumR * sumR {
                            siblingNeighbors.append((cells[j].position, jr))
                        }
                    }
                }
            }

            if !nearWall && nearbyMass.isEmpty && siblingNeighbors.isEmpty {
                for k in 0..<vertexCount {
                    let targetX = trig[k].cos * visualRadius
                    let targetY = trig[k].sin * visualRadius
                    let cur = cells[i].deformedVertices[k]
                    cells[i].deformedVertices[k] = CGPoint(
                        x: cur.x + (targetX - cur.x) * relax,
                        y: cur.y + (targetY - cur.y) * relax
                    )
                }
            } else {
                let squashFactor = CGFloat(OriginalGameplay.percentageOfCellToSquash * 2.0)
                let massRad = OriginalGameplay.shotMassBaseRadiusCGFloat
                let minR = visualRadius * 0.45
                for k in 0..<vertexCount {
                    let c = trig[k].cos
                    let s = trig[k].sin
                    var vx = c * visualRadius
                    var vy = s * visualRadius
                    var overlap: CGFloat = 0

                    let wx = pos.x + vx
                    let wy = pos.y + vy
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
                    if overlap > 0 {
                        let rClamped = max(minR, visualRadius - overlap)
                        vx = c * rClamped
                        vy = s * rClamped
                    }
                    if nearWall {
                        if wx < 0 { vx -= wx * squashFactor }
                        else if wx > worldSize { vx -= (wx - worldSize) * squashFactor }
                        if wy < 0 { vy -= wy * squashFactor }
                        else if wy > worldSize { vy -= (wy - worldSize) * squashFactor }
                    }

                    let cur = cells[i].deformedVertices[k]
                    cells[i].deformedVertices[k] = CGPoint(
                        x: cur.x + (vx - cur.x) * relax,
                        y: cur.y + (vy - cur.y) * relax
                    )
                }
            }
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
