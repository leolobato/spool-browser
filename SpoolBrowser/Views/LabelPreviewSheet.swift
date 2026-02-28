import SwiftUI

struct LabelPreviewSheet: View {
    let spool: Spool
    let spoolmanURL: String
    var labelPrinterService: LabelPrinterService
    @Environment(\.dismiss) private var dismiss

    @State private var previewImage: UIImage?
    @State private var isPrinting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .border(Color.secondary.opacity(0.3), width: 1)
                        .padding(.horizontal)

                    if isPrinting {
                        VStack(spacing: 8) {
                            ProgressView(value: labelPrinterService.printProgress)
                                .padding(.horizontal)
                            Text("Printing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            printLabel()
                        } label: {
                            Label("Print", systemImage: "printer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                } else {
                    ProgressView("Rendering label...")
                        .frame(maxHeight: .infinity)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Label Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isPrinting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let image = previewImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("Spool Label", image: Image(uiImage: image))
                        )
                        .disabled(isPrinting)
                    }
                }
            }
            .task {
                let data = LabelRenderer.labelData(from: spool, spoolmanURL: spoolmanURL)
                previewImage = LabelRenderer.renderPreview(data: data)
            }
            .alert("Printed", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Label sent to printer.")
            }
            .alert("Print Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func printLabel() {
        guard let image = previewImage else { return }
        isPrinting = true

        Task {
            do {
                let (rasterData, widthBytes, rows) = LabelRenderer.rasterize(image: image)
                try await labelPrinterService.printLabel(
                    rasterData: rasterData,
                    widthBytes: widthBytes,
                    rows: rows
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isPrinting = false
        }
    }
}
