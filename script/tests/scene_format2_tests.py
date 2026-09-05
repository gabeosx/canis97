#!/usr/bin/env python3
"""Production scene codec and director checks in a standalone, offline CLI."""
from pathlib import Path
import subprocess, tempfile, json, hashlib
ROOT=Path(__file__).resolve().parent;REPO=ROOT.parents[1];SKIN=REPO/'SiriusMac/Skins/Bundled'
def region(s,b,e):return s[s.index(b):s.index(e,s.index(b))]
def source(include_view=False):
 r=(REPO/'SiriusMac/Motion/AnimatedSkinRuntime.swift').read_text();a=(REPO/'SiriusMac/Skins/SkinAppearance.swift').read_text()
 return 'import Foundation\nimport AppKit\nimport QuartzCore\n'+region(a,'struct CompactSkinRect:','/// The only three typography')+region(a,'enum SkinMotionEvent:','struct SkinMotionRange:')+region(r,'struct AnimatedSkinEventTrigger:','/// Lottie is deliberately')+region(r,'enum SpriteMotionSceneFailure:','/// This deliberately tiny adapter' if include_view else '@MainActor\nprivate final class SpriteMotionSceneView:')
DRIVER=r'''
import Foundation
import ImageIO
@main struct Check {
 static func main() throws {
  let skin=URL(fileURLWithPath:CommandLine.arguments[1]),package=skin
  let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:package.appendingPathComponent("Abyssal97.json"))) as! [String:Any]
  let motion=manifest["motion"] as! [String:Any],allowed=Set(motion["spriteAssets"] as! [String])
  let data=try Data(contentsOf:package.appendingPathComponent("Abyssal97.scene.json"))
  let decoded=try SpriteMotionSceneCodec.decode(data,allowedAssets:allowed)
  var atlasURLs = Dictionary(uniqueKeysWithValues: allowed.map { ($0, package.appendingPathComponent("Assets/Abyssal97/"+$0)) })
  try SpriteMotionSceneCodec.validateAtlasDimensions(decoded, assets: atlasURLs)
  let invalidGrid = URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("nondivisible.png")
  let imageContext = CGContext(data:nil,width:3,height:3,bitsPerComponent:8,bytesPerRow:12,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  let imageDestination = CGImageDestinationCreateWithURL(invalidGrid as CFURL,"public.png" as CFString,1,nil)!
  CGImageDestinationAddImage(imageDestination,imageContext.makeImage()!,nil)
  precondition(CGImageDestinationFinalize(imageDestination))
  atlasURLs[decoded.layers.first { $0.atlas != nil }!.asset] = invalidGrid
  do { try SpriteMotionSceneCodec.validateAtlasDimensions(decoded,assets:atlasURLs);fatalError("Nondivisible atlas accepted") }
  catch is SpriteMotionSceneFailure { }
  let base=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  var checks=0
  func reject(_ mutate:(inout [String:Any])->Void) throws {
   var root=base;mutate(&root)
   do { _ = try SpriteMotionSceneCodec.decode(JSONSerialization.data(withJSONObject:root),allowedAssets:allowed);fatalError("Invalid scene accepted: case \(checks)") }
   catch is SpriteMotionSceneFailure {checks+=1}
  }
  func layers(_ root:inout [String:Any],_ edit:(inout [[String:Any]])->Void){var l=root["layers"] as! [[String:Any]];edit(&l);root["layers"]=l}
  func performances(_ root:inout [String:Any],_ edit:(inout [[String:Any]])->Void){var p=root["performances"] as! [[String:Any]];edit(&p);root["performances"]=p}
  try reject{$0["script"]="forbidden"}
  try reject{$0["formatVersion"]=3}
  try reject{$0["formatVersion"]=1}
  try reject{$0["director"]=NSNull()}
  try reject{layers(&$0){$0[0]["asset"]="https://example.invalid/evil.png"}}
  try reject{layers(&$0){$0[0]["frame"]=["x":Int.max,"y":0,"width":2,"height":2]}}
  try reject{layers(&$0){$0[0]["identifier"]=$0[1]["identifier"]}}
  try reject{layers(&$0){$0 += $0}}
  try reject{performances(&$0){$0 += $0}}
  try reject{performances(&$0){$0[0]["duration"]=31}}
  try reject{performances(&$0){$0[0]["actor"]="../unsafe"}}
  try reject{performances(&$0){$0[0]["identifier"]=$0[1]["identifier"]}}
  try reject{performances(&$0){$0[0]["tier"]=NSNull()}}
  try reject{performances(&$0){$0[0]["expression"]="forbidden"}}
  let atlasIndex=decoded.layers.firstIndex{$0.atlas != nil}!
  for atlas in [["columns":0,"rows":4,"frameCount":16],["columns":Int.max,"rows":4,"frameCount":16],["columns":4,"rows":4,"frameCount":65]] {
   try reject{layers(&$0){$0[atlasIndex]["atlas"]=atlas}}
  }
  let posePerformance=(decoded.performances!).firstIndex{$0.tracks[0].poseCycle != nil}!
  for mutation in 0..<8 {
   try reject{performances(&$0){p in
    var tracks=p[posePerformance]["tracks"] as! [[String:Any]],cycle=tracks[0]["poseCycle"] as! [String:Any]
    switch mutation {
    case 0:cycle["framesPerSecond"]=100
    case 1:cycle["frames"]=[-1,0]
    case 2:cycle["frames"]=[0,999]
    case 3:cycle["frames"]=Array(repeating:0,count:257)
    case 4:cycle["shader"]="forbidden"
    case 5:tracks[0]["layerID"]="missing"
    case 6:var keys=tracks[0]["timeline"] as! [[String:Any]];keys[0]["time"]=1;tracks[0]["timeline"]=keys
    default:var keys=tracks[0]["timeline"] as! [[String:Any]];keys[keys.count-1]["opacity"]=1;tracks[0]["timeline"]=keys
    }
    tracks[0]["poseCycle"]=cycle;p[posePerformance]["tracks"]=tracks
   }}
  }
  for fixed in ["vessel_fixed","frame_fixed","song_jar","channel_beacon"] {precondition(decoded.layers.first{$0.identifier==fixed}!.timeline==nil)}
  var imagePixels=0, checkedCells=Set<String>()
  for asset in allowed {
   let image=CGImageSourceCreateWithURL(package.appendingPathComponent("Assets/Abyssal97/"+asset) as CFURL,nil)!
   precondition(CGImageSourceGetCount(image)==1)
   let cg=CGImageSourceCreateImageAtIndex(image,0,nil)!
   precondition(cg.width<=4096 && cg.height<=4096);imagePixels+=cg.width*cg.height
   for layer in decoded.layers where layer.asset==asset {
    if let atlas=layer.atlas {
     precondition(cg.width%atlas.columns==0 && cg.height%atlas.rows==0)
     let w=cg.width/atlas.columns,h=cg.height/atlas.rows
     for frame in 0..<atlas.frameCount where checkedCells.insert("\(asset):\(frame)").inserted {
      let cell=cg.cropping(to:CGRect(x:(frame%atlas.columns)*w,y:(frame/atlas.columns)*h,width:w,height:h))!
      var pixels=[UInt8](repeating:0,count:w*h*4)
      pixels.withUnsafeMutableBytes { bytes in
       let c=CGContext(data:bytes.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
       c.draw(cell,in:CGRect(x:0,y:0,width:w,height:h))
      }
      precondition(pixels.enumerated().contains{$0.offset%4==3 && $0.element>12})
      for y in 0..<h {for x in 0..<w where x==0 || x==w-1 || y==0 || y==h-1 {
       precondition(pixels[(y*w+x)*4+3]<=12,"Clipped atlas cell: \(asset) \(frame)")
      }}
     }
    }
   }
  }
  precondition(checkedCells.count==144)
  // Read actual old documents through the updated decoder.
  for path in ["Exit97.scene.json", "QuartzDeck.scene.json"] {
   let old=try Data(contentsOf:skin.appendingPathComponent(path))
   let raw=try JSONSerialization.jsonObject(with:old) as! [String:Any]
   let oldAssets=Set((raw["layers"] as! [[String:Any]]).map{$0["asset"] as! String})
   precondition(try SpriteMotionSceneCodec.decode(old,allowedAssets:oldAssets).formatVersion==1)
  }
  for seed in [UInt64(1),5,42,97,123,2026] {
   let original=try decoded.performancePlan()!
   let plan=try ScenePerformancePlan(seed:seed,cadences:original.cadences,performances:original.performances,rest:original.rest)
   var director=ScenePerformanceDirector(plan:plan),time=0.0,last:ScenePerformanceDirector.Selection?,seen=Set<String>()
   while time<8*3600 {
    // Half-hour blocks exercise both ordinary and saved-specimen visits.
    let context=ScenePerformanceDirector.Context(songFavorite:Int(time/1800)%2==1)
    if let s=director.next(activeTime:time,context:context) {
     if let p=last {precondition(s.startedAt>=p.endsAt+6 && s.actor != p.actor && s.startedAt-p.endsAt<=90)}
     seen.insert(s.identifier);last=s
    }
    guard let delay=director.nextWakeDelay(activeTime:time,context:context) else {fatalError("Starvation")}
    time+=min(delay,1800-time.truncatingRemainder(dividingBy:1800))
   }
   precondition(seen.count==original.performances.count)
  }
  print("PASS: production scene v1/v2 codec, \(checks) hostile-document cases, 144 nonempty unclipped atlas cells, stationary lighting, six actual-repertoire eight-hour schedules; \(imagePixels*4) decoded RGBA bytes")
 }
}
'''
def run():
 with tempfile.TemporaryDirectory(prefix='abyssal97-v3-validation-',dir='/private/tmp') as d:
  d=Path(d);(d/'Scene.swift').write_text(source());(d/'Check.swift').write_text(DRIVER.replace('precondition(try SpriteMotionSceneCodec.decode(old,allowedAssets:oldAssets).formatVersion==1)','let oldDecoded = try SpriteMotionSceneCodec.decode(old,allowedAssets:oldAssets);precondition(oldDecoded.formatVersion == (path == "Exit97.scene.json" ? 2 : 1))'))
  director=REPO/'Packages/Canis97MotionSafety/Sources/Canis97MotionSafety/ScenePerformanceDirector.swift'
  subprocess.run(['swiftc','-O','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(d/'cache'),str(director),str(d/'Scene.swift'),str(d/'Check.swift'),'-o',str(d/'check')],check=True)
  result=subprocess.run([str(d/'check'),str(SKIN),str(d)],text=True,capture_output=True,check=True);print(result.stdout,end='')
  (d/'Runtime.swift').write_text(source(True))
  subprocess.run(['swiftc','-parse-as-library','-emit-module','-module-name','SceneBuildCheck','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(d/'cache'),'-emit-module-path',str(d/'SceneBuildCheck.swiftmodule'),str(director),str(d/'Runtime.swift')],check=True)
  check_animation_methods(d)
  print('PASS: complete production sprite view + codec compile, Swift 6 strict concurrency, warnings as errors; no app/test host launched')


def check_animation_methods(d):
 r=(REPO/'SiriusMac/Motion/AnimatedSkinRuntime.swift').read_text()
 methods='\n'.join([region(r,'    private func applyPersistentVisibility(', '    private func play('),region(r,'    private func animation(', '    private func baseOpacity('),region(r,'    private func runPerformance(', '    private func playPerformanceEvent(')])
 # atlasRect ends immediately before playPerformanceEvent in production.
 harness='''
import AppKit
import QuartzCore
// Unattached layers discard animations at transaction commit. Capture the
// exact animations passed by production code without creating an app/window.
final class RecordingLayer: CALayer {
 var recorded: [String:CAAnimation] = [:]
 override func add(_ animation: CAAnimation, forKey key: String?) {
  if let key { recorded[key] = animation.copy() as? CAAnimation }
 }
 override func removeAnimation(forKey key: String) { recorded.removeValue(forKey:key) }
 override func animation(forKey key: String) -> CAAnimation? { recorded[key] }
}
@MainActor final class AnimationHarness {
 var sceneLayer = CALayer()
 var layersByID: [String:CALayer] = [:]
 var modelByID: [String:SpriteMotionSceneDocument.Layer] = [:]
 var isSongFavorite = true
 var isChannelFavorite = false
'''+methods+'''
 func verify(_ scene: SpriteMotionSceneDocument) {
  let model = scene.layers.first { $0.atlas != nil }!
  modelByID[model.identifier] = model
  let layer = RecordingLayer();layersByID[model.identifier] = layer
  let original = scene.performances!.first { $0.tracks.first?.poseCycle != nil }!
  // Use production Codable types with a short finite sequence inside a long performance.
  let rawScene=try! JSONSerialization.jsonObject(with:Data(contentsOf:package.appendingPathComponent("Abyssal97.scene.json"))) as! [String:Any]
  var object=(rawScene["performances"] as! [[String:Any]]).first { $0["identifier"] as? String == original.identifier }!
  var tracks=object["tracks"] as! [[String:Any]];tracks=Array(tracks.prefix(1))
  tracks[0]["poseCycle"]=["frames":[0,2,5],"framesPerSecond":8,"loops":false];object["tracks"]=tracks
  let performance=try! JSONDecoder().decode(SpriteMotionSceneDocument.Performance.self,from:JSONSerialization.data(withJSONObject:object))
  runPerformance(performance)
  let group=layer.animation(forKey:"sprite-performance") as! CAAnimationGroup
  let pose=group.animations!.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath=="contentsRect" }!
  precondition(pose.calculationMode == .discrete && pose.values!.count==3 && pose.keyTimes!.count==4)
  precondition((pose.values!.last as! NSValue).rectValue == atlasRect(5,atlas:model.atlas!))
  precondition(pose.duration==0.375 && pose.repeatCount==0 && pose.fillMode == .forwards)
  let favorite=scene.layers.first { $0.role == .persistentSongFavorite }!
  modelByID=[favorite.identifier:favorite];layersByID=[favorite.identifier:layer]
  for saved in [true,false] {
   isSongFavorite=saved;layer.opacity=saved ? 1:0
   let fade=CABasicAnimation(keyPath:"opacity");fade.fromValue=0.4;fade.toValue=layer.opacity;fade.duration=20
   layer.add(fade,forKey:"persistent-fade")
   applyPersistentVisibility(animated:false)
   precondition(layer.animation(forKey:"persistent-fade")==nil && layer.opacity==(saved ? 1:0))
  }
 }
}
let package=URL(fileURLWithPath:CommandLine.arguments[1])
let raw=try! JSONSerialization.jsonObject(with:Data(contentsOf:package.appendingPathComponent("Abyssal97.json"))) as! [String:Any]
let allowed=Set((raw["motion"] as! [String:Any])["spriteAssets"] as! [String])
let scene=try! SpriteMotionSceneCodec.decode(Data(contentsOf:package.appendingPathComponent("Abyssal97.scene.json")),allowedAssets:allowed)
MainActor.assumeIsolated { AnimationHarness().verify(scene) }
print("PASS: production discrete pose intervals, finite terminal frame, and immediate paused favorite truth; offscreen CALayer only")
'''
 (d/'main.swift').write_text(harness)
 subprocess.run(['swiftc','-Onone','-g','-swift-version','6','-module-cache-path',str(d/'cache'),str(REPO/'Packages/Canis97MotionSafety/Sources/Canis97MotionSafety/ScenePerformanceDirector.swift'),str(d/'Scene.swift'),str(d/'main.swift'),'-o',str(d/'animation-check')],check=True)
 subprocess.run([str(d/'animation-check'),str(SKIN)],check=True)

if __name__=='__main__':run()
