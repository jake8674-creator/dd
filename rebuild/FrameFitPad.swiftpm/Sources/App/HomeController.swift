import UIKit

@MainActor
final class HomeController: UITableViewController {
    private var store: FitStore?
    private var loadingError: String?
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Programmatic UI") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "프레임핏 패드"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.tintColor = .systemTeal
        do { store = try FitStore() } catch { loadingError = error.localizedDescription }
        tableView.accessibilityIdentifier = "home-table"
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let error = loadingError { loadingError = nil; showMessage("기록을 읽지 못했습니다. 기존 파일 보호를 위해 작업을 중지합니다.\n" + error) }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 2 ? (store?.sessions.count ?? 0) : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["FRAMEFIT PAD 1.0", "새 작업", "저장한 피팅"][section] }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        if indexPath.section == 0 {
            cell.textLabel?.text = "눈과 안경테를 사진으로 확인하세요"
            cell.detailTextLabel?.text = "지그 없이 촬영 · 기준점 확대 확인 · 기기 내 저장\n\n사진 추정값입니다. 실제 측정기와 비교 검증 전이며 렌즈 주문 확정값으로 사용하지 마세요."
            cell.selectionStyle = .none
        } else if indexPath.section == 1 {
            cell.textLabel?.text = "＋ 새 피팅 시작"
            cell.textLabel?.textColor = .systemTeal
            cell.accessibilityIdentifier = "new-fitting"
            cell.accessoryType = .disclosureIndicator
        } else if let record = store?.sessions[indexPath.row] {
            cell.textLabel?.text = record.title
            cell.detailTextLabel?.text = "사진 \(record.photos.count)장 · " + DateFormatter.localizedString(from: record.created, dateStyle: .medium, timeStyle: .none)
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let store = store else { return }
        if indexPath.section == 1 {
            let record = FitSession()
            do { try store.save(record); navigationController?.pushViewController(SessionController(store: store, record: record), animated: true) }
            catch { showMessage(error.localizedDescription) }
        } else if indexPath.section == 2 {
            navigationController?.pushViewController(SessionController(store: store, record: store.sessions[indexPath.row]), animated: true)
        }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 2, let store = store else { return nil }
        let record = store.sessions[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _,_,done in
            let alert = UIAlertController(title: "기록과 사진을 삭제할까요?", message: record.title, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in done(false) })
            alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { _ in
                do { try store.delete(record); self?.tableView.reloadData(); done(true) }
                catch { self?.showMessage(error.localizedDescription); done(false) }
            })
            self?.present(alert, animated: true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }
}
