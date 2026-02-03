import SwiftUI

struct ImageSelectorView: View {
    let images: [String]
    var onSelect: (String) -> Void

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(images, id: \.self) { name in
                        ZStack {
                            Image(name)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(name) }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Choose a Picture")
        }
    }
}

struct ImageSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        ImageSelectorView(images: (1...12).map { String(format: "drawing%02d", $0) }) { _ in }
    }
}
