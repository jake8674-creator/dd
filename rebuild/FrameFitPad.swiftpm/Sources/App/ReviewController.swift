import UIKit

@MainActor
final class MarkerCanvas: UIView {
    let image: UIImage
    var photo: FitPhoto { didSet { setNeedsDisplay() } }
    var selected: FitLandmark { didSet { setNeedsDisplay() } }
    var outlines: [[FitPoint]] = [] { didSet { setNeedsDisplay() } }
    var showOutlines = false { didSet { setNeedsDisplay() } }
    var moved: ((FitPoint)->Void)?
    init(image:UIImage,photo:FitPhoto) {
        self.image = image; self.photo = photo; selected = photo.position.required[0]
        super.init(frame:.zero); backgroundColor = .black
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(touch(_:))))
        addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(touch(_:))))
    }
    required init?(coder:NSCoder) { fatalError("Programmatic UI") }
    private var fitted: CGRect {
        let scale = min(bounds.width/image.size.width,bounds.height/image.size.height)
        let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
        return CGRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
    }
    override func draw(_ rect:CGRect) {
        let frame = fitted
        image.draw(in:frame)
        if showOutlines {
            UIColor.cyan.withAlphaComponent(0.5).setStroke()
            for outline in outlines {
                guard let first = outline.first else { continue }
                let path = UIBezierPath(); path.lineWidth = 1
                path.move(to:CGPoint(x:frame.minX+first.x*frame.width,y:frame.minY+first.y*frame.height))
                for p in outline.dropFirst() { path.addLine(to:CGPoint(x:frame.minX+p.x*frame.width,y:frame.minY+p.y*frame.height)) }
                path.stroke()
            }
        }
        for key in photo.position.editable {
            guard let point = photo.points[key.rawValue] else { continue }
            let center = CGPoint(x:frame.minX+point.x*frame.width,y:frame.minY+point.y*frame.height)
            let radius:CGFloat = key == selected ? 13 : 7
            let color:UIColor = key == selected ? .white : (photo.reviewed.contains(key.rawValue) ? .systemGreen : .systemOrange)
            color.setStroke()
            let ring = UIBezierPath(ovalIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)); ring.lineWidth = 2; ring.stroke()
            let cross = UIBezierPath(); cross.move(to:CGPoint(x:center.x-4,y:center.y)); cross.addLine(to:CGPoint(x:center.x+4,y:center.y)); cross.move(to:CGPoint(x:center.x,y:center.y-4)); cross.addLine(to:CGPoint(x:center.x,y:center.y+4)); cross.stroke()
        }
    }
    @objc private func touch(_ gesture:UIGestureRecognizer) {
        let p = gesture.location(in:self), frame = fitted
        guard frame.width > 0, frame.height > 0, frame.contains(p) else { return }
        moved?(FitPoint(x:Double((p.x-frame.minX)/frame.width),y:Double((p.y-frame.minY)/frame.height)))
    }
    func crop(at p:FitPoint)->UIImage {
        let size = CGSize(width:140,height:140)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size:size,format:format).image { _ in
            UIColor.black.setFill(); UIRectFill(CGRect(origin:.zero,size:size))
            image.draw(at:CGPoint(x:70-p.x*image.size.width,y:70-p.y*image.size.height))
            UIColor.systemRed.setStroke()
            let cross = UIBezierPath(); cross.move(to:CGPoint(x:60,y:70)); cross.addLine(to:CGPoint(x:80,y:70)); cross.move(to:CGPoint(x:70,y:60)); cross.addLine(to:CGPoint(x:70,y:80)); cross.stroke()
        }
    }
}

