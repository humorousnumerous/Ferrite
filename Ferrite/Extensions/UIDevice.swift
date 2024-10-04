//
//  UIDevice.swift
//  Ferrite
//
//  Created by Brian Dashore on 2/16/23.
//

import UIKit

extension UIDevice {
    var hasNotch: Bool {
        UIApplication.shared.currentUIWindow?.safeAreaInsets.bottom ?? 0 > 0
    }
}
