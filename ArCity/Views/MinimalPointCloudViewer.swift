import SwiftUI
import SceneKit
import ARKit
import RealityKit

struct MinimalPointCloudViewer: View {
    @StateObject private var viewModel = MinimalViewerViewModel()
    @State private var viewMode: ViewMode = .scene
    @State private var showScanSelector = false
    @State private var showDebugOptions = false
    
    enum ViewMode {
        case scene, ar
    }
    
    var body: some View {
        ZStack {
            // Main viewer based on selected mode
            if viewMode == .scene {
                // 3D scene view for regular viewing
                SceneView(scene: viewModel.scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                    .edgesIgnoringSafeArea(.all)
                    .background(Color.black)
            } else {
                // AR view for immersive viewing
                MinimalARViewerContainer(pointCloud: viewModel.currentPointCloud)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Overlay UI
            VStack {
                // Top bar with model name
                if let currentScan = viewModel.currentScan {
                    HStack {
                        Text(currentScan.name)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(15)
                        
                        Spacer()
                        
                        Button(action: { showScanSelector = true }) {
                            Label("Change", systemImage: "square.grid.2x2")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(15)
                        }
                    }
                    .padding()
                    
                    // View mode toggle
                    Picker("View Mode", selection: $viewMode) {
                        Text("3D Model").tag(ViewMode.scene)
                        Text("AR Walk").tag(ViewMode.ar)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 60)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                } else {
                    // Prompt when no model is loaded
                    VStack(spacing: 20) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("No room model loaded")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Button(action: { showScanSelector = true }) {
                            Text("Load a model")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(25)
                        }
                        
                        // Debug button
                        Button(action: {
                            showDebugOptions = true
                        }) {
                            Text("Debug Options")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.purple.opacity(0.8))
                                .cornerRadius(20)
                        }
                        .padding(.top, 16)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(15)
                }
                
                Spacer()
                
                // Bottom instructions
                if viewModel.currentScan != nil {
                    VStack {
                        if viewMode == .scene {
                            // 3D view instructions
                            HStack {
                                Image(systemName: "hand.draw")
                                Text("Pinch to zoom, drag to rotate")
                            }
                        } else {
                            // AR view instructions
                            HStack {
                                Image(systemName: "figure.walk")
                                Text("Walk around to explore the room")
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showScanSelector) {
            MinimalScanSelectorView(onScanSelected: { url in
                viewModel.loadPointCloud(from: url)
                showScanSelector = false
            })
        }
        .actionSheet(isPresented: $showDebugOptions) {
            ActionSheet(
                title: Text("Debug Options"),
                message: Text("Choose a debug action"),
                buttons: [
                    .default(Text("Create Test Model")) {
                        viewModel.createAndLoadTestModel()
                    },
                    .default(Text("List Available Models")) {
                        viewModel.listAndPrintAvailableModels()
                    },
                    .default(Text("Print Debug Info")) {
                        viewModel.printDebugInfo()
                    },
                    .cancel()
                ]
            )
        }
        .onAppear {
            // Load most recent scan if available
            viewModel.loadMostRecentScan()
        }
    }
}

// AR Viewer Container
struct MinimalARViewerContainer: UIViewRepresentable {
    var pointCloud: [SIMD3<Float>]?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        arView.session.run(configuration)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Clear previous content
        uiView.scene.anchors.removeAll()
        
        guard let points = pointCloud, !points.isEmpty else { 
            print("No points to display in AR")
            return 
        }
        
        print("Displaying \(points.count) points in AR")
        
        // Create an anchor for the point cloud
        let anchor = AnchorEntity()
        
        // Place the anchor 1 meter in front of the camera
        anchor.position = [0, 0, -1]
        
        // For memory efficiency, limit points and use aggressive sampling
        let maxPointsInAR = 5000 // AR mode needs to be even more limited
        let samplingRate = max(1, points.count / maxPointsInAR) // Use at most 5,000 points
        
        // Use stride to sample points evenly
        var sampledPoints = [SIMD3<Float>]()
        for i in stride(from: 0, to: points.count, by: samplingRate) {
            if sampledPoints.count < maxPointsInAR {
                sampledPoints.append(points[i])
            } else {
                break
            }
        }
        
        print("Sampled down to \(sampledPoints.count) points for AR display (memory optimization)")
        
        // For better performance, batch points into entities
        let batchSize = 100 // Smaller batches for AR performance and memory usage
        
        // Process in autoreleasepools to manage memory
        autoreleasepool {
            let batches = stride(from: 0, to: sampledPoints.count, by: batchSize).map {
                Array(sampledPoints[($0)..<min($0 + batchSize, sampledPoints.count)])
            }
            
            // Add batches to the scene
            for (index, batch) in batches.enumerated() {
                if index % 5 == 0 {
                    print("Creating AR batch \(index)/\(batches.count)")
                }
                
                autoreleasepool {
                    let entity = createSimplePointEntity(for: batch)
                    anchor.addChild(entity)
                }
            }
        }
        
        // Add the anchor to the scene
        uiView.scene.addAnchor(anchor)
    }
    
    // Create a more efficient point representation for AR
    private func createSimplePointEntity(for points: [SIMD3<Float>]) -> ModelEntity {
        let parentEntity = ModelEntity()
        
        // Use a single shared mesh and material for all points to save memory
        let sphereMesh = MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: .green, isMetallic: false)
        
        // Add points batch by batch
        for point in points {
            autoreleasepool {
                // Use tiny spheres to represent points
                let sphere = ModelEntity(
                    mesh: sphereMesh, // Reuse the same mesh
                    materials: [material] // Reuse the same material
                )
                sphere.position = point
                parentEntity.addChild(sphere)
            }
        }
        
        return parentEntity
    }
}

// Scan Selector View
struct MinimalScanSelectorView: View {
    @StateObject private var viewModel = ScanSelectorViewModel()
    var onScanSelected: (URL) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.availableScans, id: \.url) { scan in
                    Button(action: {
                        onScanSelected(scan.url)
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(scan.name)
                                    .font(.headline)
                                
                                Text(scan.formattedDate)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(scan.pointCount) points")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    viewModel.deleteScans(at: indexSet)
                }
            }
            .navigationTitle("Your Room Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .onAppear {
                viewModel.loadAvailableScans()
            }
        }
    }
}

// View Models
class MinimalViewerViewModel: ObservableObject {
    @Published var scene = SCNScene()
    @Published var currentScan: PointCloudData?
    @Published var currentPointCloud: [SIMD3<Float>]?
    @Published var loadingError: String?
    
    func loadPointCloud(from url: URL) {
        do {
            print("Attempting to load point cloud from: \(url.path)")
            
            // Load point cloud from storage
            let data = try Data(contentsOf: url)
            print("Data loaded, size: \(data.count) bytes")
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Decode the point cloud data
            let pointCloudData = try decoder.decode(PointCloudData.self, from: data)
            print("Successfully decoded point cloud with \(pointCloudData.points.count) points")
            
            self.currentScan = pointCloudData
            self.currentPointCloud = pointCloudData.points
            
            // Create and configure the scene
            createScene(with: pointCloudData.points)
            
        } catch {
            print("Error loading point cloud: \(error.localizedDescription)")
            loadingError = error.localizedDescription
            self.currentScan = nil
            self.currentPointCloud = nil
        }
    }
    
    func loadMostRecentScan() {
        // List available scans and try to load the most recent one
        print("Looking for most recent scan...")
        
        // Get list of scans using our new method
        let jsonFiles = PointCloudStore.shared.listAvailableScans()
        
        if jsonFiles.isEmpty {
            print("No scan files found")
            return
        }
        
        // Sort by modification date to get most recent
        do {
            if let mostRecent = jsonFiles.sorted(by: { 
                let date1 = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let date2 = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return date1 ?? Date.distantPast > date2 ?? Date.distantPast
            }).first {
                print("Loading most recent scan: \(mostRecent.lastPathComponent)")
                loadPointCloud(from: mostRecent)
            } else {
                print("Could not sort scan files by date")
            }
        } catch {
            print("Error sorting scans: \(error.localizedDescription)")
        }
    }
    
    private func createScene(with points: [SIMD3<Float>]) {
        print("Creating scene with \(points.count) points")
        
        // Create a new scene
        let scene = SCNScene()
        
        // Ensure we have points
        guard !points.isEmpty else {
            print("Warning: Creating scene with empty point cloud")
            self.scene = scene
            return
        }
        
        // Add point cloud visualization
        let pointNode = createPointCloudNode(with: points)
        scene.rootNode.addChildNode(pointNode)
        
        // Add a camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        
        // Position the camera at a good distance
        // Calculate bounds of points to determine a good camera position
        var minX: Float = Float.greatestFiniteMagnitude
        var maxX: Float = -Float.greatestFiniteMagnitude
        var minY: Float = Float.greatestFiniteMagnitude
        var maxY: Float = -Float.greatestFiniteMagnitude
        var minZ: Float = Float.greatestFiniteMagnitude
        var maxZ: Float = -Float.greatestFiniteMagnitude
        
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
        
        // Calculate center and size
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2
        let sizeX = maxX - minX
        let sizeY = maxY - minY
        let sizeZ = maxZ - minZ
        let maxSize = max(max(sizeX, sizeY), sizeZ)
        
        // Position camera to see the entire model
        let distance = maxSize * 1.5 // Distance from center based on size
        cameraNode.position = SCNVector3(centerX, centerY, centerZ + distance)
        
        // Look at center
        let lookAtConstraint = SCNLookAtConstraint(target: scene.rootNode)
        cameraNode.constraints = [lookAtConstraint]
        
        scene.rootNode.addChildNode(cameraNode)
        
        // Add ambient light
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLightNode)
        
        // Update the scene
        self.scene = scene
        print("Scene created successfully")
    }
    
    private func createPointCloudNode(with points: [SIMD3<Float>]) -> SCNNode {
        print("Creating point cloud node with \(points.count) points")
        let node = SCNNode()
        
        // For better memory performance, limit total points to render
        let maxPointsToRender = 100000 // Limit to 100K points max
        
        // Calculate sampling rate based on number of points
        let samplingRate = max(1, points.count / maxPointsToRender)
        let sampledPoints = stride(from: 0, to: points.count, by: samplingRate).map { points[$0] }
        print("Sampled down to \(sampledPoints.count) points for better memory usage")
        
        // For performance, split points into smaller batches
        let batchSize = 2000 // Reduced from 5000 to 2000 for better memory management
        let batches = stride(from: 0, to: sampledPoints.count, by: batchSize).map {
            Array(sampledPoints[$0..<min($0 + batchSize, sampledPoints.count)])
        }
        
        print("Split into \(batches.count) batches")
        
        // Use autoreleasepool for each batch to help with memory
        for (index, batch) in batches.enumerated() {
            autoreleasepool {
                let batchNode = createPointBatchNode(with: batch)
                node.addChildNode(batchNode)
                
                if index % 5 == 0 {
                    print("Added batch \(index+1)/\(batches.count)")
                }
            }
        }
        
        print("Point cloud node created")
        return node
    }
    
    private func createPointBatchNode(with points: [SIMD3<Float>]) -> SCNNode {
        // Create a node to hold points
        let node = SCNNode()
        
        // Create geometry for the points
        let geometry = SCNGeometry.pointCloud(with: points)
        node.geometry = geometry
        
        return node
    }
    
    func createAndLoadTestModel() {
        print("Creating and loading test model...")
        
        // Create and save a test model
        if let url = PointCloudStore.shared.saveTestModel() {
            // Load the created test model
            loadPointCloud(from: url)
            print("Test model created and loaded")
        } else {
            print("Failed to create test model")
        }
    }
    
    func listAndPrintAvailableModels() {
        print("\n--- LISTING ALL AVAILABLE MODELS ---")
        let allModels = PointCloudStore.shared.listAvailableScans()
        
        if allModels.isEmpty {
            print("No models found in storage")
            return
        }
        
        print("Found \(allModels.count) models:")
        for (index, modelURL) in allModels.enumerated() {
            print("\(index+1). \(modelURL.lastPathComponent)")
            
            // Try to load the model data for additional debug info
            do {
                let data = try Data(contentsOf: modelURL)
                print("   - File size: \(data.count) bytes")
                
                // Try to decode
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let modelData = try decoder.decode(PointCloudData.self, from: data)
                print("   - Name: \(modelData.name)")
                print("   - Points: \(modelData.points.count)")
                print("   - Date: \(modelData.timestamp)")
            } catch {
                print("   - Error reading data: \(error.localizedDescription)")
            }
        }
        print("--- END OF MODEL LISTING ---\n")
    }
    
    func printDebugInfo() {
        print("\n====== DEBUG INFORMATION ======")
        
        // App info
        print("App Directory: \(PointCloudStore.shared.getDirectory().path)")
        
        // Check if directory exists
        let dirExists = FileManager.default.fileExists(atPath: PointCloudStore.shared.getDirectory().path)
        print("Directory exists: \(dirExists)")
        
        // Current model info
        if let currentModel = currentScan {
            print("\nCurrent Model:")
            print("- Name: \(currentModel.name)")
            print("- Points: \(currentModel.points.count)")
            print("- Date: \(currentModel.timestamp)")
            
            if let firstPoint = currentModel.points.first {
                print("- Sample point: (\(firstPoint.x), \(firstPoint.y), \(firstPoint.z))")
            }
        } else {
            print("\nNo model currently loaded")
        }
        
        // Available models
        let availableModels = PointCloudStore.shared.listAvailableScans()
        print("\nAvailable Models: \(availableModels.count)")
        
        // Check if models can be loaded
        for (index, url) in availableModels.enumerated() {
            print("\nModel \(index+1): \(url.lastPathComponent)")
            do {
                let data = try Data(contentsOf: url)
                print("- File size: \(data.count) bytes")
                
                // Try to decode
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let model = try decoder.decode(PointCloudData.self, from: data)
                print("- Successfully decoded")
                print("- Name: \(model.name)")
                print("- Points: \(model.points.count)")
            } catch {
                print("- Error loading: \(error.localizedDescription)")
            }
        }
        
        print("\n====== END DEBUG INFO ======")
    }
}

class ScanSelectorViewModel: ObservableObject {
    struct ScanInfo {
        let name: String
        let url: URL
        let date: Date
        let pointCount: Int
        
        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    @Published var availableScans: [ScanInfo] = []
    
