import SwiftUI
import PDFKit

class PDFManager {
    static let shared = PDFManager()
    weak var currentPDFView: PDFView?
}

struct ContentView: View {
    // --- 状態変数 ---
    @State private var isPickerPresented = false
    @State private var selectedFileURL: URL?
    
    // マネージャー
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    @ObservedObject var bookshelfManager = BookshelfManager.shared
    
    // 現在開いている本の設定
    @State private var currentBookIsRightToLeft = false
    @State private var isTwoUp = false
    
    // 初回設定用ダイアログ
    @State private var showDirectionDialog = false
    @State private var selectedBookToOpen: Book?
    
    // AI & アラート
    @State private var isAnalyzing = false
    @State private var analysisResult: AIResponse?
    @State private var showResultModal = false
    @State private var errorMessage: String?
    
    @State private var showHistory = false
    @State private var showQuestionInput = false
    @State private var questionText = ""

    @State private var currentPageIndex = 0

    // 検索機能
    @State private var showSearch = false
    @State private var pendingSearchResult: SearchResultItem?

    // セマンティック検索（しおり検索）- フローティングウィンドウ
    @ObservedObject var floatingSearchState = FloatingSearchState.shared

    // マーカー機能
    @State private var showMarkerToolbar = false
    @ObservedObject var markerManager = SmartMarkerManager.shared
    @State private var currentOpenBook: Book?

    // ページめくりアニメーション
    @State private var isPageTurnAnimating = false
    @State private var pageTurnDirection: PageTurnDirection = .left
    @State private var currentPageImage: UIImage?
    @State private var nextPageImage: UIImage?

    // 本棚ピッカー用
    @State private var showBookshelfPicker = false
    @State private var bookToMoveToShelf: Book?

    // インポート後の本棚選択用
    @State private var showImportBookshelfPicker = false
    @State private var newlyImportedBook: Book?

    // 本棚管理画面
    @State private var showBookshelfManager = false

    // 論文要約機能
    @State private var showPaperSummaryConfirm = false
    @State private var isSummarizing = false
    @State private var summaryProgress: Float = 0
    @State private var summaryProgressText = ""
    @State private var summaryCompleteBook: Book?
    @State private var showSummaryComplete = false

    // 音声読み上げ
    @ObservedObject var ttsManager = TextToSpeechManager.shared

