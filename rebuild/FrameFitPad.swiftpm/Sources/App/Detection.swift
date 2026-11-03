import UIKit
import Vision

struct Detection {
    var points: [String:FitPoint] = [:]
    var outlines: [[FitPoint]] = []
    var message = ""
}
enum FrameDetection {
    static func analyze(_ image: UIImage, position: PhotoPosition) -> Detection {
        guard let cg = image.cgImage else { return Detection(message:"사진을 읽지 못했습니다") }
        var result = Detection()
        let faces = VNDetectFaceLandmarksRequest()
        let edges = VNDetectContoursRequest()
        edges.maximumImageDimension = 1024; edges.contrastAdjustment = 1.4; edges.detectsDarkOnLight = true
        do { try VNImageRequestHandler(cgImage:cg,orientation:.up).perform(position.frontal ? [faces,edges] : [edges]) }
        catch { return Detection(message:"자동 인식 실패. 기준점을 직접 지정하세요.") }
        if let observation = edges.results?.first {
            func walk(_ contour: VNContour) {
                let points = contour.normalizedPoints.map { FitPoint(x:Double($0.x),y:1-Double($0.y)) }
                if points.count >= 12 { result.outlines.append(points) }
                for child in contour.childContours { walk(child) }
            }
            for contour in observation.topLevelContours { walk(contour) }
        }
        guard position.frontal else {
            result.message = position.side ? "윤곽은 안내용입니다. 렌즈 후면 위·아래와 각막 꼭짓점을 직접 지정하세요." : "윤곽은 안내용입니다. 양쪽 렌즈 후면의 코쪽·귀쪽 방향점을 직접 지정하세요."
            return result
        }
        guard faces.results?.count == 1, let face = faces.results?.first, let marks = face.landmarks, abs(face.yaw?.doubleValue ?? 0) < 0.15 else { result.message = "한 명의 얼굴을 정면으로 맞춰주세요. 자동 후보가 없으면 직접 지정할 수 있습니다."; return result }
        func center(_ region: VNFaceLandmarkRegion2D?) -> FitPoint? {
            guard let region = region, region.pointCount > 0 else { return nil }
            var x = 0.0, y = 0.0
            for p in region.normalizedPoints { x += Double(p.x); y += Double(p.y) }
            x /= Double(region.pointCount); y /= Double(region.pointCount)
            return FitPoint(x:Double(face.boundingBox.minX)+x*Double(face.boundingBox.width),y:1-(Double(face.boundingBox.minY)+y*Double(face.boundingBox.height)))
        }
        let pupils = [center(marks.leftPupil),center(marks.rightPupil)].compactMap{$0}.sorted{$0.x<$1.x}
        if pupils.count == 2 { result.points[FitLandmark.rightPupil.rawValue] = pupils[0]; result.points[FitLandmark.leftPupil.rawValue] = pupils[1] }
        let eyes = [center(marks.leftEye),center(marks.rightEye)].compactMap{$0}.sorted{$0.x<$1.x}
        if eyes.count == 2 {
            if let pair = LensCandidates.pair(contours:result.outlines,eyes:eyes,aspect:Double(cg.width)/Double(cg.height)) {
                for (index,box) in [pair.right,pair.left].enumerated() {
                    let keys:[FitLandmark] = index == 0 ? [.rightOuter,.rightInner,.rightTop,.rightBottom] : [.leftInner,.leftOuter,.leftTop,.leftBottom]
                    let positions = [FitPoint(x:box.left,y:box.center.y),FitPoint(x:box.right,y:box.center.y),FitPoint(x:box.center.x,y:box.top),FitPoint(x:box.center.x,y:box.bottom)]
                    for (key,p) in zip(keys,positions) { result.points[key.rawValue] = p }
                }
            }
            for i in 0..<2 {
                if let reflection = brightCandidate(cg,eye:eyes[i],width:(eyes[1].x-eyes[0].x)*0.28) {
                    result.points[(i == 0 ? FitLandmark.rightReflection : .leftReflection).rawValue] = reflection
                }
            }
        }
        result.message = "주황색은 미확인 자동 후보입니다. 동공과 실제 렌즈 경계를 확대 확인하세요. 반사 후보는 렌즈 반사일 수도 있으며 PD 계산에 사용하지 않습니다."
        return result
    }
    private static func brightCandidate(_ image:CGImage,eye:FitPoint,width:Double)->FitPoint? {
        let rect = CGRect(x:(eye.x-width/2)*Double(image.width),y:eye.y*Double(image.height)-width*Double(image.width)/4,width:width*Double(image.width),height:width*Double(image.width)/2).integral.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
        guard !rect.isNull, let crop = image.cropping(to:rect) else { return nil }
        let w = crop.width, h = crop.height
        var pixels = [UInt8](repeating:0,count:w*h*4)
        let drew = pixels.withUnsafeMutableBytes { memory -> Bool in
            guard let ctx = CGContext(data:memory.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
            ctx.draw(crop,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        guard drew else { return nil }
        var best: (Double,Int,Int)?
        var saturated = 0
        for y in 0..<h { for x in 0..<w {
            let i = (y*w+x)*4
            if min(pixels[i],min(pixels[i+1],pixels[i+2])) > 245 {
                saturated += 1
                let distance = hypot(Double(x)-Double(w)/2,Double(y)-Double(h)/2)
                if best == nil || distance < best!.0 { best = (distance,x,y) }
            }
        }}
        guard saturated < max(3,w*h/25), let best = best else { return nil }
        return FitPoint(x:(rect.minX+Double(best.1))/Double(image.width),y:(rect.minY+Double(best.2))/Double(image.height))
    }
}
