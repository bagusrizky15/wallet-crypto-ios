import EvmKit
import Foundation
import MarketKit
import SwiftUI

class BaseEvmMultiSwapProvider: IMultiSwapProvider {
    private let adapterManager = App.shared.adapterManager
    let evmBlockchainManager = App.shared.evmBlockchainManager
    let storage: MultiSwapSettingStorage

    init(storage: MultiSwapSettingStorage) {
        self.storage = storage
    }

    var id: String {
        fatalError("Must be implemented in subclass")
    }

    var name: String {
        fatalError("Must be implemented in subclass")
    }

    var icon: String {
        fatalError("Must be implemented in subclass")
    }

    func supports(tokenIn _: Token, tokenOut _: Token) -> Bool {
        fatalError("Must be implemented in subclass")
    }

    func quote(tokenIn _: Token, tokenOut _: Token, amountIn _: Decimal) async throws -> IMultiSwapQuote {
        fatalError("Must be implemented in subclass")
    }

    func confirmationQuote(tokenIn _: Token, tokenOut _: Token, amountIn _: Decimal, transactionSettings _: TransactionSettings?) async throws -> IMultiSwapConfirmationQuote {
        fatalError("Must be implemented in subclass")
    }

    func settingsView(tokenIn _: Token, tokenOut _: Token, onChangeSettings _: @escaping () -> Void) -> AnyView {
        fatalError("settingsView(tokenIn:tokenOut:onChangeSettings:) has not been implemented")
    }

    func settingView(settingId _: String) -> AnyView {
        fatalError("settingView(settingId:) has not been implemented")
    }

    func preSwapView(step: MultiSwapPreSwapStep, tokenIn: Token, tokenOut _: Token, amount: Decimal, isPresented: Binding<Bool>) -> AnyView {
        switch step {
        case let unlockStep as UnlockStep:
            let view = ThemeNavigationView { MultiSwapApproveView(tokenIn: tokenIn, amount: amount, spenderAddress: unlockStep.spenderAddress, isPresented: isPresented) }
            return AnyView(view)
        default:
            return AnyView(Text("Invalid Pre Swap Step"))
        }
    }

    func swap(tokenIn _: Token, tokenOut _: Token, amountIn _: Decimal, quote _: IMultiSwapConfirmationQuote) async throws {
        fatalError("Must be implemented in subclass")
    }

    func spenderAddress(chain _: Chain) throws -> EvmKit.Address {
        fatalError("Must be implemented in subclass")
    }

    func allowanceState(token: Token, amount: Decimal) async -> AllowanceState {
        if token.type.isNative {
            return .notRequired
        }

        guard let adapter = adapterManager.adapter(for: token) as? IErc20Adapter else {
            return .unknown
        }

        do {
            let chain = evmBlockchainManager.chain(blockchainType: token.blockchainType)
            let spenderAddress = try spenderAddress(chain: chain)

            if let pendingAllowance = pendingAllowance(pendingTransactions: adapter.pendingTransactions, spenderAddress: spenderAddress) {
                return .pending(amount: CoinValue(kind: .token(token: token), value: pendingAllowance))
            }

            let allowance = try await adapter.allowance(spenderAddress: spenderAddress, defaultBlockParameter: .latest)

            if amount <= allowance {
                return .allowed
            } else {
                return .notEnough(amount: CoinValue(kind: .token(token: token), value: allowance), spenderAddress: spenderAddress)
            }
        } catch {
            return .unknown
        }
    }

    private func pendingAllowance(pendingTransactions: [TransactionRecord], spenderAddress: EvmKit.Address) -> Decimal? {
        for transaction in pendingTransactions {
            if let record = transaction as? ApproveTransactionRecord, record.spender == spenderAddress.eip55, let value = record.value.decimalValue {
                return value
            }
        }

        return nil
    }
}

extension BaseEvmMultiSwapProvider {
    enum AllowanceState {
        case notRequired
        case pending(amount: CoinValue)
        case notEnough(amount: CoinValue, spenderAddress: EvmKit.Address)
        case allowed
        case unknown
    }

    class UnlockStep: MultiSwapPreSwapStep {
        let spenderAddress: EvmKit.Address

