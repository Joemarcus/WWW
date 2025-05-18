import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    private init() {}

    func loadGames(for sportKeys: [String]) async throws -> [Game] {
        var combined: [Game] = []
        for key in sportKeys {
            let urlString = "\(OddsAPI.baseURL)?sport=\(key)&region=us&mkt=h2h&apiKey=\(OddsAPI.apiKey)"
            guard let url = URL(string: urlString) else { continue }
            let (data, _) = try await URLSession.shared.data(from: url)
            let games = try JSONDecoder().decode([Game].self, from: data)
            combined.append(contentsOf: games)
        }
        return combined
    }

    func fetchGameResult(gameID: String, sportKey: String) async throws -> (String, Bool) {
        let urlString = "\(OddsAPI.resultsBaseURL)/\(sportKey)/events/\(gameID)/scores?apiKey=\(OddsAPI.apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(GameResult.self, from: data)
        return determineWinner(from: result)
    }

    private func determineWinner(from result: GameResult) -> (String, Bool) {
        guard let scores = result.scores, scores.count >= 2 else {
            return ("Result not available", false)
        }
        let team1Score = scores[0].score ?? 0
        let team2Score = scores[1].score ?? 0
        let winner = team1Score > team2Score ? scores[0].name : scores[1].name
        return (winner, true)
    }
}
