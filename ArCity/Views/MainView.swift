import SwiftUI
import ARKit

struct MainView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ScannerView()
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }
                .tag(0)
            
            PointCloudViewer()
                .tabItem {
                    Label("View", systemImage: "eye.fill")
                }
                .tag(1)
            
            InfoView()
                .tabItem {
                    Label("Info", systemImage: "info.circle.fill")
                }
                .tag(2)
        }
        .accentColor(.green)
    }
}

struct InfoView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("App Information")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ArCity - 3D Scanner")
                            .font(.headline)
                        
                        Text("This app allows you to scan 3D point clouds of your surroundings using LiDAR and ARKit technology, save them, and view them as green dots either as a virtual object or in augmented reality.")
                            .font(.body)
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("How to Use")) {
                    NavigationLink(destination: ScanningHelpView()) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Scanning")
                        }
                    }
                    
                    NavigationLink(destination: ViewingHelpView()) {
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.green)
                                .frame(width: 30)
                            Text("Viewing")
                        }
                    }
                }
                
                Section(header: Text("Device Requirements")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("For best results:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("• iPhone with LiDAR Scanner")
                        Text("• iOS 15.0 or later")
                        Text("• Good lighting conditions")
                        
                        if !hasLiDAR() {
                            Text("Your device does not have a LiDAR scanner. Some features may be limited.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Info")
        }
    }
    
    private func hasLiDAR() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            return true
        }
        return false
        #endif
    }
}

struct ScanningHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to Scan")
                    .font(.title)
                    .padding(.top)
                
                instructionItem(
                    icon: "1.circle.fill",
                    title: "Prepare the Area",
                    description: "Make sure the area you want to scan is well-lit and has enough visual features. Avoid reflective or transparent surfaces."
                )
                
                instructionItem(
                    icon: "2.circle.fill",
                    title: "Start Scanning",
                    description: "Press the 'Start Scanning' button and slowly move around the object or person you're trying to scan."
                )
                
                instructionItem(
                    icon: "3.circle.fill",
                    title: "Move Carefully",
                    description: "Move the device steadily and slowly. Try to capture the subject from different angles while maintaining a consistent distance."
                )
                
                instructionItem(
                    icon: "4.circle.fill",
                    title: "Stop and Save",
                    description: "When you've captured enough points, tap 'Stop Scanning'. Then tap 'Save Scan' and give it a name."
                )
                
                Text("Tips for Better Scans")
                    .font(.title2)
                    .padding(.top)
                
                tipItem(
                    title: "Distance",
                    description: "Keep a distance of 0.5 to 3 meters from the subject for best results."
                )
                
                tipItem(
                    title: "Coverage",
                    description: "Try to move around the subject to capture it from multiple angles."
                )
                
                tipItem(
                    title: "Lighting",
                    description: "Scan in well-lit environments. Avoid direct sunlight that may interfere with the sensors."
                )
                
                tipItem(
                    title: "Stability",
                    description: "Hold the device steadily and move slowly to capture more accurate data."
                )
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Scanning Guide")
    }
    
    private func instructionItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func tipItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(title)
                    .font(.headline)
            }
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.leading, 25)
        }
        .padding(.vertical, 5)
    }
}

struct ViewingHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How to View Scans")
                    .font(.title)
                    .padding(.top)
                
                instructionItem(
                    icon: "1.circle.fill",
                    title: "Load a Scan",
                    description: "Tap the 'Load Scan' button and select a scan from the list of your saved scans."
                )
                
                instructionItem(
                    icon: "2.circle.fill",
                    title: "Choose View Mode",
                    description: "Select between 'Motion' mode (which uses device motion to rotate the point cloud) or 'AR' mode (which places the point cloud in your environment)."
                )
                
                instructionItem(
                    icon: "3.circle.fill",
                    title: "Interact with the Point Cloud",
                    description: "In Motion mode, move your device to see different angles. In AR mode, move around to view the point cloud from different perspectives."
                )
                
                Text("Available View Modes")
                    .font(.title2)
                    .padding(.top)
                
                modeItem(
                    icon: "gyroscope",
                    title: "Motion Mode",
                    description: "Uses your device's motion sensors to rotate the point cloud. Move your device to see different angles."
                )
                
                modeItem(
                    icon: "arkit",
                    title: "AR Mode",
                    description: "Places the point cloud in augmented reality so you can walk around it and view it from different perspectives."
                )
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Viewing Guide")
    }
    
    private func instructionItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.green)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func modeItem(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 25)
                Text(title)
                    .font(.headline)
            }
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.leading, 25)
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    MainView()
} 
