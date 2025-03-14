import SwiftUI
import SceneKit
import CoreMotion
import ARKit
import RealityKit

struct PointCloudViewer: View {
    @StateObject private var viewerViewModel = ViewerViewModel()
    @State private var selectedScanURL: URL?
    @State private var showingScanSelector = false
    @State private var viewMode: ViewMode = .motion
    @State private var showAlert = false
    
    enum ViewMode {
        case motion, ar
    }
    
    var body: some View {
        ZStack {
            // Content based on view mode
            if viewMode == .motion {
                // Regular SceneKit view for motion-based viewing
                SceneView(scene: viewerViewModel.scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                    .edgesIgnoringSafeArea(.all)
                    .background(Color.black)
            } else {
                // AR view for viewing in augmented reality
                ARViewerContainer(pointCloud: viewerViewModel.currentPointCloud)
                    .edgesIgnoringSafeArea(.all)
            }
            
            VStack {
                // Top bar with scan name and stats
                if let currentScan = viewerViewModel.currentScan {
                    HStack {
                        Text(currentScan.name)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        if let count = viewerViewModel.currentPointCloud?.count {
                            Text("\(count) points")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.horizontal)
                } else {
                    Text("No scan loaded")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.top, 20)
                }
                
                Spacer()
                
                // Bottom controls
                VStack {
                    if viewerViewModel.currentScan != nil {
                        // View mode selector
                        Picker("View Mode", selection: $viewMode) {
                            Text("Motion").tag(ViewMode.motion)
                            Text("AR").tag(ViewMode.ar)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    Button(action: {
                        showingScanSelector = true
                    }) {
                        Text("Load Scan")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.bottom, 20)
                    .padding(.top, 10)
                }
            }
        }
        .sheet(isPresented: $showingScanSelector) {
            ScanSelectorView(onScanSelected: { url in
                selectedScanURL = url
                showingScanSelector = false
                viewerViewModel.loadPointCloud(from: url)
            })
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text(viewerViewModel.errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if viewMode == .motion {
                viewerViewModel.startMotionUpdates()
            } else {
                viewerViewModel.stopMotionUpdates()
            }
        }
        .onChange(of: viewMode) { newMode in
            if newMode == .motion {
                viewerViewModel.startMotionUpdates()
            } else {
                viewerViewModel.stopMotionUpdates()
            }
        }
        .onDisappear {
            viewerViewModel.stopMotionUpdates()
        }
    }
}

struct ARViewerContainer: UIViewRepresentable {
    var pointCloud: [SIMD3<Float>]?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR session with more robust error handling
        let configuration = ARWorldTrackingConfiguration()
        // Set more robust tracking options
        configuration.isAutoFocusEnabled = true
        configuration.environmentTexturing = .automatic
        
        // Only enable plane detection which is more stable than other options
        configuration.planeDetection = [.horizontal]
        
        // Avoid using complex features that might cause interruptions
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        
        // Set session options for more robustness
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Add coordinator as the delegate to handle session errors
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        if let points = pointCloud {
            // Load point cloud after a slight delay to ensure AR session is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                context.coordinator.displayPointCloud(points, in: arView)
            }
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Only update if the point cloud changed or is not yet displayed
        if let points = pointCloud, 
           (context.coordinator.pointCloudEntity == nil || 
            context.coordinator.lastPointCount != points.count) {
            
            // Clean up previous visualizations first
            context.coordinator.cleanupPointCloud(in: uiView)
            
            // Load with a short delay to ensure clean state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                context.coordinator.displayPointCloud(points, in: uiView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?
        var pointCloudEntity: ModelEntity?
        var lastPointCount: Int = 0
        var anchorEntity: AnchorEntity?
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("AR session failed: \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("AR session was interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("AR session interruption ended")
            // Recreate the scene if needed
            if let arView = arView, let points = getLastDisplayedPoints() {
                displayPointCloud(points, in: arView)
            }
        }
        
        // Helper to get the last displayed points
        private func getLastDisplayedPoints() -> [SIMD3<Float>]? {
            // Logic to retrieve points from the existing entity
            // This is just a placeholder - we'd need actual implementation
            return nil
        }
        
        func cleanupPointCloud(in arView: ARView) {
            // Remove previous point cloud entity
            pointCloudEntity?.removeFromParent()
            pointCloudEntity = nil
            
            // Also remove any anchors we created
            if let anchor = anchorEntity {
                anchor.removeFromParent()
                anchorEntity = nil
            }
        }
        
        func displayPointCloud(_ points: [SIMD3<Float>], in arView: ARView) {
            // Clean up previous visualization
            cleanupPointCloud(in: arView)
            
            guard !points.isEmpty else { return }
            
            // Save point count for comparison later
            lastPointCount = points.count
            
            // Create a model entity for the point cloud
            do {
                let pointCloudEntity = try createPointCloudEntity(from: points)
                
                // Use a more stable anchor (world origin) instead of plane detection
                anchorEntity = AnchorEntity(.plane(.horizontal, classification: .floor, minimumBounds: SIMD2<Float>(0.2, 0.2)))
                
                // Fallback to world origin if anchor doesn't work
                if anchorEntity == nil {
                    anchorEntity = AnchorEntity(world: .zero)
                }
                
                guard let anchorEntity = anchorEntity else {
                    print("Failed to create anchor entity")
                    return
                }
                
                anchorEntity.addChild(pointCloudEntity)
                
                // Center the point cloud for better viewing
                var center = SIMD3<Float>(0, 0, 0)
                for point in points {
                    center += point
                }
                center /= Float(points.count)
                
                // Position the point cloud at a reasonable viewing distance
                pointCloudEntity.position = SIMD3<Float>(-center.x, -center.y, -center.z)
                
                // Add to the scene
                arView.scene.addAnchor(anchorEntity)
                
                self.pointCloudEntity = pointCloudEntity
                
                print("Displayed point cloud with \(points.count) points in AR")
            } catch {
                print("Error creating point cloud entity: \(error)")
            }
        }
        
        private func createPointCloudEntity(from points: [SIMD3<Float>]) throws -> ModelEntity {
            // Create a mesh from points
            var vertices: [SIMD3<Float>] = []
            
            // Scale down the points to fit better in AR view
            let scale: Float = 0.05  // Unchanged scale - works well for most objects
            for point in points {
                vertices.append(point * scale)
            }
            
            guard !vertices.isEmpty else {
                throw NSError(domain: "ARViewerContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No vertices to display"])
            }
            
            // Create a parent entity
            let parentEntity = ModelEntity()
            
            // Size of each point representation - smaller for better detail
            let boxSize: Float = 0.002  // Was 0.004 - smaller for better detail
            
            // Create a single sphere mesh to be instanced (looks better than boxes)
            let pointMesh = MeshResource.generateSphere(radius: boxSize)
            var material = SimpleMaterial(color: UIColor.green, roughness: 0.1, isMetallic: false)
            
            // Add each point as a tiny instanced sphere
            // For better performance, we need to be selective about points
            let maxPoints = min(vertices.count, 3000) // Limit to prevent AR session issues
            let strideValue = max(1, vertices.count / maxPoints)
            
            // Create batches of points to improve memory usage
            let batchSize = 500
            var currentBatch = 0
            var batchParent = ModelEntity()
            
            for i in stride(from: 0, to: vertices.count, by: strideValue) {
                // Create a new batch parent every batchSize points
                if currentBatch % batchSize == 0 {
                    // Add completed batch to parent
                    if currentBatch > 0 {
                        parentEntity.addChild(batchParent)
                        batchParent = ModelEntity()
                    }
                }
                
                let point = ModelEntity(mesh: pointMesh, materials: [material])
                point.position = vertices[i]
                batchParent.addChild(point)
                currentBatch += 1
                
                // Stop if we've reached the maximum allowable points
                if currentBatch >= maxPoints {
                    break
                }
            }
            
            // Add the final batch
            if batchParent.children.count > 0 {
                parentEntity.addChild(batchParent)
            }
            
            print("Displaying \(currentBatch) points out of \(vertices.count) total in \(ceil(Double(currentBatch) / Double(batchSize))) batches")
            
            return parentEntity
        }
    }
}

struct ScanSelectorView: View {
    @State private var availableScans: [URL] = []
    @State private var isLoading = true
    var onScanSelected: (URL) -> Void
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading scans...")
                } else if availableScans.isEmpty {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .padding()
                        
                        Text("No saved scans found")
                            .font(.headline)
                        
                        Text("Create a scan first using the Scanner tab")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                } else {
                    List {
                        ForEach(availableScans, id: \.self) { url in
                            Button(action: {
                                onScanSelected(url)
                            }) {
                                VStack(alignment: .leading) {
                                    Text(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_\\d+$", with: "", options: .regularExpression))
                                        .font(.headline)
                                    
                                    Text(formatDate(from: url.lastPathComponent))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Available Scans")
            .onAppear {
                isLoading = true
                // Load scans in the background
                DispatchQueue.global().async {
                    let scans = PointCloudStore.shared.getAllSavedPointClouds().sorted { a, b in
                        a.lastPathComponent > b.lastPathComponent
                    }
                    
                    DispatchQueue.main.async {
                        availableScans = scans
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func formatDate(from filename: String) -> String {
        // Extract timestamp from filename
        if let timestampString = filename.split(separator: "_").last?.split(separator: ".").first,
           let timestamp = Double(timestampString) {
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return filename
    }
}

class ViewerViewModel: ObservableObject {
    @Published var currentScan: PointCloudData?
    @Published var errorMessage: String?
    @Published var currentPointCloud: [SIMD3<Float>]?
    
    let scene = SCNScene()
    private let cameraNode = SCNNode()
    private var pointCloudNode = SCNNode()
    private let motionManager = CMMotionManager()
    
    init() {
        setupScene()
    }
    
    private func setupScene() {
        // Set the scene background to black
        scene.background.contents = UIColor.black
        
        // Setup camera
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 2) // Position the camera 2 units away from the origin
        scene.rootNode.addChildNode(cameraNode)
        
        // Add empty point cloud node for later population
        scene.rootNode.addChildNode(pointCloudNode)
    }
    
    func loadPointCloud(from url: URL) {
        do {
            let pointCloudData = try PointCloudStore.shared.load(from: url)
            displayPointCloud(pointCloudData)
            self.currentScan = pointCloudData
            self.currentPointCloud = pointCloudData.points
            print("Loaded point cloud with \(pointCloudData.points.count) points")
        } catch {
            errorMessage = "Failed to load scan: \(error.localizedDescription)"
            print("Error loading point cloud: \(error)")
        }
    }
    
    private func displayPointCloud(_ pointCloudData: PointCloudData) {
        // Clear any existing point cloud
        pointCloudNode.removeFromParentNode()
        let newPointCloudNode = SCNNode()
        
        // Calculate centroid for centering
        var centroid = SIMD3<Float>(0, 0, 0)
        for point in pointCloudData.points {
            centroid += point
        }
        if !pointCloudData.points.isEmpty {
            centroid /= Float(pointCloudData.points.count)
        }
        
        // Create geometry with points
        let pointCount = pointCloudData.points.count
        var vertices = [SCNVector3]()
        
        for point in pointCloudData.points {
            // Center the point cloud around the origin
            let centeredPoint = point - centroid
            vertices.append(SCNVector3(centeredPoint.x, centeredPoint.y, centeredPoint.z))
        }
        
        // Create point cloud geometry with improved visuals
        let geometry = SCNGeometry.pointCloudGeometry(with: vertices, color: .green, size: 7)
        newPointCloudNode.geometry = geometry
        
        // Add to scene
        scene.rootNode.addChildNode(newPointCloudNode)
        self.pointCloudNode = newPointCloudNode
        
        print("Displayed \(pointCount) points")
    }
    
    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else { return }
            
            // Use attitude (orientation) to update camera
            let attitude = motion.attitude
            
            // Convert attitude to rotation matrix
            var rotationMatrix = SCNMatrix4Identity
            rotationMatrix = SCNMatrix4Rotate(rotationMatrix, Float(attitude.roll), 1, 0, 0)
            rotationMatrix = SCNMatrix4Rotate(rotationMatrix, Float(attitude.pitch), 0, 1, 0)
            rotationMatrix = SCNMatrix4Rotate(rotationMatrix, Float(attitude.yaw), 0, 0, 1)
            
            // Apply rotation to point cloud rather than camera for better effect
            self.pointCloudNode.transform = rotationMatrix
        }
    }
    
    func stopMotionUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
}

// Extension to create point cloud geometry with improved visuals
extension SCNGeometry {
    static func pointCloudGeometry(with points: [SCNVector3], color: UIColor, size: CGFloat) -> SCNGeometry {
        let vertexData = NSData(
            bytes: points,
            length: MemoryLayout<SCNVector3>.size * points.count
        )
        
        let positionSource = SCNGeometrySource(
            data: vertexData as Data,
            semantic: .vertex,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let pointSize = size
        let pointElement = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: 0
        )
        pointElement.pointSize = pointSize
        pointElement.minimumPointScreenSpaceRadius = pointSize / 2
        pointElement.maximumPointScreenSpaceRadius = pointSize * 2
        
        let pointsGeometry = SCNGeometry(sources: [positionSource], elements: [pointElement])
        
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.lightingModel = .constant // No lighting effect
        
        // Make points glow slightly
        material.emission.contents = color.withAlphaComponent(0.3)
        
        pointsGeometry.materials = [material]
        
        return pointsGeometry
    }
} 