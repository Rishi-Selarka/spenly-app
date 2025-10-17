import SwiftUI
import Speech
import AVFoundation
import CoreData
import UniformTypeIdentifiers
import PDFKit
import UIKit

// Chat message model
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
}

// Message section for formatting
struct MessageSection {
    let text: String
    let type: SectionType
    
    enum SectionType {
        case heading
        case bullet
        case paragraph
    }
}

struct SpenlyChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var accountManager: AccountManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @StateObject private var aiManager = AIManager.shared
    
    // Chat state
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isListening: Bool = false
    @State private var showIncompatibleAlert: Bool = false
    @State private var isProcessing: Bool = false
    @State private var lastResultTransactions: [Transaction] = []
    @State private var showingAttachmentMenu: Bool = false
    @State private var showingReceiptPicker: Bool = false
    @State private var selectedImportImage: UIImage?
    @State private var showingFileImporter: Bool = false
    @State private var importDrafts: [DraftTransaction] = []
    @State private var showImportConfirmation: Bool = false
    @State private var pendingReceiptForAttachment: UIImage?
    @State private var speechSilenceTimer: Timer? = nil
    @State private var didAutoSend: Bool = false
    
    // Speech recognition - proper initialization
    private let speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Mic overlay visual state
    @State private var micPulse = false
    @State private var micWavePhase: CGFloat = 0
    
    // Fetch all transactions for analysis
    @FetchRequest(
        entity: Transaction.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
    ) private var allTransactions: FetchedResults<Transaction>
    
    var body: some View {
        NavigationView {
            ZStack {
                // Liquid glass background
                liquidGlassBackground
                
                VStack(spacing: 0) {
                    // AI compatibility banner (if incompatible)
                    if !aiManager.isAvailable {
                        incompatibilityBanner
                    }
                    
                    // Chat messages area
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                // Welcome message
                                if messages.isEmpty {
                                    welcomeSection
                                }
                                
                                // Chat messages
                                ForEach(messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                                
                                // Typing indicator
                                if isProcessing {
                                    typingIndicator
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _ in
                            // Auto-scroll to bottom when new message arrives
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Mic overlay centered while listening
                    if isListening {
                        MicOverlay()
                            .transition(.opacity.combined(with: .scale))
                            .zIndex(2)
                    }
                    
                    // Input area
                    inputSection
                }
            }
            .navigationTitle("Spenly AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Close")
                        }
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        clearChat()
                    }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                }
            }
        }
        .onAppear {
            checkAIAvailability()
            requestSpeechAuthorization()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.pdf, UTType.commaSeparatedText, UTType.image],
            allowsMultipleSelection: true
        ) { (result: Result<[URL], Error>) in
            switch result {
            case .success(let urls):
                handleImportedFiles(urls)
            case .failure(let error):
                let aiMessage = ChatMessage(content: "Import failed: \(error.localizedDescription)", isUser: false, timestamp: Date())
                withAnimation { self.messages.append(aiMessage) }
            }
        }
        .sheet(isPresented: $showingReceiptPicker) {
            ReceiptPickerView(
                selectedImage: $selectedImportImage,
                isPresented: $showingReceiptPicker
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedImportImage) { newImage in
            guard let image = newImage else { return }
            pendingReceiptForAttachment = image
            isProcessing = true
            print("📸 Starting receipt scan...")
            GeminiManager.shared.extractTransactionsFromImage(image: image, currency: selectedCurrency) { result in
                DispatchQueue.main.async {
                    self.isProcessing = false
                    switch result {
                    case .success(let text):
                        print("✅ Gemini response received:")
                        print(text)
                        if let drafts = parseDraftsFromLLMText(text) {
                            print("✅ Parsed \(drafts.count) draft(s)")
                            self.importDrafts = drafts
                            self.showImportConfirmation = true
                        } else {
                            print("❌ Failed to parse drafts from response")
                            let aiMessage = ChatMessage(content: "Could not confidently read receipt. Please try a clearer photo.", isUser: false, timestamp: Date())
                            withAnimation { self.messages.append(aiMessage) }
                        }
                    case .failure(let error):
                        print("❌ Gemini API error: \(error.localizedDescription)")
                        let aiMessage = ChatMessage(content: "Receipt scan failed: \(error.localizedDescription)", isUser: false, timestamp: Date())
                        withAnimation { self.messages.append(aiMessage) }
                    }
                }
            }
        }
        .sheet(isPresented: $showImportConfirmation) {
            ImportConfirmationView(
                drafts: $importDrafts,
                attachImage: pendingReceiptForAttachment,
                onConfirm: { confirmed in
                    saveImportedTransactions(confirmed, attachImage: pendingReceiptForAttachment)
                    pendingReceiptForAttachment = nil
                },
                onCancel: {
                    pendingReceiptForAttachment = nil
                }
            )
            .environment(\.managedObjectContext, viewContext)
            .environmentObject(themeManager)
            .environmentObject(accountManager)
        }
        .alert("Device Not Compatible", isPresented: $showIncompatibleAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(aiManager.getCompatibilityMessage())
        }
    }
    
    // MARK: - UI Components
    
    private var liquidGlassBackground: some View {
        ZStack {
            // Base dark gradient - matching HomeView (top to bottom)
            LinearGradient(
                gradient: Gradient(colors: [
                    themeManager.getAccentColor(for: colorScheme).opacity(0.3),
                    Color.black,
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Animated liquid orbs
            GeometryReader { geometry in
                ZStack {
                    // Orb 1 (top-left subtle glow)
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    themeManager.getAccentColor(for: colorScheme).opacity(0.3),
                                    themeManager.getAccentColor(for: colorScheme).opacity(0.1),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 300, height: 300)
                        .offset(x: -100, y: -150)
                        .blur(radius: 60)
                    
                    // (Removed bottom-right orb to keep corner pure black)
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Mic Overlay
    @ViewBuilder
    private func MicOverlay() -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 140, height: 140)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
                .scaleEffect(micPulse ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: micPulse)
                .onAppear { micPulse = true }
                .onDisappear { micPulse = false }
            
            // Concentric waves
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.25), lineWidth: 2)
                        .frame(width: CGFloat(140 + i*20), height: CGFloat(140 + i*20))
                        .scaleEffect(micPulse ? 1.02 : 0.98)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: micPulse)
                }
            }
            
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    .shadow(color: themeManager.getAccentColor(for: colorScheme).opacity(0.4), radius: 6)
                Text("Listening...")
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
    
    private var incompatibilityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            
            Text("Limited functionality on this device")
                .font(selectedFont.font(size: 13))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            Button(action: {
                showIncompatibleAlert = true
            }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.orange.opacity(0.2)
                .background(.ultraThinMaterial)
        )
    }
    
    // Typing indicator with better animation
    private var typingIndicator: some View {
        HStack(spacing: 12) {
            // AI avatar
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            themeManager.getAccentColor(for: colorScheme).opacity(0.3),
                            themeManager.getAccentColor(for: colorScheme).opacity(0.15)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                )
            
            // Animated dots with smooth wave effect
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    DotView(index: index, accentColor: themeManager.getAccentColor(for: colorScheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
            )
            
            Spacer()
        }
        .padding(.leading, 8)
    }
    
    private var welcomeSection: some View {
        VStack(spacing: 20) {
            // AI icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                themeManager.getAccentColor(for: colorScheme).opacity(0.3),
                                themeManager.getAccentColor(for: colorScheme).opacity(0.15)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)
                
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.6),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                themeManager.getAccentColor(for: colorScheme),
                                themeManager.getAccentColor(for: colorScheme).opacity(0.7)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 40)
            
            VStack(spacing: 12) {
                Text("Welcome to Spenly AI")
                    .font(selectedFont.font(size: 26, bold: true))
                    .foregroundColor(.white)
                
                Text("Your intelligent financial assistant")
                    .font(selectedFont.font(size: 15))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }
    
    private var inputSection: some View {
        VStack(spacing: 0) {
            // Glass divider
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 20)
            
            HStack(spacing: 12) {
                // Voice input button
                Button(action: {
                    toggleVoiceInput()
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                isListening ?
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.red.opacity(0.3),
                                        Color.red.opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.2),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: isListening ? "mic.fill" : "mic")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isListening ? .red : themeManager.getAccentColor(for: colorScheme))
                    }
                }
                .disabled(!aiManager.isAvailable)
                
                // Attachment button (paperclip)
                Button(action: {
                    showingAttachmentMenu = true
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.2),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                    }
                }
                .disabled(!aiManager.isAvailable)
                
                // Text input field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme).opacity(0.8))
                    
                    TextField("Ask me anything...", text: $inputText)
                        .font(selectedFont.font(size: 16))
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .disabled(isListening)
                    
                    if !inputText.isEmpty {
                        Button(action: {
                            inputText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme).opacity(0.7))
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // transparent background for liquid effect; no material
                // content behind will scroll visibly under this area
                // no overlay stroke or shadow to keep it clean
                
                // Send button
                Button(action: {
                    sendMessage(inputText)
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.isEmpty ?
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.05)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.getAccentColor(for: colorScheme),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(inputText.isEmpty ? .white.opacity(0.3) : .white)
                    }
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .confirmationDialog("Add from…", isPresented: $showingAttachmentMenu, titleVisibility: .visible) {
                Button("Scan Receipt (Camera/Photos)") { showingReceiptPicker = true }
                Button("Import from Files (PDF/CSV/Image)") { showingFileImporter = true }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    // MARK: - Functions
    
    private func checkAIAvailability() {
        aiManager.checkAvailability()
        if !aiManager.isAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showIncompatibleAlert = true
            }
        }
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                // Handle authorization status
            }
        }
    }
    
    private func toggleVoiceInput() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    private func startListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            return
        }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            
            let inputNode = audioEngine.inputNode
            guard let recognitionRequest = recognitionRequest else { return }
            
            // Reset auto-send state and timer
            didAutoSend = false
            speechSilenceTimer?.invalidate()
            
            recognitionRequest.shouldReportPartialResults = true
            
            withAnimation(.easeInOut(duration: 0.2)) { isListening = true }
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    inputText = result.bestTranscription.formattedString
                    restartSpeechSilenceTimer()
                }
                
                if error != nil || result?.isFinal == true {
                    audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.speechSilenceTimer?.invalidate()
                    let trimmed = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !self.didAutoSend {
                        self.didAutoSend = true
                        self.sendMessage(trimmed)
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { isListening = false }
                }
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            withAnimation(.easeInOut(duration: 0.2)) { isListening = true }
        } catch {
            print("Could not start audio engine: \(error.localizedDescription)")
        }
    }
    
    private func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        speechSilenceTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.2)) { isListening = false }
    }

    private func restartSpeechSilenceTimer() {
        speechSilenceTimer?.invalidate()
        speechSilenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.isListening {
                    let trimmed = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.didAutoSend = true
                        self.stopListening()
                        self.sendMessage(trimmed)
                    } else {
                        self.stopListening()
                    }
                }
            }
        }
    }
    
    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(content: text, isUser: true, timestamp: Date())
        messages.append(userMessage)
        
        // Clear input
        inputText = ""
        
        // Get AI response using OpenAI
        isProcessing = true
        
        Task {
            await getAIResponse(for: text)
        }
    }

    private func looksLikeMultiTransactionInput(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Heuristics: contains multiple commas or 'and' with amounts
        let hasCommaList = lower.components(separatedBy: ",").count >= 2
        let amountRegex = try? NSRegularExpression(pattern: "\\b(₹|rs\\.?|inr|usd|eur|gbp)?\\s?\\d+(?:[.,]\\d{1,2})?\\b", options: .caseInsensitive)
        let matches = amountRegex?.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? 0
        return matches >= 2 || hasCommaList || lower.contains(" and ")
    }
    
    private func getAIResponse(for input: String) async {
        // Fast-path: user typed multiple transactions in one sentence
        if looksLikeMultiTransactionInput(input) {
            await withCheckedContinuation { continuation in
                GeminiManager.shared.extractTransactionsFromText(text: input, currency: selectedCurrency) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let resp):
                            if let drafts = self.parseDraftsFromLLMText(resp), !drafts.isEmpty {
                                self.isProcessing = false
                                self.importDrafts = drafts
                                self.showImportConfirmation = true
                                let msg = "Found \(drafts.count) transaction(s) in your message. Please confirm or edit before adding."
                                let aiMessage = ChatMessage(content: msg, isUser: false, timestamp: Date())
                                withAnimation { self.messages.append(aiMessage) }
                                continuation.resume()
                                return
                            }
                        case .failure:
                            break
                        }
                        // Fallback to normal chat response
                        self.isProcessing = true
                        let systemPrompt = SpenlyAIContext.buildSystemPrompt(
                            with: Array(self.allTransactions.filter { $0.account?.id == self.accountManager.currentAccount?.id && !$0.isDemo }),
                            currency: self.selectedCurrency,
                            accountId: self.accountManager.currentAccount?.id,
                            conversationHistory: self.messages.suffix(4).map { $0.isUser ? "User: \($0.content)" : "Assistant: \($0.content)" }.joined(separator: "\n")
                        )
                        GeminiManager.shared.getResponse(
                            systemPrompt: systemPrompt,
                            userMessage: input
                        ) { result in
                            Task { @MainActor in
                                self.isProcessing = false
                                switch result {
                                case .success(let response):
                                    if let intent = SpenlyAIContext.parseTransactionIntent(from: response) { self.createTransaction(from: intent) }
                                    var cleaned = self.sanitizeAIText(response)
                                    if cleaned.lowercased().contains("invalid response") || cleaned.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                                        cleaned = "I can add transactions if you tell me:\n- amount (e.g., 50)\n- type (expense or income)\n- note (what is it for)\n- date (optional).\n\nFor example: 'Add \(self.selectedCurrency.symbol)50 expense for coffee today'."
                                    }
                                    let aiMessage = ChatMessage(content: cleaned, isUser: false, timestamp: Date())
                                    withAnimation { self.messages.append(aiMessage) }
                                case .failure(let error):
                                    let errorMessage = "Sorry, I encountered an error: \(error.localizedDescription)\n\nPlease check your internet connection and API key."
                                    let aiMessage = ChatMessage(content: errorMessage, isUser: false, timestamp: Date())
                                    withAnimation { self.messages.append(aiMessage) }
                                }
                                continuation.resume()
                            }
                        }
                    }
                }
            }
            return
        }
        // Get current account transactions (exclude demo transactions)
        let currentAccountTransactions = allTransactions.filter { transaction in
            transaction.account?.id == accountManager.currentAccount?.id && !transaction.isDemo
        }
        
        // Lightweight local intent handling to ensure correct follow-ups
        let lower = input.lowercased()
        let todayExpenses = currentAccountTransactions.filter { t in
            guard let d = t.date else { return false }
            return t.isExpense && Calendar.current.isDateInToday(d)
        }
        
        // If user asks for details after a previous count/list
        if (lower.contains("detail") || lower.contains("details")) && !lastResultTransactions.isEmpty {
            let details = formatTransactionList(lastResultTransactions)
            let reply = "Here are the details you asked for:\n\n" + details
            DispatchQueue.main.async {
                self.isProcessing = false
                let aiMessage = ChatMessage(content: reply, isUser: false, timestamp: Date())
                withAnimation { self.messages.append(aiMessage) }
            }
            return
        }
        
        // If user asks for count of today's expenses, answer locally and cache
        if lower.contains("how many") && lower.contains("expense") && (lower.contains("today") || lower.contains("today's")) {
            let count = todayExpenses.count
            let total = todayExpenses.reduce(0.0) { $0 + $1.amount }
            self.lastResultTransactions = todayExpenses
            let reply = "You have \(count) expenses today totaling \(selectedCurrency.symbol)\(String(format: "%.2f", total)).\n\nSay 'details' if you want the list."
            DispatchQueue.main.async {
                self.isProcessing = false
                let aiMessage = ChatMessage(content: reply, isUser: false, timestamp: Date())
                withAnimation { self.messages.append(aiMessage) }
            }
            return
        }
        
        // Cache context when user asks about today's expenses for potential follow-up
        if (lower.contains("today") || lower.contains("today's")) && lower.contains("expense") {
            self.lastResultTransactions = todayExpenses
        }
        
        // Build conversation history (last 4 messages for context)
        let recentHistory = messages.suffix(4).map { message in
            "\(message.isUser ? "User" : "Assistant"): \(message.content)"
        }.joined(separator: "\n")
        
        // Build system prompt with app context and user data
        let systemPrompt = SpenlyAIContext.buildSystemPrompt(
            with: Array(currentAccountTransactions),
            currency: selectedCurrency,
            accountId: accountManager.currentAccount?.id,
            conversationHistory: recentHistory
        )
        
        // Get response from Gemini (FREE)
        GeminiManager.shared.getResponse(
            systemPrompt: systemPrompt,
            userMessage: input
        ) { [self] result in
            DispatchQueue.main.async { [self] in
                self.isProcessing = false
                
                switch result {
                case .success(let response):
                    // Check if GPT wants to create a transaction
                    if let intent = SpenlyAIContext.parseTransactionIntent(from: response) {
                        self.createTransaction(from: intent)
                    }
                    
                    // Add AI response to chat (sanitized)
                    var cleaned = sanitizeAIText(response)
                    // If model returned JSON/error when user asked something vague, guide the user
                    if cleaned.lowercased().contains("invalid response") || cleaned.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                        cleaned = "I can add transactions if you tell me:\n- amount (e.g., 50)\n- type (expense or income)\n- note (what is it for)\n- date (optional).\n\nFor example: ‘Add ₹50 expense for coffee today’."
                    }
                    let aiMessage = ChatMessage(content: cleaned, isUser: false, timestamp: Date())
                    withAnimation {
                        self.messages.append(aiMessage)
                    }
                    
                case .failure(let error):
                    // Show error message
                    let errorMessage = "Sorry, I encountered an error: \(error.localizedDescription)\n\nPlease check your internet connection and API key."
                    let aiMessage = ChatMessage(content: errorMessage, isUser: false, timestamp: Date())
                    withAnimation {
                        self.messages.append(aiMessage)
                    }
                }
            }
        }
    }
    
    // MARK: - Import helpers
    
    private func handleImportedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isProcessing = true
        var aggregatedDrafts: [DraftTransaction] = []
        var rawResponses: [String] = []
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 3) // Limit to 3 concurrent API calls
        let lock = NSLock() // Thread-safe access to shared arrays
        for url in urls {
            if url.startAccessingSecurityScopedResource() { }
            defer { url.stopAccessingSecurityScopedResource() }
            if url.pathExtension.lowercased() == "pdf" {
                if let text = extractText(fromPDF: url) {
                    let chunks = chunkText(text, size: 2500)
                    if chunks.isEmpty {
                        print("⚠️ PDF text extraction produced no chunks")
                        continue
                    }
                    print("📄 PDF text extracted (\(text.count) chars, \(chunks.count) chunk(s))")
                    for (index, chunk) in chunks.enumerated() {
                        group.enter()
                        semaphore.wait()
                        GeminiManager.shared.extractTransactionsFromText(text: chunk, currency: selectedCurrency) { result in
                            if case .success(let resp) = result {
                                print("✅ AI response for PDF chunk #\(index + 1):")
                                print(resp)
                                lock.lock()
                                rawResponses.append("Chunk #\(index + 1):\n" + resp)
                                if let drafts = parseDraftsFromLLMText(resp) {
                                    aggregatedDrafts.append(contentsOf: drafts)
                                }
                                lock.unlock()
                            } else if case .failure(let error) = result {
                                print("❌ PDF chunk #\(index + 1) error: \(error)")
                            }
                            semaphore.signal()
                            group.leave()
                        }
                    }
                }
            } else if ["csv", "txt"].contains(url.pathExtension.lowercased()) {
                if let data = try? Data(contentsOf: url) {
                    // Try multiple encodings for text-based files
                    let text = String(data: data, encoding: .utf8) ?? 
                              String(data: data, encoding: .ascii) ?? 
                              String(data: data, encoding: .isoLatin1)
                    if let text = text {
                        let chunks = chunkText(text, size: 2500)
                        if chunks.isEmpty {
                            print("⚠️ Text file extraction produced no chunks")
                            continue
                        }
                        print("📊 Text file extracted (\(text.count) chars, \(chunks.count) chunk(s))")
                        for (index, chunk) in chunks.enumerated() {
                            group.enter()
                            semaphore.wait()
                            GeminiManager.shared.extractTransactionsFromText(text: chunk, currency: selectedCurrency) { result in
                                if case .success(let resp) = result {
                                    print("✅ AI response for text chunk #\(index + 1):")
                                    print(resp)
                                    lock.lock()
                                    rawResponses.append("Chunk #\(index + 1):\n" + resp)
                                    if let drafts = parseDraftsFromLLMText(resp) {
                                        aggregatedDrafts.append(contentsOf: drafts)
                                    }
                                    lock.unlock()
                                } else if case .failure(let error) = result {
                                    print("❌ Text chunk #\(index + 1) error: \(error)")
                                }
                                semaphore.signal()
                                group.leave()
                            }
                        }
                    } else {
                        print("❌ Could not decode text file with any supported encoding")
                    }
                }
            } else {
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    group.enter()
                    semaphore.wait()
                    GeminiManager.shared.extractTransactionsFromImage(image: image, currency: selectedCurrency) { result in
                        if case .success(let resp) = result {
                            lock.lock()
                            rawResponses.append(resp)
                            if let drafts = parseDraftsFromLLMText(resp) {
                                aggregatedDrafts.append(contentsOf: drafts)
                            }
                            lock.unlock()
                        }
                        semaphore.signal()
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) {
            self.isProcessing = false
            // Deduplicate drafts across chunks (amount + day + note + type)
            let deduped: [DraftTransaction] = {
                var seen = Set<String>()
                var result: [DraftTransaction] = []
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "yyyy-MM-dd"
                for d in aggregatedDrafts {
                    let dayKey = dayFormatter.string(from: d.date ?? Date())
                    let noteKey = (d.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let key = "\(String(format: "%.2f", d.amount))|\(dayKey)|\(noteKey)|\(d.isExpense ? "D" : "C")"
                    if !seen.contains(key) {
                        seen.insert(key)
                        result.append(d)
                    }
                }
                return result
            }()
            self.importDrafts = deduped
            self.pendingReceiptForAttachment = nil
            
            // Enhanced validation and reporting
            print("📊 Final aggregation: \(aggregatedDrafts.count) total transactions (\(deduped.count) after de-dup) from \(rawResponses.count) responses")
            
            // Validate transaction quality
            let validTransactions = deduped.filter { $0.amount > 0 }
            let totalAmount = validTransactions.reduce(0) { $0 + $1.amount }
            let expenseCount = validTransactions.filter { $0.isExpense }.count
            let incomeCount = validTransactions.filter { !$0.isExpense }.count
            
            print("📈 Transaction Summary:")
            print("   - Valid transactions: \(validTransactions.count)")
            print("   - Total amount: \(totalAmount)")
            print("   - Expenses: \(expenseCount)")
            print("   - Income: \(incomeCount)")
            
            if aggregatedDrafts.isEmpty {
                // Show AI response in chat for debugging
                if !rawResponses.isEmpty {
                    let debugMsg = "AI could not extract transactions. Response:\n\n\(rawResponses.joined(separator: "\n---\n"))"
                    let aiMessage = ChatMessage(content: debugMsg, isUser: false, timestamp: Date())
                    withAnimation { self.messages.append(aiMessage) }
                } else {
                    let aiMessage = ChatMessage(content: "No valid transactions found in the selected files.", isUser: false, timestamp: Date())
                    withAnimation { self.messages.append(aiMessage) }
                }
            } else {
                // Show success message with transaction count
                let successMsg = "✅ Successfully extracted \(validTransactions.count) transactions (₹\(String(format: "%.2f", totalAmount)))"
                let aiMessage = ChatMessage(content: successMsg, isUser: false, timestamp: Date())
                withAnimation { self.messages.append(aiMessage) }
                self.showImportConfirmation = true
            }
        }
    }

    private func chunkText(_ text: String, size: Int) -> [String] {
        guard size > 0, !text.isEmpty else { return [] }
        var chunks: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = text[index..<end]
            chunks.append(String(chunk))
            index = end
        }
        print("📝 Created \(chunks.count) chunks of size \(size)")
        return chunks
    }
    
    private func extractText(fromPDF url: URL) -> String? {
        guard let doc = PDFKit.PDFDocument(url: url) else { return nil }
        var text = ""
        // Process all pages, not just first 10
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractJSONArray(from text: String) -> Data? {
        if let start = text.firstIndex(of: "[") , let end = text.lastIndex(of: "]"), start < end {
            let jsonStr = String(text[start...end])
            return jsonStr.data(using: .utf8)
        }
        return nil
    }
    
    private func parseDraftsFromLLMText(_ text: String) -> [DraftTransaction]? {
        print("🔍 Attempting to parse LLM text...")
        print("📝 Raw AI response: \(text)")
        
        // Strategy 1: direct JSON array extraction
        if let data = extractJSONArray(from: text), let drafts = try? JSONDecoder.iso8601.decode([DraftTransaction].self, from: data) {
            print("✅ Strategy 1 succeeded (direct JSON array) - Found \(drafts.count) transactions")
            return drafts
        }
        
        // Strategy 2: try fenced code blocks
        if let range = text.range(of: "```"), let endRange = text.range(of: "```", options: .backwards), range.lowerBound < endRange.upperBound {
            let inner = String(text[range.upperBound..<endRange.lowerBound])
            if let data = extractJSONArray(from: inner), let drafts = try? JSONDecoder.iso8601.decode([DraftTransaction].self, from: data) {
                print("✅ Strategy 2 succeeded (fenced code blocks) - Found \(drafts.count) transactions")
                return drafts
            }
        }
        
        // Strategy 3: Enhanced permissive mapping with better error handling
        func toDrafts(from any: Any) -> [DraftTransaction]? {
            if let arr = any as? [[String: Any]] {
                print("🔄 Strategy 3: Found array with \(arr.count) item(s)")
                let drafts = arr.compactMap { dictToDraft($0) }
                print("📊 Successfully parsed \(drafts.count) out of \(arr.count) items")
                return drafts
            }
            if let obj = any as? [String: Any], let arr = obj["transactions"] as? [[String: Any]] {
                print("🔄 Strategy 3: Found transactions wrapper with \(arr.count) item(s)")
                let drafts = arr.compactMap { dictToDraft($0) }
                print("📊 Successfully parsed \(drafts.count) out of \(arr.count) items")
                return drafts
            }
            return nil
        }
        
        // Try parsing the whole text as JSON
        if let dataWhole = text.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: dataWhole) {
            if let drafts = toDrafts(from: any), !drafts.isEmpty {
                print("✅ Strategy 3 succeeded (whole text JSON) - Found \(drafts.count) transactions")
                return drafts
            }
        }
        
        // Try extracting JSON array from text
        if let dataBrackets = extractJSONArray(from: text), let any = try? JSONSerialization.jsonObject(with: dataBrackets) {
            if let drafts = toDrafts(from: any), !drafts.isEmpty {
                print("✅ Strategy 3 succeeded (extracted JSON array) - Found \(drafts.count) transactions")
                return drafts
            }
        }
        
        // Strategy 4: Try to find JSON-like patterns in the text
        let jsonPattern = #"\[[\s\S]*?\]"#
        if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            let jsonString = String(text[Range(match.range, in: text)!])
            if let data = jsonString.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) {
                if let drafts = toDrafts(from: any), !drafts.isEmpty {
                    print("✅ Strategy 4 succeeded (regex extraction) - Found \(drafts.count) transactions")
                    return drafts
                }
            }
        }
        
        print("❌ All parsing strategies failed")
        print("📝 Failed to parse text: \(text)")
        return nil
    }
    
    private func dictToDraft(_ d: [String: Any]) -> DraftTransaction? {
        print("🔄 Parsing dict: \(d)")
        
        // Enhanced amount parsing with multiple fallbacks
        let amount: Double? = {
            // Try direct number
            if let n = d["amount"] as? NSNumber { return n.doubleValue }
            if let n = d["amount"] as? Double { return n }
            if let n = d["amount"] as? Int { return Double(n) }
            
            // Try string parsing with multiple formats
            if let s = d["amount"] as? String {
                let cleaned = s
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "₹", with: "")
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: "€", with: "")
                    .replacingOccurrences(of: "£", with: "")
                    .replacingOccurrences(of: "[^0-9.\\-]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let parsed = Double(cleaned), parsed > 0 {
                    return parsed
                }
            }
            
            // Try alternative field names
            if let debit = d["debit"] as? Double, debit > 0 { return debit }
            if let credit = d["credit"] as? Double, credit > 0 { return credit }
            if let value = d["value"] as? Double, value > 0 { return value }
            
            return nil
        }()
        
        guard let amt = amount, amt > 0 else {
            print("⚠️ Could not parse valid amount from: \(d["amount"] ?? "nil")")
            return nil
        }
        
        // Enhanced expense detection with multiple indicators
        let isExpense: Bool = {
            // Direct boolean
            if let b = d["isExpense"] as? Bool { return b }
            
            // Type field
            if let t = d["type"] as? String {
                let type = t.lowercased()
                if type.contains("expense") || type.contains("debit") || type.contains("withdrawal") {
                    return true
                }
                if type.contains("income") || type.contains("credit") || type.contains("deposit") {
                    return false
                }
            }
            
            // Transaction type field
            if let tt = d["transactionType"] as? String {
                let type = tt.lowercased()
                if type.contains("debit") || type.contains("withdrawal") || type.contains("payment") {
                    return true
                }
                if type.contains("credit") || type.contains("deposit") || type.contains("salary") {
                    return false
                }
            }
            
            // Check for debit/credit indicators in description
            if let note = d["note"] as? String {
                let noteLower = note.lowercased()
                if noteLower.contains("debit") || noteLower.contains("withdrawal") || noteLower.contains("payment") {
                    return true
                }
                if noteLower.contains("credit") || noteLower.contains("deposit") || noteLower.contains("salary") {
                    return false
                }
            }
            
            // Default to expense for receipts, income for salary/credit patterns
            if let note = d["note"] as? String {
                let noteLower = note.lowercased()
                if noteLower.contains("salary") || noteLower.contains("income") || noteLower.contains("credit") {
                    return false
                }
            }
            
            return true // Default to expense
        }()
        
        // Enhanced note parsing
        let note: String? = {
            let candidates = ["note", "description", "desc", "memo", "narration", "particulars"]
            for key in candidates {
                if let value = d[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }()
        
        // Enhanced category parsing
        let category: String? = {
            if let cat = d["category"] as? String, !cat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cat.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }()
        
        // Enhanced date parsing
        var date: Date? = nil
        let dateFields = ["date", "transactionDate", "txnDate", "valueDate"]
        for field in dateFields {
            if let ds = d[field] as? String {
                date = parseFlexibleDate(ds)
                if date != nil { break }
            }
        }
        
        // Fallback to current date if parsing failed
        if date == nil {
            date = Date()
        }
        
        print("✅ Created draft: amount=\(amt), isExpense=\(isExpense), note=\(note ?? "nil"), category=\(category ?? "nil")")
        return DraftTransaction(amount: amt, isExpense: isExpense, note: note, category: category, date: date)
    }
    
    private func parseFlexibleDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try ISO8601 first
        if let d = ISO8601DateFormatter().date(from: trimmed) { return d }
        let fmts = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "MM-dd-yyyy", "dd-MM-yyyy"]
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        for f in fmts { df.dateFormat = f; if let d = df.date(from: trimmed) { return d } }
        return nil
    }
    
    private func saveImportedTransactions(_ drafts: [DraftTransaction], attachImage: UIImage?) {
        guard let currentAccountId = accountManager.currentAccount?.id else { return }
        viewContext.perform { [self] in
            do {
                let accountFetch: NSFetchRequest<Account> = Account.fetchRequest()
                accountFetch.predicate = NSPredicate(format: "id == %@", currentAccountId as CVarArg)
                accountFetch.fetchLimit = 1
                guard let account = try? self.viewContext.fetch(accountFetch).first else { return }
                for (index, d) in drafts.enumerated() {
                    let t = Transaction(context: self.viewContext)
                    t.id = UUID()
                    t.amount = d.amount
                    t.isExpense = d.isExpense
                    t.date = d.date ?? Date()
                    t.note = d.note
                    t.account = account
                    // Category mapping
                    if let hint = d.category, !hint.isEmpty {
                        let cf: NSFetchRequest<Category> = Category.fetchRequest()
                        cf.predicate = NSPredicate(format: "name CONTAINS[cd] %@", hint)
                        cf.fetchLimit = 1
                        if let c = try? self.viewContext.fetch(cf).first { t.category = c }
                    }
                    // Attach receipt only for single-image imports
                    if let img = attachImage, drafts.count == 1 && index == 0 {
                        _ = ReceiptManager.shared.saveReceiptImageData(img, to: t)
                    }
                }
                try self.viewContext.save()
                DispatchQueue.main.async {
                    self.showImportConfirmation = false
                    let summary = drafts.count == 1 ? "Added 1 transaction: \(drafts.first?.note ?? "")" : "Added \(drafts.count) transactions from import"
                    let aiMessage = ChatMessage(content: "✅ \(summary)", isUser: false, timestamp: Date())
                    withAnimation { self.messages.append(aiMessage) }
                    NotificationCenter.default.post(name: NSNotification.Name("TransactionUpdated"), object: nil)
                }
            } catch {
                print("❌ Error saving imported transactions: \(error.localizedDescription)")
            }
        }
    }
    
    
    // Create transaction from AI intent - THREAD SAFE
    private func createTransaction(from intent: TransactionIntent) {
        guard let amount = intent.amount,
              let currentAccountId = accountManager.currentAccount?.id else {
            return
        }
        
        // CRITICAL: Perform Core Data operations on viewContext's queue
        viewContext.perform { [self] in
            
            do {
                // Create new transaction in Core Data
                let newTransaction = Transaction(context: self.viewContext)
                newTransaction.id = UUID()
                newTransaction.amount = amount
                newTransaction.isExpense = intent.isExpense
                newTransaction.date = Date()
                newTransaction.note = intent.note.map { sanitizeNote($0) }
                
                // Find and set account
                let accountFetch: NSFetchRequest<Account> = Account.fetchRequest()
                accountFetch.predicate = NSPredicate(format: "id == %@", currentAccountId as CVarArg)
                accountFetch.fetchLimit = 1
                
                if let account = try? self.viewContext.fetch(accountFetch).first {
                    newTransaction.account = account
                } else {
                    print("⚠️ Could not find account, transaction not created")
                    return
                }
                
                // Try to find matching category
                if let categoryHint = intent.category {
                    let categoryFetch: NSFetchRequest<Category> = Category.fetchRequest()
                    categoryFetch.predicate = NSPredicate(format: "name CONTAINS[cd] %@", categoryHint)
                    categoryFetch.fetchLimit = 1
                    
                    if let category = try? self.viewContext.fetch(categoryFetch).first {
                        newTransaction.category = category
                    }
                }
                
                // Save to Core Data
                try self.viewContext.save()
                
                // Post notification on main thread
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TransactionUpdated"),
                        object: nil
                    )
                }
                
                print("✅ AI created transaction: \(amount) - \(newTransaction.note ?? "No note")")
            } catch {
                print("❌ Error creating transaction: \(error.localizedDescription)")
            }
        }
    }
    
    // Format a transaction list into neat bullet points
    private func formatTransactionList(_ transactions: [Transaction]) -> String {
        guard !transactions.isEmpty else { return "No transactions found." }
        let formatter = DateFormatter(); formatter.dateFormat = "h:mm a"
        return transactions.enumerated().map { (idx, t) in
            let time = formatter.string(from: t.date ?? Date())
            let cat = t.category?.name ?? "Uncategorized"
            let note = (t.note?.isEmpty == false ? t.note! : "No note")
            return "\(idx + 1). \(selectedCurrency.symbol)\(String(format: "%.2f", t.amount)) - \(note) (\(cat)) at \(time)"
        }.joined(separator: "\n")
    }
    
    // Clean up AI notes (remove prepositions/articles)
    private func sanitizeNote(_ note: String) -> String {
        let lowered = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "(?i)\\b(for|in|on|at|to|from|with|a|an|the)\\b"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: (lowered as NSString).length)
            let cleaned = regex.stringByReplacingMatches(in: lowered, options: [], range: range, withTemplate: "").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        return note
    }
    
    private func clearChat() {
        withAnimation {
            messages.removeAll()
        }
    }
    
    // Sanitize AI text by removing markdown emphasis and code ticks
    private func sanitizeAIText(_ text: String) -> String {
        var output = text
        let patterns = [
            "\\*\\*(.*?)\\*\\*",   // **bold**
            "__(.*?)__",               // __bold__
            "\\*(.*?)\\*",           // *italic*
            "_(.*?)_",                 // _italic_
            "`(.*?)`"                  // `code`
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                output = regex.stringByReplacingMatches(in: output, options: [], range: NSRange(location: 0, length: (output as NSString).length), withTemplate: "$1")
            }
        }
        return output
    }
}

