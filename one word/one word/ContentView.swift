import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct Book: Identifiable, Codable {
    let id: UUID
    var title: String
    var words: [String]
    var currentWordIndex: Int
    var wordsPerMinute: Double
    var thumbnailData: Data?
    var dateAdded: Date

    init(id: UUID = UUID(), title: String, words: [String], currentWordIndex: Int = 0, wordsPerMinute: Double = 250, thumbnailData: Data? = nil) {
        self.id = id
        self.title = title
        self.words = words
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
                    Text(currentBook.words[currentBook.currentWordIndex])
                        .font(.system(size: 64, weight: .light, design: .monospaced))
                        .tracking(1)
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                        .padding(.horizontal, 40)
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

        let extractedWords = extractedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

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

struct BookLibraryView: View {
    @Binding var books: [Book]
    @Binding var currentBook: Book?
    @Binding var selectedTab: Int

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
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
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(books) { book in
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
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct BookCardView: View {
    let book: Book

    var body: some View {
        VStack(spacing: 12) {
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

            Text(book.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
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
