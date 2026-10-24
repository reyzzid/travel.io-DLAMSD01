import SwiftUI

private enum TravelStyle {
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.22)
    static let accent = Color(red: 0.43, green: 0.35, blue: 0.91)
    static let secondary = Color(red: 0.43, green: 0.45, blue: 0.55)
    static let panel = Color.white.opacity(0.78)
}

private struct TravelMessage: Identifiable {
    enum Role {
        case user, assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var places: [TravelPlace] = []
}

struct ContentView: View {
    @State private var input = ""
    @State private var messages: [TravelMessage] = []
    @State private var destination: String?
    @State private var loading = false

    private let service = WikivoyageService()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, Color(red: 0.94, green: 0.95, blue: 1.0), Color(red: 0.97, green: 0.95, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            welcome

                            ForEach(messages) { message in
                                messageView(message)
                                    .id(message.id)
                            }

                            if loading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Searching Wikivoyage...")
                                        .font(.subheadline)
                                        .foregroundStyle(TravelStyle.secondary)
                                }
                                .padding(.vertical, 12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastID = messages.last?.id {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "globe.europe.africa.fill")
                .foregroundStyle(TravelStyle.accent)
            Text("travel.io")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(TravelStyle.ink)
            Spacer()
            Button {
                destination = nil
                messages.removeAll()
                input = ""
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
                    .foregroundStyle(TravelStyle.accent)
            }
            .accessibilityLabel("New destination")
            .disabled(loading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
           
             Text("Where would you like to go?")
                 .font(.system(size: 37, weight: .regular, design: .serif))
                 .foregroundStyle(TravelStyle.ink)
                 .fixedSize(horizontal: false, vertical: true)

            Text("Enter a city. I'll find sights, restaurants and places to stay using Wikivoyage.")
                .font(.subheadline)
                .foregroundStyle(TravelStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func messageView(_ message: TravelMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 50)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(TravelStyle.ink)
                    .padding(14)
                    .background(Color(red: 0.89, green: 0.88, blue: 1.0), in: RoundedRectangle(cornerRadius: 19))
            }
        } else {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(TravelStyle.accent)
                    Text("travel.io")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(TravelStyle.ink)

                ForEach(message.places) { place in
                    placeCard(place)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func placeCard(_ place: TravelPlace) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(place.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TravelStyle.ink)
                Spacer()
                Image(systemName: "mappin")
                    .foregroundStyle(TravelStyle.accent)
            }

            if !place.description.isEmpty {
                Text(place.description)
                    .font(.system(size: 13))
                    .foregroundStyle(TravelStyle.secondary)
            }

            if let address = place.address, !address.isEmpty {
                Label(address, systemImage: "location")
                    .font(.system(size: 12))
                    .foregroundStyle(TravelStyle.secondary)
            }

            HStack(spacing: 4) {
                Link(destination: place.articleURL) {
                    Label("Wikivoyage source", systemImage: "arrow.up.right.square")
                }
                Text("·")
                Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(TravelStyle.accent)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TravelStyle.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.9)))
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if destination != nil {
                HStack(spacing: 9) {
                    quickButton("Sights", symbol: "building.columns")
                    quickButton("Eat", symbol: "fork.knife")
                    quickButton("Stay", symbol: "bed.double")
                }
            }

            HStack(alignment: .bottom, spacing: 12) {

                TextField("Enter a city or ask a question...", text: $input, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .padding(.vertical, 10)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(TravelStyle.accent, in: Circle())
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                .opacity(loading ? 0.45 : 1)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 6)
            .background(.white.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .background(.regularMaterial)
    }

    private func quickButton(_ label: String, symbol: String) -> some View {
        Button {
            send(label)
        } label: {
            Label(label, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TravelStyle.accent)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(.white.opacity(0.8), in: Capsule())
        }
        .disabled(loading)
    }

    private func send(_ predefined: String? = nil) {
        let text = (predefined ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loading else { return }
        input = ""
        messages.append(TravelMessage(role: .user, text: text))
        Task { await handle(text) }
    }

    @MainActor
    private func handle(_ text: String) async {
        let requestedCategory = TravelCategory.recognize(text)
        let category: TravelCategory
        let city: String

        if let requestedCategory {
            guard let currentCity = destination else {
                messages.append(TravelMessage(role: .assistant, text: "First, tell me which city you'd like to explore."))
                return
            }
            category = requestedCategory
            city = currentCity
        } else {
            city = text
            destination = city
            category = .sights
        }

        loading = true
        defer { loading = false }

        do {
            let places = try await service.findPlaces(in: city, category: category)
            if places.isEmpty {
                messages.append(TravelMessage(
                    role: .assistant,
                    text: "I couldn't find listed \(category.heading) for \(city) in Wikivoyage. Try another category or destination."
                ))
            } else {
                messages.append(TravelMessage(
                    role: .assistant,
                    text: "Here are \(places.count) \(category.heading) in \(city). These are guidebook listings, not a ranked top list.",
                    places: places
                ))
            }
        } catch {
            messages.append(TravelMessage(
                role: .assistant,
                text: "Sorry, I couldn't load that information. \(error.localizedDescription)"
            ))
        }
    }
}

#Preview {
    ContentView()
}
