//
//  InlineHeader.swift
//  Ferrite
//
//  Created by Brian Dashore on 9/5/22.
//
//  For iOS 15's weird defaults regarding sectioned list padding
//

import SwiftUI

struct InlineHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
    }
}
