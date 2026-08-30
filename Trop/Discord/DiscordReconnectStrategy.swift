//
//  DiscordReconnectStrategy.swift
//  Trop
//
//  Created by 686udjie on 31/08/2026.
//

import Foundation

enum ReconnectAction: Equatable {
    case resume(sessionId: String, seq: Int)
    case reIdentify
    case refreshAndReIdentify
    case surfaceFatal
}

enum DiscordReconnectStrategy {
    static func decide(closeCode: Int, hadSession: Bool, seq: Int, sessionId: String?) -> ReconnectAction {
        switch closeCode {
        case 4000:
            if hadSession, let sid = sessionId, !sid.isEmpty, seq > 0 {
                return .resume(sessionId: sid, seq: seq)
            } else {
                return .reIdentify
            }
        case 4001: return .reIdentify
        case 4003: return .reIdentify
        case 4004: return .refreshAndReIdentify
        case 4005: return .reIdentify
        case 4007: return .reIdentify
        case 4009: return .reIdentify
        case 4014: return .surfaceFatal
        default: return .reIdentify
        }
    }
}
