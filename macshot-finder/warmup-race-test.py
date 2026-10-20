from pathlib import Path
import subprocess,tempfile,sys
source=Path(sys.argv[1])/'macshot/UI/Overlay/OverlayWindowController.swift'
text=source.read_text()
def method(signature):
 if signature not in text:return ""
 start=text.index(signature);brace=text.index('{',start);depth=1;i=brace+1
 while depth:
  depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[start:i]
methods='\n'.join(method(s) for s in ['private func invalidateWarmup()', 'func showOverlay()', 'func makeKey()', 'func warmPanel()', 'func dismiss()', 'func tearDown()'])
harness='''import AppKit
import QuartzCore

@MainActor final class TestPanel {
 var isVisible=false; var ignoresMouseEvents=true; var alphaValue:CGFloat=1
 var isKeyWindow=false; var isOpaque=false; var backgroundColor=NSColor.clear
 var contentView:NSView?
 func orderFrontRegardless(){isVisible=true}
 func orderOut(_ sender:Any?){isVisible=false}
 func makeKeyAndOrderFront(_ sender:Any?){isVisible=true;isKeyWindow=true}
 func makeFirstResponder(_ view:NSView){}
 func close(){isVisible=false}
}
@MainActor final class TestView:NSView {
 var screenshotImage:NSImage?; var captureSourceImage:NSImage?; var overlayDelegate:AnyObject?
 func reset(){}
 func clearScreenshotPreview(){}
}
@MainActor final class Subject {
 var overlayWindow:TestPanel?=TestPanel()
 var overlayView:TestView?=TestView()
 var rootView:TestView?=TestView()
 var warmupGeneration:UInt=0
 var timingMark:((String)->Void)?
 var hasInteractiveWindow:Bool {
  guard let w=overlayWindow else{return false}
  return w.isVisible && !w.ignoresMouseEvents && w.alphaValue>0.5
 }
 func saveSelectionIfNeeded(){}
 METHODS
}
@MainActor func drain(){RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
let application=NSApplication.shared
MainActor.assumeIsolated {
 let idle=Subject();idle.warmPanel();drain()
 precondition(!idle.overlayWindow!.isVisible && idle.overlayWindow!.ignoresMouseEvents)
 let race=Subject();race.warmPanel();race.showOverlay();drain()
 precondition(race.hasInteractiveWindow && race.overlayWindow!.alphaValue==1,"late warmup hid a live capture")
 race.warmPanel();drain();precondition(race.hasInteractiveWindow,"warming a live session hid it")
 let replaced=Subject();replaced.warmPanel();replaced.dismiss();replaced.showOverlay();drain()
 precondition(replaced.hasInteractiveWindow,"old warmup hid a later session")
 let focus=Subject();focus.warmPanel();focus.makeKey();drain()
 precondition(focus.hasInteractiveWindow,"warmup hid a refocused session")
 let closed=Subject();closed.warmPanel();closed.tearDown();drain()
 precondition(closed.overlayWindow==nil)
 print("PASS: production overlay methods survive delayed warmup, replacement, focus and teardown; idle panels still hide")
}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='snaplet-warmup-test-') as d:
 p=Path(d);(p/'main.swift').write_text(harness)
 subprocess.run(['swiftc','-swift-version','5',str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
