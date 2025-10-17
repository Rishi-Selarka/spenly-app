import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

struct ReceiptPickerView: View {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingDocumentPicker = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Attach Receipt")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Choose how you'd like to add your receipt")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                // Camera Button
                Button(action: {
                    handleCameraAccess()
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Take Photo")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(themeManager.getAccentColor(for: colorScheme))
                    .cornerRadius(12)
                }
                
                // Photo Library Button
                Button(action: {
                    showingPhotoLibrary = true
                }) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                        Text("Choose from Photos")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(themeManager.getAccentColor(for: colorScheme).opacity(0.85))
                    .cornerRadius(12)
                }
                
                // Files Button
                Button(action: {
                    showingDocumentPicker = true
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                        Text("Choose from Files")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(themeManager.getAccentColor(for: colorScheme).opacity(0.7))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            // Cancel Button
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.secondary)
            .padding(.top)
        }
        .padding()
        .cornerRadius(20)
        .background(
            Color.clear
                .ignoresSafeArea()
        )
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView { image in
                selectedImage = image
                isPresented = false
            }
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            PhotoLibraryPickerView { image in
                selectedImage = image
                isPresented = false
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPickerView { image in
                selectedImage = image
                isPresented = false
            }
        }
        .alert("Camera Access Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionAlertMessage)
        }
    }
    
    // MARK: - Camera Permission Handling
    
    private func handleCameraAccess() {
        // Check if camera is available
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            permissionAlertMessage = "Camera is not available on this device. Please use 'Choose from Photos' or 'Choose from Files' instead."
            showingPermissionAlert = true
            return
        }
        
        // Check camera authorization status
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authStatus {
        case .authorized:
            // Permission already granted
            showingCamera = true
            
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showingCamera = true
                    } else {
                        self.permissionAlertMessage = "Camera access is required to take receipt photos. Please grant permission in Settings to use this feature."
                        self.showingPermissionAlert = true
                    }
                }
            }
            
        case .denied, .restricted:
            // Permission denied or restricted
            permissionAlertMessage = "Camera access is required to take receipt photos. Please enable camera access in Settings to use this feature."
            showingPermissionAlert = true
            
        @unknown default:
            // Handle future cases
            permissionAlertMessage = "Unable to access camera. Please try again or use 'Choose from Photos' instead."
            showingPermissionAlert = true
        }
    }
}

// MARK: - Camera Picker View

struct CameraPickerView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion, presentationMode: presentationMode)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        let presentationMode: Binding<PresentationMode>
        
        init(completion: @escaping (UIImage?) -> Void, presentationMode: Binding<PresentationMode>) {
            self.completion = completion
            self.presentationMode = presentationMode
            super.init()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            DispatchQueue.main.async {
                let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
                
                picker.dismiss(animated: true) {
                    self.completion(image)
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async {
                picker.dismiss(animated: true) {
                    self.completion(nil)
                }
            }
        }
    }
}

// MARK: - Photo Library Picker View

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (UIImage?) -> Void
        
        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                completion(nil)
                return
            }
            
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error loading image: \(error.localizedDescription)")
                            self.completion(nil)
                        } else {
                            self.completion(image as? UIImage)
                        }
                    }
                }
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Document Picker View

struct DocumentPickerView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.image])
        documentPicker.allowsMultipleSelection = false
        documentPicker.delegate = context.coordinator
        return documentPicker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (UIImage?) -> Void
        
        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                completion(nil)
                return
            }
            
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                completion(nil)
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Load image from the selected file
            do {
                let imageData = try Data(contentsOf: url)
                if let image = UIImage(data: imageData) {
                    completion(image)
                } else {
                    print("❌ Failed to create image from file data: \(url.lastPathComponent)")
                    completion(nil)
                }
            } catch {
                print("❌ Error reading file: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
} 