@MainActor
final class ReviewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private var photo: FitPhoto
    private let image: UIImage
    private let onSave: (FitPhoto)throws->Void
    private let canvas: MarkerCanvas
    private let list = UITableView(frame:.zero,style:.plain)
    private let zoom = UIImageView()
    private let label = UILabel()
    private let note = UILabel()
    private let confirm = UIButton(type:.system)
    private let posture = UISwitch()
    private var selected: FitLandmark { didSet { canvas.selected = selected; refresh() } }
    init(photo:FitPhoto,image:UIImage,outlines:[[FitPoint]]=[],onSave:@escaping(FitPhoto)throws->Void) {
        self.photo = photo; self.image = image; self.onSave = onSave; selected = photo.position.required[0]
        canvas = MarkerCanvas(image:image,photo:photo); canvas.outlines = outlines
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) { fatalError("Programmatic UI") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "기준점 확인"; view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title:"저장",style:.done,target:self,action:#selector(save))
        label.font = .preferredFont(forTextStyle:.headline); label.numberOfLines = 0
        note.text = photo.detectionMessage; note.font = .preferredFont(forTextStyle:.caption1); note.numberOfLines = 0
        zoom.contentMode = .scaleAspectFit; zoom.backgroundColor = .black
        zoom.heightAnchor.constraint(equalToConstant:140).isActive = true
        list.dataSource = self; list.delegate = self; list.rowHeight = 45
        confirm.setTitle("선택한 점 확인 → 다음",for:.normal); confirm.configuration = .filled(); confirm.addTarget(self,action:#selector(acceptPoint),for:.touchUpInside)
        posture.isOn = photo.postureAccepted; posture.addTarget(self,action:#selector(postureChanged),for:.valueChanged)
        let poseLabel = UILabel(); poseLabel.text = "촬영 자세 확인"; poseLabel.font = .preferredFont(forTextStyle:.callout)
        let poseRow = UIStackView(arrangedSubviews:[poseLabel,posture]); poseRow.spacing = 8
        let outlineSwitch = UISwitch(); outlineSwitch.addTarget(self,action:#selector(outlinesChanged(_:)),for:.valueChanged)
        let outlineLabel = UILabel(); outlineLabel.text = "윤곽 후보 보기"; outlineLabel.font = .preferredFont(forTextStyle:.callout)
        let outlineRow = UIStackView(arrangedSubviews:[outlineLabel,outlineSwitch])
        let sidebar = UIStackView(arrangedSubviews:[label,zoom,note,list,confirm,poseRow,outlineRow]); sidebar.axis = .vertical; sidebar.spacing = 10
        sidebar.widthAnchor.constraint(equalToConstant:290).isActive = true
        let layout = UIStackView(arrangedSubviews:[canvas,sidebar]); layout.axis = .horizontal; layout.spacing = 12; layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        NSLayoutConstraint.activate([layout.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:12),layout.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:12),layout.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-12),layout.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-12)])
        canvas.moved = { [weak self] point in guard let self = self else { return }; self.photo.move(self.selected,to:point); self.canvas.photo = self.photo; self.refresh() }
        refresh()
    }
    private func refresh() {
        guard isViewLoaded else { return }
        label.text = selected.title+"\n사진을 탭하거나 끌어 지정"
        zoom.image = photo.points[selected.rawValue].map{canvas.crop(at:$0)}
        confirm.isEnabled = photo.points[selected.rawValue] != nil
        list.reloadData()
        navigationItem.rightBarButtonItem?.title = photo.allReviewed ? "확인 완료" : "중간 저장"
    }
    func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int { photo.position.editable.count }
    func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell {
        let key = photo.position.editable[indexPath.row]
        let cell = UITableViewCell(style:.default,reuseIdentifier:nil)
        cell.textLabel?.text = key.title; cell.textLabel?.font = .preferredFont(forTextStyle:.caption1)
        cell.accessoryType = photo.reviewed.contains(key.rawValue) ? .checkmark : .none
        cell.backgroundColor = key == selected ? .systemTeal.withAlphaComponent(0.15) : .clear
        return cell
    }
    func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath) { selected = photo.position.editable[indexPath.row] }
    @objc private func acceptPoint() {
        guard photo.points[selected.rawValue]?.valid == true else { return }
        if !photo.reviewed.contains(selected.rawValue) { photo.reviewed.append(selected.rawValue) }
        canvas.photo = photo
        if let i = photo.position.editable.firstIndex(of:selected), i+1 < photo.position.editable.count { selected = photo.position.editable[i+1] }
        refresh()
    }
    @objc private func postureChanged() { photo.postureAccepted = posture.isOn; refresh() }
    @objc private func outlinesChanged(_ sender:UISwitch) { canvas.showOutlines = sender.isOn }
    @objc private func save() { do { try onSave(photo); navigationController?.popViewController(animated:true) } catch { showMessage(error.localizedDescription) } }
}
