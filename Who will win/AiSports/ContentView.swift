import SwiftUI
import StoreKit
import UIKit

// MARK: - SearchManager
class SearchManager: ObservableObject {
    @Published var remainingForecasts: Int {
        didSet {
            UserDefaults.standard.set(remainingForecasts, forKey: "RemainingForecasts")
        }
    }
    
    init() {
        let saved = UserDefaults.standard.integer(forKey: "RemainingForecasts")
        self.remainingForecasts = saved == 0 ? 2 : saved
    }
    
    func addExtraForecasts(_ count: Int) {
        remainingForecasts += count
    }
    
    func useForecast() {
        if remainingForecasts > 0 {
            remainingForecasts -= 1
        }
    }
}

// MARK: - Forecast Model and History Store
struct Forecast: Identifiable {
    let id = UUID()
    let team1Name: String
    let team2Name: String
    let team1Odds: String
    let team2Odds: String
    let selectedSport: Sport
    let gameDate: Date
    let result: String
    let timestamp: Date = Date()
    var actualResult: String?
    var isCorrect: Bool?
    var isLive: Bool
}

class ForecastHistoryStore: ObservableObject {
    @Published var forecasts: [Forecast] = []
    static let shared = ForecastHistoryStore()
    
    func updateForecastResult(_ forecastID: UUID, actualResult: String, isCorrect: Bool) {
        if let index = forecasts.firstIndex(where: { $0.id == forecastID }) {
            forecasts[index].actualResult = actualResult
            forecasts[index].isCorrect = isCorrect
        }
    }
}

// MARK: - GameViewModel and Data Models
class GameViewModel: ObservableObject {
    @Published var allGames: [Game] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var hedgeNotifications: [String] = []
    
    private var lastLoadTime: Date?
    let supportedSportKeys = ["basketball_nba", "icehockey_nhl", "americanfootball_nfl", "soccer_epl", "baseball_mlb"]
    
    func loadAllGames(forceRefresh: Bool = false) {
        if !forceRefresh, let lastTime = lastLoadTime, Date().timeIntervalSince(lastTime) < 250 {
            return
        }
        isLoading = true
        error = nil
        
        let apiKey = OddsAPI.apiKey
        let region = "us"
        let market = "h2h"
        
        let dispatchGroup = DispatchGroup()
        var combinedGames: [String: Game] = [:]
        var encounteredError: String? = nil
        
        for sportKey in supportedSportKeys {
            dispatchGroup.enter()
            let urlString = "\(OddsAPI.baseURL)?sport=\(sportKey)®ion=\(region)&mkt=\(market)&apiKey=\(apiKey)"
            guard let url = URL(string: urlString) else {
                encounteredError = "Invalid URL for sport \(sportKey)"
                dispatchGroup.leave()
                continue
            }
            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { dispatchGroup.leave() }
                if let error = error {
                    encounteredError = error.localizedDescription
                    return
                }
                guard let data = data else {
                    encounteredError = "No data returned for sport \(sportKey)"
                    return
                }
                do {
                    let games = try JSONDecoder().decode([Game].self, from: data)
                    for game in games { combinedGames[game.id] = game }
                } catch {
                    encounteredError = "Decoding error for \(sportKey): \(error.localizedDescription)"
                }
            }.resume()
        }
        
        dispatchGroup.notify(queue: .main) {
            self.isLoading = false
            self.lastLoadTime = Date()
            if let errMsg = encounteredError {
                self.error = errMsg
            } else {
                self.allGames = Array(combinedGames.values)
            }
        }
    }
    
    func games(for sport: Sport) -> [Game] {
        sport == .all ? allGames : allGames.filter { $0.sport_key == sport.apiEndpointKey }
    }
    
    func checkGameResult(gameID: String, sportKey: String, completion: @escaping (Result<(String, Bool), Error>) -> Void) {
        let urlString = "\(OddsAPI.resultsBaseURL)/\(sportKey)/events/\(gameID)/scores?apiKey=\(OddsAPI.apiKey)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 400, userInfo: nil)))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "No data returned", code: 404, userInfo: nil)))
                return
            }
            do {
                let result = try JSONDecoder().decode(GameResult.self, from: data)
                let winner = self.determineWinner(from: result)
                completion(.success(winner))
            } catch {
                completion(.failure(error))
            }
        }.resume()
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
    
    func startHedgeNotifications() {
        guard let url = URL(string: "wss://early-quiver-shingle.glitch.me") else { return }
        let webSocket = WebSocket(url: url)
        webSocket.delegate = self
        webSocket.connect()
    }
}

