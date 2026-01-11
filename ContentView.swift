import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var words: [String]
    var arabicWords: [String]? // For dual-language books like Quran
    var currentWordIndex: Int
    var wordsPerMinute: Double
    var thumbnailData: Data?
    var dateAdded: Date

    var isDualLanguage: Bool {
        arabicWords != nil && !arabicWords!.isEmpty
    }

    init(id: UUID = UUID(), title: String, words: [String], arabicWords: [String]? = nil, currentWordIndex: Int = 0, wordsPerMinute: Double = 250, thumbnailData: Data? = nil) {
        self.id = id
        self.title = title
        self.words = words
        self.arabicWords = arabicWords
        self.currentWordIndex = currentWordIndex
        self.wordsPerMinute = wordsPerMinute
        self.thumbnailData = thumbnailData
        self.dateAdded = Date()
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var savedBooks: [Book] = []
    @State private var currentBook: Book?

    var body: some View {
        TabView(selection: $selectedTab) {
            BookLibraryView(
                books: $savedBooks,
                currentBook: $currentBook,
                selectedTab: $selectedTab
            )
            .tag(0)

            ReaderView(
                book: $currentBook,
                savedBooks: $savedBooks
            )
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onAppear {
            loadBooks()
        }
    }

    private func loadBooks() {
        if let data = UserDefaults.standard.data(forKey: "savedBooks"),
           let decoded = try? JSONDecoder().decode([Book].self, from: data) {
            savedBooks = decoded
        }
    }
}

struct ReaderView: View {
    @Binding var book: Book?
    @Binding var savedBooks: [Book]

    @State private var showingDocumentPicker = false
    @State private var isPlaying = false
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            VStack {
                Button(action: {
                    showingDocumentPicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: book == nil ? "doc.badge.plus" : "doc.text")
                        Text(book?.title ?? "Upload PDF")
                            .lineLimit(1)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                }
                .padding(.top, 20)

                Spacer()

                if let currentBook = book, !currentBook.words.isEmpty {
                    if currentBook.isDualLanguage {
                        // Dual language display (Quran): English top, Arabic bottom
                        VStack(spacing: 20) {
                            Text(currentBook.words[currentBook.currentWordIndex])
                                .font(.system(size: 48, weight: .light, design: .default))
                                .tracking(1)
                                .minimumScaleFactor(0.3)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            if let arabicWords = currentBook.arabicWords,
                               currentBook.currentWordIndex < arabicWords.count {
                                Text(arabicWords[currentBook.currentWordIndex])
                                    .font(.system(size: 48, weight: .regular, design: .default))
                                    .tracking(1)
                                    .minimumScaleFactor(0.3)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }
                        }
                    } else {
                        // Single language display
                        Text(currentBook.words[currentBook.currentWordIndex])
                            .font(.system(size: 64, weight: .light, design: .monospaced))
                            .tracking(1)
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .padding(.horizontal, 40)
                    }
                } else {
                    Text("Upload a PDF to begin")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let currentBook = book, !currentBook.words.isEmpty {
                    VStack(spacing: 30) {
                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 70))
                                .foregroundColor(.blue)
                        }

                        VStack(spacing: 8) {
                            Text("\(Int(currentBook.wordsPerMinute))")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)

                            Slider(value: Binding(
                                get: { currentBook.wordsPerMinute },
                                set: { newValue in
                                    book?.wordsPerMinute = newValue
                                    saveBooks()
                                    if isPlaying {
                                        restartTimer()
                                    }
                                }
                            ), in: 100...600, step: 10)
                            .tint(.blue)
                            .frame(width: 200)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in
                loadPDF(from: url)
            }
        }
        .onDisappear {
            saveBooks()
            timer?.invalidate()
        }
    }

    private func loadPDF(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security scoped resource")
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        guard let pdfDocument = PDFDocument(url: url) else {
            print("Failed to load PDF")
            return
        }

        let fileName = url.lastPathComponent.replacingOccurrences(of: ".pdf", with: "")
        var extractedText = ""

        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex) {
                if let pageText = page.string {
                    extractedText += pageText + " "
                }
            }
        }

        // Check if this is a Quran/dual-language book
        let isQuranBook = fileName.lowercased().contains("quran") || fileName.lowercased().contains("qur")

        var extractedWords: [String]
        var arabicWords: [String]?

        if isQuranBook {
            // Separate English and Arabic words
            let (english, arabic) = separateLanguages(from: extractedText)
            extractedWords = english
            arabicWords = arabic
        } else {
            // Regular single-language extraction
            extractedWords = extractedText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
        }

        var thumbnailData: Data?
        if let firstPage = pdfDocument.page(at: 0) {
            let pageRect = firstPage.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200 * pageRect.height / pageRect.width))
            let thumbnail = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
                ctx.cgContext.translateBy(x: 0, y: renderer.format.bounds.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                ctx.cgContext.scaleBy(x: renderer.format.bounds.width / pageRect.width,
                                     y: renderer.format.bounds.height / pageRect.height)
                firstPage.draw(with: .mediaBox, to: ctx.cgContext)
            }
            thumbnailData = thumbnail.jpegData(compressionQuality: 0.8)
        }

        let newBook = Book(
            title: fileName,
            words: extractedWords,
            arabicWords: arabicWords,
            currentWordIndex: 0,
            wordsPerMinute: 250,
            thumbnailData: thumbnailData
        )

        book = newBook
        savedBooks.append(newBook)
        isPlaying = false
        timer?.invalidate()

        saveBooks()
    }

    private func separateLanguages(from text: String) -> ([String], [String]) {
        let allWords = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var englishWords: [String] = []
        var arabicWords: [String] = []

        for word in allWords {
            // Check if word contains Arabic characters (Unicode range U+0600 to U+06FF)
            let hasArabic = word.unicodeScalars.contains { scalar in
                (0x0600...0x06FF).contains(scalar.value)
            }

            if hasArabic {
                arabicWords.append(word)
            } else {
                englishWords.append(word)
            }
        }

        // Ensure both arrays have the same length by padding the shorter one
        let maxLength = max(englishWords.count, arabicWords.count)
        while englishWords.count < maxLength {
            englishWords.append("")
        }
        while arabicWords.count < maxLength {
            arabicWords.append("")
        }

        return (englishWords, arabicWords)
    }

    private func togglePlayback() {
        guard let currentBook = book else { return }

        isPlaying.toggle()

        if isPlaying {
            startTimer()
        } else {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        guard let currentBook = book else { return }
        let interval = 60.0 / currentBook.wordsPerMinute
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            nextWord()
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        if isPlaying {
            startTimer()
        }
    }

    private func nextWord() {
        guard var currentBook = book else { return }

        if currentBook.currentWordIndex < currentBook.words.count - 1 {
            currentBook.currentWordIndex += 1
            book = currentBook
            updateBookInList()
            saveBooks()
        } else {
            isPlaying = false
            timer?.invalidate()
        }
    }

    private func saveBooks() {
        updateBookInList()
        if let encoded = try? JSONEncoder().encode(savedBooks) {
            UserDefaults.standard.set(encoded, forKey: "savedBooks")
        }
    }

    private func updateBookInList() {
        guard let currentBook = book,
              let index = savedBooks.firstIndex(where: { $0.id == currentBook.id }) else {
            return
        }
        savedBooks[index] = currentBook
    }
}

