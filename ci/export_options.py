"""Render app and widget signing options from the CI environment."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
app = os.environ.get("APP_ID", "com.hgsldswk.weightcycle")
data["teamID"] = os.environ["TEAM_ID"]
data["provisioningProfiles"] = {
    app: os.environ.get("APP_PROFILE", "WeightCycle AppStore"),
    app + ".widget": os.environ.get("WIDGET_PROFILE", "WeightCycle Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
