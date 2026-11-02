import AppKit
import SwiftUI

struct ModelControls: View {
    @EnvironmentObject var m: AppModel
    @State private var showingModels = false

    var body: some View {
        VStack(spacing: 6) {
            Picker(L("Recognition Model"), selection: Binding(get: { m.selectedModelID }, set: { m.selectModel($0) })) {
                ForEach(m.modelProfiles) { profile in Text(profile.name).tag(profile.id) }
            }
            .labelsHidden().disabled(!m.canManageModels)
            HStack {
                Button(m.serverState == .starting ? L("Cancel Loading") : L("Unload Model")) { m.unloadServer() }
                    .disabled(m.busy || m.serverState == .stopping || m.serverState == .unloaded)
                Button(L("Load Model")) { m.startServer() }
                    .disabled(m.busy || m.serviceTransitioning || m.serverState == .ready)
            }.font(.caption)
            if let error = m.serviceError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(4).help(error).textSelection(.enabled)
            }
            Button(L("Manage Models…")) { showingModels = true }
                .font(.caption).disabled(!m.canManageModels)
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
        .sheet(isPresented: $showingModels) { ModelManager().environmentObject(m) }
    }
}

struct ModelManager: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var style: ModelPromptStyle = .paddleOCR
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Recognition Models")).font(.headline)
            Text(L("Register a complete local MLX-VLM model folder. No downloads. Compatibility is checked when loading; custom Python code is never enabled."))
                .font(.callout).foregroundStyle(.secondary)
            List(m.modelProfiles) { profile in
                HStack {
                    VStack(alignment: .leading) {
                        Text(profile.name)
                        Text(profile.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(profile.style.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if profile.id != ModelCatalog.builtinID {
                        Button(L("Remove from List")) { m.removeModel(profile.id) }.disabled(!m.canManageModels)
                    }
                }
            }.frame(height: 180)
            Picker(L("Model Prompts"), selection: $style) {
                ForEach(ModelPromptStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text(L("Removing a model from this list keeps all model files. Selecting another model unloads the previous one; click Load Model to use it."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button(L("Add Local Model…")) { chooseFolder() }.disabled(!m.canManageModels)
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 560)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Add Local Model…")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try m.addModel(url, style: style); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
