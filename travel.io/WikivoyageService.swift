import Foundation
import SwiftSoup

nonisolated enum TravelCategory: String, CaseIterable, Sendable {
    case sights = "See"
    case eat = "Eat"
    case stay = "Sleep"

    var limit: Int {
        self == .sights ? 5 : 3
    }

    var heading: String {
        switch self {
        case .sights: return "places to visit"
        case .eat: return "places to eat"
        case .stay: return "places to stay"
        }
    }

    static func recognize(_ text: String) -> TravelCategory? {
        let input = text.lowercased()

        if ["restaurant", "eat", "food", "cafe", "café",
            "поесть", "ресторан", "кафе", "покушать"]
            .contains(where: input.contains) {
            return .eat
        }

        if ["hotel", "stay", "sleep", "accommodation",
            "hostel", "переночевать", "ночлег",
            "отель", "гостиниц", "жильё", "жилье"]
            .contains(where: input.contains) {
            return .stay
        }

        if ["sight", "visit", "attraction", "see",
            "достопримечательност", "посмотреть", "посетить"]
            .contains(where: input.contains) {
            return .sights
        }

        return nil
    }
}

nonisolated struct TravelPlace: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let description: String
    let address: String?
    let articleURL: URL
}

nonisolated enum TravelError: LocalizedError {
    case invalidCity
    case articleNotFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCity:
            return "Please enter a valid city name."
        case .articleNotFound:
            return "Destination not found in Wikivoyage."
        case .invalidResponse:
            return "Unexpected response from Wikivoyage."
        }
    }
}

nonisolated private struct ParseResponse: Decodable {
    let parse: ParsedArticle?
}

nonisolated private struct ParsedArticle: Decodable {
    let title: String
    let text: HTMLBody
    let links: [ArticleLink]?
}

nonisolated private struct HTMLBody: Decodable {
    let html: String

    enum CodingKeys: String, CodingKey {
        case html = "*"
    }
}

nonisolated private struct ArticleLink: Decodable {
    let namespace: Int
    let title: String

    enum CodingKeys: String, CodingKey {
        case namespace = "ns"
        case title = "*"
    }
}

nonisolated private struct GuideArticle: Sendable {
    let title: String
    let places: [TravelCategory: [TravelPlace]]
    let districtArticles: [String]
}

actor WikivoyageService {
    
    private var cache: [String: GuideArticle] = [:]
    
    func findPlaces(in city: String, category: TravelCategory) async throws -> [TravelPlace] {
        let destination = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { throw TravelError.invalidCity }
        
        let main = try await loadArticle(destination)
        var found = main.places[category] ?? []
        
        if found.count < category.limit {
            for district in main.districtArticles.prefix(12) {
                if found.count >= category.limit { break }
                guard let page = try? await loadArticle(district) else { continue }
                found += page.places[category] ?? []
            }
        }
        
        var names = Set<String>()
        return found.filter { place in
            let key = place.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return names.insert(key).inserted
        }
        .prefix(category.limit)
        .map { $0 }
    }
    
    private func loadArticle(_ title: String) async throws -> GuideArticle {
        let key = title.lowercased()
        if let cached = cache[key] { return cached }
        
        guard var components = URLComponents(string: "https://en.wikivoyage.org/w/api.php") else {
            throw TravelError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: title),
            URLQueryItem(name: "prop", value: "text|links"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "maxlag", value: "5")
        ]
        guard let url = components.url else { throw TravelError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 25

        request.setValue("travel.io/0.1 (https://github.com/reyzzid/travel.io) URLSession/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TravelError.invalidResponse
        }
        
        let json = try JSONDecoder().decode(ParseResponse.self, from: data)
        guard let article = json.parse else { throw TravelError.articleNotFound }
        
        let source = articleURL(for: article.title)
        let parsedHTML = try SwiftSoup.parse(article.text.html)
        var byCategory: [TravelCategory: [TravelPlace]] = [:]
        var activeCategory: TravelCategory?
        
        for node in try parsedHTML.select("h2, .vcard") {
            if node.tagName().lowercased() == "h2" {
                let heading = try node.text()
                    .components(separatedBy: "[").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                activeCategory = TravelCategory.allCases.first(where: { $0.rawValue.lowercased() == heading })
                continue
            }
            
            guard let category = activeCategory else { continue }
            let name = try node.select(".org, .listing-name").first()?.text() ?? ""
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }
            
            let fullDescription = try node.select(".listing-content").first()?.text() ?? ""
            let shortDescription = String(fullDescription.prefix(240)) + (fullDescription.count > 240 ? "…" : "")
            let address = try node.select(".listing-address").first()?.text()
            
            byCategory[category, default: []].append(
                TravelPlace(
                    name: cleanName,
                    description: shortDescription,
                    address: address,
                    articleURL: source
                )
            )
        }
        
        let prefix = article.title + "/"
        let districts = Array(Set((article.links ?? [])
            .filter { $0.namespace == 0 && $0.title.hasPrefix(prefix) }
            .map(\.title)))
            .sorted {
                let left = districtPriority($0)
                let right = districtPriority($1)
                return left == right ? $0 < $1 : left < right
            }
        
        let result = GuideArticle(title: article.title, places: byCategory, districtArticles: districts)
        cache[key] = result
        return result
    }
    
    private func districtPriority(_ title: String) -> Int {
        let name = title.lowercased()
        if ["mitte", "centre", "center", "central", "old town", "historic", "1st arrondissement"]
            .contains(where: name.contains) { return 0 }
        return 1
    }
    
    private func articleURL(for title: String) -> URL {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "en.wikivoyage.org"
        url.path = "/wiki/" + title.replacingOccurrences(of: " ", with: "_")
        return url.url!
    }
}
