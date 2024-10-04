//
//  NavView.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/4/22.
//  Contributed by Mantton
//
//  A wrapper that switches between NavigationStack and the legacy NavigationView
//

import SwiftUI

struct NavView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
        }
    }
}
