#!/bin/bash

echo "========================================="
echo "🚀 Levanter Termux Installer"
echo "========================================="
echo "Grant storage permission when prompted."
sleep 3

# Ask Termux for storage access
termux-setup-storage
termux-wake-lock

echo "[1/9] Updating repositories..."
apt-get update -y && apt-get upgrade -y

echo "[2/9] Installing required repositories..."
pkg install -y tur-repo x11-repo

echo "[3/9] Installing required packages..."
pkg install -y python python-pip nano clang make git ffmpeg nodejs-lts pkg-config \
libxml2 libxslt rust binutils wget build-essential libvips glib openjdk-21 file sqlite unzip

echo "[4/9] Installing Python dependencies..."
pip install --upgrade pip
pip install cython wheel setuptools python-dotenv

echo "[5/9] Creating directories..."
mkdir -p ~/.gyp ~/android-ndk ~/levanter

echo "[6/9] Downloading Android NDK..."
curl -fsSL https://github.com/lzhiyong/termux-ndk/releases/download/android-ndk/android-ndk-r27b-aarch64.zip -o ~/android-ndk.zip
unzip ~/android-ndk.zip -d ~/android-ndk
rm ~/android-ndk.zip

echo "[7/9] Cloning Levanter repository..."
git clone https://github.com/lyfe00011/levanter.git ~/levanter

echo "[8/9] Installing Node.js dependencies..."
npm install -g yarn pm2
cd ~/levanter
yarn install

echo "[9/9] Setting up auto-start..."
echo "cd ~/levanter && pm2 start index.js --name levanter && pm2 save && pm2 startup" >> ~/.bashrc

echo "✅ Installation complete!"
echo "Next time you open Termux, Levanter will auto-start."