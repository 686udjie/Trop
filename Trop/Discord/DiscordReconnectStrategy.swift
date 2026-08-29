//
//  DiscordReconnectStrategy.swift
//  Trop
//

import Foundation

enum DiscordReconnectAction: Equatable {
    case resume(sessionId: String, seq: Int)
    case reIdentify
    case refreshAndReIdentify
    case surfaceFatal
}

enum DiscordReconnectStrategy {
    static func decide(
        closeCode: Int,
        hadSession: Bool,
        seq: Int,
        sessionId: String?
    ) -> DiscordReconnectAction {
        switch closeCode {
        case 4000:
            if hadSession, let sessionId, seq > 0 {
                return .resume(sessionId: sessionId, seq: seq)
            }
            return .reIdentify
        case 4001, 4003, 4005, 4007, 4009:
            return .reIdentify
        case 4004:
            return .refreshAndReIdentify
        case 4014:
            return .surfaceFatal
        default:
            return .reIdentify
        }
    }
}
