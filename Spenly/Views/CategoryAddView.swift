import SwiftUI
import CoreData
import UIKit

struct CategoryAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    
    @State private var name = ""
    @State private var type = "expense"
    @State private var selectedIcon = "cart.fill"
    @State private var searchText = ""
    @State private var selectedIconCategory: IconCategory = .common
    
    // Define icon categories for better organization
    enum IconCategory: String, CaseIterable, Identifiable {
        case common = "Common"
        case finance = "Finance" 
        case home = "Home & Living"
        case food = "Food & Dining"
        case travel = "Travel & Transport"
        case health = "Health & Fitness"
        case entertainment = "Entertainment"
        case shopping = "Shopping"
        case tech = "Technology"
        
        var id: String { self.rawValue }
    }
    
    // Organized icons by category
    let iconCategories: [IconCategory: [String]] = [
        .common: ["cart.fill", "tag.fill", "star.fill", "gift.fill", "globe", "calendar", "bell.fill", "person.fill"],
        .finance: ["dollarsign.circle.fill", "creditcard.fill", "banknote.fill", "wallet.pass.fill", "building.columns.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill", "briefcase.fill"],
        .home: ["house.fill", "bed.double.fill", "couch.fill", "lamp.desk.fill", "washer.fill", "shower.fill", "sink.fill", "key.fill"],
        .food: ["fork.knife.circle.fill", "cup.and.saucer.fill", "wineglass.fill", "takeoutbag.and.cup.and.straw.fill", "carrot.fill", "birthday.cake.fill", "drop.fill", "leaf.fill"],
        .travel: ["car.fill", "airplane.circle.fill", "bus.fill", "train.side.front.car", "sailboat.fill", "bicycle", "scooter", "map.fill"],
        .health: ["cross.case.fill", "heart.fill", "pills.fill", "stethoscope", "bandage.fill", "brain.head.profile", "bed.double.fill", "figure.walk"],
        .entertainment: ["tv.fill", "gamecontroller.fill", "theatermasks.fill", "music.note", "ticket.fill", "popcorn.fill", "film.fill", "mic.fill"],
        .shopping: ["bag.fill", "basket.fill", "hanger", "tag.fill", "tshirt.fill", "eyeglasses", "shoeprints", "handbag.fill"],
        .tech: ["desktopcomputer", "laptopcomputer", "iphone", "headphones", "printer.fill", "keyboard", "externaldrive.fill", "network"]
    ]
    
    // Computed property to get filtered icons based on search and category
    private var filteredIcons: [String] {
        let categoryIcons = iconCategories[selectedIconCategory] ?? []
        if searchText.isEmpty {
            return categoryIcons
        } else {
            return categoryIcons.filter { $0.contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with Icon Preview
                    VStack(spacing: 20) {
                        // Category Icon Preview
                        Circle()
                            .fill(type == "expense" ? Color.red.opacity(0.2) : Color.green.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay {
                                Image(systemName: selectedIcon)
                                    .foregroundColor(type == "expense" ? .red : .green)
                                    .font(.system(size: 40))
                            }
                            .shadow(color: (type == "expense" ? Color.red : Color.green).opacity(0.2), radius: 8, x: 0, y: 4)
                            .padding(.top)
                        
                        // Name Input with better styling and character counter
                        VStack(spacing: 8) {
                            TextField("", text: $name)
                                .font(selectedFont.font(size: 22, bold: true))
                                .multilineTextAlignment(.center)
                                .placeholder(when: name.isEmpty) {
                                    Text("Category Name")
                                        .font(selectedFont.font(size: 22))
                                        .foregroundColor(.secondary)
                                }
                                .onChange(of: name) { newValue in
                                    // Limit to 25 characters
                                    if newValue.count > 25 {
                                        name = String(newValue.prefix(25))
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            
                            // Character counter
                            HStack {
                                Spacer()
                                Text("\(name.count)/25")
                                    .font(selectedFont.font(size: 12))
                                    .foregroundColor(name.count > 20 ? (name.count == 25 ? .red : .orange) : .secondary)
                            }
                            .padding(.horizontal, 8)
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom)
                    
                    // Type Selection with enhanced UI
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category Type")
                            .font(selectedFont.font(size: 16, bold: true))
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        HStack(spacing: 0) {
                            ForEach(["expense", "income"], id: \.self) { categoryType in
                                Button {
                                    withAnimation(.spring()) {
                                        type = categoryType
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: categoryType == "expense" ? 
                                            "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                            .font(.system(size: 18))
                                        Text(categoryType.capitalized)
                                            .fontWeight(.medium)
                                    }
                                    .font(selectedFont.font(size: 16))
                                    .foregroundColor(type == categoryType ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(type == categoryType ? 
                                                (categoryType == "expense" ? Color.red : Color.green) : 
                                                Color(.systemGray6))
                                    )
                                }
                            }
                        }
                        .padding(4)
                        .background(Color(.systemGray5))
                        .cornerRadius(20)
                        .padding(.horizontal)
                    }
                    
                    // Icon Selection with enhanced UI and categories
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Select Icon")
                                .font(selectedFont.font(size: 16, bold: true))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Search field for icon filtering
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Search", text: $searchText)
                                    .font(selectedFont.font(size: 14))
                                
                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .frame(width: 120)
                        }
                        .padding(.horizontal)
                        
                        // Icon Categories Horizontal Scroll
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(IconCategory.allCases) { category in
                                    Button(action: {
                                        withAnimation {
                                            selectedIconCategory = category
                                        }
                                    }) {
                                        Text(category.rawValue)
                                            .font(selectedFont.font(size: 14))
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(
                                                Capsule()
                                                    .fill(selectedIconCategory == category ?
                                                         (type == "expense" ? Color.red.opacity(0.2) : Color.green.opacity(0.2)) :
                                                         Color(.systemGray6))
                                            )
                                            .foregroundColor(selectedIconCategory == category ?
                                                            (type == "expense" ? .red : .green) : .primary)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Icon Grid with improved UI
                        if filteredIcons.isEmpty {
                            Text("No icons match your search")
                                .font(selectedFont.font(size: 14))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 65), spacing: 16)
                            ], spacing: 16) {
                                ForEach(filteredIcons, id: \.self) { icon in
                                    Button {
                                        withAnimation {
                                            selectedIcon = icon
                                            // Add haptic feedback
                                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                            impactMed.impactOccurred()
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(selectedIcon == icon ? 
                                                    (type == "expense" ? Color.red.opacity(0.15) : Color.green.opacity(0.15)) :
                                                    Color(.systemGray6))
                                                .frame(width: 60, height: 60)
                                            
                                            Image(systemName: icon)
                                                .foregroundColor(selectedIcon == icon ?
                                                                (type == "expense" ? .red : .green) :
                                                                .primary)
                                                .font(.system(size: 24))
                                            
                                            if selectedIcon == icon {
                                                Circle()
                                                    .strokeBorder(type == "expense" ? Color.red : Color.green, lineWidth: 2)
                                                    .frame(width: 60, height: 60)
                                            }
                                        }
                                        .contentShape(Circle())
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                    }
                    .font(selectedFont.font(size: 16, bold: true))
                    .foregroundColor(!name.isEmpty ? .blue : .gray)
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveCategory() {
        let category = Category(context: viewContext)
        category.id = UUID()
        category.name = name
        category.type = type
        category.isCustom = true
        category.icon = selectedIcon
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving category: \(error.localizedDescription)")
        }
    }
}

// Helper extension for placeholder text
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
} 