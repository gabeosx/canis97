// Offscreen CALayer primitive checks. No NSView, NSApplication or test host.
import Foundation
import CoreGraphics
import QuartzCore

@main struct SpriteAtlasGeometryChecks {
    static func main() {
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        func context(_ side:Int)->CGContext {CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!}
        let source=context(64)
        for (i,color) in [[1.0,0,0],[0,1.0,0],[0,0,1.0],[1.0,1.0,0]].enumerated() {
            source.setFillColor(CGColor(red:color[0],green:color[1],blue:color[2],alpha:1))
            source.fill(CGRect(x:(i%2)*32,y:(i/2)*32,width:32,height:32))
        }
        let image=source.makeImage()!
        func center(_ image:CGImage)->[UInt8] {
            let c=context(16);c.draw(image,in:CGRect(x:0,y:0,width:16,height:16))
            let bytes=c.data!.assumingMemoryBound(to:UInt8.self)
            return (0..<4).map{bytes[(8*16+8)*4+$0]}
        }
        for row in 0..<2 {for col in 0..<2 {
            let root=CALayer();root.bounds=CGRect(x:0,y:0,width:32,height:32);root.isGeometryFlipped=true
            let sprite=CALayer();sprite.frame=root.bounds;sprite.contents=image;sprite.contentsGravity = .resize
            sprite.contentsRect=CGRect(x:Double(col)/2,y:Double(row)/2,width:0.5,height:0.5)
            root.addSublayer(sprite)
            let out=context(32);root.render(in:out)
            let expected=image.cropping(to:CGRect(x:col*32,y:row*32,width:32,height:32))!
            precondition(center(out.makeImage()!)==center(expected),"Atlas rectangle orientation mismatch")
        }}
        print("PASS: four atlas cells render in the same top-left source-rectangle order as CoreGraphics cropping; offscreen CALayer only")
    }
}
