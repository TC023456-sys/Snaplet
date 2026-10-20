from pathlib import Path
import tempfile,subprocess,sys
text=(Path(sys.argv[1])/'macshot/AppDelegate.swift').read_text()
def extract(signature):
 a=text.index(signature);b=text.index('{',a);depth=1;i=b+1
 while depth:
  depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[a:i]
methods=extract('private func recoverOrphanedCaptureIfNeeded()')+'\n'+extract('private var canStartCapture: Bool')
code='''import Foundation
@MainActor final class Controller {var hasInteractiveWindow=false}
@MainActor final class Subject {
 var isCapturing=true;var captureSessionID:UInt=1;var captureStartupTimeout:DispatchWorkItem?
 var delayTimer:Timer?;var delayCountdownWindow:NSObject?;var recordingEngine:NSObject?;var scrollCaptureController:NSObject?
 var overlayControllers:[Controller]=[];var dismissed=0
 func cancelPreCaptureCountdown(){isCapturing=false}
 func dismissOverlays(refocusPreviousApp:Bool){dismissed+=1;isCapturing=false;overlayControllers=[]}
 METHODS
 func admit()->Bool{canStartCapture}
}
MainActor.assumeIsolated {
 let hidden=Subject();hidden.overlayControllers=[Controller()]
 precondition(hidden.admit() && hidden.dismissed==1 && hidden.captureSessionID==2)
 precondition(hidden.admit() && hidden.dismissed==1)
 let visible=Subject();let panel=Controller();panel.hasInteractiveWindow=true;visible.overlayControllers=[panel]
 precondition(!visible.admit() && visible.dismissed==0)
 let startup=Subject();startup.captureStartupTimeout=DispatchWorkItem{}
 precondition(!startup.admit() && startup.dismissed==0)
 let delay=Subject();delay.delayTimer=Timer(timeInterval:1,repeats:false){_ in}
 precondition(!delay.admit() && delay.dismissed==0)
 let countdown=Subject();countdown.delayCountdownWindow=NSObject()
 precondition(!countdown.admit() && countdown.dismissed==0)
 let recording=Subject();recording.recordingEngine=NSObject()
 precondition(!recording.admit() && recording.dismissed==0)
 let scroll=Subject();scroll.scrollCaptureController=NSObject()
 precondition(!scroll.admit() && scroll.dismissed==0)
 print("PASS: orphaned captures recover; visible selection, startup, countdown, recording and scroll sessions remain protected")
}
'''.replace('METHODS',methods)
with tempfile.TemporaryDirectory(prefix='snaplet-orphan-test-') as d:
 p=Path(d);(p/'main.swift').write_text(code)
 subprocess.run(['swiftc','-swift-version','5',str(Path(sys.argv[1])/'macshot/Services/CaptureDeadline.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
