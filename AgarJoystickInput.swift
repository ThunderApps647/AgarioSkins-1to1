import Foundation
import CoreGraphics

/// Direct clean-room port of `JoystickInput` (`0x10028dfd0`, `0x10028e158`, `0x10028df08`).
struct AgarJoystickInput {
    /// Touch-pad outer radius (screen points), matching `ControlsWidget`.
    var maxRadius: CGFloat = 65.0
    /// Inner deadzone before directional thrust kicks in (screen points).
    var minRadius: CGFloat = 8.0
    /// Floating-base follow threshold (`maxRadius * 1.35`).
    var maxDetectionFactor: CGFloat = 1.35
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

    /// `JoystickInput::updateAxisWithTouchPosition:priority:` (`0x10028dfd0`)
    mutating func updateTouch(offset: CGSize) {
        wasDragging = true
        releaseTimer = 0.0
        let dx = offset.width
        let dy = offset.height
        let dist = hypot(dx, dy)
        let rawMag = min(1.0, max(0.0, dist / max(1.0, maxRadius)))

        var dir = CGSize(width: dx, height: dy)
        if dist > 0.001 {
            dir.width /= dist
            dir.height /= dist
        } else {
            dir = lastNonZeroDirection
        }

        // Low-throw angular damping (`rawMag < 0.5`): blends heading smoothly instead of snapping 180 deg near center
        let curMag = hypot(axis.width, axis.height)
        if rawMag < 0.5 && curMag > 0.001 && dist > 0.001 {
            let newAngle = atan2(dir.height, dir.width)
            let curAngle = atan2(axis.height, axis.width)
            var delta = newAngle - curAngle
            while delta > .pi { delta -= 2.0 * .pi }
            while delta <= -.pi { delta += 2.0 * .pi }
            let blended = curAngle + delta * (2.0 * rawMag)
            dir = CGSize(width: cos(blended), height: sin(blended))
        }

        // Smooth 0..1 curve between `minRadius` and `maxRadius`
        let span = max(1.0, maxRadius - minRadius)
        let mag = dist <= minRadius ? 0.0 : min(1.0, (dist - minRadius) / span)
        scale = mag

        if mag > 0.001 {
            axis = CGSize(width: dir.width * mag, height: dir.height * mag)
            lastNonZeroDirection = dir
        } else {
            axis = .zero
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
            let rem = CGFloat(max(0.0, 1.0 - progress))
            axis = CGSize(width: axisAtRelease.width * rem, height: axisAtRelease.height * rem)
            scale = hypot(axis.width, axis.height)
        } else if hypot(axis.width, axis.height) < 0.001 && hypot(lastNonZeroDirection.width, lastNonZeroDirection.height) > 0.001 {
            axis = .zero
            scale = 0.0
        }
    }
}
