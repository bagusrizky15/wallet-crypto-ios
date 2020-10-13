import ThemeKit
import RxSwift
import RxCocoa
import UIExtensions
import HUD
import SectionsTableView
import SnapKit

class WalletConnectMainViewController: ThemeViewController {
    private static let spinnerLineWidth: CGFloat = 2
    private static let spinnerSideSize: CGFloat = 20

    private let viewModel: WalletConnectViewModel
    private let presenter: WalletConnectMainViewModel
    private weak var sourceViewController: UIViewController?

    private let loadingView = HUDProgressView(strokeLineWidth: WalletConnectMainViewController.spinnerLineWidth,
            radius: WalletConnectMainViewController.spinnerSideSize / 2 - WalletConnectMainViewController.spinnerLineWidth / 2,
            strokeColor: .themeGray)

    private let buttonsHolder = BottomGradientHolder()

    private let disconnectButton = ThemeButton()
    private var disconnectButtonBottomConstraint: Constraint?
    private var disconnectButtonHeightConstraint: Constraint?

    private let rejectButton = ThemeButton()
    private var rejectButtonBottomConstraint: Constraint?
    private var rejectButtonHeightConstraint: Constraint?

    private let approveButton = ThemeButton()
    private var approveButtonBottomConstraint: Constraint?
    private var approveButtonHeightConstraint: Constraint?

    private let cancelButton = ThemeButton()
    private var cancelButtonBottomConstraint: Constraint?
    private var cancelButtonHeightConstraint: Constraint?

    private let tableView = SectionsTableView(style: .grouped)

    private let disposeBag = DisposeBag()

    private var peerMeta: WalletConnectMainViewModel.PeerMetaViewItem?
    private var status: WalletConnectMainViewModel.Status?
    private var hint: String?

    init(viewModel: WalletConnectViewModel, sourceViewController: UIViewController?) {
        self.viewModel = viewModel
        presenter = viewModel.mainViewModel
        self.sourceViewController = sourceViewController

        super.init()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Wallet Connect"

        view.addSubview(loadingView)
        loadingView.snp.makeConstraints { maker in
            maker.edges.equalToSuperview()
        }

        loadingView.set(hidden: true)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.leading.top.trailing.equalToSuperview()
        }

        tableView.sectionDataSource = self

        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear

        tableView.registerCell(forClass: TermsHeaderCell.self)
        tableView.registerCell(forClass: FullTransactionInfoTextCell.self)
        tableView.registerHeaderFooter(forClass: BottomDescriptionHeaderFooterView.self)

        view.addSubview(buttonsHolder)
        buttonsHolder.snp.makeConstraints { maker in
            maker.top.equalTo(tableView.snp.bottom).offset(-CGFloat.margin4x)
            maker.leading.trailing.bottom.equalToSuperview()
        }

