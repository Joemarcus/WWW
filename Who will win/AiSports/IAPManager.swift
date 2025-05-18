import StoreKit
import SwiftUI

class IAPManager: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    static let shared = IAPManager()
    
    @Published var strategiesPurchased: Bool = false
    @Published var strategiesProduct: SKProduct?
    @Published var extraSearchesProduct: SKProduct?
    
    // Updated product identifier for extra searches.
    private let productIdentifiers: Set<String> = ["Tips", "search1"]
    private var productsDict: [String: SKProduct] = [:]
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }
    
    func fetchProducts() {
        let request = SKProductsRequest(productIdentifiers: productIdentifiers)
        request.delegate = self
        request.start()
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            for product in response.products {
                self.productsDict[product.productIdentifier] = product
            }
            self.strategiesProduct = self.productsDict["Tips"]
            self.extraSearchesProduct = self.productsDict["search1"]
        }
    }
    
    func purchaseStrategies() {
        guard let product = strategiesProduct, SKPaymentQueue.canMakePayments() else {
            print("Cannot make payments or strategies product not available")
            return
        }
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    func purchaseExtraSearches(completion: @escaping (Bool) -> Void) {
        guard let product = extraSearchesProduct, SKPaymentQueue.canMakePayments() else {
            print("Cannot make payments or extra searches product not available")
            completion(false)
            return
        }
        let payment = SKPayment(product: product)
        ExtraSearchesPurchaseHandler.shared.completion = completion
        SKPaymentQueue.default().add(payment)
    }
    
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased, .restored:
                if transaction.payment.productIdentifier == "Tips" {
                    DispatchQueue.main.async {
                        self.strategiesPurchased = true
                    }
                } else if transaction.payment.productIdentifier == "search1" {
                    ExtraSearchesPurchaseHandler.shared.completion?(true)
                }
                SKPaymentQueue.default().finishTransaction(transaction)
            case .failed:
                if transaction.payment.productIdentifier == "search1" {
                    ExtraSearchesPurchaseHandler.shared.completion?(false)
                }
                SKPaymentQueue.default().finishTransaction(transaction)
            default:
                break
            }
        }
    }
}

class ExtraSearchesPurchaseHandler {
    static let shared = ExtraSearchesPurchaseHandler()
    var completion: ((Bool) -> Void)?
}
