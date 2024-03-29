//
//  HMSInteractor.swift
//  HMSSDKExample
//
//  Created by Yogesh Singh on 26/02/21.
//  Copyright © 2021 100ms. All rights reserved.
//

import Foundation
import HMSSDK

final class HMSSDKInteractor: HMSUpdateListener {

    private(set) var hmsSDK: HMSSDK?

    internal var onPreview: ((HMSRoom, [HMSTrack]) -> Void)?
    internal var onRoleChange: ((HMSRoleChangeRequest) -> Void)?
    internal var onChangeTrackState: ((HMSChangeTrackStateRequest) -> Void)?
    internal var onRemovedFromRoom: ((HMSRemovedFromRoomNotification) -> Void)?
    internal var onRecordingUpdate: (() -> Void)?
    internal var updatedMuteStatus: ((HMSAudioTrack) -> Void)?

    // MARK: - Instance Properties

    internal var messages = [HMSMessage]()
    
    internal var isRecording: Bool {
        get {
            guard let room = hmsSDK?.room else { return false }
            return room.browserRecordingState.running || room.serverRecordingState.running
        }
    }
    
    internal var isStreaming: Bool {
        get {
            guard let room = hmsSDK?.room else { return false }
            return room.rtmpStreamingState.running
        }
    }

    private var config: HMSConfig?

    // MARK: - Setup SDK

    init(for user: String,
         in room: String,
         _ completion: @escaping () -> Void) {

        RoomService.setup(for: user, room) { [weak self] token in
            guard let token = token else {
                Utilities.showToast(message: "Something went wrong")
                print(#function, "Error fetching token")
                
                if #available(iOS 13.0, *) {
                     if var topController = UIApplication.shared.keyWindow?.rootViewController  {
                           while let presentedViewController = topController.presentedViewController {
                                 topController = presentedViewController
                                }
                         topController.dismiss(animated: true, completion: nil)
                }
            }
                return
            }

            self?.setup(for: user, token: token, room)

            completion()
        }
    }

    private func setup(for user: String, token: String, _ room: String) {

        hmsSDK = HMSSDK.build { sdk in
            sdk.analyticsLevel = .verbose
            let videoSettings = HMSVideoTrackSettings(codec: .VP8,
                                                      resolution: .init(width: 320, height: 180),
                                                      maxBitrate: 512,
                                                      maxFrameRate: 25,
                                                      cameraFacing: .front,
                                                      trackDescription: "Just a normal video track")
            let audioSettings = HMSAudioTrackSettings(maxBitrate: 32, trackDescription: "Just a normal audio track")
            sdk.trackSettings = HMSTrackSettings(videoSettings: videoSettings, audioSettings: audioSettings)
            sdk.logger = self
        }

        config = HMSConfig(userName: user, authToken: token)

        guard let config = config else { return }
        hmsSDK?.preview(config: config, delegate: self)
    }

    internal func join() {
        guard let config = config else { return }
        hmsSDK?.join(config: config, delegate: self)
    }

    internal func leave() {
        hmsSDK?.leave()
    }

    // MARK: - HMSSDK Listener Callbacks

    func on(join room: HMSRoom) {
        if let peer = room.peers.first {
            NotificationCenter.default.post(name: Constants.joinedRoom, object: nil, userInfo: ["peer": peer])
        }
    }

