//
//  VideoGridGeneratorApp.swift
//  VideoGridGenerator
//
//  Created by Alexander Vaynshteyn on 12/8/25.
//

import SwiftUI

@main
struct VideoGridGeneratorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = GeneratorViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // S3: Cancel work when app is backgrounded or closed
            if newPhase == .inactive || newPhase == .background {
                viewModel.cancelGeneration()
            }
        }
    }
}
