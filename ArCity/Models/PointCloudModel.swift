import Foundation
import simd

struct PointCloudData: Codable {
    var points: [SIMD3<Float>]
    var timestamp: Date
    var name: String
    
    // Custom initializer
    init(points: [SIMD3<Float>], timestamp: Date, name: String) {
        self.points = points
        self.timestamp = timestamp
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case points, timestamp, name
    }
    
    // Custom encoding/decoding for SIMD3<Float> arrays
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        name = try container.decode(String.self, forKey: .name)
        
        // Decode points as array of float arrays
        let pointArrays = try container.decode([[Float]].self, forKey: .points)
        points = pointArrays.compactMap { pointArray in
            guard pointArray.count >= 3 else { return nil }
            return SIMD3<Float>(pointArray[0], pointArray[1], pointArray[2])
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(name, forKey: .name)
        
        // Encode points as array of float arrays
        let pointArrays = points.map { [$0.x, $0.y, $0.z] }
        try container.encode(pointArrays, forKey: .points)
    }
    
    // Apply voxel grid filter to reduce point count
    func withVoxelGridFilter(voxelSize: Float = 0.02) -> PointCloudData {
        // Create a dictionary to store one point per voxel
        var voxelGrid: [VoxelKey: SIMD3<Float>] = [:]
        
        // Process in batches to reduce memory pressure
        let batchSize = 10000
        
        for i in stride(from: 0, to: points.count, by: batchSize) {
            autoreleasepool {
                let end = min(i + batchSize, points.count)
                let batch = points[i..<end]
                
                for point in batch {
                    // Convert point to voxel coordinates
                    let voxelKey = VoxelKey(point: point, voxelSize: voxelSize)
                    
                    // If multiple points fall in the same voxel, keep the first one
                    // (or implement a more sophisticated strategy like averaging)
                    if voxelGrid[voxelKey] == nil {
                        voxelGrid[voxelKey] = point
                    }
                }
            }
        }
        
        // Extract points from voxel grid
        let filteredPoints = Array(voxelGrid.values)
        
        return PointCloudData(
            points: filteredPoints,
            timestamp: timestamp,
            name: name
        )
    }
}

// Struct to represent a voxel in 3D space
public struct VoxelKey: Hashable {
    public let x: Int
    public let y: Int
    public let z: Int
    
    public init(point: SIMD3<Float>, voxelSize: Float) {
        x = Int(floor(point.x / voxelSize))
        y = Int(floor(point.y / voxelSize))
        z = Int(floor(point.z / voxelSize))
    }
}

class PointCloudStore {
    static let shared = PointCloudStore()
    
    private let fileManager = FileManager.default
    private var documentsDirectory: URL
    private let maxPointsInSave = 150000 // Increased from 100000
    