    let columns = [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 20)]

    // 選択中の本棚でフィルタされた本の一覧
    var filteredBooks: [Book] {
        libraryManager.getBooks(for: bookshelfManager.selectedShelfId)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    if let url = selectedFileURL {
                        // === A. PDF表示モード ===
                        ZStack(alignment: .topTrailing) {
                            PDFKitView(
                                url: url,
                                isRightToLeft: currentBookIsRightToLeft,
                                isTwoUp: isTwoUp,
                                currentPageIndex: $currentPageIndex,
                                isPageTurnAnimating: $isPageTurnAnimating,
                                pageTurnDirection: $pageTurnDirection,
                                currentPageImage: $currentPageImage,
                                nextPageImage: $nextPageImage
                            )
                            .edgesIgnoringSafeArea(.all)
                            .id("\(url.absoluteString)-\(currentBookIsRightToLeft)-\(isTwoUp)")
                            .pageTurnAnimation(
                                isAnimating: $isPageTurnAnimating,
                                currentImage: currentPageImage,
                                nextImage: nextPageImage,
                                direction: pageTurnDirection
                            )

                            // マーカーオーバーレイ（Apple Pencil対応）
                            // マーカーモードON時のみオーバーレイを表示（タッチイベントのブロックを防ぐ）
                            if let pdfView = PDFManager.shared.currentPDFView,
                               markerManager.isMarkerMode {
                                MarkerOverlayView(
                                    pdfView: pdfView,
                                    currentBook: currentOpenBook,
                                    currentPageIndex: currentPageIndex,
                                    isRightToLeft: currentBookIsRightToLeft
                                )
                                .edgesIgnoringSafeArea(.all)
                            }

                            // しおりリボン（マーカー色に連動）
                            if bookmarkManager.isBookmarked(pdfFileName: url.lastPathComponent, pageIndex: currentPageIndex) {
                                let markerColor = SmartMarkerManager.shared.getMarkerColor(for: url.lastPathComponent, pageIndex: currentPageIndex)
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(markerColor?.swiftUIColor ?? .white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                    .padding(.top, -5)
                                    .padding(.trailing, 20)
                                    .transition(.move(edge: .top))
                                    .animation(.spring(), value: currentPageIndex)
                            }

                            // フローティング検索ウィンドウ
                            FloatingSearchWindow { pdfFileName, pageIndex in
                                handleSemanticSearchResult(pdfFileName: pdfFileName, pageIndex: pageIndex)
                            }
                        }
                    } else {
                        // === B. 本棚モード ===
                        VStack(spacing: 0) {
                            // 本棚タブ
                            BookshelfTabView()

                            Divider()

                            // 本の一覧
                            ScrollView {
                                if filteredBooks.isEmpty {
                                    if libraryManager.books.isEmpty {
                                        EmptyLibraryView(isPickerPresented: $isPickerPresented)
                                    } else {
                                        // 本棚は空だがライブラリには本がある
                                        EmptyShelfView(shelfName: bookshelfManager.selectedShelf?.name ?? "この本棚")
                                    }
                                } else {
                                    LazyVGrid(columns: columns, spacing: 30) {
                                        ForEach(filteredBooks) { book in
                                        Button(action: {
                                            checkDirectionAndOpen(book)
                                        }) {
                                            VStack {
                                                if let thumb = libraryManager.getThumbnail(for: book) {
                                                    Image(uiImage: thumb)
                                                        .resizable().scaledToFit().frame(height: 140)
                                                        .cornerRadius(8).shadow(radius: 4)
                                                } else {
                                                    ZStack {
                                                        Color.gray.opacity(0.3)
                                                        Image(systemName: "doc.text").font(.largeTitle)
                                                    }
                                                    .frame(height: 140).cornerRadius(8)
                                                }
                                                // 現在の設定を表示
                                                HStack {
                                                    Text(book.fileName)
                                                        .font(.caption).foregroundColor(.primary)
                                                        .lineLimit(1)
                                                    if let isRTL = book.isRightToLeft {
                                                        Image(systemName: isRTL ? "arrow.right.to.line" : "arrow.left.to.line")
                                                            .font(.caption2)
                                                            .foregroundColor(.gray)
                                                    }
                                                }
                                            }
                                        }
                                            // 長押しで設定変更
                                            .contextMenu {
                                                // 本棚を変更
                                                Button {
                                                    bookToMoveToShelf = book
                                                    showBookshelfPicker = true
                                                } label: {
                                                    Label("本棚を変更", systemImage: "folder")
                                                }

                                                Divider()

                                                Section(header: Text("開き方向の設定")) {
                                                    Button {
                                                        LibraryManager.shared.updateBookDirection(book: book, isRightToLeft: true)
                                                    } label: {
                                                        Label("右開きに変更 (縦書き)", systemImage: "arrow.right.to.line")
                                                    }
                                                    Button {
                                                        LibraryManager.shared.updateBookDirection(book: book, isRightToLeft: false)
                                                    } label: {
                                                        Label("左開きに変更 (横書き)", systemImage: "arrow.left.to.line")
                                                    }
                                                }

                                                Divider()

                                                Button(role: .destructive) {
                                                    if let index = libraryManager.books.firstIndex(where: { $0.id == book.id }) {
                                                        libraryManager.deleteBook(at: IndexSet(integer: index))
                                                    }
                                                } label: { Label("削除", systemImage: "trash") }
                                            }
                                        }
                                    }
                                    .padding()
                                }
                            }
                        }
                    }
                }
                
                // === ローディング ===
                if isAnalyzing {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack {
                        ProgressView().scaleEffect(2).padding()
                        Text("AIが思考中...").foregroundColor(.white).font(.headline)
                    }
                    .padding(40).background(Color.gray.opacity(0.8)).cornerRadius(20)
                }

                // === 論文要約中のローディング ===
                if isSummarizing {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 16) {
                        ProgressView(value: summaryProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text(summaryProgressText)
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("\(Int(summaryProgress * 100))%")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.caption)
                    }
                    .padding(40).background(Color.gray.opacity(0.8)).cornerRadius(20)
                }
            }
            .navigationBarTitle(selectedFileURL == nil ? "ライブラリ" : "", displayMode: .inline)
            .navigationBarItems(
                leading: HStack {
                    if selectedFileURL == nil {
                        NavigationLink(destination: SettingsView()) { Image(systemName: "gear") }
                    } else {
                        Button(action: { selectedFileURL = nil }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("ライブラリ")
                            }
                        }
                    }
                },
                trailing: HStack(spacing: 16) {
                    if let url = selectedFileURL {
                        // === 読書中のメニュー ===

                        // 検索（タップ: しおりセマンティック検索、長押し: PDF内検索）
                        Button(action: {
                            floatingSearchState.toggle()
                        }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(floatingSearchState.isVisible ? .blue : .primary)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    showSearch = true
                                }
                        )

                        // マーカーツール
                        // タップ: ON/OFF切替、長押し: 設定ポップオーバー
                        Button(action: { markerManager.isMarkerMode.toggle() }) {
                            Image(systemName: markerManager.isMarkerMode ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                                .foregroundColor(markerManager.isMarkerMode ? markerManager.selectedColor.swiftUIColor : .orange)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    showMarkerToolbar = true
                                }
                        )
                        
                        // しおり
                        Button(action: toggleBookmark) {
                            let isBookmarked = bookmarkManager.isBookmarked(pdfFileName: url.lastPathComponent, pageIndex: currentPageIndex)
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .foregroundColor(isBookmarked ? .red : .blue)
                        }
                        
                        // 音声読み上げコントロール（読み上げ中のみ表示）
                        if ttsManager.isSpeaking {
                            HStack(spacing: 8) {
                                Button(action: { ttsManager.togglePause() }) {
                                    Image(systemName: ttsManager.isPaused ? "play.fill" : "pause.fill")
                                        .foregroundColor(.blue)
                                }
                                Button(action: { ttsManager.stop() }) {
                                    Image(systemName: "stop.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // AI
                        Menu {
                            Button(action: { readCurrentPageAloud() }) {
                                Label("音声読み上げ", systemImage: "speaker.wave.2")
                            }
                            .disabled(ttsManager.isSpeaking)

                            Button(action: { analyzeCurrentPage(instruction: "このページの内容を自然な日本語に翻訳してください") }) { Label("日本語に翻訳", systemImage: "character.book.closed.ja") }
                            Button(action: { questionText = ""; showQuestionInput = true }) { Label("このページに質問...", systemImage: "bubble.left.and.bubble.right") }

                            Divider()

                            Button(action: { showPaperSummaryConfirm = true }) {
                                Label("論文を要約（全体）", systemImage: "doc.text.magnifyingglass")
                            }
                        } label: {
                            HStack(spacing: 4) { Image(systemName: "sparkles"); Text("AI解析") }
                                .padding(6).background(Color.purple.opacity(0.1)).cornerRadius(8)
                        }
                        .disabled(isAnalyzing || isSummarizing)
                        
                        // 表示設定（開き方向設定は削除しました）
                        Menu {
                            Button(action: { isTwoUp.toggle() }) {
                                Label(isTwoUp ? "見開き表示" : "単ページ表示", systemImage: isTwoUp ? "book.fill" : "doc.fill")
                            }
                        } label: { Image(systemName: "eye") }
                        
                    } else {
                        // === 本棚 ===
                        Button(action: { showSearch = true }) { Image(systemName: "magnifyingglass") }
                        Button(action: { showHistory = true }) { Image(systemName: "note.text") }
                        Button(action: { isPickerPresented = true }) { Image(systemName: "plus.circle.fill").font(.title2) }
                    }
                }
            )
            // === ダイアログ・シート ===
            .confirmationDialog("本の開き方は？", isPresented: $showDirectionDialog, titleVisibility: .visible) {
                Button("右開き (縦書き)") {
                    if let book = selectedBookToOpen {
                        LibraryManager.shared.updateBookDirection(book: book, isRightToLeft: true)
                        openBook(book, direction: true)
                    }
                }
                Button("左開き (横書き)") {
                    if let book = selectedBookToOpen {
                        LibraryManager.shared.updateBookDirection(book: book, isRightToLeft: false)
                        openBook(book, direction: false)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(isPresented: $isPickerPresented) {
                DocumentPicker(selectedFileURL: Binding(
                    get: { nil },
                    set: { url in
                        if let url = url {
                            libraryManager.importPDF(from: url)
                            // インポート後に本棚選択ダイアログを表示
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if let book = libraryManager.books.first {
                                    newlyImportedBook = book
                                    showImportBookshelfPicker = true
                                }
                            }
                        }
                    }
                ))
            }
            .sheet(isPresented: $showResultModal) {
                if let result = analysisResult { ResultView(result: result) }
            }
            .sheet(isPresented: $showHistory) {
                NavigationView { HistoryView().navigationBarItems(trailing: Button("閉じる") { showHistory = false }) }
            }
            .sheet(isPresented: $showSearch) {
                SearchView { result in
                    handleSearchResult(result)
                }
            }
            // セマンティック検索はフローティングウィンドウに移行
            .popover(isPresented: $showMarkerToolbar, arrowEdge: .top) {
                MarkerToolbarView(
                    isPresented: $showMarkerToolbar,
                    pdfFileName: selectedFileURL?.lastPathComponent,
                    pageIndex: currentPageIndex,
                    pdfView: PDFManager.shared.currentPDFView
                )
            }
            .sheet(isPresented: $showBookshelfPicker) {
                if let book = bookToMoveToShelf {
                    BookshelfPickerView(book: book)
                        .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $showImportBookshelfPicker) {
                if let book = newlyImportedBook {
                    ImportBookshelfPickerView(book: book, isPresented: $showImportBookshelfPicker)
                        .presentationDetents([.medium])
                }
            }
            .sheet(isPresented: $showBookshelfManager) {
                BookshelfManagerView()
            }
            .alert("AIに質問", isPresented: $showQuestionInput) {
                TextField("ここに入力...", text: $questionText)
                Button("送信") { if !questionText.isEmpty { analyzeCurrentPage(instruction: questionText) } }
                Button("キャンセル", role: .cancel) { }
            } message: { Text("このページについて知りたいことは？") }
            .alert(item: Binding<AlertItem?>(get: { errorMessage.map { AlertItem(message: $0) } }, set: { _ in errorMessage = nil })) { item in
                Alert(title: Text("エラー"), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
            // 論文要約確認アラート
            .alert("論文を要約", isPresented: $showPaperSummaryConfirm) {
                Button("要約する") {
                    summarizePaper()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この論文全体を解析し、要約ページ付きPDFを生成します。\n\n• 50ページ以下の論文に対応\n• 処理には数分かかる場合があります\n• 要約PDFは「要約」本棚に保存されます")
            }
            // 論文要約完了アラート
            .alert("要約完了", isPresented: $showSummaryComplete) {
                Button("要約を見る") {
                    // 要約本棚を選択してPDFを開く
                    if let book = summaryCompleteBook {
                        bookshelfManager.selectShelf(bookshelfManager.getSummaryShelf())
                        selectedFileURL = nil  // 一旦ライブラリに戻る
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            checkDirectionAndOpen(book)
                        }
                    }
                }
                Button("後で見る", role: .cancel) {
                    summaryCompleteBook = nil
                }
            } message: {
                Text("論文の要約が完了しました。\n要約ページ付きPDFが「要約」本棚に保存されました。")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Functions
    
    func checkDirectionAndOpen(_ book: Book) {
        if let direction = book.isRightToLeft {
            openBook(book, direction: direction)
        } else {
            selectedBookToOpen = book
            showDirectionDialog = true
        }
    }
    
    func openBook(_ book: Book, direction: Bool) {
        let url = libraryManager.getBookURL(book)
        self.currentBookIsRightToLeft = direction
        self.selectedFileURL = url
        self.currentOpenBook = book
    }
    
    func toggleBookmark() {
        let fileName = selectedFileURL?.lastPathComponent ?? "unknown"
        if bookmarkManager.isBookmarked(pdfFileName: fileName, pageIndex: currentPageIndex) {
            bookmarkManager.removeBookmark(pdfFileName: fileName, pageIndex: currentPageIndex)
        } else {
            // しおり追加時にPDFDocumentとbookIdを渡してインデックス作成
            bookmarkManager.addBookmark(
                pdfFileName: fileName,
                pageIndex: currentPageIndex,
                bookId: currentOpenBook?.id,
                pdfDocument: PDFManager.shared.currentPDFView?.document
            )
        }
    }
    
    func analyzeCurrentPage(instruction: String) {
        guard let pdfView = PDFManager.shared.currentPDFView else { errorMessage = "PDFが開かれていません"; return }

        // 見開き表示の場合は両ページをキャプチャ
        let image: UIImage?
        if isTwoUp {
            image = pdfView.takeSpreadSnapshot(isRightToLeft: currentBookIsRightToLeft)
        } else {
            image = pdfView.takeSnapshot()
        }

        guard let capturedImage = image else { errorMessage = "ページの画像取得に失敗しました"; return }
        let pdfName = selectedFileURL?.lastPathComponent ?? "不明なファイル"
        let pageIndex = currentPageIndex
        isAnalyzing = true

        Task {
            do {
                let result = try await GeminiService.shared.analyzePage(image: capturedImage, instruction: instruction)
                DispatchQueue.main.async {
                    let summaryToSave = instruction.contains("要点") ? result.summary : "【指示】\(instruction)\n\n\(result.summary)"
                    HistoryManager.shared.addLog(pdfName: pdfName, pageIndex: pageIndex, summary: summaryToSave, rawText: result.rawText)
                    self.analysisResult = result
                    self.isAnalyzing = false
                    self.showResultModal = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.errorMessage = "AI処理失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Search Result Handling

    func handleSemanticSearchResult(pdfFileName: String, pageIndex: Int) {
        // pdfFileNameから該当する本を検索
        guard let book = libraryManager.books.first(where: { $0.fileName == pdfFileName }) else {
            errorMessage = "書籍が見つかりません: \(pdfFileName)"
            return
        }
        openBookAndNavigate(book: book, pageIndex: pageIndex)
    }

    func handleSearchResult(_ result: SearchResultItem) {
        // Find the book matching the search result
        guard let book = libraryManager.books.first(where: { $0.id == result.bookId }) else {
            // Try to find by filename as fallback
            guard let book = libraryManager.books.first(where: { $0.fileName == result.pdfFileName }) else {
                errorMessage = "書籍が見つかりません"
                return
            }
            openBookAndNavigate(book: book, pageIndex: result.pageIndex)
            return
        }
        openBookAndNavigate(book: book, pageIndex: result.pageIndex)
    }

    func openBookAndNavigate(book: Book, pageIndex: Int) {
        // If direction is not set, use default (left-to-right)
        let direction = book.isRightToLeft ?? false

        // Store the pending navigation
        pendingSearchResult = SearchResultItem(
            bookId: book.id,
            pdfFileName: book.fileName,
            pageIndex: pageIndex,
            matchedText: "",
            score: 0
        )

        // Open the book
        let url = libraryManager.getBookURL(book)
        self.currentBookIsRightToLeft = direction
        self.selectedFileURL = url

        // Navigate to the page after a short delay (wait for PDF to load)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let pdfView = PDFManager.shared.currentPDFView,
               let document = pdfView.document,
               let page = document.page(at: pageIndex) {
                pdfView.go(to: page)
                self.currentPageIndex = pageIndex
            }
            self.pendingSearchResult = nil
        }
    }

    // MARK: - Text-to-Speech

    func readCurrentPageAloud() {
        guard let pdfView = PDFManager.shared.currentPDFView else {
            errorMessage = "PDFが開かれていません"
            return
        }

        // 見開き表示の場合は両ページをキャプチャ
        let image: UIImage?
        if isTwoUp {
            image = pdfView.takeSpreadSnapshot(isRightToLeft: currentBookIsRightToLeft)
        } else {
            image = pdfView.takeSnapshot()
        }

        guard let capturedImage = image else {
            errorMessage = "ページの画像取得に失敗しました"
            return
        }

        isAnalyzing = true

        Task {
            do {
                // OCRでテキストを抽出（音声読み上げ用なので整形を依頼）
                let result = try await GeminiService.shared.analyzePage(
                    image: capturedImage,
                    instruction: "このページのテキストを読み上げ用に整形して出力してください。図表の説明は簡潔に、本文は自然な読み上げ順序で出力してください。余計な説明は不要です。"
                )

                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    // 抽出したテキストを音声で読み上げ
                    TextToSpeechManager.shared.speak(text: result.rawText)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.errorMessage = "テキスト抽出に失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Paper Summary

    func summarizePaper() {
        guard let book = currentOpenBook else {
            errorMessage = "本が選択されていません"
            return
        }

        isSummarizing = true
        summaryProgress = 0
        summaryProgressText = "準備中..."

        Task {
            do {
                let newBook = try await PaperSummaryService.shared.summarizePaper(book: book) { text, progress in
                    DispatchQueue.main.async {
                        self.summaryProgressText = text
                        self.summaryProgress = progress
                    }
                }

                DispatchQueue.main.async {
                    self.isSummarizing = false
                    self.summaryCompleteBook = newBook
                    self.showSummaryComplete = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSummarizing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// 既存の補助コンポーネント (ResultView, ShareSheet, AlertItem, EmptyLibraryView) はそのまま残してください
// 1. ライブラリが空の時の表示
struct EmptyLibraryView: View {
    @Binding var isPickerPresented: Bool

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))
            Text("ライブラリは空です")
                .font(.title2)
                .foregroundColor(.gray)

            Button(action: { isPickerPresented = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("PDFを追加する")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            Spacer()
        }
        .frame(minHeight: 400)
    }
}

// 1.5 本棚は空だが本はある時の表示
struct EmptyShelfView: View {
    let shelfName: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("「\(shelfName)」には本がありません")
                .font(.headline)
                .foregroundColor(.gray)
            Text("本を長押しして本棚に追加できます")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(minHeight: 300)
    }
}

// 2. エラー表示用
struct AlertItem: Identifiable {
    var id = UUID()
    var message: String
}

// 3. iOS標準のシェアシート
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// 4. 解析結果表示画面
struct ResultView: View {
    let result: AIResponse
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // AI回答エリア
                    VStack(alignment: .leading, spacing: 10) {
                        Text("💡 AI回答")
                            .font(.headline)
                            .foregroundColor(.purple)
                        
                        Text(result.summary)
                            .font(.body)
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(10)
                            .textSelection(.enabled)
                    }
                    Divider()
                    // 原文エリア
                    VStack(alignment: .leading, spacing: 10) {
                        Text("📄 読み取ったテキスト")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text(result.rawText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("解析結果")
            .navigationBarItems(
                leading: Button(action: {
                    showShareSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("共有")
                    }
                },
                trailing: Button("閉じる") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .sheet(isPresented: $showShareSheet) {
                let textToShare = """
                【AI回答】
                \(result.summary)
                
                ---
                【原文】
                \(result.rawText)
                """
                ShareSheet(items: [textToShare])
            }
        }
    }
}