        init(spenderAddress: EvmKit.Address) {
            self.spenderAddress = spenderAddress
        }

        override var id: String {
            "evm_unlock"
        }
    }
}

extension BaseEvmMultiSwapProvider {
    class Quote: IMultiSwapQuote {
        let allowanceState: AllowanceState

        init(allowanceState: AllowanceState) {
            self.allowanceState = allowanceState
        }

        var amountOut: Decimal {
            fatalError("Must be implemented in subclass")
        }

        var customButtonState: MultiSwapButtonState? {
            switch allowanceState {
            case let .notEnough(_, spenderAddress): return .init(title: "Unlock", preSwapStep: UnlockStep(spenderAddress: spenderAddress))
            case .pending: return .init(title: "Unlocking...", disabled: true, showProgress: true)
            case .unknown: return .init(title: "Allowance Error", disabled: true)
            default: return nil
            }
        }

        var settingsModified: Bool {
            false
        }

        func cautions() -> [CautionNew] {
            []
        }

        func fields(tokenIn _: Token, tokenOut _: Token, currency _: Currency, tokenInRate _: Decimal?, tokenOutRate _: Decimal?) -> [MultiSwapMainField] {
            var fields = [MultiSwapMainField]()

            switch allowanceState {
            case let .notEnough(amount, _):
                if let formatted = ValueFormatter.instance.formatShort(coinValue: amount) {
                    fields.append(
                        MultiSwapMainField(
                            title: "Allowance",
                            value: "\(formatted)",
                            valueLevel: .error
                        )
                    )
                }
            case let .pending(amount):
                if let formatted = ValueFormatter.instance.formatShort(coinValue: amount) {
                    fields.append(
                        MultiSwapMainField(
                            title: "Pending Allowance",
                            value: "\(formatted)",
                            valueLevel: .warning
                        )
                    )
                }
            default: ()
            }

            return fields
        }
    }

    class ConfirmationQuote: IMultiSwapConfirmationQuote {
        let gasPrice: GasPrice?
        let gasLimit: Int?
        let nonce: Int?

        init(gasPrice: GasPrice?, gasLimit: Int?, nonce: Int?) {
            self.gasPrice = gasPrice
            self.gasLimit = gasLimit
            self.nonce = nonce
        }

        var amountOut: Decimal {
            fatalError("Must be implemented in subclass")
        }

        var feeData: FeeData? {
            gasLimit.map { .evm(gasLimit: $0) }
        }

        var canSwap: Bool {
            gasPrice != nil && gasLimit != nil
        }

        func cautions(feeToken _: Token?) -> [CautionNew] {
            []
        }

        private func feeData(feeToken: Token, currency: Currency, feeTokenRate: Decimal?) -> AmountData? {
            guard let gasPrice, let gasLimit else {
                return nil
            }

            let amount = Decimal(gasLimit) * Decimal(gasPrice.max) / pow(10, feeToken.decimals)
            let coinValue = CoinValue(kind: .token(token: feeToken), value: amount)
            let currencyValue = feeTokenRate.map { CurrencyValue(currency: currency, value: amount * $0) }

            return AmountData(coinValue: coinValue, currencyValue: currencyValue)
        }

        func priceSectionFields(tokenIn _: Token, tokenOut _: Token, feeToken _: Token?, currency _: Currency, tokenInRate _: Decimal?, tokenOutRate _: Decimal?, feeTokenRate _: Decimal?) -> [MultiSwapConfirmField] {
            []
        }

        func otherSections(tokenIn _: Token, tokenOut _: Token, feeToken: Token?, currency: Currency, tokenInRate _: Decimal?, tokenOutRate _: Decimal?, feeTokenRate: Decimal?) -> [[MultiSwapConfirmField]] {
            var sections = [[MultiSwapConfirmField]]()

            if let feeToken {
                let feeData = feeData(feeToken: feeToken, currency: currency, feeTokenRate: feeTokenRate)

                sections.append(
                    [
                        .value(
                            title: "Network Fee",
                            description: .init(title: "Network Fee", description: "Network Fee Description"),
                            coinValue: feeData?.coinValue,
                            currencyValue: feeData?.currencyValue
                        ),
                    ]
                )
            }

            return sections
        }
    }
}
