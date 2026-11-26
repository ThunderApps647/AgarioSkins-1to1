import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Values recovered from the original client's `GameConfiguration.json` and
/// `ValueMap.json`. Simulation code uses seconds; the original configuration's
/// velocity values are expressed per 20 Hz gameplay tick.
enum OriginalGameplay {
    static let arenaSideLength: Double = 11180
    static let arenaSideLengthCGFloat: CGFloat = 11180

    static let baseRadius: Double = 31.6227766016837
    static let minRadiusToShoot: Double = 56.56854249
    static let minRadiusToSplit: Double = 60
    static let foodBaseRadius: Double = 10
    static let shotMassBaseRadius: Double = 40
    static let shotMassBaseRadiusCGFloat: CGFloat = 40
    static let virusBaseRadius: Double = 100.01
    static let virusSplitRadius: Double = 141.421356237

    static let velocityMultiplier: Double = 106.06601717
    static let inputFactorPow: Double = -0.45
    static let baseVelocityCompensation: Double = 20
    static let cellDeceleration: Double = 0.87965
    static let onSplitVelocity: Double = 100
    static let onShootFoodVelocity: Double = 100
    static let directionAngleVariation: Double = 0.2
    static let spawnFoodVelocityVariation: Double = 0.2
    static let minVelocityToMove: Double = 0.01

    static let scaleFactorForEating: Double = 0.866
    static let scaleFactorForMergingBack: Double = 0.999
    static let overlapRatioForEating: Double = 0.5
    static let maxMagnitudeFactor: Double = 1.5
    static let percentageOfCellToSquash: CGFloat = 0.4

    // BaseArenaView camera constants (`agar.io` `0x100374bbc..0x10037579c`)
    static let cameraScaleSnapRate: CGFloat = 0.07
    static let cameraPositionSnapRate: CGFloat = 0.315
    static let zoomMultiplier: CGFloat = 1.5
    static let minZoomValue: CGFloat = 0.05

    static func calculateZoom(totalRadius: CGFloat,
                              cellCount: Int,
                              viewportSize: CGSize,
                              customZoomMultiplier: CGFloat = 1.0) -> CGFloat {
        let w = max(viewportSize.width, 1)
        let h = max(viewportSize.height, 1)
        #if canImport(UIKit)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        #else
        let isPhone = true
        #endif
        let phoneRatio = isPhone ? ((w / h) / zoomMultiplier) : 1.0
        let windowHeight = h / max(phoneRatio, 0.001)
        let rEff = max(totalRadius, CGFloat(baseRadius))
        let n = CGFloat(max(1, cellCount))
        let scaleFactor = pow(n, 0.1)
        let maxScaleFactor = pow(n, 0.32)
        let minZoom = max(minZoomValue, (0.37 * windowHeight * maxScaleFactor) / rEff)
        let q = min(1.0, windowHeight / (42.0 * rEff))
        return min(pow(q, 0.4) * scaleFactor, minZoom) * customZoomMultiplier
    }

    static func radius(forMass mass: Double) -> Double {
        sqrt(max(mass, 0)) * 10
    }

    static func radius(forMass mass: CGFloat) -> CGFloat {
        sqrt(max(mass, 0)) * 10
    }

    static func mass(forRadius radius: Double) -> Double {
        radius * radius / 100
    }

    static func speed(forRadius radius: Double) -> Double {
        velocityMultiplier * pow(max(radius, 0.01), inputFactorPow) * baseVelocityCompensation
    }

    static func speed(forMass mass: Double) -> Double {
        speed(forRadius: radius(forMass: mass))
    }

    static func speed(forMass mass: CGFloat) -> CGFloat {
        CGFloat(speed(forMass: Double(mass)))
    }

    static var minSplitMass: Double { mass(forRadius: minRadiusToSplit) }
    static var minEjectMass: Double { mass(forRadius: minRadiusToShoot) }
    static var ejectPelletMass: Double { mass(forRadius: shotMassBaseRadius) }
    static var virusBaseMass: Double { mass(forRadius: virusBaseRadius) }
    static var virusSplitMass: Double { mass(forRadius: virusSplitRadius) }

    static var splitImpulsePerSecond: Double { onSplitVelocity * baseVelocityCompensation }
    static var ejectImpulsePerSecond: Double { onShootFoodVelocity * baseVelocityCompensation }

    static func impulseDecay(dt: Double) -> Double {
        pow(cellDeceleration, dt * baseVelocityCompensation)
    }

    static func impulseDecay(dt: CGFloat) -> CGFloat {
        CGFloat(impulseDecay(dt: Double(dt)))
    }
}
