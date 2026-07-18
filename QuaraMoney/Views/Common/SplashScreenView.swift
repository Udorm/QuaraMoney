//
//  SplashScreenView.swift
//  QuaraMoney
//
//  Created by Udorm Phon on 15-03-2026.
//

import SwiftUI

struct SplashScreenView: View {
    var onFinished: () -> Void

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("AppIconDisplay")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
            }
            .scaleEffect(isAnimating ? 1.0 : 0.92)
        }
        .task {
            withAnimation(.easeOut(duration: 0.3)) {
                isAnimating = true
            }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

#Preview("Splash Screen") {
    SplashScreenView(onFinished: {})
}

#Preview("Splash Screen (Static)") {
    ZStack {
        Color(UIColor.systemBackground)
            .ignoresSafeArea()

        VStack(spacing: 16) {
            Image("AppIconDisplay")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
        }
    }
}
