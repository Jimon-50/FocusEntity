//
//  FocusEntity+Colored.swift
//  FocusEntity
//
//  Created by Max Cobb on 8/26/19.
//  Copyright © 2019 Max Cobb. All rights reserved.
//

import RealityKit

/// An extension of FocusEntity holding the methods for the "colored" style.
public extension FocusEntity {

    internal func coloredStateChanged() {
        guard let coloredStyle = self.focus.coloredStyle else {
            return
        }
        var endColor: MaterialColorParameter
        if self.state == .initializing {
            endColor = coloredStyle.nonTrackingColor
        } else {
            endColor = self.onPlane ? coloredStyle.onColor : coloredStyle.offColor
        }
        if self.fillPlane?.model?.materials.count == 0 {
            self.fillPlane?.model?.materials = [SimpleMaterial()]
        }
        var modelMaterial: Material!
        if #available(iOS 15, macOS 12, *) {
            var mat = PhysicallyBasedMaterial()
            switch endColor {
            case .color(let uikitColour):
                mat.baseColor = .init(tint: .black.withAlphaComponent(uikitColour.cgColor.alpha))
                mat.emissiveColor = .init(color: uikitColour)
                mat.emissiveIntensity = 2
            case .texture(let tex):
                mat.baseColor = .init(tint: .white.withAlphaComponent(0.9999), texture: .init(tex))
            @unknown default: break
            }
            modelMaterial = mat
        } else {
            var mat = UnlitMaterial(color: .clear)
            mat.baseColor = endColor
            mat.tintColor = .white.withAlphaComponent(0.9999)
            modelMaterial = mat
        }
        self.fillPlane?.model?.materials[0] = modelMaterial
    }
}