    func loadAvailableScans() {
        print("Loading available scans...")
        
        // Use our new method to list scans
        let jsonFiles = PointCloudStore.shared.listAvailableScans()
        
        if jsonFiles.isEmpty {
            self.availableScans = []
            return
        }
        
        // Load scan info for each file
        var scans: [ScanInfo] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for fileURL in jsonFiles {
            do {
                print("Loading scan details from: \(fileURL.lastPathComponent)")
                let data = try Data(contentsOf: fileURL)
                let pointCloud = try decoder.decode(PointCloudData.self, from: data)
                
                let scan = ScanInfo(
                    name: pointCloud.name,
                    url: fileURL,
                    date: pointCloud.timestamp,
                    pointCount: pointCloud.points.count
                )
                
                print("Successfully loaded scan: \(pointCloud.name) with \(pointCloud.points.count) points")
                scans.append(scan)
            } catch {
                print("Error loading scan \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        // Sort by date, newest first
        self.availableScans = scans.sorted { $0.date > $1.date }
        print("Loaded \(self.availableScans.count) scans")
    }
    
    func deleteScans(at offsets: IndexSet) {
        let scansToDelete = offsets.map { availableScans[$0] }
        
        for scan in scansToDelete {
            do {
                try FileManager.default.removeItem(at: scan.url)
            } catch {
                print("Error deleting scan: \(error)")
            }
        }
        
        // Update the list
        availableScans.remove(atOffsets: offsets)
    }
}

// Point cloud geometry extension - memory optimized version
extension SCNGeometry {
    static func pointCloud(with points: [SIMD3<Float>]) -> SCNGeometry {
        // Memory protection - limit maximum points for geometry
        let maxGeometryPoints = 150000
        
        // Sample if needed
        let pointsToDraw: [SIMD3<Float>]
        if points.count > maxGeometryPoints {
            print("Point cloud too large for geometry - sampling down to \(maxGeometryPoints) points")
            let samplingRate = points.count / maxGeometryPoints
            pointsToDraw = stride(from: 0, to: points.count, by: samplingRate)
                .map { points[$0] }
                .prefix(maxGeometryPoints)
                .map { $0 }
        } else {
            pointsToDraw = points
        }
        
        // Create vertices from points
        let vertices = pointsToDraw.map { SCNVector3($0.x, $0.y, $0.z) }
        
        let pointCount = vertices.count
        print("Creating geometry with \(pointCount) points")
        
        // Use autoreleasepool to manage memory during data transformation
        return autoreleasepool {
            let vertexData = Data(bytes: vertices, count: MemoryLayout<SCNVector3>.stride * pointCount)
            let vertexSource = SCNGeometrySource(data: vertexData,
                                          semantic: .vertex,
                                     vectorCount: pointCount,
                                 usesFloatComponents: true,
                           componentsPerVector: 3,
                             bytesPerComponent: MemoryLayout<Float>.size,
                                    dataOffset: 0,
                                    dataStride: MemoryLayout<SCNVector3>.stride)
            
            // Create geometry elements for points
            let pointElements = SCNGeometryElement(data: nil,
                                         primitiveType: .point,
                                        primitiveCount: pointCount,
                                        bytesPerIndex: MemoryLayout<Int>.size)
            
            // Create geometry from sources and elements
            let pointGeometry = SCNGeometry(sources: [vertexSource], elements: [pointElements])
            
            // Configure the visual appearance
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.green
            material.lightingModel = .constant // No lighting
            material.isDoubleSided = true
            
            // Increase point size for better visibility
            material.setValue(NSNumber(value: 5.0), forKey: "pointSize")
            
            pointGeometry.firstMaterial = material
            
            return pointGeometry
        }
    }
} 