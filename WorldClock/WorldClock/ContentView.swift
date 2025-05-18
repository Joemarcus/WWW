import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WorldClockViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.timeZones) { zone in
                HStack {
                    VStack(alignment: .leading) {
                        Text(zone.displayName)
                            .font(.headline)
                        Text(zone.currentTime)
                            .font(.title)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("World Clock")
            .background(
                LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
