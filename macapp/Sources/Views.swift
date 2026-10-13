import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var dropTargeted = false

    var body: some View {
        HSplitView {
            HistoryList()
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 320)
            DetailPane()
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(6)
            }
        }
        .overlay(alignment: .bottom) {
            if let t = m.toast {
                Text(t)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: m.toast)
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let data = ImagePrep.readImageFile(url)
                DispatchQueue.main.async {
                    if let data { m.recognize(imageData: data) } else { m.showToast(L("Cannot read the image, or it is larger than 50 MB")) }
                }
            }
            return true
        }
        p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            DispatchQueue.main.async { m.recognize(imageData: data) }
        }
        return true
    }
}

// MARK: - 历史记录

struct HistoryList: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(m.serverState == .ready ? Color.green : m.serverState == .failed ? Color.red : Color.orange)
                    .frame(width: 8, height: 8)
                Text(m.serverState == .ready ? L("Model ready") : m.serverState == .failed ? L("Model failed to start") : L("Loading model…"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L("%@ items", String(m.history.count))).font(.caption).foregroundStyle(.secondary)
                Menu {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Button {
                            m.setLanguage(lang)
                        } label: {
                            if m.language == lang { Label(lang.title, systemImage: "checkmark") } else { Text(lang.title) }
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Language"))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            List(selection: $m.selectedID) {
                ForEach(m.history) { r in
                    HistoryRow(result: r).tag(r.id)
                        .contextMenu {
                            Button(L("Copy LaTeX")) { m.copy(r.latex) }
                            Button(L("Copy Markdown")) { m.copy(r.markdown) }
                            Divider()
                            Button(L("Delete")) { m.delete(r.id) }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct HistoryRow: View {
    @EnvironmentObject var m: AppModel
    let result: OCRResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let img = m.store.image(result.id) {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 44, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text("\(result.kindTitle) · \(String(result.time.dropFirst(5)))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 详情

struct DetailPane: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        Group {
            if m.busy {
                VStack(spacing: 16) {
                    if let img = m.pendingImage {
                        Image(nsImage: img).resizable().scaledToFit()
                            .frame(maxHeight: 180).background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    ProgressView(L("Recognizing…"))
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let r = m.selected {
                ResultDetail(result: r).id(r.id)
            } else {
                VStack(spacing: 10) {
                    Text("∑").font(.system(size: 54, weight: .light)).foregroundStyle(.tertiary)
                    Text(L("Press ⌃⌘M to snip and recognize")).font(.title3)
                    Text(L("Or drag an image here, or paste one with ⌘V")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

enum SourceFormat: CaseIterable {
    case latex, markdown, raw

    var title: String {
        switch self {
        case .latex: return "LaTeX"
        case .markdown: return "Markdown"
        case .raw: return L("Raw model output")
        }
    }
}

struct ResultDetail: View {
    @EnvironmentObject var m: AppModel
    let result: OCRResult
    @State private var format: SourceFormat

    init(result: OCRResult) {
        self.result = result
        _format = State(initialValue: result.kind == "formula" ? .latex : .markdown)
    }

    private var text: Binding<String> {
        Binding(
            get: {
                switch format {
                case .latex: return result.latex
                case .markdown: return result.markdown
                case .raw: return result.raw
                }
            },
            set: { v in
                switch format {
                case .latex: m.update(result.id, latex: v)
                case .markdown: m.update(result.id, markdown: v)
                case .raw: break
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(result.kindTitle) · \(String(format: "%.2f", result.seconds))s · \(result.time)")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu(L("Re-recognize")) {
                    ForEach(RecognizeMode.allCases, id: \.self) { mode in
                        Button(mode.title) { m.rerun(result, mode: mode) }
                    }
                }
                .fixedSize()
                Button(L("Delete")) { m.delete(result.id) }
            }

            Section(L("Original")) {
                if let img = m.store.image(result.id) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 130)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Section(L("Preview")) {
                MathPreview(kind: result.kind, text: result.kind == "formula" ? result.latex : result.markdown)
                    .frame(maxWidth: .infinity, minHeight: 120, idealHeight: 170, maxHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            }

            HStack {
                Picker("", selection: $format) {
                    ForEach(SourceFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 340)
                Spacer()
                Button {
                    m.copy(text.wrappedValue, label: L("Copied %@", format.title))
                } label: {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            TextEditor(text: text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                .frame(minHeight: 110)
        }
        .padding(16)
    }

    private func Section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - 公式渲染（应用内嵌 WebKit + 本地 KaTeX）

struct MathPreview: NSViewRepresentable {
    let kind: String
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: "preview", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.web = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.render(kind: kind, text: text)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var web: WKWebView?
        private var loaded = false
        private var pending: (String, String)?

        func render(kind: String, text: String) {
            pending = (kind, text)
            flush()
        }

        private func flush() {
            guard loaded, let web, let (kind, text) = pending else { return }
            let args = (try? JSONSerialization.data(withJSONObject: [kind, text]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"text\", \"\"]"
            web.evaluateJavaScript("render(...\(args))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush()
        }

        /// 只允许加载应用自带的 preview.html；识别结果中的内容不能让页面跳转到其他地址
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let preview = Bundle.main.url(forResource: "preview", withExtension: "html")
            let allowed = action.request.url?.isFileURL == true
                && action.request.url?.standardizedFileURL == preview?.standardizedFileURL
            decisionHandler(allowed ? .allow : .cancel)
        }
    }
}
