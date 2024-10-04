//
//  InlinedList.swift
//  Ferrite
//
//  Created by Brian Dashore on 9/4/22.
//
//  Removes the top padding on unsectioned lists
//  If a list is sectioned, see InlineHeader
//

import SwiftUI
import SwiftUIIntrospect

struct InlinedListModifier: ViewModifier {
    let inset: CGFloat

    func body(content: Content) -> some View {
        content
            .introspect(.list, on: .iOS(.v16, .v17, .v18)) { collectionView in
                collectionView.contentInset.top = inset
            }
    }
}
