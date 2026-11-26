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
}

final class SoundManager {
    static let shared = SoundManager()

    private var pools: [AgarSFX: [AVAudioPlayer]] = [:]
    private var lastPlayed: [AgarSFX: CFTimeInterval] = [:]
    private let poolSize = 4

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for sfx in AgarSFX.allCases {
            guard let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: "mp3") else { continue }
            var players: [AVAudioPlayer] = []
            for _ in 0..<poolSize {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.prepareToPlay()
                    players.append(p)
                }
            }
            if !players.isEmpty { pools[sfx] = players }
        }
    }

    func play(_ sfx: AgarSFX, minInterval: CFTimeInterval = 0.04) {
        guard UserDefaults.standard.object(forKey: "macro.soundEnabled") as? Bool ?? true else { return }
        let now = CACurrentMediaTime()
        if let prev = lastPlayed[sfx], now - prev < minInterval { return }
        lastPlayed[sfx] = now
        guard let list = pools[sfx], !list.isEmpty else { return }
        if let idle = list.first(where: { !$0.isPlaying }) {
            idle.currentTime = 0
            idle.play()
        } else {
            list[0].currentTime = 0
            list[0].play()
        }
    }
}
