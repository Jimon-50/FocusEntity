//
//  DroneEntity.swift
//  FocusEntity-Example
//
//  Created by 五十嵐卓也 on 2023/07/03.
//  Copyright © 2023 Max Cobb. All rights reserved.
//

import Foundation
import Combine
import ARKit
import SwiftUI
import RealityKit

class DroneEntity: Entity {
    var droneModel: Entity? = nil
    var takeoffAudioPlaybackController: AudioPlaybackController? = nil
    var landAudioPlaybackController: AudioPlaybackController? = nil
    var takeoffAudioResource: AudioResource? = nil
    var landAudioResource: AudioResource? = nil
    let normalAudioGain: AudioPlaybackController.Decibel = -10
    let muteAudioGain: AudioPlaybackController.Decibel = -100
    var width: Float = 0
    var height: Float = 0
    var depth: Float = 0
    let scale: Float = 0.02
    var offsetY: Float = 0.0
    
    required init(droneAssetName: String, position: simd_float3) {
        super.init()
        
        let fileName = droneAssetName
        self.droneModel = try! Entity.load(named: fileName)
        guard let droneModel = self.droneModel else {return}
    
        
        let bbox = droneModel.visualBounds(recursive: true, relativeTo: droneModel, excludeInactive: false)
        let width = (bbox.max.x - bbox.min.x)
        let height = (bbox.max.y - bbox.min.y)
        let depth = (bbox.max.z - bbox.min.z)
        droneModel.scale = [self.scale, self.scale, self.scale]
        
        self.width = width * self.scale
        self.height = height * self.scale
        self.depth = depth * self.scale
        self.offsetY = self.height/2
        self.addChild(droneModel)
        
        self.setPosition(position: position)
        
        self.loadAudioResources()
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
    func setPosition(position: simd_float3, orientation: simd_quatf! = nil) {
        var entity_orientation: simd_quatf =  self.orientation
        // if orientaton is nil, the drone does not change the orientation
        if orientation != nil {
            let radians = 90 * Float.pi / 180.0
            entity_orientation = orientation * simd_quatf(angle: radians, axis: SIMD3<Float>(0,1,0))        // This makes Drone facing the camera since the drone model faces x-axis
        }
        let entityPositionY = position.y + offsetY
        let translation = SIMD3<Float>(position.x,
                                       entityPositionY,
                                       position.z)
        
        self.move(to: Transform(scale: self.scale,
                                rotation: entity_orientation,
                                translation: translation),
                  relativeTo: nil)
    }
    
    func getPosition() -> simd_float3 {
        var dronePosition = self.position
        
        dronePosition.y -= offsetY
        
        return dronePosition
    }
    
    
    private func loadAudioResources() {
        do {
            self.takeoffAudioResource = try AudioFileResource.load(named: "take-off.m4a",
                                                                   in: nil,
                                                                   inputMode:.spatial,
                                                                   loadingStrategy: .preload,
                                                                   shouldLoop: false)
            
            self.landAudioResource = try AudioFileResource.load(named: "land.m4a",
                                                                in: nil,
                                                                inputMode: .spatial,
                                                                loadingStrategy: .preload,
                                                                shouldLoop: false)
            
        } catch {
            fatalError("Cannot load audio resouces")
        }
    }
    
    func loadAudioResoucesAsync() {
        var cancellable: AnyCancellable? = nil
        cancellable = AudioFileResource.loadAsync(named: "take-off.m4a",
                                                  in: nil,
                                                  inputMode:.nonSpatial,
                                                  loadingStrategy: .preload,
                                                  shouldLoop: false)
        .sink(receiveCompletion: { error in
            print("audio resource unexpected error: \(error)")
            cancellable?.cancel()
        }, receiveValue: { resouce in
            self.takeoffAudioResource = resouce
            cancellable?.cancel()
        })
        var cancellable3: AnyCancellable? = nil
        cancellable3 = AudioFileResource.loadAsync(named: "land.m4a",
                                                   in: nil,
                                                   inputMode:.nonSpatial,
                                                   loadingStrategy: .preload,
                                                   shouldLoop: false)
        .sink(receiveCompletion: { error in
            print("audio resource unexpected error: \(error)")
            cancellable3?.cancel()
        }, receiveValue: { resouce in
            self.landAudioResource = resouce
            cancellable3?.cancel()
        })
    }
    
    func takeOff() {
        self.stopAllAudio()     // just in case landing audio is not yet stopped

        if let takeoffAudioResource = self.takeoffAudioResource {
            self.takeoffAudioPlaybackController = self.prepareAudio(takeoffAudioResource)
            if let player = self.takeoffAudioPlaybackController {
                player.fade(to: self.muteAudioGain, duration: 0)
                player.play()
                player.fade(to: self.normalAudioGain, duration: 0.1)
            }
        }
        
    }
    
    func landing() {
        if let landAudioResource = self.landAudioResource {
            self.landAudioPlaybackController = self.prepareAudio(landAudioResource)
            if let player = self.landAudioPlaybackController  {
                // print("ggg landing play gain=\(self.audioGain)")
                player.fade(to: self.muteAudioGain, duration: 0)
                player.play()
                player.fade(to: self.normalAudioGain, duration: 0.1)
                // print("landing isPlaying \(player.isPlaying)")
                player.completionHandler = {
                    [weak self] in
                    guard let self = self else {return}
                    // print("ggg landing complete")
                    self.droneModel?.stopAllAnimations(recursive: true)
                    self.stopAllAudio()     // no stop
                    self.landAudioPlaybackController = nil
                }
            }
        }
    
        if let player =  self.takeoffAudioPlaybackController  {
            // stop
            let duration = 0.2
            player.fade(to: self.muteAudioGain, duration: duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                player.stop()  // stop takeoff sound
                self.takeoffAudioPlaybackController = nil
            }
        }
    }
}
