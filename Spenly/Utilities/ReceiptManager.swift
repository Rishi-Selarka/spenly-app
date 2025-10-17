import Foundation
import UIKit
import CoreData
import QuickLook
import UniformTypeIdentifiers

class ReceiptManager {
    static let shared = ReceiptManager()
    
    private init() {
        createReceiptsDirectoryIfNeeded()
    }
    
    // MARK: - Directory Management
    
    private var receiptsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Receipts")
    }
    
    private func createReceiptsDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: receiptsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: receiptsDirectory, withIntermediateDirectories: true)
                print("✅ Receipts directory created successfully")
            } catch {
                print("❌ Error creating receipts directory: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Image Storage
    
    func saveReceiptImage(_ image: UIImage, for transactionID: UUID) -> String? {
        // Compress image to reduce storage space (optimized for CloudKit sync)
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("❌ Failed to convert image to JPEG data")
            return nil
        }
        
        let fileName = generateFileName(for: transactionID)
        let fileURL = receiptsDirectory.appendingPathComponent(fileName)
        
        // Save to local file system (for backward compatibility)
        do {
            try imageData.write(to: fileURL)
            print("✅ Receipt image saved locally: \(fileName)")
        } catch {
            print("⚠️ Failed to save receipt locally: \(error.localizedDescription)")
            // Continue anyway - we'll use binary data for sync
        }
        
        return fileName
    }
    
    // New method to save receipt with binary data for CloudKit sync
    func saveReceiptImageData(_ image: UIImage, to transaction: Transaction) -> Bool {
        // Validate image size before processing
        let maxDimension: CGFloat = 2048
        let maxFileSize = 8 * 1024 * 1024 // 8MB limit for CloudKit safety
        
        var processedImage = image
        
        // Resize if image is too large
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            processedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            
            print("✅ Receipt image resized from \(image.size) to \(newSize)")
        }
        
        // Try progressive compression to meet size limit
        var compressionQuality: CGFloat = 0.7
        var imageData = processedImage.jpegData(compressionQuality: compressionQuality)
        
        while let data = imageData, data.count > maxFileSize && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            imageData = processedImage.jpegData(compressionQuality: compressionQuality)
        }
        
        guard let finalData = imageData else {
            print("❌ Failed to convert image to JPEG data")
            return false
        }
        
        if finalData.count > maxFileSize {
            print("❌ Receipt image too large even after compression: \(finalData.count / 1024 / 1024)MB")
            return false
        }
        
        print("✅ Receipt image compressed to \(finalData.count / 1024)KB at quality \(compressionQuality)")
        
        // Store binary data in Core Data (will sync with CloudKit)
        transaction.receiptImageData = finalData
        
        // Also save locally for faster access and backward compatibility
        if let transactionID = transaction.id {
            let fileName = generateFileName(for: transactionID)
            transaction.receiptFileName = fileName
            transaction.receiptImagePath = fileName
            transaction.receiptUploadDate = Date()
            
            // Save local file
            let fileURL = receiptsDirectory.appendingPathComponent(fileName)
            do {
                try finalData.write(to: fileURL)
                print("✅ Receipt saved both locally and for CloudKit sync")
            } catch {
                print("⚠️ Local save failed but CloudKit data is stored: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    private func generateFileName(for transactionID: UUID) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "receipt_\(transactionID.uuidString)_\(timestamp).jpg"
    }
    
    // MARK: - Image Retrieval
    
    func getReceiptImage(fileName: String) -> UIImage? {
        let fileURL = receiptsDirectory.appendingPathComponent(fileName)
        
        // First try to load from local file system (faster)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let image = UIImage(contentsOfFile: fileURL.path) {
                return image
            }
        }
        
        print("⚠️ Receipt image not found locally: \(fileName)")
        return nil
    }
    
    // New method to get receipt from binary data (CloudKit synced)
    func getReceiptImage(from transaction: Transaction) -> UIImage? {
        // First try local file for better performance
        if let fileName = transaction.receiptFileName {
            let fileURL = receiptsDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let image = UIImage(contentsOfFile: fileURL.path) {
                return image
            }
        }
        
        // If local file missing, use binary data from CloudKit sync
        if let imageData = transaction.receiptImageData {
            if let image = UIImage(data: imageData) {
                print("✅ Receipt loaded from CloudKit binary data")
                
                // Optionally save to local file for future fast access
                if let fileName = transaction.receiptFileName {
                    let fileURL = receiptsDirectory.appendingPathComponent(fileName)
                    do {
                        try imageData.write(to: fileURL)
                        print("✅ Receipt cached locally from CloudKit data")
                    } catch {
                        print("⚠️ Failed to cache receipt locally: \(error.localizedDescription)")
                    }
                }
                
                return image
            }
        }
        
        print("❌ No receipt image found (local or CloudKit)")
        return nil
    }
    
    func getReceiptImageURL(fileName: String) -> URL? {
        let fileURL = receiptsDirectory.appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        return fileURL
    }
    
    // MARK: - Image Deletion
    
    func deleteReceiptImage(fileName: String) {
        let fileURL = receiptsDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("✅ Receipt image deleted: \(fileName)")
        } catch {
            print("❌ Error deleting receipt image: \(error.localizedDescription)")
        }
    }
    
    // New method to delete receipt from transaction (both local and binary data)
    func deleteReceiptImage(from transaction: Transaction) {
        // Delete local file if exists
        if let fileName = transaction.receiptFileName {
            deleteReceiptImage(fileName: fileName)
        }
        
        // Clear binary data (will sync deletion to CloudKit)
        transaction.receiptImageData = nil
        transaction.receiptFileName = nil
        transaction.receiptImagePath = nil
        transaction.receiptUploadDate = nil
        
        print("✅ Receipt deleted from both local and CloudKit storage")
    }
    
    // MARK: - Storage Management
    
    func getStorageSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: receiptsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                print("⚠️ Error calculating file size for: \(fileURL.lastPathComponent)")
            }
        }
        
        return totalSize
    }
    
    func getStorageSizeFormatted() -> String {
        let bytes = getStorageSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Cleanup
    
    func cleanupOrphanedReceipts(context: NSManagedObjectContext) {
        guard let enumerator = FileManager.default.enumerator(at: receiptsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        // Get all current receipt file names from Core Data
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "receiptFileName != nil")
        
        do {
            let transactions = try context.fetch(fetchRequest)
            let currentFileNames = Set(transactions.compactMap { $0.receiptFileName })
            
            // Find and delete orphaned files
            for case let fileURL as URL in enumerator {
                let fileName = fileURL.lastPathComponent
                if !currentFileNames.contains(fileName) {
                    deleteReceiptImage(fileName: fileName)
                }
            }
            
            print("✅ Orphaned receipts cleanup completed")
        } catch {
            print("❌ Error during orphaned receipts cleanup: \(error.localizedDescription)")
        }
    }
}

// MARK: - QLPreviewItem for QuickLook support

class ReceiptPreviewItem: NSObject, QLPreviewItem {
    let fileURL: URL
    let displayName: String
    
    init(fileURL: URL, displayName: String) {
        self.fileURL = fileURL
        self.displayName = displayName
        super.init()
    }
    
    var previewItemURL: URL? {
        return fileURL
    }
    
    var previewItemTitle: String? {
        return displayName
    }
} 