import SwiftUI

/// Dummy film picker: choose the stock, set the roll length, start a new roll.
struct FilmPickerSheet: View {
    let selectedID: String
    @Binding var rollLength: Int
    let onPick: (FilmStock) -> Void
    let onNewRoll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Roll") {
                    Picker("Length", selection: $rollLength) {
                        Text("12").tag(12)
                        Text("24").tag(24)
                        Text("36").tag(36)
                    }
                    .pickerStyle(.segmented)
                    Button("Start new roll") {
                        onNewRoll()
                        dismiss()
                    }
                }
                Section("Film") {
                    ForEach(FilmStock.all) { film in
                        Button {
                            onPick(film)
                            dismiss()
                        } label: {
                            HStack {
                                Text(film.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("ISO \(film.iso)")
                                    .foregroundStyle(.secondary)
                                if film.id == selectedID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
