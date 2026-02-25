//
//  SwiftUIView.swift
//  ExampleProject
//
//  Created by Behruz on 03/02/26.
//

import SwiftUI

struct CustomLoaderView: View {
    let size: CGFloat
    
    init(size: CGFloat = 1.0) {
        self.size = size
    }
    
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .scaleEffect(CGSize(width: size, height: size))
    }
}

#Preview {
    CustomLoaderView(size: 2)
}
