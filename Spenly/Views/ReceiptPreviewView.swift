import SwiftUI
import QuickLook
import UIKit

struct ReceiptPreviewView: View {
    let transaction: Transaction
    @State private var showingQuickLook = false
    @State private var showingDeleteAlert = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if let image = ReceiptManager.shared.getReceiptImage(from: transaction) {
                    
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical], showsIndicators: false) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    minWidth: geometry.size.width,
                                    minHeight: geometry.size.height
                                )
                        }
                    }
                    .background(Color.black)
                    .onTapGesture {
                        showingQuickLook = true
                    }
                    
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Receipt not found")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("The receipt image may have been deleted or moved.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: HStack {
                    if transaction.receiptFileName != nil {
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showingQuickLook) {
            if let fileName = transaction.receiptFileName,
               let url = ReceiptManager.shared.getReceiptImageURL(fileName: fileName) {
                QuickLookView(url: url, fileName: fileName)
            }
        }
        .alert("Delete Receipt", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteReceipt()
            }
        } message: {
            Text("Are you sure you want to delete this receipt? This action cannot be undone.")
        }
    }
    
    private func deleteReceipt() {
        // Delete receipt using new CloudKit-enabled method
        ReceiptManager.shared.deleteReceiptImage(from: transaction)
        
        // Save changes to Core Data
        let context = PersistenceController.shared.container.viewContext
        do {
            try context.save()
            
            // Force immediate UI refresh
            DispatchQueue.main.async {
                // Refresh the specific transaction object
                context.refresh(self.transaction, mergeChanges: true)
                
                // Force refresh all objects to trigger @FetchRequest updates
                context.refreshAllObjects()
                
                // Post notification for any observers
                NotificationCenter.default.post(
                    name: NSNotification.Name("TransactionUpdated"),
                    object: self.transaction
                )
                
                // Dismiss the preview
                self.presentationMode.wrappedValue.dismiss()
            }
        } catch {
            print("❌ Error deleting receipt: \(error.localizedDescription)")
        }
    }
}

// MARK: - QuickLook View

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    let fileName: String
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: QuickLookView
        
        init(_ parent: QuickLookView) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return ReceiptPreviewItem(fileURL: parent.url, displayName: parent.fileName)
        }
    }
}

// MARK: - Preview Wrapper for SwiftUI

struct ReceiptPreviewWrapper: View {
    let transaction: Transaction
    @Binding var isPresented: Bool
    
    var body: some View {
        ReceiptPreviewView(transaction: transaction)
            .onDisappear {
                isPresented = false
            }
    }
} 