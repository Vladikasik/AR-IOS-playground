//
//  ContentView.swift
//  ArCity
//
//  Created by Vladislav Ainshtein on 14.03.25.
//

import SwiftUI

struct ContentView: View {
    @State private var activeView: ActiveView = .scanner
    
    enum ActiveView {
        case scanner, viewer
    }
    
    var body: some View {
        ZStack {
            switch activeView {
            case .scanner:
                MinimalScannerView()
            case .viewer:
                MinimalPointCloudViewer()
            }
            
            // Minimalistic toggle button at the bottom
            VStack {
                Spacer()
                
                Button(action: {
                    withAnimation {
                        activeView = activeView == .scanner ? .viewer : .scanner
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: activeView == .scanner ? "eye" : "camera")
                            .font(.system(size: 22))
                        Text(activeView == .scanner ? "View Model" : "Scan Room")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(30)
                }
                .padding(.bottom, 30)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    ContentView()
}
