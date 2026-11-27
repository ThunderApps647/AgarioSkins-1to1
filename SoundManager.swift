//
//  SoundManager.swift — 1:1 SFX playback using the original IPA audio assets.
//

import AVFoundation
import SwiftUI

enum AgarSFX: String, CaseIterable {
    case split = "AGAR.IO_sfx_INGAME_split"
    case shoot = "AGAR.IO_sfx_INGAME_shoot"
    case eatCell = "AGAR.IO_sfx_INGAME_eatCell"
    case eatOwnCell = "AGAR.IO_sfx_INGAME_eatOwnCell"
    case virusPop = "AGAR.IO_sfx_INGAME_splitBecauseVirus"
    case gameOver = "AGAR.IO_sfx_INGAME_gameOver"
    case menuClick = "AGAR.IO_sfx_MENU_click"

    /// Exact Mach-O per-sound debounce window (`w3` milliseconds in `0x1000e670c`).
    var binaryCooldownSec: CFTimeInterval {
        switch self {
        case .split, .shoot: return 0.150 // ControlsWidget 0x96 ms
        case .menuClick: return 0.200     // 0x10006cc48 0xc8 ms
        case .eatCell, .eatOwnCell, .virusPop, .gameOver: return 0.0
        }
    }

    /// Exact Mach-O base volume (`s1` in `0x1000e670c` callers).
    var binaryVolume: Double {
        switch self {
        case .menuClick: return 0.25
        default: return 1.0
        }
    }

    /// Exact Mach-O pitch jitter (`a5` in `0x1000e670c` callers).
    var binaryPitchJitter: Float {
        switch self {
        case .split, .shoot, .menuClick: return 0.05
        case .eatCell, .eatOwnCell, .virusPop: return 0.20
        case .gameOver: return 0.0
        }
    }
}

struct SoundEvent: Equatable {
    let soundID: String
    let tick: Int
    let volume: Double
}

final class SoundManager {
    static let shared = SoundManager()

    private var pools: [AgarSFX: [AVAudioPlayer]] = [:]
    private var lastPlayed: [AgarSFX: CFTimeInterval] = [:]
    private var spyLastPlayed: [AgarSFX: CFTimeInterval] = [:]
    private var spyEvents: [SoundEvent]? = nil
    private let poolSize = 4

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for sfx in AgarSFX.allCases {
            guard let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: "mp3") else { continue }
            var players: [AVAudioPlayer] = []
            for _ in 0..<poolSize {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.enableRate = true
                    p.prepareToPlay()
                    players.append(p)
                }
            }
            if !players.isEmpty { pools[sfx] = players }
        }
    }

    func beginSpy() {
        spyLastPlayed = [:]
        spyEvents = []
    }

    func endSpy() -> [SoundEvent] {
        let out = spyEvents ?? []
        spyEvents = nil
        spyLastPlayed = [:]
        return out
    }

    func play(_ sfx: AgarSFX) {
        play(sfx, minInterval: sfx.binaryCooldownSec, volume: sfx.binaryVolume, simTime: nil, tick: 0)
    }

    func play(_ sfx: AgarSFX, minInterval: CFTimeInterval) {
        play(sfx, minInterval: minInterval, volume: sfx.binaryVolume, simTime: nil, tick: 0)
    }

    func playBinary(_ sfx: AgarSFX, simTime: CFTimeInterval? = nil, tick: Int = 0) {
        play(sfx, minInterval: sfx.binaryCooldownSec, volume: sfx.binaryVolume, simTime: simTime, tick: tick)
    }

    func play(_ sfx: AgarSFX, minInterval: CFTimeInterval, volume: Double, simTime: CFTimeInterval? = nil, tick: Int = 0) {
        if spyEvents != nil, let t = simTime {
            if let prev = spyLastPlayed[sfx], (t - prev) + 1e-9 < minInterval { return }
            spyLastPlayed[sfx] = t
            spyEvents?.append(SoundEvent(soundID: sfx.rawValue, tick: tick, volume: volume))
            return
        }
        guard UserDefaults.standard.object(forKey: "macro.soundEnabled") as? Bool ?? true else { return }
        let now = simTime ?? CACurrentMediaTime()
        if let prev = lastPlayed[sfx], (now - prev) < minInterval { return }
        lastPlayed[sfx] = now
        if spyEvents != nil {
            spyEvents?.append(SoundEvent(soundID: sfx.rawValue, tick: tick, volume: volume))
            return
        }
        guard let list = pools[sfx], !list.isEmpty else { return }
        let target = list.first(where: { !$0.isPlaying }) ?? list[0]
        target.volume = Float(volume)
        let jitter = sfx.binaryPitchJitter
        target.rate = jitter > 0 ? Float.random(in: (1.0 - jitter)...(1.0 + jitter)) : 1.0
        target.currentTime = 0
        target.play()
    }
}
