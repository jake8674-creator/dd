import UIKit

@MainActor
final class DetailsController: UITableViewController {
    private let initial: FitSession
    private let onSave: (FitSession) throws -> Void
    private let fields = [UITextField(), UITextField(), UITextField(), UITextField()]
    private let memo = UITextView()
    init(record: FitSession, onSave: @escaping (FitSession) throws -> Void) {
        initial = record; self.onSave = onSave
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "기본정보 입력"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "저장", style: .done, target: self, action: #selector(save))
        let values = [initial.name, initial.lensWidth, initial.bridgeWidth, initial.readingDistance]
        let placeholders = ["고객 별칭 / 안경테 모델", "A · 렌즈 가로폭 mm", "DBL · 브리지 mm", "눈–화면 거리 cm"]
        for i in fields.indices {
            fields[i].text = values[i]; fields[i].placeholder = placeholders[i]
            fields[i].font = .preferredFont(forTextStyle: .body)
            fields[i].keyboardType = i == 0 ? .default : .decimalPad
            fields[i].borderStyle = .roundedRect
            fields[i].autocorrectionType = .no
            fields[i].accessibilityIdentifier = ["name-input","lens-width-input","bridge-input","near-distance-input"][i]
        }
        memo.text = initial.memo
        memo.font = .preferredFont(forTextStyle: .body)
        memo.accessibilityIdentifier = "memo-input"
        tableView.keyboardDismissMode = .interactive
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 4 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["이름과 실측 치수", "메모", "크기 기준"][section] }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { indexPath.section == 1 ? 180 : (indexPath.section == 2 ? 100 : 64) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let input: UIView
        if indexPath.section == 0 { input = fields[indexPath.row] }
        else if indexPath.section == 1 { input = memo }
        else {
            cell.textLabel?.text = "실측 A·DBL을 기준으로 사진을 mm로 환산합니다. 렌즈의 박싱 치수를 입력하세요. 입력 중에는 기록을 덮어쓰지 않으며 저장을 눌러야 반영됩니다."
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.font = .preferredFont(forTextStyle: .footnote)
            return cell
        }
        input.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(input)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            input.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            input.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            input.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)
        ])
        return cell
    }
    @objc private func save() {
        view.endEditing(true)
        var edited = initial
        edited.name = fields[0].text ?? ""
        edited.lensWidth = fields[1].text ?? ""
        edited.bridgeWidth = fields[2].text ?? ""
        edited.readingDistance = fields[3].text ?? ""
        edited.memo = memo.text ?? ""
        guard let a = FitSession.number(edited.lensWidth), (30...80).contains(a), let b = FitSession.number(edited.bridgeWidth), (5...40).contains(b) else { showMessage("A는 30–80 mm, DBL은 5–40 mm 범위로 입력하세요."); return }
        guard let near = FitSession.number(edited.readingDistance), (15...100).contains(near) else { showMessage("근거리 거리는 15–100 cm 범위로 입력하세요."); return }
        do { try onSave(edited); navigationController?.popViewController(animated: true) }
        catch { showMessage(error.localizedDescription) }
    }
}