        buttonsHolder.addSubview(disconnectButton)
        disconnectButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin6x)

            disconnectButtonBottomConstraint = maker.bottom.equalToSuperview().offset(-CGFloat.margin4x).constraint
            disconnectButtonHeightConstraint = maker.height.equalTo(CGFloat.heightButton).constraint
        }

        disconnectButton.apply(style: .primaryRed)
        disconnectButton.setTitle("Disconnect", for: .normal)
        disconnectButton.addTarget(self, action: #selector(onTapDisconnect), for: .touchUpInside)

        buttonsHolder.addSubview(rejectButton)
        rejectButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin6x)

            rejectButtonBottomConstraint = maker.bottom.equalTo(disconnectButton.snp.top).offset(-CGFloat.margin4x).constraint
            rejectButtonHeightConstraint = maker.height.equalTo(CGFloat.heightButton).constraint
        }

        rejectButton.apply(style: .primaryGray)
        rejectButton.setTitle("Reject", for: .normal)
        rejectButton.addTarget(self, action: #selector(onTapReject), for: .touchUpInside)

        buttonsHolder.addSubview(approveButton)
        approveButton.snp.makeConstraints { maker in
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin6x)

            approveButtonBottomConstraint = maker.bottom.equalTo(rejectButton.snp.top).offset(-CGFloat.margin4x).constraint
            approveButtonHeightConstraint = maker.height.equalTo(CGFloat.heightButton).constraint
        }

        approveButton.apply(style: .primaryYellow)
        approveButton.setTitle("Approve", for: .normal)
        approveButton.addTarget(self, action: #selector(onTapApprove), for: .touchUpInside)

        buttonsHolder.addSubview(cancelButton)
        cancelButton.snp.makeConstraints { maker in
            maker.top.equalToSuperview().inset(CGFloat.margin8x)
            maker.leading.trailing.equalToSuperview().inset(CGFloat.margin6x)

            cancelButtonBottomConstraint = maker.bottom.equalTo(approveButton.snp.top).offset(-CGFloat.margin4x).constraint
            cancelButtonHeightConstraint = maker.height.equalTo(CGFloat.heightButton).constraint
        }

        cancelButton.apply(style: .primaryGray)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(onTapCancel), for: .touchUpInside)

        presenter.connectingDriver
                .drive(onNext: { [weak self] connecting in
                    self?.sync(connecting: connecting)
                })
                .disposed(by: disposeBag)

        presenter.cancelVisibleDriver
                .drive(onNext: { [weak self] visible in
                    self?.syncButtonConstraints(bottom: self?.cancelButtonBottomConstraint, height: self?.cancelButtonHeightConstraint, visible: visible)
                })
                .disposed(by: disposeBag)

        presenter.approveAndRejectVisibleDriver
                .drive(onNext: { [weak self] visible in
                    self?.syncButtonConstraints(bottom: self?.approveButtonBottomConstraint, height: self?.approveButtonHeightConstraint, visible: visible)
                    self?.syncButtonConstraints(bottom: self?.rejectButtonBottomConstraint, height: self?.rejectButtonHeightConstraint, visible: visible)
                })
                .disposed(by: disposeBag)

        presenter.disconnectVisibleDriver
                .drive(onNext: { [weak self] visible in
                    self?.syncButtonConstraints(bottom: self?.disconnectButtonBottomConstraint, height: self?.disconnectButtonHeightConstraint, visible: visible)
                })
                .disposed(by: disposeBag)

        presenter.closeVisibleDriver
                .drive(onNext: { [weak self] visible in
                    self?.syncCloseButton(visible: visible)
                })
                .disposed(by: disposeBag)

        presenter.signedTransactionsVisibleDriver
                .drive(onNext: { [weak self] visible in
                })
                .disposed(by: disposeBag)

        presenter.peerMetaDriver
                .drive(onNext: { [weak self] peerMeta in
                    self?.peerMeta = peerMeta
                    self?.tableView.reload()
                })
                .disposed(by: disposeBag)

        presenter.hintDriver
                .drive(onNext: { [weak self] hint in
                    self?.hint = hint
                    self?.tableView.reload()
                })
                .disposed(by: disposeBag)

        presenter.statusDriver
                .drive(onNext: { [weak self] status in
                    self?.status = status
                    self?.tableView.reload()
                })
                .disposed(by: disposeBag)

        presenter.openRequestSignal
                .emit(onNext: { [weak self] id in
                    self?.openRequest(id: id)
                })
                .disposed(by: disposeBag)

        presenter.finishSignal
                .emit(onNext: { [weak self] in
                    self?.sourceViewController?.dismiss(animated: true)
                })
                .disposed(by: disposeBag)
    }

    private func sync(connecting: Bool) {
        loadingView.set(hidden: !connecting)
        if connecting {
            loadingView.startAnimating()
        } else {
            loadingView.stopAnimating()
        }
    }

    private func syncButtonConstraints(bottom: Constraint?, height: Constraint?, visible: Bool) {
        bottom?.update(offset: visible ? -CGFloat.margin4x : 0)
        height?.update(offset: visible ? CGFloat.heightButton : 0)
    }

    @objc private func onTapCancel() {
        sourceViewController?.dismiss(animated: true)
    }

    @objc private func onTapApprove() {
        presenter.approve()
    }

    @objc private func onTapReject() {
        presenter.reject()
    }

    @objc private func onTapDisconnect() {
        presenter.disconnect()
    }

    @objc private func onTapClose() {
        presenter.close()
    }

    private func syncCloseButton(visible: Bool) {
        if visible {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "button.close".localized, style: .plain, target: self, action: #selector(onTapClose))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    private func openRequest(id: Int) {
        let viewController = WalletConnectRequestViewController(viewModel: viewModel, requestId: id).toBottomSheet
        present(viewController, animated: true)
    }

}

extension WalletConnectMainViewController: SectionsDataSource {

    public func buildSections() -> [SectionProtocol] {
        var rows = [RowProtocol]()

        let statusRow = status.map { status in
            valueRow(title: "status".localized, subtitle: status.title, subtitleColor: status.color)
        }

        if let peerMeta = peerMeta {
            rows.append(headerRow(imageUrl: peerMeta.icon, title: peerMeta.name))

            if let statusRow = statusRow {
                rows.append(statusRow)
            }

            rows.append(valueRow(title: "wallet_connect.url".localized, subtitle: peerMeta.url))
        }

        return [Section(id: "wallet_connect", footerState: footer ?? .margin(height: 0), rows: rows)]
    }

    private var footer: ViewState<BottomDescriptionHeaderFooterView>? {
        hint.map { hint -> ViewState<BottomDescriptionHeaderFooterView> in
            .cellType(hash: "hint_footer", binder: { view in
                view.bind(text: hint)
            }, dynamicHeight: { width in
                BottomDescriptionHeaderFooterView.height(containerWidth: width, text: hint)
            })
        }
    }

    private func headerRow(imageUrl: String?, title: String) -> RowProtocol {
        Row<TermsHeaderCell>(id: "header", height: TermsHeaderCell.height, bind: { cell, _ in
            cell.bind(imageUrl: imageUrl, title: title, subtitle: nil)
        })
    }

    private func valueRow(title: String, subtitle: String, subtitleColor: UIColor? = nil) -> RowProtocol {
        Row<FullTransactionInfoTextCell>(id: "row_\(title)", height: .heightSingleLineCell, bind: { cell, _ in
            cell.bind(title: title, subtitle: subtitle, subtitleColor: subtitleColor)
        })
    }

}
