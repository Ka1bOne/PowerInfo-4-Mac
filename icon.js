const fs = require('fs');
const { createCanvas } = require('canvas');

// Create a simple placeholder icon (256x256 PNG)
const canvas = createCanvas(256, 256);
const ctx = canvas.getContext('2d');

// Background
ctx.fillStyle = '#333';
ctx.beginPath();
ctx.arc(128, 128, 120, 0, Math.PI * 2);
ctx.fill();

// Draw a battery icon
ctx.fillStyle = '#fff';
ctx.fillRect(60, 80, 136, 96);
ctx.fillRect(200, 110, 16, 36);
ctx.fillStyle = '#4CAF50';
ctx.fillRect(70, 90, 116, 76);

const buffer = canvas.toBuffer('image/png');
fs.writeFileSync('icon.png', buffer);
console.log('Created icon.png');
