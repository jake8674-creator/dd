import UIKit

@MainActor
final class SessionController: UITableViewController {
    private let store: FitStore
    private var record: FitSession
    private var results: [FitResult] { FittingCalculator.results(record) }
    init(store:FitStore,record:FitSession) {
        self.store = store; self.record = record
        super.init(style:.insetGrouped)
    }
    required init?(coder:NSCoder) { fatalError("Programmatic UI") }
    override func viewDidLoad() { super.viewDidLoad(); title = record.title; navigationItem.largeTitleDisplayMode = .never; tableView.accessibilityIdentifier = "session-table" }
    override func numberOfSections(in tableView:UITableView)->Int { 5 }
    override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int {
        switch section { case 0:return 1;case 1:return 1;case 2:return record.positions.count;case 3:return results.count;default:return 1 }
    }
    override func tableView(_ tableView:UITableView,titleForHeaderInSection section:Int)->String? { ["기본정보","촬영 측면","사진과 기준점","확인된 사진 추정값","결과 보관"][section] }
    override func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell {
        let cell = UITableViewCell(style:.subtitle,reuseIdentifier:nil)
        cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = "기본정보 입력"
            cell.detailTextLabel?.text = "\(record.title) · A \(record.lensWidth) / DBL \(record.bridgeWidth) mm · 근거리 \(record.readingDistance) cm"
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "open-details"
        case 1:
            cell.textLabel?.text = record.leftSide ? "고객 왼쪽" : "고객 오른쪽"
            cell.detailTextLabel?.text = "탭하면 촬영할 측면을 바꿉니다. 한쪽만 촬영합니다."
        case 2:
            let position = record.positions[indexPath.row]
            cell.textLabel?.text = position.title
            if let photo = record.photos[position.rawValue] { cell.detailTextLabel?.text = photo.allReviewed ? "기준점 확인 완료 · 탭해서 편집 또는 재촬영" : "촬영됨 · 기준점 확인 필요" }
            else { cell.detailTextLabel?.text = position == .reading ? "전면 카메라 + 화면 플래시" : "후면 카메라 + LED 플래시" }
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "photo-"+position.rawValue
        case 3:
            let value = results[indexPath.row]
            cell.textLabel?.text = value.name+"  "+value.text+" "+value.unit
            cell.detailTextLabel?.text = value.note
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "result-\(indexPath.row)"
        default:
            cell.textLabel?.text = "CSV 내보내기"
            cell.detailTextLabel?.text = "사진은 포함하지 않습니다."
        }
        return cell
    }
    override func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath) {
        tableView.deselectRow(at:indexPath,animated:true)
        switch indexPath.section {
        case 0:
            navigationController?.pushViewController(DetailsController(record:record) { [weak self] edited in
                guard let self = self else { return }; try self.store.save(edited); self.record = edited; self.refresh()
            },animated:true)
        case 1:
            var next = record; next.leftSide.toggle()
            do { try store.save(next); record = next; refresh() } catch { showMessage(error.localizedDescription) }
        case 2:
            let position = record.positions[indexPath.row]
            if record.photos[position.rawValue] == nil { capture(position); return }
            let alert = UIAlertController(title:position.title,message:nil,preferredStyle:.actionSheet)
            alert.addAction(UIAlertAction(title:"기준점 확인",style:.default) { [weak self] _ in self?.review(position) })
            alert.addAction(UIAlertAction(title:"다시 촬영",style:.default) { [weak self] _ in self?.capture(position) })
            alert.addAction(UIAlertAction(title:"취소",style:.cancel))
            if let pop = alert.popoverPresentationController { pop.sourceView = tableView; pop.sourceRect = tableView.rectForRow(at:indexPath) }
            present(alert,animated:true)
        case 4:
            do {
                let url = try store.csv(record)
                let share = UIActivityViewController(activityItems:[url],applicationActivities:nil)
                if let pop = share.popoverPresentationController { pop.sourceView = tableView; pop.sourceRect = tableView.rectForRow(at:indexPath) }
                present(share,animated:true)
            } catch { showMessage(error.localizedDescription) }
        default:break
        }
    }
    private func refresh() { title = record.title; tableView.reloadData() }
    private func capture(_ position:PhotoPosition) {
        let controller = CaptureController(position:position,nearCM:record.readingDistance) { [weak self] frame in
            guard let self = self else { return }
            self.dismiss(animated:true) { self.process(frame,position:position) }
        }
        let navigation = UINavigationController(rootViewController:controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation,animated:true)
    }
    private func process(_ frame:CapturedFrame,position:PhotoPosition) {
        view.isUserInteractionEnabled = false
        let spinner = UIActivityIndicatorView(style:.large); spinner.center = view.center; spinner.startAnimating(); view.addSubview(spinner)
        DispatchQueue.global(qos:.userInitiated).async {
            let detection = FrameDetection.analyze(frame.image,position:position)
            DispatchQueue.main.async {
                self.view.isUserInteractionEnabled = true; spinner.removeFromSuperview()
                var metadata = FitPhoto(file:"",position:position,width:Double(frame.image.size.width),height:Double(frame.image.size.height))
                metadata.points = detection.points; metadata.automatic = Array(detection.points.keys)
                metadata.rearFlashFired = frame.fired; metadata.gravityX = frame.gravity?.x; metadata.gravityY = frame.gravity?.y; metadata.detectionMessage = detection.message
                do { self.record = try self.store.attach(frame.image,metadata:metadata,to:self.record); self.refresh(); self.review(position,outlines:detection.outlines) }
                catch { self.showMessage(error.localizedDescription) }
            }
        }
    }
    private func review(_ position:PhotoPosition,outlines:[[FitPoint]] = []) {
        guard let photo = record.photos[position.rawValue], let image = store.image(for:photo) else { showMessage("사진을 읽지 못했습니다. 다시 촬영하세요."); return }
        let controller = ReviewController(photo:photo,image:image,outlines:outlines) { [weak self] edited in
            guard let self = self else { return }
            var next = self.record; next.photos[position.rawValue] = edited
            try self.store.save(next); self.record = next; self.refresh()
        }
        navigationController?.pushViewController(controller,animated:true)
    }
}
