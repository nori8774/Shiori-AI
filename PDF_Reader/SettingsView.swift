import SwiftUI

struct SettingsView: View {
    // 入力欄のテキスト
    @State private var apiKeyInput: String = ""
    // 保存済みかどうかの状態
    @State private var isKeySaved: Bool = false

    // ページめくりアニメーション設定
    @ObservedObject var pageTurnSettings = PageTurnSettings.shared

    // Keychainで使用する識別子（アプリ内で統一）
    let serviceName = "com.myapp.gemini" // 任意の識別子に変えてOK
    let accountName = "gemini_api_key"

    var body: some View {
        NavigationView {
            Form {
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
                    
                    // キー入力欄（SecureFieldで文字を隠す）
                    SecureField("API Keyを入力", text: $apiKeyInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button(action: saveKey) {
                        Text("保存する")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
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
            }
            .navigationTitle("設定")
            .onAppear(perform: loadStatus) // 画面表示時に保存状態を確認
        }
    }
    
    // MARK: - Functions
    
    func saveKey() {
        guard !apiKeyInput.isEmpty else { return }
        
        // 文字列をData型に変換して保存
        if let data = apiKeyInput.data(using: .utf8) {
            KeychainHelper.standard.save(service: serviceName, account: accountName, data: data)
            apiKeyInput = "" // 入力欄をクリア
            loadStatus()     // 状態更新
            print("API Key Saved safely!")
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
}

// プレビュー用
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
