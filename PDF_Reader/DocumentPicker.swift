import SwiftUI
import UIKit
import UniformTypeIdentifiers

// UIViewControllerRepresentableを使って、UIKitのドキュメントピッカーをSwiftUIで使えるようにします
struct DocumentPicker: UIViewControllerRepresentable {
    // ファイルが選ばれたらこのURLに値を入れます
    @Binding var selectedFileURL: URL?
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // PDFファイルのみを選択可能にする
        let types: [UTType] = [.pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true) // asCopy: trueにするとアプリ内に一時コピーを作ります（安全のため推奨）
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false // 1つだけ選ぶ
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // イベントを受け取るコーディネーター
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // 選択された最初のファイルを親に渡す
            if let url = urls.first {
                parent.selectedFileURL = url
            }
        }
    }
}
