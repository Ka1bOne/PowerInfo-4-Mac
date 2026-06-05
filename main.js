const { app, BrowserWindow, Tray, Menu, ipcMain, nativeImage, powerMonitor } = require('electron');
const path = require('path');
const { exec } = require('child_process');
const AutoLaunch = require('auto-launch');

let mainWindow;
let settingsWindow;
let tray;
let lastPowerState = null;
let lastNotifiedThreshold = 100;
let lastThermalState = 'nominal';
let lastHighPowerState = false;
let currentBatteryPercent = 100;
let isOnACPower = true;

const userSettings = {
  enableThresholdAlerts: true,
  themePref: 0,
  hudStyle: 0,
  enableThermalAlerts: true,
  enableHighPowerAlerts: true,
  launchAtLogin: false
};

const autoLauncher = new AutoLaunch({
  name: 'PowerInfo'
});

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 360,
    height: 250,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    show: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  mainWindow.loadFile('index.html');
}

function createSettingsWindow() {
  if (settingsWindow) {
    settingsWindow.focus();
    return;
  }

  settingsWindow = new BrowserWindow({
    width: 340,
    height: 400,
    frame: true,
    resizable: false,
    show: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  settingsWindow.loadFile('settings.html');

  settingsWindow.on('closed', () => {
    settingsWindow = null;
  });

  settingsWindow.once('ready-to-show', () => {
    settingsWindow.show();
  });
}

function createTray() {
  let icon;
  try {
    icon = nativeImage.createFromPath(path.join(__dirname, 'icon.png'));
    if (icon.isEmpty()) throw new Error('Empty icon');
  } catch (e) {
    // Create a simple icon from a base64 string
    const base64 = 'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAADFJREFUOE9jZKAQMJnwf8E8D8j8g8D8D8j8g8D8D8j8g8D8D8j8g8D8D8j8g8D8D8j8g8D8D8j8g8D8D4CwAAD//wMAhWgCogAAAABJRU5ErkJggg==';
    icon = nativeImage.createFromDataURL(`data:image/png;base64,${base64}`);
  }
  tray = new Tray(icon.resize({ width: 16, height: 16 }));
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Settings...', click: () => createSettingsWindow() },
    { type: 'separator' },
    { label: 'Quit PowerInfo', click: () => app.quit() }
  ]);
  tray.setToolTip('PowerInfo');
  tray.setContextMenu(contextMenu);
}

let batteryTimeRemaining = '';

function updateBatteryStatus() {
  if (process.platform === 'win32') {
    // Use PowerShell to get battery status, charge percentage, and time remaining
    exec('powershell -Command "$battery = Get-WmiObject -Class Win32_Battery; $battery.BatteryStatus; $battery.EstimatedChargeRemaining; $battery.EstimatedRunTime"', (error, stdout) => {
      if (error) return;
      const lines = stdout.trim().split('\n').filter(line => line.trim() !== '');
      if (lines.length >= 3) {
        const batteryStatus = parseInt(lines[0].trim());
        currentBatteryPercent = parseInt(lines[1].trim());
        const estimatedRunTime = parseInt(lines[2].trim());
        
        // BatteryStatus values that indicate plugged in/AC power:
        // 2 = AC power, 3 = fully charged, 6 = charging, 7-9 = charging states, 11 = partially charged
        isOnACPower = [2, 3, 6, 7, 8, 9, 11].includes(batteryStatus);
        
        // Format time remaining
        if (!isOnACPower && estimatedRunTime > 0) {
          const hours = Math.floor(estimatedRunTime / 60);
          const minutes = estimatedRunTime % 60;
          batteryTimeRemaining = `${hours}h ${minutes}m`;
        } else {
          batteryTimeRemaining = isOnACPower ? 'Charging' : '';
        }
      }
    });
  }
}

function isCurrentlyPluggedIn() {
  return isOnACPower;
}

function checkPowerStatus() {
  const current = isCurrentlyPluggedIn();
  if (lastPowerState === current) return;
  lastPowerState = current;

  setTimeout(() => {
    showPopup(current ? 'plugged' : 'unplugged');
  }, 300);
}

function checkBatteryThresholds() {
  if (!userSettings.enableThresholdAlerts) return;
  if (isOnACPower) {
    lastNotifiedThreshold = 100;
    return;
  }
  const percentage = currentBatteryPercent;
  if (percentage <= 10 && lastNotifiedThreshold > 10) {
    lastNotifiedThreshold = 10;
    showPopup('battery10');
  } else if (percentage <= 20 && percentage > 10 && lastNotifiedThreshold > 20) {
    lastNotifiedThreshold = 20;
    showPopup('battery20');
  }
}

function showPopup(state) {
  if (!mainWindow) return;
  
  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;

  let windowWidth, windowHeight, x, y;
  
  if (userSettings.hudStyle === 1) {
    windowWidth = 280;
    windowHeight = 56;
    x = Math.floor((width - windowWidth) / 2);
    y = height - windowHeight - 20;
  } else {
    windowWidth = 360;
    windowHeight = 250;
    x = Math.floor((width - windowWidth) / 2);
    y = 40;
  }

  mainWindow.setBounds({ x, y, width: windowWidth, height: windowHeight });
  mainWindow.webContents.send('show-popup', state, userSettings, currentBatteryPercent, batteryTimeRemaining);
  mainWindow.show();
}

app.whenReady().then(() => {
  createMainWindow();
  createTray();

  updateBatteryStatus();
  lastPowerState = isCurrentlyPluggedIn();

  setTimeout(() => {
    showPopup(isCurrentlyPluggedIn() ? 'plugged' : 'unplugged');
  }, 1500);

  setInterval(() => {
    const oldState = isOnACPower;
    updateBatteryStatus();
    if (oldState !== isOnACPower) {
      if (isOnACPower) lastNotifiedThreshold = 100;
      checkPowerStatus();
    }
    checkBatteryThresholds();
  }, 5000);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

ipcMain.handle('get-settings', () => userSettings);
ipcMain.handle('save-settings', (event, newSettings) => {
  Object.assign(userSettings, newSettings);
  if (newSettings.launchAtLogin) {
    autoLauncher.enable();
  } else {
    autoLauncher.disable();
  }
});

ipcMain.handle('test-notification', () => {
  showPopup(isCurrentlyPluggedIn() ? 'plugged' : 'unplugged');
});

ipcMain.on('hide-popup', () => {
  if (mainWindow) {
    mainWindow.hide();
  }
});
