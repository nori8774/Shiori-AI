import SwiftUI

struct SettingsView: View {
    // 入力欄のテキスト
    @State private var apiKeyInput: String = ""
    // 保存済みかどうかの状態
    @State private var isKeySaved: Bool = false

    // ページめくりアニメーション設定
    @ObservedObject var pageTurnSettings = PageTurnSettings.shared

    // AI同意管理
    @ObservedObject var consentManager = AIConsentManager.shared
    @State private var showConsentSheet = false
    @State private var showRevokeConfirm = false

    // マーカー入力設定
    @ObservedObject var inputMethodSettings = InputMethodSettings.shared

    // 裏メニュー用
    @State private var devTapCount: Int = 0
    @State private var showDevMenu: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportFileURL: URL? = nil

    // Keychainで使用する識別子（アプリ内で統一）
    let serviceName = "com.myapp.gemini" // 任意の識別子に変えてOK
    let accountName = "gemini_api_key"

    var body: some View {
        NavigationView {
            Form {
                // MARK: - マーカー設定
                Section(header: Text("マーカー設定")) {
                    if InputMethodSettings.InputMethod.allCases.count > 1 {
                        Picker("入力方法", selection: $inputMethodSettings.inputMethod) {
                            ForEach(InputMethodSettings.InputMethod.allCases, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Text(inputMethodSettings.inputMethod.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                // MARK: - ページめくりアニメーション設定
                Section(header: Text("表示設定")) {
                    Toggle("ページめくりアニメーション", isOn: $pageTurnSettings.isPageTurnAnimationEnabled)

                    if pageTurnSettings.isPageTurnAnimationEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("アニメーション速度")
                                .font(.subheadline)

                            HStack {
                                Text("速い")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Slider(value: $pageTurnSettings.animationSpeed, in: 0.2...1.0, step: 0.1)

                                Text("遅い")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("現在: \(String(format: "%.1f", pageTurnSettings.animationSpeed))秒")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Gemini API設定
                Section(header: Text("Gemini API設定")) {
                    Text("Google AI Studioで取得したAPIキーを入力してください。キーは端末内のKeychainに安全に保存されます。")
                        .font(.caption)
                        .foregroundColor(.gray)

                    // キー入力欄
                    SecureField("API Keyを入力", text: $apiKeyInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section {
                    Button(action: saveKey) {
                        HStack {
                            Spacer()
                            Text("保存する")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(apiKeyInput.isEmpty)
                }
                
                Section {
                    if isKeySaved {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("APIキーは保存されています")
                        }

                        Button("キーを削除する") {
                            deleteKey()
                        }
                        .foregroundColor(.red)
                    } else {
                        Text("APIキーは未保存です")
                            .foregroundColor(.orange)
                    }
                }

                // MARK: - AI機能の同意状態
                Section(header: Text("AI機能のデータ送信")) {
                    if consentManager.hasConsent {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("同意済み")
                                    .font(.body)
                                if let date = consentManager.consentDate {
                                    Text("同意日: \(date, style: .date)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Button("同意内容を確認する") {
                            showConsentSheet = true
                        }

                        Button("同意を取り消す") {
                            showRevokeConfirm = true
                        }
                        .foregroundColor(.red)
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.orange)
                            Text("未同意（AI機能は使用できません）")
                        }

                        Button("同意してAI機能を有効にする") {
                            showConsentSheet = true
                        }
                        .foregroundColor(.blue)
                    }

                    Text("AI機能（翻訳・要約・しおり検索など）を使用すると、PDFのテキストデータがGoogle Gemini APIに送信されます。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                // MARK: - プライバシー
                Section(header: Text("プライバシー")) {
                    Link(destination: URL(string: "https://nori8774.github.io/Shiori-AI/privacy-policy")!) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("プライバシーポリシー")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - バージョン情報（5回タップで裏メニュー表示）
                Section {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("\(version) (\(build))")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        devTapCount += 1
                        if devTapCount >= 5 {
                            showDevMenu = true
                            devTapCount = 0
                        }
                    }
                }

                // MARK: - 開発者メニュー（裏メニュー）
                if showDevMenu {
                    Section(header: Text("開発者メニュー")) {
                        Button {
                            exportMarkersJSON()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("markers.json をエクスポート")
                            }
                        }

                        Button {
                            exportBookmarksJSON()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("bookmarks.json をエクスポート")
                            }
                        }

                        Button {
                            showDevMenu = false
                        } label: {
                            Text("開発者メニューを閉じる")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportFileURL {
                    ActivityView(activityItems: [url])
                }
            }
            .sheet(isPresented: $showConsentSheet) {
                AIConsentView(isPresented: $showConsentSheet)
            }
            .alert("同意を取り消しますか？", isPresented: $showRevokeConfirm) {
                Button("取り消す", role: .destructive) {
                    consentManager.revokeConsent()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("同意を取り消すと、AI機能（翻訳・要約・しおり検索など）が使用できなくなります。")
            }
            .navigationTitle("設定")
            .onAppear(perform: loadStatus) // 画面表示時に保存状態を確認
        }
    }
    
    // MARK: - Functions
    
    func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        print("saveKey called, input length: \(trimmed.count)")
        guard !trimmed.isEmpty else {
            print("saveKey: input is empty after trim")
            return
        }

        // 文字列をData型に変換して保存
        if let data = trimmed.data(using: .utf8) {
            KeychainHelper.standard.save(service: serviceName, account: accountName, data: data)
            apiKeyInput = "" // 入力欄をクリア
            loadStatus()     // 状態更新
            print("API Key Saved! isKeySaved=\(isKeySaved)")
        }
    }
    
    func loadStatus() {
        // キーが読み出せるか確認
        if let _ = KeychainHelper.standard.read(service: serviceName, account: accountName) {
            isKeySaved = true
        } else {
            isKeySaved = false
        }
    }
    
    func deleteKey() {
        KeychainHelper.standard.delete(service: serviceName, account: accountName)
        loadStatus()
        print("API Key Deleted!")
    }

    // MARK: - 開発者メニュー: エクスポート

    func exportMarkersJSON() {
        let src = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("markers.json")
        exportFile(at: src, fallbackName: "markers.json")
    }

    func exportBookmarksJSON() {
        let src = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bookmarks.json")
        exportFile(at: src, fallbackName: "bookmarks.json")
    }

    private func exportFile(at url: URL, fallbackName: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("\(fallbackName) not found")
            return
        }
        // tmpにコピーして共有（元ファイルを直接渡すとサンドボックスの問題が起きる場合がある）
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fallbackName)
        try? FileManager.default.removeItem(at: tmpURL)
        try? FileManager.default.copyItem(at: url, to: tmpURL)
        exportFileURL = tmpURL
        showExportSheet = true
    }
}

// MARK: - UIActivityViewController wrapper
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// プレビュー用
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