enum SortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case title = "Title"
    case progress = "Progress"
}

struct BookLibraryView: View {
    @Binding var books: [Book]
    @Binding var currentBook: Book?
    @Binding var selectedTab: Int

    @State private var searchText = ""
    @State private var sortOption: SortOption = .dateAdded
    @State private var showingSortMenu = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var filteredAndSortedBooks: [Book] {
        let filtered = searchText.isEmpty ? books : books.filter { book in
            book.title.localizedCaseInsensitiveContains(searchText)
        }

        switch sortOption {
        case .dateAdded:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .progress:
            return filtered.sorted {
                let progress1 = Double($0.currentWordIndex) / Double($0.words.count)
                let progress2 = Double($1.currentWordIndex) / Double($1.words.count)
                return progress1 > progress2
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search books", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)

                // Sort options
                if !books.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button(action: {
                                    sortOption = option
                                }) {
                                    Text(option.rawValue)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(sortOption == option ? Color.blue : Color(.systemGray5))
                                        .foregroundColor(sortOption == option ? .white : .primary)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                }

                // Books grid
                ScrollView {
                    if books.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "books.vertical")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No books yet")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("Swipe right to add a book")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if filteredAndSortedBooks.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No books found")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("Try a different search")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredAndSortedBooks) { book in
                                BookCardView(book: book)
                                    .onTapGesture {
                                        currentBook = book
                                        selectedTab = 1
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct BookCardView: View {
    let book: Book

    var progressPercentage: Double {
        guard !book.words.isEmpty else { return 0 }
        return Double(book.currentWordIndex) / Double(book.words.count) * 100
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let thumbnailData = book.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 220)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 220)
                        .overlay(
                            Image(systemName: "doc.text")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                        )
                }

                // Progress indicator
                VStack(spacing: 4) {
                    if book.isDualLanguage {
                        HStack(spacing: 4) {
                            Image(systemName: "book.pages")
                                .font(.system(size: 10))
                            Text("Quran")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.0f%%", progressPercentage))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                }
                .padding(8)
            }

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 3)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * (progressPercentage / 100), height: 3)
                    }
                    .cornerRadius(1.5)
                }
                .frame(height: 3)
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onDocumentPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onDocumentPicked: (URL) -> Void

        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onDocumentPicked(url)
        }
    }
}

#Preview {
    ContentView()
}
