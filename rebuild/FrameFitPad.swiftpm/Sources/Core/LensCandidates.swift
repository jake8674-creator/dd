import Foundation

struct LensBounds:Equatable {
    var left:Double;var top:Double;var right:Double;var bottom:Double
    var width:Double{right-left};var height:Double{bottom-top}
    var center:FitPoint{FitPoint(x:(left+right)/2,y:(top+bottom)/2)}
    func contains(_ p:FitPoint)->Bool{p.x>left && p.x<right && p.y>top && p.y<bottom}
}
struct LensPair {
    var right:LensBounds
    var left:LensBounds
}
enum LensCandidates {
    // Geometry filter, not a trained spectacle segmentation model. Every result still needs review.
    static func pair(contours:[[FitPoint]],eyes:[FitPoint],aspect:Double)->LensPair?{
        guard eyes.count==2,eyes.allSatisfy(\.finite),aspect.isFinite,aspect>0 else{return nil}
        let sorted=eyes.sorted{$0.x<$1.x},separation=sorted[1].x-sorted[0].x
        guard separation>0.03,abs(sorted[1].y-sorted[0].y)<separation*aspect*0.3 else{return nil}
        func candidates(_ eye:FitPoint)->[(LensBounds,Double)] {
            contours.compactMap { points -> (LensBounds,Double)? in
                guard points.count>=12,points.allSatisfy({$0.finite && (0...1).contains($0.x) && (0...1).contains($0.y)}),let first=points.first,let last=points.last,(first-last).length<0.025 else{return nil}
                let xs=points.map(\.x),ys=points.map(\.y)
                let b=LensBounds(left:xs.min()!,top:ys.min()!,right:xs.max()!,bottom:ys.max()!)
                guard b.contains(eye),inside(eye,polygon:points),b.width>separation*0.45,b.width<separation*1.1,
                      b.height>separation*aspect*0.25,b.height<separation*aspect*0.95 else{return nil}
                let centerDistance=hypot(b.center.x-eye.x,(b.center.y-eye.y)/aspect)/separation
                return (b,centerDistance+abs(b.width/separation-0.75)*0.2)
            }.sorted{$0.1<$1.1}.prefix(12).map{$0}
        }
        let right=candidates(sorted[0]),left=candidates(sorted[1])
        var best:(LensPair,Double)?
        for r in right {for l in left {
            let gap=l.0.left-r.0.right
            guard gap>separation*0.04,gap<separation*0.6,
                  min(r.0.width,l.0.width)/max(r.0.width,l.0.width)>0.8,
                  min(r.0.height,l.0.height)/max(r.0.height,l.0.height)>0.7,
                  abs(r.0.center.y-l.0.center.y)<separation*aspect*0.2 else{continue}
            let score=r.1+l.1+abs(r.0.width-l.0.width)/separation+abs(r.0.height-l.0.height)/(separation*aspect)
            if best==nil || score<best!.1{best=(LensPair(right:r.0,left:l.0),score)}
        }}
        return best?.0
    }
    private static func inside(_ p:FitPoint,polygon:[FitPoint])->Bool {
        var result=false
        var previous=polygon.last!
        for current in polygon {
            if (current.y>p.y) != (previous.y>p.y) && p.x<(previous.x-current.x)*(p.y-current.y)/(previous.y-current.y)+current.x {result.toggle()}
            previous=current
        }
        return result
    }
}
