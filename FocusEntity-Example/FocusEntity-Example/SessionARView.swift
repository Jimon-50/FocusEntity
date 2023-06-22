//
//  SessionARView.swift
//  FocusEntity-Example
//

import SwiftUI
import RealityKit
import FocusEntity
import ARKit

struct SessionARView: UIViewRepresentable {
    typealias UIViewType = ARView
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let arConfig = ARWorldTrackingConfiguration()
        arConfig.planeDetection = [.horizontal]
        // restarting a new session requires the options of .removeExistingAnchors and .resetTracking
        arView.session.run(arConfig, options: [.removeExistingAnchors, .resetTracking])
        
        let onColor: MaterialColorParameter = .color(.green.withAlphaComponent(0.5))
        let offColor: MaterialColorParameter = .color(.yellow.withAlphaComponent(0.5))
        let nonTrackingColor: MaterialColorParameter = .color(.red.withAlphaComponent(0.5))
        let mesh = MeshResource.generatePlane(width: 0.2, depth: 0.2)  // 20cm, the size of plain will be changed according to the AR world tracking
        
        _ = FocusEntity(on: arView, style: .colored(onColor: onColor, offColor: offColor, nonTrackingColor: nonTrackingColor, mesh: mesh))
        return arView
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    // Before restarting a new session, pause the AR session to avoide the warning 'ARSession is being deallocated without being paused. Please pause running sessions explicitly'.
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
    }
}

struct SessionARView_Previews: PreviewProvider {
    static var previews: some View {
        SessionARView()
    }
}
