//
//  SessionARView.swift
//  FocusEntity-Example
//

import SwiftUI
import RealityKit
import FocusEntity
import ARKit
import Combine

// This is based on the article https://www.ralfebert.com/ios/realitykit-dice-tutorial/

struct ARSessionView: UIViewRepresentable {
    var autoStartSec:Int
    typealias UIViewType = ARView
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        // arView.debugOptions = [.showFeaturePoints, .showAnchorOrigins, .showAnchorGeometry]
        
        arView.debugOptions = [.showStatistics]     // .showAnchorOrigins may cause a crash
        // arView.debugOptions = [.showAnchorOrigins, .showPhysics]
        
        arView.automaticallyConfigureSession = false
        
        let session = arView.session

        context.coordinator.view = arView
        session.delegate = context.coordinator
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        config.providesAudioData = true // This causes Thread 5: signal SIGABRT if Privacy Microphone Usage Description is not added
        session.run(config, options: [.removeExistingAnchors, .resetTracking])
        
        arView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap)))
        
        return arView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(autoStartSec: self.autoStartSec)
    }
    func updateUIView(_ uiView: ARView, context: Context) {
  
    }
    
    // Before restarting a new session, pause the AR session to avoide the warning 'ARSession is being deallocated without being paused. Please pause running sessions explicitly'.
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        debugPrint("dismantleUIView()")
        uiView.session.pause()
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var autoStartSec: Int = 0
        weak var view: ARView?
        var focusEntity: FocusEntity?
        var entity: Entity?
        var tableEntity: Entity?
        var anchorEntity: AnchorEntity? = nil
        private var homePosition: SIMD3<Float> = .zero
        private var droneTranslation: SIMD3<Float> = .zero
        private var droneOffsetY: Float = 0
        private var myTimer: Timer? = nil
        private var direction: CGFloat = 1.0
        private var secPerFrame: CGFloat = 1/30.0
        var takeoffAudioPlaybackController: AudioPlaybackController? = nil
        var landAudioPlaybackController: AudioPlaybackController? = nil
        var takeoffAudioResource: AudioResource? = nil
        var landAudioResource: AudioResource? = nil
        let normalAudioGain: AudioPlaybackController.Decibel = -10
        let muteAudioGain: AudioPlaybackController.Decibel = -100
        var prevCameraFrameTimestamp: Double = 0.0
        var cameraFramePerSec: Int = 0
        var cameraPrevFps: Double = 0.0
        
        init(autoStartSec: Int = 0) {
            super.init()
            self.autoStartSec = autoStartSec
            
            self.loadAudioResouces()
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let view = self.view else { return }
            // debugPrint("Anchors added to the scene: ", anchors)
            
            if self.anchorEntity == nil && self.focusEntity == nil {       // only once
                let onColor: MaterialColorParameter = .color(.green.withAlphaComponent(0.5))
                let offColor: MaterialColorParameter = .color(.yellow.withAlphaComponent(0.5))
                let nonTrackingColor: MaterialColorParameter = .color(.red.withAlphaComponent(0.5))
                let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)  // 20cm, the size of plain will be changed according to the AR world tracking
                
                self.focusEntity = FocusEntity(on: view, style: .colored(onColor: onColor, offColor: offColor, nonTrackingColor: nonTrackingColor, mesh: mesh))
                
                if autoStartSec > 0{
                    DispatchQueue.main.asyncAfter(deadline: .now() + Float64(autoStartSec)) {
                        self.handleTap()
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arCamera = session.currentFrame?.camera else { return }
            let diff = frame.timestamp - self.prevCameraFrameTimestamp
            if diff >= 1.0 {
                var fps = Double(self.cameraFramePerSec)/diff
                fps = round(fps*100)/100
                if fps != self.cameraPrevFps {
                    self.cameraPrevFps = fps
                    let state = ProcessInfo.processInfo.thermalState
                    let df = DateFormatter()
                    df.dateFormat = "yyyy/MM/dd HH:mm:ss.SSS"
                    debugPrint("\(df.string(from: Date())) Camera FPS=\(fps) thermalState=\(state)")
                }
                self.cameraFramePerSec = 0
                self.prevCameraFrameTimestamp = frame.timestamp
            }
            self.cameraFramePerSec += 1
        }
        
        func session(_ session: ARSession,
                     didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer
        ) {
           // debugPrint("audioSample")
        }
        
        @objc func handleTap() {
            guard let view = self.view else { return }
            
            if let focusEntity = self.focusEntity { // tracking a horizontal plane, i.e. no yet started
                // create the dice on 1st tap
                let anchorEntity = AnchorEntity()
                view.scene.addAnchor(anchorEntity)
                self.anchorEntity = anchorEntity
                
                self.homePosition = focusEntity.position
                let entity = createEntity(size: 0.05, position: focusEntity.position)
                anchorEntity.addChild(entity)
                self.entity = entity
                self.setEntityPosition(position: self.homePosition)
            
                let tableEntity = createTable(size: 0.5, position: focusEntity.position)
                anchorEntity.addChild(tableEntity)
                
                focusEntity.destroy()
                self.focusEntity = nil
                
                typealias RealityProject = ExperienceNoObject
                guard let droneScene = try? RealityProject.loadDroneScene() else {return}
                droneScene.generateCollisionShapes(recursive: true)
                view.scene.anchors.append(droneScene)
                
                // add light
                
                let directionalLight = DirectionalLight()
                directionalLight.light.color = .white
                directionalLight.light.intensity = 5000
                directionalLight.shadow?.maximumDistance = 5
                directionalLight.shadow?.depthBias = 5
                let lightAnchor = AnchorEntity(world: .zero)
                lightAnchor.position = .init(x: 0, y: 20, z: 10) // 20m?
                directionalLight.look(at: .zero, from: lightAnchor.position, relativeTo: nil)
                lightAnchor.addChild(directionalLight)
                view.scene.addAnchor(lightAnchor)
                
                if self.myTimer == nil {
                    // start
                    self.myTimer = Timer.scheduledTimer(withTimeInterval: secPerFrame,
                                                        repeats: true) {
                        [weak self]
                        _ in
                        guard let `self` = self else { return }
                        
                        var entityPosition = self.getEntityPosition()
                        if entityPosition.y <= self.homePosition.y {
                            // takeoff
                            self.takeOff()
                            self.direction = 1
                        } else if entityPosition.y >= self.homePosition.y + 0.5 { // 50 cm
                            // land
                            self.landing()
                            self.direction = -1.0
                        }
                        entityPosition.y += Float(self.direction * 1.0/30.0)      // 1m/s
                        self.setEntityPosition(position: entityPosition)
                    }
                }
            }
        }
        
        func createEntity(size: Float, position: SIMD3<Float>) -> Entity {
            do {
                let droneEntity = try Entity.load(named: "DroneWhite")
                droneEntity.scale = [0.02, 0.02, 0.02]
                
                droneEntity.availableAnimations.forEach {
                    droneEntity.playAnimation($0.repeat(duration: .infinity),
                                              transitionDuration: 0,
                                              startsPaused: false)       // start imediately
                }
                
                let bbox = droneEntity.visualBounds(recursive: true, relativeTo: entity, excludeInactive: false)
                let width = (bbox.max.x - bbox.min.x)
                let height = (bbox.max.y - bbox.min.y)
                self.droneOffsetY = (height*droneEntity.scale.y)/2 // place on the top the pad
                
                self.setEntityPosition(position: position)
            
                return droneEntity
            } catch {
                fatalError("Cannot the load the entity model")
            }
        }
        
        func setEntityPosition(position: simd_float3, orientation: simd_quatf! = nil) {
            guard let entity = self.entity else {return}
            
            var entity_orientation: simd_quatf =  entity.orientation
            // if orientaton is nil, the drone does not change the orientation
            if orientation != nil {
                let radians = 90 * Float.pi / 180.0
                entity_orientation = orientation * simd_quatf(angle: radians, axis: SIMD3<Float>(0,1,0))        // This makes Drone facing the camera since the drone model faces x-axis
            }
            let entityPositionY = position.y + droneOffsetY
            let translation = SIMD3<Float>(position.x,
                                           entityPositionY,
                                           position.z)
            
            entity.move(to: Transform(scale: entity.scale,
                                      rotation: entity_orientation,
                                      translation: translation),
                        relativeTo: nil)
        }
        
        func getEntityPosition() -> simd_float3 {
            guard let entity = self.entity else {return simd_make_float3(0, 0, 0)}
            
            var dronePosition = entity.position
            
            dronePosition.y -= droneOffsetY
            
            return dronePosition
        }
        
        /*
        func createDice(size: Float, position: SIMD3<Float>) -> ModelEntity {
            let box = MeshResource.generateBox(size: size, cornerRadius: size*0.2)
            let material = SimpleMaterial(color: .blue, isMetallic: true)
            let diceEntity = ModelEntity(mesh: box, materials: [material])
            diceEntity.position = position
            
            let extent = diceEntity.visualBounds(relativeTo: diceEntity).extents.y
            let boxShape = ShapeResource.generateBox(size: [extent, extent, extent])
            diceEntity.collision = CollisionComponent(shapes: [boxShape])
            diceEntity.physicsBody = PhysicsBodyComponent(massProperties: .default, material: .default, mode: .dynamic)
            /*
            diceEntity.physicsBody = PhysicsBodyComponent(
                massProperties: .init(shape: boxShape, mass: 50),
                material: nil,
                mode: .dynamic)*/
            
            return diceEntity
        }
         */
        
        func createTable(size: Float, position: SIMD3<Float>) -> Entity {
            // Create a plane below the dice
            let planeMesh = MeshResource.generatePlane(width: size, depth: size)
            let meshMaterial = SimpleMaterial(color: .init(white: 1.0, alpha: 0.5), isMetallic: false)
            let planeEntity = ModelEntity(mesh: planeMesh, materials: [meshMaterial])
            planeEntity.position = position
            planeEntity.physicsBody = PhysicsBodyComponent(massProperties: .default, material: nil, mode: .static)
            planeEntity.collision = CollisionComponent(shapes: [.generateBox(width: size, height: 0.001, depth: size)])
            
            return planeEntity
        }
        
        func loadAudioResouces() {
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
            guard let entity = self.entity else {return}
            
            entity.stopAllAudio()     // just in case landing audio is not yet stopped

            if let takeoffAudioResource = self.takeoffAudioResource {
                self.takeoffAudioPlaybackController = entity.prepareAudio(takeoffAudioResource)
                if let player = self.takeoffAudioPlaybackController {
                    player.fade(to: self.muteAudioGain, duration: 0)
                    player.play()
                    player.fade(to: self.normalAudioGain, duration: 0.1)
                }
            }
            
        }
        
        func landing() {
            guard let entity = self.entity else {return}
            
            if let landAudioResource = self.landAudioResource {
                self.landAudioPlaybackController = entity.prepareAudio(landAudioResource)
                if let player = self.landAudioPlaybackController  {
                    player.fade(to: self.muteAudioGain, duration: 0)
                    player.play()
                    player.fade(to: self.normalAudioGain, duration: 0.1)
                }
            }
        
            if let player =  self.takeoffAudioPlaybackController  {
                let duration = 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    player.stop()  // stop takeoff sound
                }
            }
        }
    }
}

struct ARSessionView_Previews: PreviewProvider {
    static var previews: some View {
        ARSessionView(autoStartSec: 0)
    }
}
