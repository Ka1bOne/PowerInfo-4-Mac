# Transfer These Files to Your Mac!

Here's everything you need to build the PowerInfo DMGs on your Mac!

## 📁 Files to Transfer (copy all of these to your Mac)

1. `PowerInfo.swift` - Main Mac app source
2. `PowerInfo-Legacy.swift` - Legacy Mac app source
3. `build.sh` - Build script for main app
4. `build-legacy.sh` - Build script for legacy app
5. `package-mac.sh` - Package main app to DMG
6. `package-mac-legacy.sh` - Package legacy app to DMG

## 🛠️ Steps on Your Mac

1. Copy all these files to a folder on your Mac
2. Open Terminal and navigate to that folder
3. Make scripts executable:
   ```bash
   chmod +x build.sh build-legacy.sh package-mac.sh package-mac-legacy.sh
   ```

4. Build and package main app (macOS 15.0+):
   ```bash
   ./package-mac.sh
   ```

5. Build and package legacy app (macOS 12.0-14.x):
   ```bash
   ./package-mac-legacy.sh
   ```

You'll have two DMGs ready to distribute! 🎉
