//
//  DebridLabelView.swift
//  Ferrite
//
//  Created by Brian Dashore on 11/27/22.
//

import SwiftUI

struct DebridLabelView: View {
    @Store var debridSource: DebridSource

    @State var cloudLinks: [String] = []
    @State var tagColor: Color = .red
    var magnet: Magnet?

    var body: some View {
        Tag(
            name: debridSource.id.abbreviation,
            color: tagColor,
            horizontalPadding: 5,
            verticalPadding: 3
        )
        .onAppear {
            tagColor = getTagColor()
        }
        .onChange(of: debridSource.IAValues) { _ in
            tagColor = getTagColor()
        }
    }

    func getTagColor() -> Color {
        if let magnet, cloudLinks.isEmpty {
            guard let match = debridSource.IAValues.first(where: { magnet.hash == $0.magnet.hash }) else {
                return .red
            }

            return match.files.count > 1 ? .orange : .green
        } else if cloudLinks.count == 1 {
            return .green
        } else if cloudLinks.count > 1 {
            return .orange
        } else {
            return .red
        }
    }
}