    func on(peer: HMSPeer, update: HMSPeerUpdate) {

        print(#function, peer.name, update.description)

        NotificationCenter.default.post(name: Constants.peersUpdated, object: nil, userInfo: ["peer": peer])

        switch update {
        case .peerJoined:
            Utilities.showToast(message: "🙌 \(peer.name) joined!")
        case .peerLeft:
            Utilities.showToast(message: "👋 \(peer.name) left!")
        case .roleUpdated:
            if let role = peer.role?.name {
                Utilities.showToast(message: "🎉 \(peer.name)'s role updated to \(role)")
                NotificationCenter.default.post(name: Constants.roleUpdated, object: nil)
            }
        default:
            print(#function, "Unhandled update type encountered")
        }
    }

    func on(track: HMSTrack, update: HMSTrackUpdate, for peer: HMSPeer) {
        print("#!", #function, peer.name, update.description, track.trackId, kindString(from: track.kind), track.source)
        if let audio = track as? HMSAudioTrack {
            updatedMuteStatus?(audio)
        }
    }

    func on(error: HMSError) {
        NotificationCenter.default.post(name: Constants.gotError,
                                        object: nil,
                                        userInfo: ["error": error.message])
    }

    func on(message: HMSMessage) {

        messages.append(message)
        NotificationCenter.default.post(name: Constants.messageReceived, object: nil)
        Utilities.showToast(message: "💬 \(message.sender!.name) sent you a message")
    }

    func on(updated speakers: [HMSSpeaker]) {

        let date = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let dateString = "\(hour):\(minutes):\(second)"

        print("Speaker update " + dateString, speakers.map { $0.peer.name },
              speakers.map { kindString(from: $0.track.kind) },
              speakers.map { $0.track.source })
    }

    func on(room: HMSRoom, update: HMSRoomUpdate) {
        print(#function, room.name ?? "", update.description)
        
        if update == .browserRecordingStateUpdated || update == .rtmpStreamingStateUpdated {
            onRecordingUpdate?()
        }
    }

    func on(roleChangeRequest: HMSRoleChangeRequest) {
        print(#function, roleChangeRequest.requestedBy?.name ?? "100ms app", roleChangeRequest.suggestedRole.name)
        onRoleChange?(roleChangeRequest)
    }

    func onReconnecting() {
        Utilities.showToast(message: "Trying to Reconnect")
    }

    func onReconnected() {
        Utilities.showToast(message: "Reconnection Successful")
    }

    func on(changeTrackStateRequest: HMSChangeTrackStateRequest) {
        onChangeTrackState?(changeTrackStateRequest)
    }

    func on(removedFromRoom notification: HMSRemovedFromRoomNotification) {
        onRemovedFromRoom?(notification)
    }

    // MARK: - Role Actions

    internal func changeRole(for peer: HMSPeer, to role: HMSRole, force: Bool = false) {
        hmsSDK?.changeRole(for: peer, to: role, force: force)
    }

    internal func accept(changeRole request: HMSRoleChangeRequest) {
        hmsSDK?.accept(changeRole: request)
    }

    internal func mute(role: HMSRole?) {
        var roleFilter: [HMSRole]?
        if let role = role {
            roleFilter = [role]
        }
        hmsSDK?.changeTrackState(mute: true, for: .audio, roles: roleFilter)
    }

    // MARK: - Role Info

    internal var roles: [HMSRole]? {
        hmsSDK?.roles
    }

    internal var canChangeRole: Bool {
        hmsSDK?.localPeer?.role?.permissions.changeRole ?? false
    }

    internal var canRemoteMute: Bool {
        hmsSDK?.localPeer?.role?.permissions.mute ?? false
    }

    internal var canRemovePeer: Bool {
        hmsSDK?.localPeer?.role?.permissions.removeOthers ?? false
    }

    internal var canEndRoom: Bool {
        hmsSDK?.localPeer?.role?.permissions.endRoom ?? false
    }
}

// MARK: - Preview Listener

extension HMSSDKInteractor: HMSPreviewListener {
    func onPreview(room: HMSRoom, localTracks: [HMSTrack]) {
        print(#function, localTracks.map { $0.kind.rawValue }, localTracks.map { $0.source })
        onPreview?(room, localTracks)
    }
}

// MARK: - Logger

extension HMSSDKInteractor: HMSLogger {
    func log(_ message: String, _ level: HMSLogLevel) {
        guard level.rawValue <= HMSLogLevel.verbose.rawValue else { return }
        print(message)
    }
}

// MARK: - Enums to String Converter

extension HMSSDKInteractor {
    func kindString(from kind: HMSTrackKind) -> String {
        switch kind {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        default:
            return "Unknown Kind"
        }
    }
}
