import SwiftUI
import ARKit
import RealityKit
import Combine
import Foundation

struct MinimalScannerView: View {
    @StateObject private var viewModel = MinimalScannerViewModel()
    @State private var showSaveDialog = false
    @State private var scanName = ""
    
    var body: some View {
        ZStack {
            // AR View
            MinimalARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay UI
            VStack {
                // Status indicator at top
                HStack {
                    // Scan status
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.isScanning ? Color.red : Color.gray)
                            .frame(width: 12, height: 12)
                        
                        Text(viewModel.statusMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    
                    Spacer()
                    
                    // Point counter
                    if viewModel.isScanning || viewModel.pointCount > 0 {
                        Text("\(viewModel.pointCount) points")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                    }
                }
                .foregroundColor(.white)
                .padding()
                
                // Memory usage indicator
                if viewModel.isScanning {
                    HStack {
                        Text("Memory: \(viewModel.memoryUsageString)")
                            .font(.caption)
                            .foregroundColor(viewModel.memoryWarningColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                // Visual scan guidance in the middle (when not scanning)
                if !viewModel.isScanning {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text("Move around to scan your room")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(16)
                    
                    Spacer()
                }
                
                // Scan guidance or progress indicator (during scanning)
                if viewModel.isScanning {
                    ScanQualityIndicator(
                        coverage: viewModel.scanCoverage,
                        numberOfPoints: viewModel.pointCount
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                
                // Action buttons
                HStack(spacing: 20) {
                    // Reset button
                    if viewModel.pointCount > 0 && !viewModel.isScanning {
                        Button(action: viewModel.resetScan) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.8))
                                .cornerRadius(25)
                        }
                    }
                    
                    // Main action button
                    Button(action: {
                        if viewModel.isScanning {
                            viewModel.stopScanning()
                            if viewModel.pointCount > 0 {
                                showSaveDialog = true
                            }
                        } else {
                            viewModel.startScanning()
                        }
                    }) {
                        Label(
                            viewModel.isScanning ? "Stop Scan" : "Start Scan",
                            systemImage: viewModel.isScanning ? "stop.circle" : "record.circle"
                        )
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(viewModel.isScanning ? Color.red.opacity(0.8) : Color.blue.opacity(0.8))
                        .cornerRadius(30)
                    }
                    
                    // Save button (when appropriate)
                    if viewModel.pointCount > 0 && !viewModel.isScanning {
                        Button(action: { showSaveDialog = true }) {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.8))
                                .cornerRadius(25)
                        }
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .alert("Save Your Room Scan", isPresented: $showSaveDialog) {
            TextField("Room Name", text: $scanName)
                .autocapitalization(.words)
            
            Button("Cancel", role: .cancel) {
                showSaveDialog = false
            }
            
            Button("Save") {
                if !scanName.isEmpty {
                    viewModel.saveScan(name: scanName)
                    scanName = ""
                }
                showSaveDialog = false
            }
        } message: {
            Text("Give your 3D room model a name")
        }
        .onAppear {
            viewModel.checkPermissions()
        }
    }
}

struct ScanQualityIndicator: View {
    let coverage: Double // 0.0 to 1.0
    let numberOfPoints: Int
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(coverageColor)
                    .frame(width: max(CGFloat(coverage) * UIScreen.main.bounds.width - 40, 0), height: 8)
            }
            
            HStack {
                Text("Scan Coverage")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text(coverageText)
                    .font(.caption)
                    .foregroundColor(coverageColor)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
    
    private var coverageColor: Color {
        if coverage < 0.3 {
            return .red
        } else if coverage < 0.7 {
            return .yellow
        } else {
            return .green
        }
    }
    
    private var coverageText: String {
        if coverage < 0.3 {
            return "Poor - Keep scanning"
        } else if coverage < 0.7 {
            return "Good - Continue"
        } else {
            return "Excellent"
        }
    }
}

// AR View Container - Renamed to MinimalARViewContainer to avoid conflicts
struct MinimalARViewContainer: UIViewRepresentable {
    var viewModel: MinimalScannerViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        viewModel.setupARView(arView)
        
        // Setup point visualization
        viewModel.pointVisualizationHandler = { points in
            // Update point visualization in real-time
            context.coordinator.updatePointVisualization(points: points)
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Updates are handled by the coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var viewModel: MinimalScannerViewModel
        var arView: ARView?
        private var pointCloudAnchor: AnchorEntity?
        
        init(viewModel: MinimalScannerViewModel) {
            self.viewModel = viewModel
            super.init()
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            viewModel.handleSessionError(error)
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            if viewModel.isScanning {
                viewModel.processARFrame(frame)
            }
        }
        
        func updatePointVisualization(points: [SIMD3<Float>]) {
            guard let arView = arView else { return }
            
            // Remove existing point cloud anchor if exists
            if let existingAnchor = pointCloudAnchor {
                arView.scene.removeAnchor(existingAnchor)
            }
            
            // Create new anchor
            let anchor = AnchorEntity(world: .zero)
            pointCloudAnchor = anchor
            
            // Only visualize a subset of points for better performance
            // Sample more sparsely as point count grows
            let maxPointsToShow = 2000 // Limit for real-time visualization
            let samplingRate = max(1, points.count / maxPointsToShow)
            
            // Use striding to sample points evenly
            let sampledPoints = stride(from: 0, to: points.count, by: samplingRate).map { points[$0] }
            
            // Create point visualization
            let parentEntity = ModelEntity()
            
            // Use even smaller spheres for better performance
            let sphereMesh = MeshResource.generateSphere(radius: 0.005)
            let material = SimpleMaterial(color: .green, isMetallic: false)
            
            // Add a point entity for each sampled point
            for point in sampledPoints {
                let sphere = ModelEntity(mesh: sphereMesh, materials: [material])
                sphere.position = point
                parentEntity.addChild(sphere)
            }
            
            // Add the entity to the anchor
            anchor.addChild(parentEntity)
            
            // Add to scene
            arView.scene.addAnchor(anchor)
        }
    }
}

// View Model
class MinimalScannerViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var pointCount = 0
    @Published var scanCoverage: Double = 0.0
    @Published var statusMessage = "Ready to scan"
    @Published var memoryUsageString: String = "0 MB"
    @Published var memoryWarningColor: Color = .green
    
    private var arView: ARView?
    private var pointCloud: [SIMD3<Float>] = []
    private var pointCloudVolumeEstimate: Float = 0
    private var pointCloudDensity: Float = 0
    private var lastFrameTime: TimeInterval = 0
    private var lastVisualizationUpdateTime: TimeInterval = 0
    private var sampleRate: TimeInterval = 0.2 // Capture points every 0.2 seconds
    private var visualizationUpdateRate: TimeInterval = 1.0 // Update visualization less frequently
    private var errorHandler: ((String) -> Void)?
    private var memoryMonitorTimer: Timer?
    
    // For voxel grid filtering during scanning
    private var voxelGridDict: [ArCity.VoxelKey: SIMD3<Float>] = [:]
    private let voxelSize: Float = 0.02
    
    // Maximum number of points to prevent memory issues
    private let maxPointsAllowed = 150000
    
    // Memory thresholds in MB - increased for iPhone 15 Pro Max
    private let memoryWarningThreshold: Double = 1000  // 1GB (increased from 250MB)
    private let memoryCriticalThreshold: Double = 1500 // 1.5GB (increased from 350MB)
    
    // Handler for visualizing points in AR view
    var pointVisualizationHandler: (([SIMD3<Float>]) -> Void)?
    
    deinit {
        memoryMonitorTimer?.invalidate()
    }
    
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh // Use mesh reconstruction for better results
        configuration.environmentTexturing = .none // No textures needed
        
        // Check if LiDAR is available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        arView.session.run(configuration)
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break // Already authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                // Handle response
            }
        default:
            statusMessage = "Camera access required"
        }
    }
    
