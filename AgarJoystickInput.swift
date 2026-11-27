import Foundation
import CoreGraphics

/// Direct clean-room port of `JoystickInput` (`0x10028dfd0`, `0x10028e158`, `0x10028df08`)
/// with `ValueMap.json` (`minDPadRadiusFactor = 0.6`) and `JoystickView` (`0x1000e2b1c`) geometry.
struct AgarJoystickInput {
    /// Default outer radius (`0.5 * 82 - 0.25 * 42.5 = 30.375` design pt, scaled by `uiScale` at runtime).
    var maxRadius: CGFloat = 30.375
    /// Center deadzone factor (`minDPadRadiusFactor = 0.6`).
    var minRadiusFactor: CGFloat = 0.6
    var minRadius: CGFloat { maxRadius * minRadiusFactor }
    /// Fixed-DPad mode detection factor (`maxDPadDetectionRadiusFactor = 1.7`).
    var maxDetectionFactor: CGFloat = 1.7
    /// Decay duration (seconds) when `stopOnRelease` is active.
    var decayTime: TimeInterval = 0.25

    /// Active scaled vector pushed to movement (`hypot <= 1.0`).
    var axis: CGSize = .zero
    /// Normalized last valid non-zero heading preserved when idling so splits stay aimed.
    var lastNonZeroDirection: CGSize = CGSize(width: 0, height: 1)
    private(set) var scale: CGFloat = 0.0
    private var releaseTimer: TimeInterval = 0.0
    private var axisAtRelease: CGSize = .zero
    private var wasDragging: Bool = false

    mutating func reset() {
        axis = .zero
        lastNonZeroDirection = CGSize(width: 0, height: 1)
        scale = 0.0
        releaseTimer = 0.0
        axisAtRelease = .zero
        wasDragging = false
    }

    /// `ControlsWidget::followJoystickToPoint:factor:` (`0x1000ec4a8`)
    static func followJoystick(currentCenter: CGPoint, touchPoint: CGPoint, totalRadius: CGFloat, factor: CGFloat = 1.0) -> CGPoint {
        let dx = currentCenter.x - touchPoint.x
        let dy = currentCenter.y - touchPoint.y
        let dist = hypot(dx, dy)
        let excess = dist - totalRadius * factor
        guard excess > 0.0, dist > 1e-6 else {
            return currentCenter
        }
        let inv = -excess / dist
        return CGPoint(
            x: currentCenter.x + dx * inv,
            y: currentCenter.y + dy * inv
        )
    }

    /// `JoystickInput::updateAxisWithTouchPosition:priority:` (`0x10028dfd0`)
    mutating func updateTouch(offset: CGSize, maxRadius overrideMaxRadius: CGFloat? = nil) {
        if let overrideMaxRadius {
            maxRadius = max(1.0, overrideMaxRadius)
        }
        wasDragging = true
        releaseTimer = 0.0
        let dx = offset.width
        let dy = offset.height
        let dist = hypot(dx, dy)
        let activeMax = max(1.0, maxRadius)
        let rawMag = min(1.0, max(0.0, dist / activeMax))

        var dir = CGSize(width: dx, height: dy)
        if dist > 0.001 {
            dir.width /= dist
            dir.height /= dist
        } else {
            dir = lastNonZeroDirection
        }

        // Low-throw angular blend (`rawMag < 0.20`, `0x102766790`)
        let curMag = hypot(axis.width, axis.height)
        if rawMag < 0.20 && curMag > 0.001 && dist > 0.001 {
            let newAngle = atan2(dir.height, dir.width)
            let curAngle = atan2(axis.height, axis.width)
            var delta = newAngle - curAngle
            while delta > .pi { delta -= 2.0 * .pi }
            while delta <= -.pi { delta += 2.0 * .pi }
            let blended = curAngle + delta * (2.0 * rawMag)
            dir = CGSize(width: cos(blended), height: sin(blended))
        }

        // `minDPadRadiusFactor = 0.6`: smooth 0..1 curve between minRadius and maxRadius;
        // inside deadzone emits 9e-5 vector so heading persists while `isStopped = true` (`0x10028e0ec`).
        let deadzone = minRadius
        let span = max(1.0, activeMax - deadzone)
        let mag = dist <= deadzone ? 0.0 : min(1.0, (dist - deadzone) / span)
        scale = mag

        if mag > 0.001 {
            axis = CGSize(width: dir.width * mag, height: dir.height * mag)
            lastNonZeroDirection = dir
        } else {
            axis = CGSize(width: dir.width * 9e-5, height: dir.height * 9e-5)
            if dist > 0.001 {
                lastNonZeroDirection = dir
            }
        }
        axisAtRelease = axis
    }

    mutating func endTouch(stopOnRelease: Bool) {
        if stopOnRelease {
            axisAtRelease = axis
            releaseTimer = 0.0
        } else {
            // Continue gliding in current direction (`axis = lastNonZeroDirection`)
            axis = lastNonZeroDirection
            scale = 1.0
        }
        wasDragging = false
    }

    /// `JoystickInput::update:` (`0x10028df08`)
    mutating func step(dt: CGFloat, isDragging: Bool, stopOnRelease: Bool) {
        if isDragging { return }
        if stopOnRelease {
            releaseTimer += TimeInterval(dt)
            let progress = min(1.0, releaseTimer / max(0.05, decayTime))
            let alpha: Double = progress < 0.70 ? 0.0 : min(1.0, (progress - 0.70) / 0.30)
            let rem = CGFloat(max(0.0, 1.0 - alpha))
            axis = CGSize(width: axisAtRelease.width * rem, height: axisAtRelease.height * rem)
            scale = hypot(axis.width, axis.height)
        } else if hypot(axis.width, axis.height) < 0.001 && hypot(lastNonZeroDirection.width, lastNonZeroDirection.height) > 0.001 {
            axis = .zero
            scale = 0.0
        }
    }
}
