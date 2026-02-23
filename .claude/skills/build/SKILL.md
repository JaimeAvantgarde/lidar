---
name: build
description: Build and verify the lidar Xcode project compiles without errors
disable-model-invocation: true
allowed-tools: Bash(xcodebuild:*)
---

Build the lidar project and report results:

```bash
xcodebuild build -scheme lidar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

If the build fails:
1. Read the error output carefully
2. Identify the file and line number
3. Read that file to understand the context
4. Fix the error
5. Build again to verify
