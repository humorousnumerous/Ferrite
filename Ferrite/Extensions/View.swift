//
//  View.swift
//  Ferrite
//
//  Created by Brian Dashore on 8/15/22.
//

import SwiftUI

extension View {
    // Modifies properties of a view. Works the same way as a ViewModifier
    // From: https://github.com/SwiftUIX/SwiftUIX/blob/master/Sources/Intermodular/Extensions/SwiftUI/View%2B%2B.swift#L10
    func modifyViewProp(_ body: (inout Self) -> Void) -> Self {
        var result = self
        body(&result)

        return result
    }

    // MARK: Modifiers

    func disabledAppearance(_ disabled: Bool, dimmedOpacity: Double? = nil, animation: Animation? = nil) -> some View {
        modifier(DisabledAppearanceModifier(disabled: disabled, dimmedOpacity: dimmedOpacity, animation: animation))
    }

    func disableInteraction(_ disabled: Bool) -> some View {
        modifier(DisableInteractionModifier(disabled: disabled))
    }

    func inlinedList(inset: CGFloat) -> some View {
        modifier(InlinedListModifier(inset: inset))
    }
}
