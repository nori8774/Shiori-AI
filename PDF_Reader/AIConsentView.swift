import SwiftUI

/// AI機能使用時のデータ送信同意ダイアログ
/// App Store審査ガイドライン 5.1.1/5.1.2 対応
struct AIConsentView: View {
    @Binding var isPresented: Bool
    @ObservedObject var consentManager = AIConsentManager.shared

    /// 同意後に実行するアクション
    var onConsent: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ヘッダー
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)

                        Text("AI機能のデータ送信について")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top)

                    Divider()

                    // 送信先の明示
                    VStack(alignment: .leading, spacing: 8) {
                        Label("送信先", systemImage: "server.rack")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Google Gemini API")
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)

                        Link(destination: URL(string: "https://policies.google.com/privacy")!) {
                            HStack {
                                Image(systemName: "link")
                                Text("Googleのプライバシーポリシー")
                            }
                            .font(.caption)
                        }
                    }

                    Divider()

                    // 送信データの説明
                    VStack(alignment: .leading, spacing: 12) {
                        Label("送信されるデータ", systemImage: "doc.text")
                            .font(.headline)
                            .foregroundColor(.primary)

                        // PDFページ画像
                        DataItemView(
                            icon: "doc.richtext",
                            title: "PDFページの画像",
                            description: "翻訳・要約・音声読み上げ時に送信され、OCR（文字認識）処理に使用されます。",
                            features: ["翻訳", "要約", "音声読み上げ", "論文要約"]
                        )

                        // テキストデータ
                        DataItemView(
                            icon: "text.alignleft",
                            title: "テキストデータ",
                            description: "しおり検索のインデックス作成時に送信され、意味検索用のベクトル化に使用されます。",
                            features: ["しおり検索"]
                        )
                    }

                    Divider()

                    // 注意事項
                    VStack(alignment: .leading, spacing: 8) {
                        Label("ご注意", systemImage: "info.circle")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Text("• これらのデータはAI処理のためにのみ使用されます")
                        Text("• アプリ開発者がデータにアクセスすることはありません")
                        Text("• 同意はいつでも設定画面から取り消せます")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Divider()

                    // プライバシーポリシーリンク
                    Link(destination: URL(string: "https://nori8774.github.io/Shiori-AI/privacy-policy")!) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("プライバシーポリシーを確認")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.subheadline)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }

                    Spacer(minLength: 20)

                    // 同意ボタン
                    VStack(spacing: 12) {
                        Button(action: {
                            consentManager.grantConsent()
                            isPresented = false
                            onConsent?()
                        }) {
                            Text("同意してAI機能を使用する")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }

                        Button(action: {
                            isPresented = false
                        }) {
                            Text("同意しない")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text("同意しない場合、AI機能は使用できません")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("同意する") {
                        consentManager.grantConsent()
                        isPresented = false
                        onConsent?()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Data Item View

struct DataItemView: View {
    let icon: String
    let title: String
    let description: String
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            // 対象機能タグ
            FlowLayout(spacing: 6) {
                ForEach(features, id: \.self) { feature in
                    Text(feature)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Flow Layout (タグを折り返し表示)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > width, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            height = y + rowHeight
        }
    }
}

// MARK: - Preview

#Preview {
    AIConsentView(isPresented: .constant(true))
}