// MARK: - WebSocket Delegate
extension GameViewModel: WebSocketDelegate {
    func webSocketDidConnect(_ webSocket: WebSocket) {}
    
    func webSocketDidDisconnect(_ webSocket: WebSocket, error: Error?) {}
    
    func webSocket(_ webSocket: WebSocket, didReceiveData data: Data) {
        do {
            let notifications = try JSONDecoder().decode([HedgeNotification].self, from: data)
            DispatchQueue.main.async {
                self.hedgeNotifications = notifications.map { $0.text }
            }
        } catch {
            print("Error decoding hedge notifications: \(error)")
        }
    }
}

// MARK: - WebSocket Client (Placeholder)
class WebSocket {
    let url: URL
    var delegate: WebSocketDelegate?
    
    init(url: URL) {
        self.url = url
    }
    
    func connect() {
        // TODO: Implement with Starscream or similar WebSocket library
    }
    
    func disconnect() {}
}

protocol WebSocketDelegate {
    func webSocketDidConnect(_ webSocket: WebSocket)
    func webSocketDidDisconnect(_ webSocket: WebSocket, error: Error?)
    func webSocket(_ webSocket: WebSocket, didReceiveData data: Data)
}

// MARK: - Hedge Notification Model
struct HedgeNotification: Decodable {
    let type: String
    let text: String
}

// MARK: - OddsAPI
struct OddsAPI {
    static let baseURL = "https://early-quiver-shingle.glitch.me/odds"
    static let resultsBaseURL = "https://api.the-odds-api.com/v4/sports"
    static let apiKey = "fa99804be12e416c46b6e9fa1ddfbc6b"
}

// MARK: - Data Models
struct Game: Identifiable, Decodable {
    let id: String
    let sport_key: String?
    let sport_title: String?
    let commence_time: String?
    let home_team: String?
    let away_team: String?
    let bookmakers: [Bookmaker]
    let completed: Bool?
    
    var teams: [String]? {
        if let home = home_team, let away = away_team {
            return [home, away]
        }
        return nil
    }
    
    var commenceTimeAsDate: Date? {
        guard let timeString = commence_time else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timeString)
    }
    
    var isLive: Bool {
        guard let commenceTime = commenceTimeAsDate else { return false }
        return commenceTime < Date() && !(completed ?? false)
    }
}

struct Bookmaker: Decodable {
    let key: String
    let title: String
    let markets: [Market]
}

struct Market: Decodable {
    let key: String
    let outcomes: [Outcome]
}

struct Outcome: Decodable {
    let name: String
    let price: Double
}

struct GameResult: Decodable {
    let id: String
    let sport_key: String
    let home_team: String
    let away_team: String
    let scores: [TeamScore]?
}

struct TeamScore: Decodable {
    let name: String
    let score: Int?
}

// MARK: - Sport Enumeration
enum Sport: String, CaseIterable, Hashable {
    case all, basketball, hockey, football, soccer, baseball
    
    var emoji: String {
        switch self {
        case .all: return "🌍"
        case .basketball: return "🏀"
        case .hockey: return "🏒"
        case .football: return "🏈"
        case .soccer: return "⚽"
        case .baseball: return "⚾"
        }
    }
    
    var apiEndpointKey: String? {
        switch self {
        case .all: return nil
        case .basketball: return "basketball_nba"
        case .hockey: return "icehockey_nhl"
        case .football: return "americanfootball_nfl"
        case .soccer: return "soccer_epl"
        case .baseball: return "baseball_mlb"
        }
    }
    
    var displayName: String {
        switch self {
        case .all: return "All Sports"
        case .basketball: return "NBA"
        case .hockey: return "NHL"
        case .football: return "NFL"
        case .soccer: return "EPL"
        case .baseball: return "MLB"
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var showWelcome: Bool = true
    @StateObject private var gameViewModel = GameViewModel()
    @StateObject private var searchManager = SearchManager()
    
    var body: some View {
        MainTabView()
            .environmentObject(ForecastHistoryStore.shared)
            .environmentObject(IAPManager.shared)
            .environmentObject(gameViewModel)
            .environmentObject(searchManager)
            .preferredColorScheme(.light)
            .fullScreenCover(isPresented: $showWelcome) {
                WelcomeView(showWelcome: $showWelcome)
            }
            .onAppear {
                gameViewModel.startHedgeNotifications()
            }
    }
}

// MARK: - MainTabView
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationView {
                PredictorView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Forecast", systemImage: "star.fill") }
            NavigationView {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "clock.fill") }
            NavigationView {
                CompletedGamesView()
            }
            .tabItem { Label("Completed", systemImage: "checkmark.circle.fill") }
            NavigationView {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .accentColor(.green)
    }
}

// MARK: - WelcomeView
struct WelcomeView: View {
    @Binding var showWelcome: Bool
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "waveform.path.ecg")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.green)
                Text("Welcome to WinPulse")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.black)
                Text("Forecast game winners with real-time insights")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Button(action: { showWelcome = false }) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
            }
            .padding()
        }
    }
}

