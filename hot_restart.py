import urllib.request, json, sys

vm_service = "http://127.0.0.1:49472/VzriebYrQDo="

# Try hot restart via VM service
try:
    url = f"{vm_service}/getVM"
    r = urllib.request.urlopen(url, timeout=10)
    print("VM:", r.read().decode()[:200])
except Exception as e:
    print(f"getVM error: {e}")

# Try _reloadSources on isolate
try:
    url = f"{vm_service}/_reload?restart=true"
    req = urllib.request.Request(url)
    r = urllib.request.urlopen(req, timeout=30)
    print("reload:", r.read().decode()[:200])
except Exception as e:
    print(f"reload error: {e}")
