import SwiftUI
import ARKit
import RealityKit
import Combine
import Foundation

struct ScannerView: View {
    @StateObject private var scannerViewModel = ScannerViewModel()
    @State private var showingSaveDialog = false
    @State private var scanName = ""
    @State private var showAlert = false
    
    var body: some View {
        ZStack {
            ARViewContainer(scannerViewModel: scannerViewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Point count and status display at the top
                HStack {
                    Text(scannerViewModel.isScanning ? "Recording..." : "Ready")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    if scannerViewModel.isScanning {
                        Text("\(scannerViewModel.pointCloud.count) points")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
                .padding()
                
                // Memory usage indicator
                if scannerViewModel.isScanning {
                    HStack {
                        Text("Memory: \(scannerViewModel.memoryUsageString)")
                            .font(.subheadline)
                            .foregroundColor(scannerViewModel.memoryWarningColor)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Bottom controls
                HStack {
                    Button(action: {
                        scannerViewModel.toggleScanning()
                    }) {
                        Text(scannerViewModel.isScanning ? "Stop Scanning" : "Start Scanning")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(scannerViewModel.isScanning ? Color.red : Color.blue)
                            .cornerRadius(10)
                    }
                    .padding()
                    
                    if !scannerViewModel.isScanning && scannerViewModel.pointCloud.count > 0 {
                        Button(action: {
                            showingSaveDialog = true
                        }) {
                            Text("Save Scan")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(10)
                        }
                        .padding()
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .alert("Save Scan", isPresented: $showingSaveDialog) {
            TextField("Scan Name", text: $scanName)
            
            Button("Cancel", role: .cancel) {
                showingSaveDialog = false
            }
            
            Button("Save") {
                if !scanName.isEmpty {
                    scannerViewModel.saveScan(name: scanName)
                    scanName = ""
                }
                showingSaveDialog = false
            }
        } message: {
            Text("Enter a name for this scan")
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("AR Error"),
                message: Text(scannerViewModel.errorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            scannerViewModel.checkPermissions()
            scannerViewModel.errorHandler = { errorMessage in
                scannerViewModel.errorMessage = errorMessage
                showAlert = true
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    var scannerViewModel: ScannerViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        
        // Add coordinator as the delegate
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        scannerViewModel.setupARView(arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update UI view if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(scannerViewModel: scannerViewModel)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var scannerViewModel: ScannerViewModel
        var arView: ARView?
        
        init(scannerViewModel: ScannerViewModel) {
            self.scannerViewModel = scannerViewModel
            super.init()
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            // Handle session failures
            scannerViewModel.handleSessionError(error)
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Update for each frame if needed
            if scannerViewModel.isScanning {
                scannerViewModel.processARFrame(frame)
            }
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            scannerViewModel.errorHandler?("ARSession was interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            // Resume the session when interruption ends
            scannerViewModel.resetTracking()
        }
    }
}

class ScannerViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var pointCloud: [SIMD3<Float>] = []
    @Published var errorMessage: String?
    @Published var memoryUsageString: String = "0 MB"
    @Published var memoryWarningColor: Color = .white
    
    var errorHandler: ((String) -> Void)?
    private var arView: ARView?
    private var cancellables = Set<AnyCancellable>()
    private var lastScanTime: TimeInterval = 0
    private var scanInterval: TimeInterval = 0.2 // Seconds between scans
    private var pointsNode: SCNNode?
    private var processingPoints = false
    private var memoryMonitorTimer: Timer?
    private var voxelGridDict: [ArCity.VoxelKey: SIMD3<Float>] = [:]
    
    // Improved voxel grid filter settings
    private var voxelSize: Float = 0.02
    
    // Add a maximum number of points to prevent memory issues
    private let maxPointsAllowed = 500000
    
    // Memory thresholds in MB - increased for iPhone 15 Pro Max
    private let memoryWarningThreshold: Double = 1000  // 1GB (increased from 250MB)
    private let memoryCriticalThreshold: Double = 1500 // 1.5GB (increased from 350MB)
    
    deinit {
        memoryMonitorTimer?.invalidate()
    }
    
    func checkPermissions() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorHandler?("AR World Tracking is not supported on this device")
            return
        }
        
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.errorHandler?("Camera access is required for AR scanning")
                }
            }
        }
    }
    
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        
        // Enable scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            print("Scene reconstruction enabled")
        } else {
            print("Scene reconstruction not supported")
        }
        
        // Enable depth data if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            print("Depth frame semantics enabled")
        } else {
            print("Depth frame semantics not supported")
        }
        
        // Run the AR session
        arView.session.run(configuration)
        
        // Use EITHER custom visualization OR built-in feature points, not both
        // Just use the built-in feature points for consistency
        arView.debugOptions = [.showFeaturePoints]
    }
    
    func toggleScanning() {
        isScanning.toggle()
        
        if isScanning {
            startScanning()
        } else {
            stopScanning()
        }
    }
    
    private func startScanning() {
        print("Starting scan...")
        pointCloud.removeAll()
        voxelGridDict.removeAll()
        lastScanTime = 0
        
        // Add additional real-time visualization of captured points
        if let arView = arView {
            let anchor = AnchorEntity()
            arView.scene.addAnchor(anchor)
            
            // Custom visualization can be added here
        }
        
        // Delay memory monitoring to avoid false alarms at startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.startMemoryMonitoring()
        }
    }
    
    private func stopScanning() {
        print("Stopping scan. Captured \(pointCloud.count) points.")
        
        // Stop memory monitoring
        memoryMonitorTimer?.invalidate()
        
        // Clean up visualizations first to free memory
        cleanupVisualizations()
        
        // Auto-limit the number of points if exceeded to prevent hangs
        if pointCloud.count > maxPointsAllowed {
            print("Warning: Limiting point cloud to \(maxPointsAllowed) points for performance")
            DispatchQueue.main.async {
                self.pointCloud = Array(self.pointCloud.prefix(self.maxPointsAllowed))
            }
        }
        
        // Improve point cloud quality with post-processing
        finalizePointCloud()
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
                    self.toggleScanning()
                    self.errorHandler?("Scan stopped automatically due to high memory usage")
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
    
    private func finalizePointCloud() {
        // Don't run multiple times
        if processingPoints {
            return
        }
        
        processingPoints = true
        print("Starting point cloud optimization...")
        
        // Process in background to avoid hanging the UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Make copy of current point cloud to work with
            let currentPoints = self.pointCloud
            
            // Track memory usage during processing
            let initialMemory = self.getMemoryUsage()
            print("Memory usage before optimization: \(initialMemory) MB")
            
            // Use a more efficient voxel grid filtering approach
            let voxelSize: Float = 0.015 // Smaller voxel size for final output
            var voxelGrid: [ArCity.VoxelKey: SIMD3<Float>] = [:]
            
            print("Processing \(currentPoints.count) points using voxel grid filtering...")
            
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
                
                // Progress update
                if i % 20000 == 0 && i > 0 {
                    print("Processed \(i) points...")
                }
            }
            
            // Extract final points
            let finalPoints = Array(voxelGrid.values)
            
            let finalMemory = self.getMemoryUsage()
            print("Memory usage after optimization: \(finalMemory) MB")
            print("Memory difference: \(finalMemory - initialMemory) MB")
            
            // Update the UI on the main thread
            DispatchQueue.main.async {
                print("Reduced point cloud from \(currentPoints.count) to \(finalPoints.count) points")
                self.pointCloud = finalPoints
                self.processingPoints = false
                
                // Force garbage collection by creating temporary pressure
                self.forceMemoryRelease()
            }
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
    
    func processARFrame(_ frame: ARFrame) {
        // Only capture at certain intervals to avoid overwhelming the app
        let currentTime = frame.timestamp
        guard currentTime - lastScanTime >= scanInterval else { return }
        
        lastScanTime = currentTime
        capturePointCloudFrame(frame)
        
        // Add real-time visualization during scanning
        if isScanning {
            visualizeCurrentPointCloud()
        }
    }
    
    private func visualizeCurrentPointCloud() {
        guard let arView = arView, isScanning else { return }
        
        // For performance reasons, we'll only visualize periodically
        // Reduced frequency to prevent too many visualizations
        guard pointCloud.count % 300 == 0 && pointCloud.count > 0 else { return }
        
        // Create visualization in ARView - inside an autorelease pool
        autoreleasepool {
            DispatchQueue.main.async {
                // Clean up ALL previous visualization entities
                // Look for any entities that might be our point visualizations
                for anchor in arView.scene.anchors {
                    if anchor.name == "point-cloud-anchor" || 
                       anchor.findEntity(named: "live-point-visualization") != nil {
                        anchor.removeFromParent()
                    }
                }
                
                // Limit the number of displayed points to avoid memory issues
                // Only visualize the most recent points to reduce clutter
                let maxVisualizationPoints = 30 // Reduced from 50 to improve performance
                let startIndex = max(0, self.pointCloud.count - maxVisualizationPoints)
                let recentPoints = Array(self.pointCloud[startIndex..<self.pointCloud.count])
                
                // Create one entity for all points to reduce overhead
                let visualEntity = Entity()
                visualEntity.name = "live-point-visualization"
                
                // Use a smaller radius to reduce visual clutter
                let radius: Float = 0.002 // Reduced from 0.003
                
                // Use a single mesh and material for all points - more efficient
                let pointMesh = MeshResource.generateSphere(radius: radius)
                let material = SimpleMaterial(color: UIColor.green, roughness: 0.2, isMetallic: false)
                
                for point in recentPoints {
                    let pointEntity = ModelEntity(mesh: pointMesh, materials: [material])
                    pointEntity.position = point
                    visualEntity.addChild(pointEntity)
                }
                
                // Create a dedicated anchor for our visualization
                let anchor = AnchorEntity(world: .zero)
                anchor.name = "point-cloud-anchor"
                anchor.addChild(visualEntity)
                arView.scene.addAnchor(anchor)
            }
        }
    }
    
    private func cleanupVisualizations() {
        // Clean up any leftover visualizations when stopping
        guard let arView = arView else { return }
        
        DispatchQueue.main.async {
            // Remove all custom visualization entities
            for anchor in arView.scene.anchors {
                if anchor.name == "point-cloud-anchor" || 
                   anchor.findEntity(named: "live-point-visualization") != nil {
                    anchor.removeFromParent()
                }
            }
        }
    }
    
    private func capturePointCloudFrame(_ frame: ARFrame) {
        // Run in an autorelease pool to manage memory
        autoreleasepool {
            guard let depthData = frame.sceneDepth?.depthMap,
                  let confidenceData = frame.sceneDepth?.confidenceMap else {
                print("No depth data available")
                return
            }
            
            // Check if we already have too many points to prevent memory issues
            if pointCloud.count >= maxPointsAllowed {
                print("Maximum point count reached (\(maxPointsAllowed)). Stopping scan.")
                DispatchQueue.main.async {
                    self.isScanning = false
                }
                return
            }
            
            // Sample a subset of points to avoid overwhelming the system
            let width = CVPixelBufferGetWidth(depthData)
            let height = CVPixelBufferGetHeight(depthData)
            
            // Lock the base address of the pixel buffer
            CVPixelBufferLockBaseAddress(depthData, .readOnly)
            CVPixelBufferLockBaseAddress(confidenceData, .readOnly)
            
            let depthPointer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthData), to: UnsafeMutablePointer<Float>.self)
            let confidencePointer = unsafeBitCast(CVPixelBufferGetBaseAddress(confidenceData), to: UnsafeMutablePointer<UInt8>.self)
            
            // Better sampling strategy - adaptive based on point cloud size
            // Increase sampling rate as the point cloud grows to prevent memory issues
            let sampleEvery: Int
            if pointCloud.count > 100000 {
                sampleEvery = 32 // Very sparse sampling for large point clouds
            } else if pointCloud.count > 50000 {
                sampleEvery = 24 // Sparse sampling for medium point clouds
            } else if pointCloud.count > 20000 {
                sampleEvery = 16 // Medium sampling
            } else {
                sampleEvery = 12 // Default sampling rate
            }
            
            var newPoints: [SIMD3<Float>] = []
            
            // Limit the number of new points we add per frame
            let maxNewPointsPerFrame = 500 // Reduced from 1000
            
            for y in stride(from: 0, to: height, by: sampleEvery) {
                if newPoints.count >= maxNewPointsPerFrame {
                    break
                }
                
                for x in stride(from: 0, to: width, by: sampleEvery) {
                    if newPoints.count >= maxNewPointsPerFrame {
                        break
                    }
                    
                    let pixelOffset = y * width + x
                    let depth = depthPointer[pixelOffset]
                    let confidence = confidencePointer[pixelOffset]
                    
                    // Only include higher confidence points with even stricter filtering
                    if confidence >= 2 && depth > 0 && depth < 5 { // Reduced range from 10 to 5 meters
                        // Convert depth point to 3D point in world space
                        if let point = self.worldPoint(for: CGPoint(x: x, y: y), depth: depth, frame: frame) {
                            // Add the point with basic filtering
                            if isValidPoint(point) {
                                // Use voxel-grid filtering during capture
                                let key = ArCity.VoxelKey(point: point, voxelSize: voxelSize)
                                
                                // Only add point if we don't already have a point in this voxel
                                if voxelGridDict[key] == nil {
                                    voxelGridDict[key] = point
                                    newPoints.append(point)
                                }
                            }
                        }
                    }
                }
            }
            
            // Unlock buffers
            CVPixelBufferUnlockBaseAddress(depthData, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceData, .readOnly)
            
            // Update point cloud on the main thread
            if !newPoints.isEmpty {
                DispatchQueue.main.async {
                    // Add new points to our point cloud
                    self.pointCloud.append(contentsOf: newPoints)
                    
                    // Log for debugging
                    print("Added \(newPoints.count) points. Total: \(self.pointCloud.count)")
                }
            }
        }
    }
    
    // Helper method to quickly filter out invalid points
    private func isValidPoint(_ point: SIMD3<Float>) -> Bool {
        // Filter out points that are too far away or likely to be noise
        guard point.x.isFinite && point.y.isFinite && point.z.isFinite else { return false }
        
        let distanceFromOrigin = length(point)
        
        // More strict filtering to eliminate outliers
        if distanceFromOrigin > 5.0 || distanceFromOrigin < 0.1 {
            return false
        }
        
        // Check if the point is within reasonable bounds relative to the device
        // Filter out points that are too high or too low - helps with room scans
        if abs(point.y) > 2.5 { // More than 2.5 meters above or below camera
            return false
        }
        
        return true
    }
    
    private func worldPoint(for pixelPoint: CGPoint, depth: Float, frame: ARFrame) -> SIMD3<Float>? {
        // Prevent NaN or invalid depth values
        guard depth.isFinite && depth > 0 else { return nil }
        
        // Convert the pixel point to normalized coordinates in [0,1]
        let viewportSize = frame.camera.imageResolution
        let normalizedPoint = CGPoint(
            x: pixelPoint.x / CGFloat(viewportSize.width),
            y: pixelPoint.y / CGFloat(viewportSize.height)
        )
        
        // Use ray casting for more accurate point projection - with compatibility fix
        if let arView = arView {
            // Fix: Use existing depth instead of .estimatedDepth which may not be available
            let raycastQuery = arView.raycast(from: pixelPoint, 
                                             allowing: .existingPlaneGeometry, 
                                             alignment: .any)
            
            // Fix: Use arView.session instead of frame.session which doesn't exist
            if let result = raycastQuery.first {
                // Use raycasting result when available - more accurate
                // Fix: simd_float4 doesn't have .xyz property
                let column = result.worldTransform.columns.3
                return SIMD3<Float>(column.x, column.y, column.z)
            }
        }
        
        // Fallback to projection matrix method
        let ndcX = (2.0 * Float(normalizedPoint.x)) - 1.0
        let ndcY = 1.0 - (2.0 * Float(normalizedPoint.y)) // Flip Y for ARKit coordinates
        
        // Use the camera projection matrix for better accuracy
        let projectionMatrix = frame.camera.projectionMatrix
        
        // Calculate view-space point using the inverse projection matrix
        let viewX = ndcX * depth / projectionMatrix.columns.0.x
        let viewY = ndcY * depth / projectionMatrix.columns.1.y
        let viewZ = -depth
        
        let viewPoint = SIMD3<Float>(viewX, viewY, viewZ)
        
        // Transform from view space to world space
        let pointInWorld = frame.camera.transform * simd_float4(viewPoint, 1)
        let result = SIMD3<Float>(pointInWorld.x, pointInWorld.y, pointInWorld.z)
        
        // Final validation
        return result.x.isFinite && result.y.isFinite && result.z.isFinite ? result : nil
    }
    
    func saveScan(name: String) {
        guard !pointCloud.isEmpty else {
            errorHandler?("No points to save")
            return
        }
        
        print("Saving scan with \(pointCloud.count) points as '\(name)'")
        
        // Make a copy of the current points to avoid threading issues
        let pointsToSave = self.pointCloud
        
        // Create the data object with the current points
        let data = PointCloudData(
            points: pointsToSave,
            timestamp: Date(),
            name: name
        )
        
        // Save in background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileURL = try PointCloudStore.shared.save(pointCloud: data)
                DispatchQueue.main.async {
                    print("Successfully saved point cloud to: \(fileURL.path)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorHandler?("Failed to save scan: \(error.localizedDescription)")
                    print("Error saving point cloud: \(error)")
                }
            }
        }
    }
    
    func handleSessionError(_ error: Error) {
        print("AR session failed: \(error.localizedDescription)")
        errorHandler?("AR session error: \(error.localizedDescription)")
    }
    
    func resetTracking() {
        guard let arView = arView else { return }
        
        // Clean up before resetting to prevent visualization issues
        cleanupVisualizations()
        
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
}

// Modified extension to fix errors
extension UIView {
    var tintColor: UIColor? {
        get { return self.tintColor }
        set {
            self.tintColor = newValue
            if let sceneView = self as? ARSCNView {
                sceneView.debugOptions = [.showFeaturePoints]
                sceneView.scene.background.contents = newValue?.withAlphaComponent(0.5)
            }
        }
    }
} 
