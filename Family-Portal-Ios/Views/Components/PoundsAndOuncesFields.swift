import SwiftUI

/// A weight entered as pounds and ounces, in place of the single value field.
struct PoundsAndOuncesFields: View {
    @Binding var pounds: String
    @Binding var ounces: String
    var isPoundsFocused: FocusState<Bool>.Binding
    var isOuncesFocused: FocusState<Bool>.Binding? = nil
    @FocusState private var localOuncesFocused: Bool

    var body: some View {
        HStack {
            TextField("Pounds", text: $pounds)
                .keyboardType(.numberPad)
                .focused(isPoundsFocused)
            Text("lb")
                .foregroundStyle(.secondary)
            TextField("Ounces", text: $ounces)
                .keyboardType(.decimalPad)
                .focused(isOuncesFocused ?? $localOuncesFocused)
            Text("oz")
                .foregroundStyle(.secondary)
        }
    }
}
