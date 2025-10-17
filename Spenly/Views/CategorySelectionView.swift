import SwiftUI

struct CategorySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedCategories: Set<Category>
    
    @FetchRequest private var categories: FetchedResults<Category>
    @State private var uniqueCategories: [Category] = []
    
    init(selectedCategories: Binding<Set<Category>>) {
        self._selectedCategories = selectedCategories
        self._categories = FetchRequest(
            entity: Category.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)],
            predicate: NSPredicate(format: "type == %@", "expense"),
            animation: .none
        )
    }
    
    private var selectedCategoryIds: Set<UUID> {
        Set(selectedCategories.compactMap { $0.id })
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(uniqueCategories, id: \.objectID) { category in
                    BudgetCategoryRow(
                        category: category,
                        isSelected: selectedCategoryIds.contains(category.id ?? UUID()),
                        onToggle: {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        }
                    )
                }
            }
            .optimizedList()
            .navigationTitle("Select Categories")
            .navigationBarItems(trailing: Button("Done") { dismiss() }
                .foregroundColor(.white))
            .background(Color.black)
            .onAppear {
                // Clean up categories in viewContext first
                CategoryManager.shared.cleanupAllDuplicateCategories(context: viewContext)
                // Then filter for display
                filterCategories()
            }
        }
    }
    
    private func filterCategories() {
        // Create a dictionary to store unique categories by normalized name
        var uniqueCategoryDict: [String: Category] = [:]
        
        // Process all categories fetched from CoreData
        for category in categories {
            guard let name = category.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            
            // Normalize the name to handle variations
            let normalizedName = name
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: " ", with: "")
            
            // If this category name doesn't exist yet, add it
            if uniqueCategoryDict[normalizedName] == nil {
                uniqueCategoryDict[normalizedName] = category
            } else {
                // If it exists, prefer system categories over custom ones
                let existingIsCustom = uniqueCategoryDict[normalizedName]?.isCustom ?? true
                let newIsCustom = category.isCustom
                
                if !newIsCustom && existingIsCustom {
                    // Replace with system category
                    uniqueCategoryDict[normalizedName] = category
                }
            }
        }
        
        // Convert the dictionary values to an array and sort
        uniqueCategories = uniqueCategoryDict.values.sorted { 
            // First by custom/system
            if ($0.isCustom != $1.isCustom) {
                return !$0.isCustom
            }
            // Then by name
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }
}

struct BudgetCategoryRow: View {
    let category: Category
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Text(category.name ?? "")
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                }
            }
        }
        .foregroundColor(.white)
    }
} 