// MARK: - PredictorView
struct PredictorView: View {
    @State private var team1Name: String = ""
    @State private var team2Name: String = ""
    @State private var gameDate = Date()
    @State private var selectedSport: Sport = .basketball
    @State private var team1Odds: String = "-150"
    @State private var team2Odds: String = "+150"
    @State private var selectedGameID: String?
    @State private var isGameLive: Bool = false
    @State private var showSportSelection: Bool = false
    @State private var showExtraForecastsView: Bool = false
    @State private var showResultSheet: Bool = false
    @State private var showAlert: Bool = false
    
    @EnvironmentObject var searchManager: SearchManager
    @EnvironmentObject var gameViewModel: GameViewModel
    
    func resetSelection() {
        team1Name = ""
        team2Name = ""
        team1Odds = "-150"
        team2Odds = "+150"
        gameDate = Date()
        selectedGameID = nil
        isGameLive = false
    }
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack {
                        Text("Game Forecaster")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        Text("Forecasts Left: \(searchManager.remainingForecasts)")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .padding(.top)
                    
                    // Hedge Notification
                    if let latestHedge = gameViewModel.hedgeNotifications.first {
                        Text("💡 Hedge Opportunity: \(latestHedge)")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                    
                    // Game Selection Card
                    VStack(spacing: 12) {
                        Text("Select a Game")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black)
                        Button(action: {
                            if searchManager.remainingForecasts > 0 {
                                searchManager.useForecast()
                                showSportSelection = true
                            } else {
                                showExtraForecastsView = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "sportscourt")
                                Text("Choose Game")
                            }
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    // Selected Game Info
                    if !team1Name.isEmpty && !team2Name.isEmpty {
                        VStack(alignment: .leading, spacing: 10) { // Fixed: Changed Vargas to VStack
                            Text("Selected Matchup")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                            HStack {
                                Text(team1Name)
                                    .foregroundColor(.black)
                                Spacer()
                                Text("vs")
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(team2Name)
                                    .foregroundColor(.black)
                            }
                            .font(.system(size: 16))
                            if let dateString = formattedDate(gameDate) {
                                Text("Date: \(dateString)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            if isGameLive {
                                Text("🔴 Game is live!")
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(15)
                        .padding(.horizontal)
                    }
                    
                    // Forecast Button
                    Button(action: {
                        if team1Name.isEmpty || team2Name.isEmpty {
                            showAlert = true
                        } else {
                            showResultSheet = true
                        }
                    }) {
                        Text("Forecast Winner")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .alert(isPresented: $showAlert) {
                        Alert(title: Text("Incomplete Selection"), message: Text("Please select a game to forecast."), dismissButton: .default(Text("OK")))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Forecast")
        .sheet(isPresented: $showSportSelection) {
            SportSelectionView(selectedSport: $selectedSport) { game, sport in
                if let teams = game.teams, teams.count >= 2 {
                    team1Name = teams[0]
                    team2Name = teams[1]
                }
                let preferredBookmakers = ["draftkings", "fanduel", "bet365"]
                let bookmaker = game.bookmakers.first { preferredBookmakers.contains($0.key.lowercased()) } ?? game.bookmakers.first
                if let bookmaker = bookmaker,
                   let market = bookmaker.markets.first(where: { $0.key == "h2h" }),
                   let homeTeam = game.home_team,
                   let awayTeam = game.away_team,
                   market.outcomes.count >= 2 {
                    let outcomes = market.outcomes
                    let homeOutcome = outcomes.first { $0.name == homeTeam }
                    let awayOutcome = outcomes.first { $0.name == awayTeam }
                    team1Odds = homeOutcome != nil ? formatAmericanOdds(from: homeOutcome!.price) : "N/A"
                    team2Odds = awayOutcome != nil ? formatAmericanOdds(from: awayOutcome!.price) : "N/A"
                } else {
                    team1Odds = "N/A"
                    team2Odds = "N/A"
                }
                if let date = game.commenceTimeAsDate {
                    gameDate = date
                }
                selectedGameID = game.id
                isGameLive = game.isLive
            }
        }
        .sheet(isPresented: $showExtraForecastsView) {
            ExtraForecastsPurchaseView {
                IAPManager.shared.purchaseExtraSearches { success in
                    if success {
                        searchManager.addExtraForecasts(5)
                        showExtraForecastsView = false
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showResultSheet) {
            ForecastAnimationView(
                team1Name: team1Name,
                team2Name: team2Name,
                team1Odds: team1Odds,
                team2Odds: team2Odds,
                selectedSport: selectedSport,
                gameDate: gameDate,
                gameID: selectedGameID,
                isGameLive: isGameLive,
                onDismiss: resetSelection
            )
            .environmentObject(ForecastHistoryStore.shared)
            .environmentObject(gameViewModel)
        }
    }
    
    func formatAmericanOdds(from decimal: Double) -> String {
        guard decimal > 1.0 else { return "N/A" }
        let odds: Double = decimal < 2 ? -100 / (decimal - 1) : (decimal - 1) * 100
        let formattedOdds = String(format: "%.0f", odds)
        return odds > 0 ? "+\(formattedOdds)" : formattedOdds
    }
    
    func formattedDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - ExtraForecastsPurchaseView
struct ExtraForecastsPurchaseView: View {
    var onPurchaseCompleted: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var purchaseInProgress = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.green)
                Text("Unlock More Forecasts")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                Text("Get 5 extra forecasts")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Button(action: {
                    if !purchaseInProgress {
                        purchaseInProgress = true
                        onPurchaseCompleted()
                    }
                }) {
                    Text(purchaseInProgress ? "Processing..." : "Buy Now")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .disabled(purchaseInProgress)
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            }
            .padding()
        }
    }
}

// MARK: - SportSelectionView
struct SportSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedSport: Sport
    var onGameSelected: (Game, Sport) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Sport.allCases, id: \.self) { sport in
                    NavigationLink(destination: GameSelectionView(selectedSport: .constant(sport), onGameSelected: { game in
                        selectedSport = sport
                        onGameSelected(game, sport)
                        dismiss()
                    })) {
                        HStack(spacing: 12) {
                            Text(sport.emoji)
                                .font(.system(size: 24))
                            Text(sport.displayName)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.white)
            .navigationTitle("Select Sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - GameSelectionView
struct GameSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedSport: Sport
    @EnvironmentObject var gameViewModel: GameViewModel
    var onGameSelected: (Game) -> Void
    
    var filteredGames: [Game] {
        let currentDate = Date()
        let initial = gameViewModel.games(for: selectedSport).filter { game in
            guard let commenceDate = game.commenceTimeAsDate else { return false }
            return commenceDate > currentDate || game.isLive
        }
        var dict: [String: Game] = [:]
        for g in initial { dict[g.id] = g }
        return Array(dict.values)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()
                if gameViewModel.isLoading {
                    ProgressView("Loading games...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .green))
                } else if let error = gameViewModel.error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                } else if filteredGames.isEmpty {
                    Text("No upcoming or live games for \(selectedSport.displayName)")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredGames) { game in
                                GameCardView(game: game) {
                                    onGameSelected(game)
                                    dismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.green)
                }
            }
            .onAppear {
                gameViewModel.loadAllGames(forceRefresh: gameViewModel.allGames.isEmpty)
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - GameCardView
struct GameCardView: View {
    let game: Game
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                if let teams = game.teams, teams.count >= 2 {
                    HStack {
                        Text(teams[0])
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                        Spacer()
                        Text("vs")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(teams[1])
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                if let date = game.commenceTimeAsDate {
                    Text(date, style: .date)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                if game.isLive {
                    Text("🔴 Live")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(15)
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - ForecastAnimationView
struct ForecastAnimationView: View {
    let team1Name: String
    let team2Name: String
    let team1Odds: String
    let team2Odds: String
    let selectedSport: Sport
    let gameDate: Date
    let gameID: String?
    let isGameLive: Bool
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var historyStore: ForecastHistoryStore
    @EnvironmentObject var gameViewModel: GameViewModel
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var forecastResult: String = ""
    @State private var isProcessing: Bool = true
    @State private var forecastID: UUID?
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                if isProcessing {
                    VStack(spacing: 20) {
                        Text("Forecasting...")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                        Circle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .scaleEffect(pulseScale)
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: pulseScale
                            )
                            .onAppear {
                                pulseScale = 1.3
                            }
                        Text("Analyzing odds...")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                } else {
                    VStack(spacing: 20) {
                        Text("Forecast")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        Text(forecastResult)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(15)
                        if isGameLive {
                            Text("🔴 Game is live!")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                        }
                        Button(action: { /* Share functionality placeholder */ }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                        Button(action: {
                            onDismiss()
                            dismiss()
                        }) {
                            Text("Done")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gray)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 40)
        }
        .onAppear { startForecast() }
    }
    
    func startForecast() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            computeForecast()
        }
    }
    
    func computeForecast() {
        let odds1 = Int(team1Odds.replacingOccurrences(of: "+", with: "")) ?? 150
        let odds2 = Int(team2Odds.replacingOccurrences(of: "+", with: "")) ?? 150
        
        func impliedProbability(for odds: Int, isNegative: Bool) -> Double {
            isNegative ? Double(-odds) / (Double(-odds) + 100) : 100 / (Double(odds) + 100)
        }
        
        let p1 = team1Odds.hasPrefix("-") ? impliedProbability(for: odds1, isNegative: true) : impliedProbability(for: odds1, isNegative: false)
        let p2 = team2Odds.hasPrefix("-") ? impliedProbability(for: odds2, isNegative: true) : impliedProbability(for: odds2, isNegative: false)
        
        let randomValue = deterministicRandom(from: "\(team1Name)|\(team2Name)|\(gameDate)")
        if max(p1, p2) >= 0.8 {
            let favored = p1 > p2 ? (team1Name, p1) : (team2Name, p2)
            let underdog = p1 > p2 ? (team2Name, p2) : (team1Name, p1)
            forecastResult = randomValue < 0.125 ? "\(underdog.0) wins!" : "\(favored.0) wins!"
        } else {
            let chanceTeam1 = p1 / (p1 + p2)
            forecastResult = randomValue < chanceTeam1 ? "\(team1Name) wins!" : "\(team2Name) wins!"
        }
        
        let newForecast = Forecast(
            team1Name: team1Name,
            team2Name: team2Name,
            team1Odds: team1Odds,
            team2Odds: team2Odds,
            selectedSport: selectedSport,
            gameDate: gameDate,
            result: forecastResult,
            actualResult: nil,
            isCorrect: nil,
            isLive: isGameLive
        )
        forecastID = newForecast.id
        historyStore.forecasts.insert(newForecast, at: 0)
        
        if let gameID = gameID, let sportKey = selectedSport.apiEndpointKey, gameDate < Date() {
            gameViewModel.checkGameResult(gameID: gameID, sportKey: sportKey) { result in
                switch result {
                case .success(let (winner, isAvailable)):
                    let actualResult = isAvailable ? "\(winner) wins!" : "Result not available"
                    let isCorrect = isAvailable ? (winner + " wins!" == forecastResult) : nil
                    historyStore.updateForecastResult(newForecast.id, actualResult: actualResult, isCorrect: isCorrect ?? false)
                case .failure:
                    historyStore.updateForecastResult(newForecast.id, actualResult: "Result unavailable", isCorrect: false)
                }
            }
        }
        
        withAnimation {
            isProcessing = false
        }
    }
    
    func deterministicRandom(from input: String) -> Double {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Double(hash % 10000) / 10000.0
    }
}

// MARK: - HistoryView
struct HistoryView: View {
    @EnvironmentObject var historyStore: ForecastHistoryStore
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if historyStore.forecasts.isEmpty {
                        Text("No forecasts yet")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                            .padding(.top, 20)
                    } else {
                        ForEach(historyStore.forecasts) { forecast in
                            ForecastCardView(forecast: forecast)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") {
                    historyStore.forecasts.removeAll()
                }
                .foregroundColor(.green)
            }
        }
    }
}

// MARK: - ForecastCardView
struct ForecastCardView: View {
    let forecast: Forecast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(forecast.team1Name) vs \(forecast.team2Name)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                if let isCorrect = forecast.isCorrect {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? .green : .red)
                }
            }
            Text("Forecast: \(forecast.result)")
                .font(.system(size: 16))
                .foregroundColor(.black)
            if let actualResult = forecast.actualResult {
                Text("Actual: \(actualResult)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            Text("Game Date: \(forecast.gameDate, formatter: itemFormatter)")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            if forecast.isLive {
                Text("🔴 Live")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @EnvironmentObject var iapManager: IAPManager
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                Text("Support: support@winpulse.app")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                Button(action: { iapManager.restorePurchases() }) {
                    Text("Restore Purchases")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top)
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Date Formatters
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()