// MARK: - Quick Action Button Component
struct QuickActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                
                Text(title)
                    .font(selectedFont.font(size: 11))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Animated Dot Component
struct DotView: View {
    let index: Int
    let accentColor: Color
    @State private var scale: CGFloat = 0.5
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(accentColor.opacity(0.8))
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .onAppear {
                isAnimating = true
                withAnimation(
                    Animation
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2)
                ) {
                    if isAnimating {
                        scale = 1.2
                    }
                }
            }
            .onDisappear {
                isAnimating = false
                scale = 0.5 // Reset to prevent crash
            }
    }
}

// MARK: - Message Bubble Component

struct MessageBubble: View {
    let message: ChatMessage
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top) {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                // Formatted message content with proper spacing
                formattedMessageContent
                    .font(selectedFont.font(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            if message.isUser {
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.getAccentColor(for: colorScheme),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .mask(
                                    RoundedRectangle(cornerRadius: 18)
                                )
                            }
                        }
                    )
                
                Text(formatTime(message.timestamp))
                    .font(selectedFont.font(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 4)
            }
            
            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
    }
    
    // Format AI responses with proper spacing and structure
    private var formattedMessageContent: some View {
        let sections = parseMessageSections(message.content)
        
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if section.type == .heading {
                    Text(section.text)
                        .font(selectedFont.font(size: 16, bold: true))
                        .foregroundColor(.white)
                        .padding(.top, index > 0 ? 8 : 0)
                } else if section.type == .bullet {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        Text(section.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(section.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func parseMessageSections(_ content: String) -> [MessageSection] {
        var sections: [MessageSection] = []
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            guard !trimmed.isEmpty else { continue }
            
            // Check if it's a heading (contains emoji indicators or all caps short text)
            if trimmed.contains("📊") || trimmed.contains("💰") || trimmed.contains("📈") || 
               trimmed.contains("📅") || trimmed.contains("🎯") || trimmed.contains("💡") ||
               trimmed.contains("⚠️") || trimmed.contains("✅") {
                sections.append(MessageSection(text: trimmed, type: .heading))
            }
            // Check if it's a bullet point
            else if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") {
                let bulletText = trimmed.replacingOccurrences(of: "^[•-]\\s*", with: "", options: .regularExpression)
                sections.append(MessageSection(text: bulletText, type: .bullet))
            }
            // Regular paragraph
            else {
                sections.append(MessageSection(text: trimmed, type: .paragraph))
            }
        }
        
        return sections
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Suggestion Chip Component

struct SuggestionChip: View {
    let text: String
    let icon: String
    let action: () -> Void
    
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                
                Text(text)
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.06)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.4),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
    }
}

#Preview {
    SpenlyChatView()
        .environmentObject(ThemeManager.shared)
}


