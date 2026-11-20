// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers
import Darwin
@main struct Probe {
 static func main() throws {
  func check(_ value:@autoclosure ()->Bool,_ name:String) {
   if !value() {print("FAIL \(name)");fflush(stdout);exit(1)}
   print("PASS \(name)");fflush(stdout)
  }
  let root=CommandLine.arguments[1]
  let empty=URLResourceValues()
  check(empty.allValues.isEmpty && empty.name == nil && empty.contentType == nil,"empty/unrequested values")
  var one=empty;one.name="héllo";one.isPackage=true
  var two=one;two.name="copy";two.isPackage=false
  check(one.name=="héllo" && one.isPackage==true && two.name=="copy" && two.isPackage==false,"value copy and setters")
  let leaves=["document.pdf","pixel.png","note.txt"]
  let expected=["com.adobe.pdf","public.png","public.plain-text"]
  let keys:Set<URLResourceKey>=[.nameKey,.contentTypeKey,.typeIdentifierKey,.fileSizeKey,.isDirectoryKey]
  for (leaf,identifier) in zip(leaves,expected) {
   let url=URL(fileURLWithPath:root+"/"+leaf)
   let values=try url.resourceValues(forKeys:keys)
   check(values.name==leaf,"retained name \(leaf)")
   check(values.typeIdentifier==identifier && values.contentType?.identifier==identifier,"real content getter \(leaf)")
   check(values.fileSize != nil && values.fileSize!>0 && values.isDirectory==false,"real metadata \(leaf)")
   check(values.contentType==UTType(identifier),"Swift UTType equality \(leaf)")
   let object=values.allValues[.contentTypeKey]!
   check((object as AnyObject) === values.contentType!._bridgeToObjectiveC(),"retained content object identity \(leaf)")
   var dictionary=values.allValues;dictionary[.nameKey]="changed"
   check(values.name==leaf,"allValues copy \(leaf)")
   let nameOnly=try url.resourceValues(forKeys:[.nameKey])
   check(nameOnly.contentType==nil && nameOnly.typeIdentifier==nil,"unrequested type remains absent")
  }
  let directory=URL(fileURLWithPath:root+"/folder")
  let dir=try directory.resourceValues(forKeys:[.nameKey,.isDirectoryKey])
  check(dir.isDirectory==true && dir.name=="folder","real directory basic metadata")
  do { _=try directory.resourceValues(forKeys:[.contentTypeKey]);check(false,"directory type rejects unavailable package metadata") }
  catch {
   let ns=error._getEmbeddedNSError() as? NSError
   check(ns?.domain()=="NSCocoaErrorDomain" && ns?.code()==3328,"directory content type explicit unsupported")
  }
  do { _=try URL(fileURLWithPath:root+"/missing.pdf").resourceValues(forKeys:[.contentTypeKey]);check(false,"missing file throws") }
  catch {
   let ns=error._getEmbeddedNSError() as? NSError
   check(ns?.domain()=="NSPOSIXErrorDomain" && ns?.code()==2,"actual missing-file error retained")
  }
  let remote=try URL(string:"https://example.invalid/no-fetch.pdf")!.resourceValues(forKeys:[.contentTypeKey])
  check(remote.allValues.isEmpty && remote.contentType==nil,"retained nonfile unavailable behavior")
  check(UTType.pdf.preferredFilenameExtension=="pdf" && UTType.png.conforms(to:.image),"prior UTType operations")
  check(String(reflecting:URLResourceValues.self)=="Foundation.URLResourceValues","real metadata")
  print("PASS URLResourceValues/contentType separate-client semantic probe")
 }
}
