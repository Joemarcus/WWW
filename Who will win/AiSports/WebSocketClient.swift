import Foundation
import Starscream

protocol WebSocketClientDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketReceived(data: Data)
}

class WebSocketClient: NSObject, Starscream.WebSocketDelegate {
    private var socket: Starscream.WebSocket?
    weak var delegate: WebSocketClientDelegate?

    init(url: URL) {
        super.init()
        var request = URLRequest(url: url)
        socket = Starscream.WebSocket(request: request)
        socket?.delegate = self
    }

    func connect() {
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
    }

    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocket) {
        switch event {
        case .connected:
            delegate?.webSocketDidConnect()
        case .disconnected(_, _):
            delegate?.webSocketDidDisconnect(error: nil)
        case .text(let text):
            if let data = text.data(using: .utf8) {
                delegate?.webSocketReceived(data: data)
            }
        case .binary(let data):
            delegate?.webSocketReceived(data: data)
        default:
            break
        }
    }
}
