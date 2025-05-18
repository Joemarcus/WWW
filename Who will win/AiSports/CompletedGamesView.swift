import SwiftUI

class CompletedGamesViewModel: ObservableObject {
    @Published var games: [CompletedGame] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let sportKeys = ["basketball_nba", "icehockey_nhl", "americanfootball_nfl", "soccer_epl", "baseball_mlb"]

    func loadCompletedGames() {
        isLoading = true
        error = nil

        let group = DispatchGroup()
        var allGames: [CompletedGame] = []
        for key in sportKeys {
            group.enter()
            let urlString = "\(OddsAPI.resultsBaseURL)/\(key)/scores/?apiKey=\(OddsAPI.apiKey)&daysFrom=1"
            guard let url = URL(string: urlString) else { group.leave(); continue }
            URLSession.shared.dataTask(with: url) { data, _, err in
                defer { group.leave() }
                if let err = err {
                    self.error = err.localizedDescription
                    return
                }
                guard let data = data else { return }
                do {
                    let decoded = try JSONDecoder().decode([CompletedGame].self, from: data)
                    let finished = decoded.filter { $0.completed }
                    allGames.append(contentsOf: finished)
                } catch {
                    self.error = error.localizedDescription
                }
            }.resume()
        }
        group.notify(queue: .main) {
            var unique: [String: CompletedGame] = [:]
            for game in allGames { unique[game.id] = game }
            self.games = Array(unique.values).sorted { ($0.commenceTimeAsDate ?? Date.distantPast) > ($1.commenceTimeAsDate ?? Date.distantPast) }
            self.isLoading = false
        }
    }
}

struct CompletedGame: Identifiable, Decodable {
    let id: String
    let sport_key: String
    let commence_time: String?
    let home_team: String
    let away_team: String
    let completed: Bool
    let scores: [TeamScore]?

    var commenceTimeAsDate: Date? {
        guard let t = commence_time else { return nil }
        return ISO8601DateFormatter().date(from: t)
    }
}

struct CompletedGamesView: View {
    @StateObject private var viewModel = CompletedGamesViewModel()

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if viewModel.isLoading {
                ProgressView("Loading scores...")
            } else if let error = viewModel.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else if viewModel.games.isEmpty {
                Text("No completed games in last 24h")
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.games) { game in
                            CompletedGameCard(game: game)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Completed")
        .onAppear { viewModel.loadCompletedGames() }
    }
}

struct CompletedGameCard: View {
    let game: CompletedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(game.home_team) vs \(game.away_team)")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if let scores = game.scores, scores.count >= 2 {
                    Text("\(scores[0].score ?? 0) - \(scores[1].score ?? 0)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            if let date = game.commenceTimeAsDate {
                Text(date, formatter: itemFormatter)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
    }
}

