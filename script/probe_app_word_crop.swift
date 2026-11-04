import Foundation
import CoreImage
import ImageIO
let folder=URL(fileURLWithPath:CommandLine.arguments[1])
let words=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("word-geometry.json"))) as! [[String:Any]]
let w=words.first{$0["text"] as? String == "beautifull"}!
let r=w["rect"] as! [String:Double]
let image=CIImage(data:try Data(contentsOf:folder.appendingPathComponent("source.png")))!
let e=image.extent
let rect=CGRect(x:r["x"]!*e.width,y:(1-r["y"]!-r["height"]!)*e.height,width:r["width"]!*e.width,height:r["height"]!*e.height).insetBy(dx:-8,dy:-12).integral.intersection(e)
let cg=CIContext().createCGImage(image.cropped(to:rect),from:rect)!
let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[2]) as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(dest,cg,nil);CGImageDestinationFinalize(dest)
print(rect)