    private init() {
        // Get the documents directory
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        
        // Create a specific subdirectory for our app
        documentsDirectory = documentsDirectory.appendingPathComponent("ArCityScans", isDirectory: true)
        
        // Create the directory if it doesn't exist
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created directory at: \(documentsDirectory.path)")
            } catch {
                print("Failed to create directory: \(error.localizedDescription)")
                // Fallback to temporary directory if we can't create our own
                documentsDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            }
        }
    }
    
    func save(pointCloud: PointCloudData) throws -> URL {
        // Validate input
        guard !pointCloud.points.isEmpty else {
            print("Error: Cannot save empty point cloud")
            throw NSError(domain: "PointCloudStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot save empty point cloud"])
        }
        
        guard !pointCloud.name.isEmpty else {
            print("Error: Point cloud name cannot be empty")
            throw NSError(domain: "PointCloudStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Point cloud name cannot be empty"])
        }
        
        print("Preparing to save point cloud with \(pointCloud.points.count) points named '\(pointCloud.name)'")
        
        // Apply voxel grid filtering to limit the number of points if needed
        var optimizedPointCloud: PointCloudData
        
        if pointCloud.points.count > maxPointsInSave {
            print("Applying voxel grid filter to reduce point cloud from \(pointCloud.points.count) points for saving")
            
            // Calculate appropriate voxel size based on point count
            let voxelSize: Float
            if pointCloud.points.count > 500000 {
                voxelSize = 0.07 // Larger voxels for very large point clouds
            } else if pointCloud.points.count > 200000 {
                voxelSize = 0.04 // Medium voxels for large point clouds
            } else {
                voxelSize = 0.03 // Default voxel size
            }
            
            // Apply voxel grid filter to reduce point count
            optimizedPointCloud = pointCloud.withVoxelGridFilter(voxelSize: voxelSize)
            
            // If still too many points after filtering, take a subset
            if optimizedPointCloud.points.count > maxPointsInSave {
                optimizedPointCloud = PointCloudData(
                    points: Array(optimizedPointCloud.points.prefix(maxPointsInSave)),
                    timestamp: pointCloud.timestamp,
                    name: pointCloud.name
                )
            }
            
            print("Reduced to \(optimizedPointCloud.points.count) points after optimization")
        } else {
            optimizedPointCloud = pointCloud
        }
        
        // Setup encoder with better options for large files
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        // Create safe filename (remove illegal characters)
        let safeFileName = optimizedPointCloud.name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let timestamp = Int(optimizedPointCloud.timestamp.timeIntervalSince1970)
        let fileName = "\(safeFileName)_\(timestamp).json"
        
        // Create file URL
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        print("Saving to file: \(fileURL.path)")
        
        // Ensure the directory exists
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
            print("Created directory at: \(documentsDirectory.path)")
        }
        
        do {
            // Encode point cloud to JSON inside an autorelease pool
            // to limit memory usage during encoding
            let data: Data = try autoreleasepool {
                return try encoder.encode(optimizedPointCloud)
            }
            
            print("Encoded point cloud data size: \(data.count) bytes")
            
            // Write to file
            try data.write(to: fileURL)
            print("Successfully saved point cloud to \(fileURL.path)")
            
            // Verify the file exists after saving
            if fileManager.fileExists(atPath: fileURL.path) {
                let fileSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
                print("Verified file exists with size: \(fileSize) bytes")
            } else {
                print("WARNING: File doesn't exist after saving!")
            }
            
            return fileURL
        } catch {
            print("Failed to save point cloud: \(error.localizedDescription)")
            throw error
        }
    }
    
    func load(from url: URL) throws -> PointCloudData {
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "PointCloudStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(url.path)"])
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Use autorelease pool for decoding to limit memory usage
            let pointCloud: PointCloudData = try autoreleasepool {
                return try decoder.decode(PointCloudData.self, from: data)
            }
            
            // Verify the point cloud has data
            guard !pointCloud.points.isEmpty else {
                throw NSError(domain: "PointCloudStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Loaded point cloud has no points"])
            }
            
            print("Successfully loaded \(pointCloud.points.count) points from \(url.lastPathComponent)")
            return pointCloud
        } catch {
            print("Error loading point cloud from \(url.path): \(error.localizedDescription)")
            throw error
        }
    }
    
    func getAllSavedPointClouds() -> [URL] {
        do {
            // Check if directory exists
            guard fileManager.fileExists(atPath: documentsDirectory.path) else {
                print("Documents directory doesn't exist: \(documentsDirectory.path)")
                return []
            }
            
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            let pointCloudURLs = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
            
            print("Found \(pointCloudURLs.count) point cloud files")
            return pointCloudURLs
        } catch {
            print("Error getting saved point clouds: \(error.localizedDescription)")
            return []
        }
    }
    
    func deletePointCloud(at url: URL) -> Bool {
        do {
            try fileManager.removeItem(at: url)
            print("Successfully deleted point cloud at: \(url.path)")
            return true
        } catch {
            print("Error deleting point cloud: \(error.localizedDescription)")
            return false
        }
    }
    
    func getDirectory() -> URL {
        return documentsDirectory
    }
    
    func listAvailableScans() -> [URL] {
        // Ensure the directory exists
        if !fileManager.fileExists(atPath: documentsDirectory.path) {
            print("Scan directory doesn't exist at: \(documentsDirectory.path)")
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created scan directory")
            } catch {
                print("Failed to create scan directory: \(error.localizedDescription)")
                return []
            }
        }
        
        do {
            // Get all files in the directory
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            
            // Filter for JSON files
            let jsonFiles = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
            
            print("Found \(jsonFiles.count) scan files in \(documentsDirectory.path):")
            for (index, file) in jsonFiles.enumerated() {
                let attrs = try fileManager.attributesOfItem(atPath: file.path)
                let fileSize = attrs[.size] as? Int64 ?? 0
                print("  \(index+1). \(file.lastPathComponent) - \(fileSize) bytes")
            }
            
            return jsonFiles
        } catch {
            print("Error listing scans: \(error.localizedDescription)")
            return []
        }
    }
    
    func saveTestModel() -> URL? {
        print("Creating and saving a test model...")
        
        // Create a simple cubic test model with 8 points (cube corners)
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(-0.5, -0.5, -0.5),
            SIMD3<Float>( 0.5, -0.5, -0.5),
            SIMD3<Float>(-0.5,  0.5, -0.5),
            SIMD3<Float>( 0.5,  0.5, -0.5),
            SIMD3<Float>(-0.5, -0.5,  0.5),
            SIMD3<Float>( 0.5, -0.5,  0.5),
            SIMD3<Float>(-0.5,  0.5,  0.5),
            SIMD3<Float>( 0.5,  0.5,  0.5)
        ]
        
        // Add more points to make it more interesting
        var extendedPoints = points
        
        // Add random spread of points around each corner for more
        // realistic point cloud visualization
        for _ in 0..<10 {
            for basePoint in points {
                let jitter = SIMD3<Float>(
                    Float.random(in: -0.05...0.05),
                    Float.random(in: -0.05...0.05),
                    Float.random(in: -0.05...0.05)
                )
                extendedPoints.append(basePoint + jitter)
            }
        }
        
        // Create a test model with our points
        let testModel = PointCloudData(
            points: extendedPoints,
            timestamp: Date(),
            name: "Test Cube"
        )
        
        // Save the model
        do {
            let fileURL = try save(pointCloud: testModel)
            print("Saved test model to: \(fileURL.path)")
            return fileURL
        } catch {
            print("Failed to save test model: \(error)")
            return nil
        }
    }
} 