    func startScanning() {
        isScanning = true
        statusMessage = "Scanning..."
        lastFrameTime = CACurrentMediaTime()
        lastVisualizationUpdateTime = CACurrentMediaTime()
        
        // Reset voxel grid to start fresh
        voxelGridDict.removeAll()
        
        // Delay memory monitoring to avoid false alarms at startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.startMemoryMonitoring()
        }
    }
    
    func stopScanning() {
        isScanning = false
        statusMessage = "Scan complete"
        
        // Stop memory monitoring
        memoryMonitorTimer?.invalidate()
        
        // One final visualization update
        pointVisualizationHandler?(pointCloud)
    }
    
    func resetScan() {
        pointCloud = []
        voxelGridDict.removeAll()
        pointCount = 0
        scanCoverage = 0.0
        statusMessage = "Ready to scan"
        
        // Update visualization
        pointVisualizationHandler?(pointCloud)
    }
    
    private func startMemoryMonitoring() {
        // Update memory usage immediately
        updateMemoryUsage()
        
        // Set up timer to periodically check memory usage
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateMemoryUsage()
        }
    }
    
    private func updateMemoryUsage() {
        let memoryUsage = getMemoryUsage()
        
        DispatchQueue.main.async {
            self.memoryUsageString = String(format: "%.1f MB", memoryUsage)
            
            // Update warning color based on usage
            if memoryUsage > self.memoryCriticalThreshold {
                self.memoryWarningColor = .red
                
                // If memory is critical, stop scanning automatically
                if self.isScanning && memoryUsage > (self.memoryCriticalThreshold + 50) {
                    print("⚠️ Critical memory threshold exceeded! Stopping scan automatically.")
                    self.isScanning = false
                    self.statusMessage = "Scan stopped - Memory limit reached"
                }
            } else if memoryUsage > self.memoryWarningThreshold {
                self.memoryWarningColor = .yellow
            } else {
                self.memoryWarningColor = .green
            }
        }
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // Convert to MB
        } else {
            return 0
        }
    }
    
    func saveScan(name: String) {
        print("\n--- SAVING SCAN ---")
        print("Preparing to save scan with \(pointCloud.count) points, name: \(name)")
        
        // Verify we have points to save
        guard !pointCloud.isEmpty else {
            statusMessage = "No points to save"
            print("Error: No points to save")
            return
        }
        
        // Apply voxel grid filtering before saving to reduce file size and memory usage
        let filteredPointCloud = applyVoxelGridFilter()
        print("Filtered from \(pointCloud.count) to \(filteredPointCloud.count) points for saving")
        
        // Create point cloud data
        let scanData = PointCloudData(
            points: filteredPointCloud,
            timestamp: Date(),
            name: name
        )
        
        // Save to storage
        do {
            let url = try PointCloudStore.shared.save(pointCloud: scanData)
            statusMessage = "Scan saved"
            print("Scan saved successfully at: \(url.path)")
            
            // Verify the file exists
            if FileManager.default.fileExists(atPath: url.path) {
                let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
                print("Verified file exists with size: \(fileSize) bytes")
                
                // Try to read it back
                try verifyModelCanBeLoaded(url: url)
            } else {
                print("WARNING: File doesn't exist after saving!")
            }
            
            // Clear memory after saving
            forceMemoryRelease()
            
            // List available scans for debugging
            _ = PointCloudStore.shared.listAvailableScans()
        } catch {
            statusMessage = "Failed to save"
            print("Save error: \(error.localizedDescription)")
        }
        
        print("--- END OF SAVE PROCESS ---\n")
    }
    
    // Apply voxel grid filtering to reduce point count
    private func applyVoxelGridFilter(voxelSize: Float = 0.015) -> [SIMD3<Float>] {
        // Use autoreleasepool to manage memory
        return autoreleasepool {
            var voxelGrid: [ArCity.VoxelKey: SIMD3<Float>] = [:]
            let currentPoints = self.pointCloud
            
            // Process in batches with autoreleasepool to minimize memory usage
            let batchSize = 5000
            for i in stride(from: 0, to: currentPoints.count, by: batchSize) {
                autoreleasepool {
                    let end = min(i + batchSize, currentPoints.count)
                    let batch = currentPoints[i..<end]
                    
                    for point in batch {
                        let key = ArCity.VoxelKey(point: point, voxelSize: voxelSize)
                        if voxelGrid[key] == nil {
                            voxelGrid[key] = point
                        }
                    }
                }
            }
            
            // Extract the final points and return
            return Array(voxelGrid.values)
        }
    }
    
    private func forceMemoryRelease() {
        // Create and immediately release temporary objects to encourage memory cleanup
        autoreleasepool {
            var temporaryArrays: [[Int]] = []
            for _ in 0..<5 {
                let tempArray = Array(repeating: 0, count: 1000)
                temporaryArrays.append(tempArray)
            }
            temporaryArrays.removeAll()
        }
    }
    
    private func verifyModelCanBeLoaded(url: URL) throws {
        print("Verifying model can be loaded...")
        
        // Attempt to load the data
        let data = try Data(contentsOf: url)
        print("Successfully read data: \(data.count) bytes")
        
        // Attempt to decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let loadedModel = try autoreleasepool {
            try decoder.decode(PointCloudData.self, from: data)
        }
        
        print("Successfully decoded model: \(loadedModel.name) with \(loadedModel.points.count) points")
    }
    
    func processARFrame(_ frame: ARFrame) {
        let currentTime = CACurrentMediaTime()
        
        // Sample points at the specified rate
        guard currentTime - lastFrameTime >= sampleRate else { return }
        lastFrameTime = currentTime
        
        // Use autoreleasepool to manage memory
        autoreleasepool {
            // Extract point cloud from current frame
            if let rawFeaturePoints = frame.rawFeaturePoints {
                // Sample points from feature points
                let newPoints = rawFeaturePoints.points
                
                // Only process if we have points
                if !newPoints.isEmpty {
                    // Memory optimization: Limit total points collection 
                    // Add points only if we're under the memory safe threshold
                    if pointCloud.count < maxPointsAllowed {
                        // Add new points with sampling and voxel grid filtering to avoid memory issues
                        let filteredPoints = addNewPointsWithVoxelFiltering(Array(newPoints))
                        
                        if !filteredPoints.isEmpty {
                            // Update the point cloud
                            autoreleasepool {
                                pointCloud.append(contentsOf: filteredPoints)
                            }
                            
                            // Update scan coverage and count
                            updateScanCoverage()
                            pointCount = pointCloud.count
                        }
                        
                        // Update the visual representation (but throttle updates)
                        if currentTime - lastVisualizationUpdateTime >= visualizationUpdateRate {
                            lastVisualizationUpdateTime = currentTime
                            
                            // Sample points for visualization to reduce memory pressure
                            let visualizationPoints = samplePointsForVisualization()
                            pointVisualizationHandler?(visualizationPoints)
                            print("Visualizing \(visualizationPoints.count) points from \(pointCloud.count) total")
                        }
                    } else if pointCount != maxPointsAllowed {
                        // Only update once when we hit the limit
                        print("WARNING: Reached maximum point cloud size limit (\(maxPointsAllowed))")
                        pointCount = maxPointsAllowed
                        statusMessage = "Max points reached (\(maxPointsAllowed))"
                    }
                }
            }
        }
    }
    
    private func samplePointsForVisualization() -> [SIMD3<Float>] {
        // If points exceed threshold, apply more aggressive sampling for visualization
        if pointCloud.count > 50000 {
            print("Large point cloud - using aggressive sampling for visualization")
            let samplingRate = max(1, pointCloud.count / 5000)
            return stride(from: 0, to: pointCloud.count, by: samplingRate)
                .map { pointCloud[$0] }
        } else if pointCloud.count > 10000 {
            let samplingRate = max(1, pointCloud.count / 2000)
            return stride(from: 0, to: pointCloud.count, by: samplingRate)
                .map { pointCloud[$0] }
        } else {
            return pointCloud
        }
    }
    
    private func addNewPointsWithVoxelFiltering(_ newPoints: [SIMD3<Float>]) -> [SIMD3<Float>] {
        // Memory optimization - add new points with voxel grid filtering for deduplication
        var filteredPoints: [SIMD3<Float>] = []
        
        // Apply sparser sampling as point count increases
        let samplingRate: Int = calculateAdaptiveSamplingRate()
        
        // Process points in batches to reduce memory pressure
        let batchSize = min(500, newPoints.count)
        
        for i in stride(from: 0, to: newPoints.count, by: batchSize) {
            autoreleasepool {
                let end = min(i + batchSize, newPoints.count)
                let batch = Array(newPoints[i..<end])
                
                for (index, point) in batch.enumerated() {
                    // Only process every nth point based on our adaptive sampling
                    if index % samplingRate == 0 {
                        // Filter out outliers or invalid points
                        if isValidPoint(point) {
                            // Use voxel grid filtering to avoid duplicates
                            let key = ArCity.VoxelKey(point: point, voxelSize: voxelSize)
                            
                            if voxelGridDict[key] == nil {
                                voxelGridDict[key] = point
                                filteredPoints.append(point)
                            }
                        }
                    }
                }
            }
        }
        
        return filteredPoints
    }
    
    private func calculateAdaptiveSamplingRate() -> Int {
        // Apply more aggressive sampling as count increases
        if pointCloud.count > 100000 {
            return 16 // 1/16 of points when over 100K
        } else if pointCloud.count > 50000 {
            return 10 // 1/10 of points when over 50K
        } else if pointCloud.count > 20000 {
            return 6 // 1/6 of points when over 20K
        } else {
            return 4 // 1/4 of points for smaller clouds
        }
    }
    
    private func isValidPoint(_ point: SIMD3<Float>) -> Bool {
        // Basic validity check
        guard point.x.isFinite && point.y.isFinite && point.z.isFinite else { 
            return false 
        }
        
        // Distance check to filter outliers
        let distanceFromOrigin = sqrt(point.x*point.x + point.y*point.y + point.z*point.z)
        if distanceFromOrigin > 5.0 || distanceFromOrigin < 0.1 {
            return false
        }
        
        // Height bounds check (assuming Y is up)
        if abs(point.y) > 2.5 {  // More than 2.5m above/below is probably noise
            return false
        }
        
        return true
    }
    
    private func updateScanCoverage() {
        // Calculate coverage based on number of points and their distribution
        if pointCloud.isEmpty {
            scanCoverage = 0.0
            return
        }
        
        // Simple heuristic based on point count
        scanCoverage = min(Double(pointCount) / 10000.0, 1.0)
    }
    
    func handleSessionError(_ error: Error) {
        print("AR Session error: \(error)")
        statusMessage = "AR error: \(error.localizedDescription)"
    }
} 