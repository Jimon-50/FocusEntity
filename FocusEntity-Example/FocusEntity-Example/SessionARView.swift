//
//  SessionARView.swift
//  FocusEntity-Example
//

import SwiftUI
import RealityKit
import FocusEntity
import ARKit

// This is based on the article https://www.ralfebert.com/ios/realitykit-dice-tutorial/

struct ARSessionView: UIViewRepresentable {
    var autoStartSec:Int
    typealias UIViewType = ARView
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        // arView.debugOptions = [.showFeaturePoints, .showAnchorOrigins, .showAnchorGeometry]
        
        arView.debugOptions = [.showStatistics]
        // arView.debugOptions = [.showAnchorOrigins, .showPhysics]
        
        let session = arView.session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = .horizontal
        session.run(config, options: [.removeExistingAnchors, .resetTracking])
        context.coordinator.view = arView
        session.delegate = context.coordinator

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
        uiView.session.pause()
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var autoStartSec: Int = 0
        weak var view: ARView?
        var focusEntity: FocusEntity?
        var entity: Entity?
        var tableEntity: Entity?
        var anchorEntity: AnchorEntity? = nil
        private var homeTranslation: SIMD3<Float> = .zero
        private var myTimer: Timer? = nil
        
        init(autoStartSec: Int = 0) {
            super.init()
            self.autoStartSec = autoStartSec
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let view = self.view else { return }
            debugPrint("Anchors added to the scene: ", anchors)
            
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
        
        @objc func handleTap() {
            guard let view = self.view else { return }
            
            if let focusEntity = self.focusEntity {
                // create the dice on 1st tap
                let anchorEntity = AnchorEntity()
                view.scene.addAnchor(anchorEntity)
                self.anchorEntity = anchorEntity
                
                let entity = createEntity(size: 0.05, position: focusEntity.position)
                anchorEntity.addChild(entity)
                self.entity = entity
            
                let tableEntity = createTable(size: 0.5, position: focusEntity.position)
                anchorEntity.addChild(tableEntity)
                
                self.homeTranslation = entity.position
                
                focusEntity.destroy()
                self.focusEntity = nil
                
                if self.myTimer == nil {
                    // start
                    self.myTimer = Timer.scheduledTimer(withTimeInterval: 1.0,
                                                        repeats: true) {
                        [weak self]
                        _ in
                        guard let `self` = self else { return }
                        guard let entity = self.entity else { return }
                        
                        DispatchQueue.main.async {
                            let distance = distance(entity.transform.translation, self.homeTranslation)
                            if distance > 0.5 { // 50 cm
                                // reset position
                                /*
                                entity.physicsBody!.mode = .kinematic
                                let translation = SIMD3<Float>(self.homeTranslation.x,
                                                               self.homeTranslation.y,
                                                               self.homeTranslation.z)
                                modelEntity.move(to: Transform(scale: modelEntity.scale,
                                                              rotation: modelEntity.orientation,
                                                              translation: translation), relativeTo: nil)
                                 */
                            } else {
                                /*
                                // roll the dice
                                if modelEntity.physicsBody!.mode != .dynamic {
                                    modelEntity.physicsBody!.mode = .dynamic
                                }
                                modelEntity.addForce([0, 5, 0], relativeTo: nil)
                                modelEntity.addTorque([Float.random(in: 0 ... 0.4), Float.random(in: 0 ... 0.4), Float.random(in: 0 ... 0.4)], relativeTo: nil)
                                 */
                            }
                        }
                    }
                }
            }
        }
        
        func createEntity(size: Float, position: SIMD3<Float>) -> Entity {
            do {
                let entity = try ModelEntity.load(named: "DroneWhite")
                entity.scale = [0.02, 0.02, 0.02]
                entity.position = position
                
                /*
                let extent = entity.visualBounds(relativeTo: entity).extents.y
                let boxShape = ShapeResource.generateBox(size: [extent, extent, extent])
                entity.collision = CollisionComponent(shapes: [boxShape])
                entity.physicsBody = PhysicsBodyComponent(
                    massProperties: .init(shape: boxShape, mass: 50),
                    material: nil,
                    mode: .kinematic
                )
                 */
                
                entity.availableAnimations.forEach {
                    entity.playAnimation($0.repeat(duration: .infinity),
                                              transitionDuration: 0,
                                              startsPaused: false)       // start imediately
                }
            
                return entity
            } catch {
                fatalError("Cannot the load the entity model")
            }
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
    }
}

struct ARSessionView_Previews: PreviewProvider {
    static var previews: some View {
        ARSessionView(autoStartSec: 0)
    }
}
