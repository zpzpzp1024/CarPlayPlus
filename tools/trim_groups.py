# -*- coding: utf-8 -*-
"""One-off: remove the disabled Logos groups (Layout/Wallpaper/StatusBar/
Fullscreen UI) from CarPlayPlus.xm while keeping the BKS screen-blank hook.

Ranges are 1-indexed and inclusive; MUST be sorted largest-first so earlier
line numbers stay valid while later blocks are removed.
"""
import io

PATH = r"f:/SourceCode/Code_Swift/CarPlayPlus/Tweak/CarPlayPlus.xm"

RANGES = [
    (749, 777),  # %hook CARAppDockButton .. trailing blank
    (722, 727),  # Fullscreen pragma block + %group line + blank
    (570, 721),  # Status Bar pragma + group .. trailing blank
    (414, 569),  # Wallpaper pragma + group .. trailing blank
    (303, 413),  # Notifications consts + Icon Layout group .. trailing blank
]
# verify sorted largest-first
assert RANGES == sorted(RANGES, reverse=True), "ranges must be largest-first"

lines = io.open(PATH, encoding="utf-8").read().splitlines()

# --- sanity checks ---------------------------------------------------------
checks = [
    (303, "// ------"),
    (307, "kIconLayoutChanged"),
    (412, "%end // CarPlayPlusLayout"),
    (414, "// ------"),
    (568, "%end // CarPlayPlusWallpaper"),
    (570, "// ------"),
    (720, "%end // CarPlayPlusStatusBar"),
    (722, "// ------"),
    (726, "%group CarPlayPlusFullscreen"),
    (728, "orig_BKSDisplayServicesSetScreenBlanked"),
    (749, "%hook CARAppDockButton"),
    (776, "%end // CarPlayPlusFullscreen"),
    (778, "// ------"),
    (779, "#pragma mark - Widgets"),
]
for n, expected in checks:
    actual = lines[n - 1]
    if expected not in actual:
        raise SystemExit(f"SANITY FAIL line {n}: expected ~{expected!r}, got {actual!r}")
print("sanity OK; total lines:", len(lines))

# --- delete from tail ------------------------------------------------------
for start, end in RANGES:
    del lines[start - 1:end]

io.open(PATH, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
print("done; total lines:", len(lines))

# --- post-check -------------------------------------------------------------
text = "\n".join(lines)
for must_have in ["orig_BKSDisplayServicesSetScreenBlanked", "hook_BKSDisplayServicesSetScreenBlanked",
                  "CarPlayPlusAnyApp", "CPInstallDashboardHooks", "CPApplyDashboardLayout",
                  "OnCarPlayConnectForWiFi", "CPWiFiPollCarPlay", "CarPlayPlusHostedWindow",
                  "%group CarPlayPlusWidgets", "CPWiFiHandleCarPlayConnected",
                  "CarPlayIsConnectedDidChange", "scheduledTimerWithTimeInterval:10.0"]:
    if must_have not in text:
        raise SystemExit(f"MISSING preserved symbol: {must_have}")
for must_not in ["%group CarPlayPlusLayout", "%group CarPlayPlusWallpaper",
                 "%group CarPlayPlusStatusBar", "%group CarPlayPlusFullscreen",
                 "kIconLayoutChanged", "kChangedImg", "kFullscreenToggle",
                 "CARAppDockButton", "gFullscreenActive"]:
    if must_not in text:
        raise SystemExit(f"STILL PRESENT removed symbol: {must_not}")
print("post-check OK")