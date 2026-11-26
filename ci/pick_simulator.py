# 从 simctl 的设备列表里挑一台可用的 iPhone 模拟器（优先最新 iOS；带 --promax 时优先 Pro Max，用于 App Store 截图尺寸）
import json
import sys

want_promax = "--promax" in sys.argv
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in runtime.rsplit("iOS-", 1)[-1].split("-") if x.isdigit())
    for d in items:
        if not (d.get("isAvailable") and d["name"].startswith("iPhone")):
            continue
        promax = "Pro Max" in d["name"]
        key = (version, (promax if want_promax else True))
        if best is None or key > best[0]:
            best = (key, d["udid"], d["name"])
if best is None:
    sys.exit("没有可用的 iPhone 模拟器")
print(best[1], file=sys.stdout)
print("选用：", best[2], file=sys.stderr)
