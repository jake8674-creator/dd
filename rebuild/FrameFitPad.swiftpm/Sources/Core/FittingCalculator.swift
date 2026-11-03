import Foundation

enum FittingCalculator {
    static func prerequisite(_ p: FitPhoto) -> String? {
        guard p.width.isFinite, p.height.isFinite, p.width > 0, p.height > 0 else { return "사진 크기 오류" }
        guard p.position == .reading || p.rearFlashFired else { return "후면 플래시 발광 확인 필요" }
        guard p.allReviewed else { return "필수 기준점과 자세를 확인하세요" }
        return nil
    }
    static func frontal(_ session: FitSession, position: PhotoPosition) -> [FitResult] {
        let names = ["양안 PD", "R 테 중심거리", "L 테 중심거리", "R 피팅 높이", "L 피팅 높이"]
        func blank(_ note: String) -> [FitResult] { names.map { FitResult(name: position.title + " · " + $0, unit: "mm", note: note) } }
        guard position.frontal, let photo = session.photos[position.rawValue] else { return blank("촬영 필요") }
        if let failure = prerequisite(photo) { return blank(failure) }
        guard let a = FitSession.number(session.lensWidth), let bridge = FitSession.number(session.bridgeWidth), (30...80).contains(a), (5...40).contains(bridge) else { return blank("실측 A·DBL을 입력하세요") }
        guard let ro = photo.pixel(.rightOuter), let ri = photo.pixel(.rightInner), let lo = photo.pixel(.leftOuter), let li = photo.pixel(.leftInner), let rp = photo.pixel(.rightPupil), let lp = photo.pixel(.leftPupil), let rt = photo.pixel(.rightTop), let rb = photo.pixel(.rightBottom), let lt = photo.pixel(.leftTop), let lb = photo.pixel(.leftBottom) else { return blank("기준점 누락") }
        let span = lo - ro
        let across = span.unit
        let down = PixelVector(x: -across.y, y: across.x)
        guard span.length > photo.width * 0.2, across.x > 0.7 else { return blank("사진 방향·좌우 경계를 다시 확인하세요") }
        let wr = (ri-ro).dot(across), wl = (lo-li).dot(across), gap = (li-ri).dot(across)
        guard wr > 0, wl > 0, gap > 0, min(wr,wl)/max(wr,wl) >= 0.9 else { return blank("좌우 렌즈가 비대칭입니다. 정면을 맞추세요") }
        let mmPerPixel = (2*a+bridge)/span.length
        guard abs(wr*mmPerPixel-a) <= a*0.1, abs(wl*mmPerPixel-a) <= a*0.1, abs(gap*mmPerPixel-bridge) <= max(2,bridge*0.15) else { return blank("렌즈 경계 비율과 A·DBL이 맞지 않습니다") }
        guard (rp-ro).dot(across) > 0, (ri-rp).dot(across) > 0, (lp-li).dot(across) > 0, (lo-lp).dot(across) > 0,
              (rp-rt).dot(down) > 0, (rb-rp).dot(down) > 0, (lp-lt).dot(down) > 0, (lb-lp).dot(down) > 0 else { return blank("동공·렌즈 상하 경계를 다시 확인하세요") }
        let center = (ri+li)*0.5
        let values = [(lp-rp).dot(across), (center-rp).dot(across), (lp-center).dot(across), (rb-rp).dot(down), (lb-lp).dot(down)].map { $0*mmPerPixel }
        guard values.allSatisfy({$0.isFinite && $0 > 0}), (35...90).contains(values[0]) else { return blank("측정 범위 밖입니다") }
        return zip(names,values).map { FitResult(name: position.title+" · "+$0.0, number: $0.1, unit: "mm", note: "2D 사진 추정 · 실측 A/DBL 보정 · 테 중심 기준") }
    }
    static func tilt(_ session: FitSession) -> FitResult {
        let kind: PhotoPosition = session.leftSide ? .left : .right
        var result = FitResult(name: kind.title+" · 경사각", unit: "°", note: "측면 촬영 필요")
        guard let p = session.photos[kind.rawValue] else { return result }
        if let reason = prerequisite(p) { result.note = reason; return result }
        guard let gx = p.gravityX, let gy = p.gravityY, gx.isFinite, gy.isFinite, hypot(gx,gy) > 0.3,
              let top = p.pixel(.lensBackTop), let bottom = p.pixel(.lensBackBottom), let cornea = p.pixel(.cornea) else { result.note = "중력 기준 또는 기준점이 없습니다"; return result }
        let down = PixelVector(x:gx,y:gy).unit
        var forward = PixelVector(x:down.y,y:-down.x)
        if ((top+bottom)*0.5-cornea).dot(forward) < 0 { forward = forward * -1 }
        let vertical = (bottom-top).dot(down)
        guard vertical > p.height*0.03, (cornea-top).dot(down) >= 0, (bottom-cornea).dot(down) >= 0,
              ((top+bottom)*0.5-cornea).dot(forward) > p.width*0.002 else { result.note = "렌즈 후면·각막 위치를 다시 확인하세요"; return result }
        let angle = atan2((top-bottom).dot(forward), vertical)*180/Double.pi
        guard angle.isFinite, abs(angle) <= 40 else { result.note = "경사각 범위 밖입니다"; return result }
        result.number = angle; result.note = "측면 투영값 · 렌즈 아래쪽이 얼굴에 가까우면 +"
        return result
    }
    static func wrap(_ session: FitSession) -> [FitResult] {
        var total = FitResult(name:"전체 감김각",unit:"°",note:"위쪽 촬영 필요")
        var half = FitResult(name:"안면각 · 편측 평균",unit:"°",note:"전체의 절반 · 좌우 개별 각도 아님")
        guard let p = session.photos[PhotoPosition.above.rawValue] else { return [total,half] }
        if let reason = prerequisite(p) { total.note = reason; return [total,half] }
        guard let ro = p.pixel(.rightOuter), let ri = p.pixel(.rightInner), let li = p.pixel(.leftInner), let lo = p.pixel(.leftOuter) else { return [total,half] }
        let r = ri-ro, l = lo-li
        guard r.length > p.width*0.08, l.length > p.width*0.08, r.x > 0, l.x > 0 else { total.note = "렌즈 방향점 확인 필요"; return [total,half] }
        let angle = acos(max(-1,min(1,r.unit.dot(l.unit))))*180/Double.pi
        guard angle.isFinite, angle <= 70 else { total.note = "각도 범위 밖입니다"; return [total,half] }
        total.number = angle; total.note = "상면 투영 추정 · 렌즈 후면 방향"
        half.number = angle/2
        return [total,half]
    }
    static func results(_ session:FitSession) -> [FitResult] {
        frontal(session,position:.distance)+frontal(session,position:.reading)+[tilt(session)]+wrap(session)+[FitResult(name:"정점간거리",unit:"mm",note:"투명 렌즈 후면 깊이 미검증 · 제공 보류")]
    }
}
