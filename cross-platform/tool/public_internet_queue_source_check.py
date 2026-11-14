"""Guard the iOS queue boundary; runtime behavior is tested by the Apple Foundation fixture."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
plugin = (root / 'cross-platform/native/ios/Classes/HueviaCorePlugin.m').read_text(encoding='utf-8')
queues = (root / 'cross-platform/native/ios/Classes/HueviaPublicInternetQueues.m').read_text(encoding='utf-8')
assert 'dispatch_queue_create("cc.huevia.shared.worker",DISPATCH_QUEUE_SERIAL)' in plugin
assert 'accountNetworkOperationWithNSString:queuedOperation' in plugin
assert 'publicNetworkOperationWithNSString:queuedOperation' in plugin
assert 'requestPublicWithNSString:operation withNSString:payload withJavaUtilFunctionBooleanSupplier:task' in plugin
assert 'else dispatch_async(self.queue,perform);' in plugin
assert 'self.tasks.count-self.publicInternetJobs.count' in plugin
assert plugin.count('[self.publicInternetJobs removeObject:job]') == 2
assert 'if(task.cancelled)@throw' in plugin
assert '_account.maxConcurrentOperationCount=2' in queues
assert '_publicInternet.maxConcurrentOperationCount=3' in queues
assert not re.search(r'cancelAllOperations|camera|sockets|bindProcess|TLS|HostnameVerifier|setCancelled', queues, re.IGNORECASE)
assert not re.search(r'\.cancelled\s*=(?!=)', plugin)
core_pipeline = (root / 'cross-platform/tool/core_ios.sh').read_text(encoding='utf-8')
mobile_pipeline = (root / 'cross-platform/tool/mobile_apple.sh').read_text(encoding='utf-8')
assert 'bash "$ROOT/cross-platform/tool/public_internet_apple.sh"' in core_pipeline
assert 'bash "$ROOT/cross-platform/tool/core_ios.sh"' in mobile_pipeline
print('PASS iOS public I/O architecture: explicit whitelist, isolated bounded queues, serial camera dispatch and readonly task cancellation preserved')
