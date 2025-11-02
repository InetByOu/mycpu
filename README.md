# 🧠 MyCPU — Smart CPU Governor & Frequency Manager  
**Author:** Edoll  
**Supports:** Linux • Android (rooted) • WSL  

---

## 🇬🇧 English Version

### 📝 Overview
**MyCPU** is a universal shell script that helps you easily manage your CPU governors and frequency ranges.  
It works on **Linux distributions**, **rooted Android devices**, and even **WSL (Windows Subsystem for Linux)**.  

You can:
- View all CPU cores and their current governors/frequencies  
- Apply a new governor (e.g. `performance`, `powersave`, etc.)  
- Set custom frequency limits (min/max)  
- Make your settings **persistent across reboots** automatically (systemd / Magisk / rc.local)  

---

### ⚙️ Installation
```bash
# Clone this repository
git clone https://github.com/InetByOu/mycpu.git
cd mycpu

# Make executable
chmod +x mycpu.sh

# Optional: Install globally
sudo ./mycpu.sh --install
```

Once installed, you can run it anywhere:
```bash
mycpu
```

---

### 💡 Usage
Run interactively:
```bash
./mycpu.sh
```

You’ll see a simple menu:
```
=== MyCPU — Smart CPU Governor/Freq Manager ===

 1) Set Governor
 2) Set Frequency
 3) Set Governor + Frequency
 0) Exit
```

Select the desired option to apply or persist your CPU settings.

---

### 🔁 Persistence Support
MyCPU automatically detects the best persistence method:
- **Systemd service** on desktop/server Linux  
- **Magisk service.d** for Android  
- **rc.local** for older systems  

This ensures your settings are restored every boot.

---

### 🧩 Example
Set all CPUs to performance mode and keep it permanent:
```bash
mycpu
# → Choose option 1
# → Enter governor: performance
# → Confirm persistence: y
```

---

### 📄 License
MIT License — free to use, modify, and distribute.

---

## 🇮🇩 Versi Bahasa Indonesia

### 📝 Deskripsi
**MyCPU** adalah skrip shell serbaguna untuk mengatur **governor** dan **frekuensi CPU** dengan mudah.  
Bisa dijalankan di **Linux desktop/server**, **Android (rooted)**, dan **WSL (Windows Subsystem for Linux)**.  

Fitur utama:
- Melihat semua core CPU dan statusnya (governor, frekuensi)  
- Mengubah governor (contoh: `performance`, `powersave`, `ondemand`)  
- Menentukan batas frekuensi minimum & maksimum  
- Menyimpan pengaturan agar aktif otomatis saat boot (systemd / Magisk / rc.local)  

---

### ⚙️ Instalasi
```bash
# Clone repository
git clone https://github.com/InetByOu/mycpu.git
cd mycpu

# Jadikan executable
chmod +x mycpu.sh

# Opsional: Install ke PATH sistem
sudo ./mycpu.sh --install
```

Setelah itu bisa dijalankan langsung:
```bash
mycpu
```

---

### 💡 Penggunaan
Jalankan secara interaktif:
```bash
./mycpu.sh
```

Akan muncul menu:
```
=== MyCPU — Smart CPU Governor/Freq Manager ===

 1) Set Governor
 2) Set Frequency
 3) Set Governor + Frequency
 0) Exit
```

Pilih opsi sesuai kebutuhan untuk mengatur governor dan frekuensi CPU.

---

### 🔁 Dukungan Persistensi
MyCPU otomatis mendeteksi cara terbaik agar pengaturan bertahan setelah reboot:
- **Systemd** (Linux modern)  
- **Magisk service.d** (Android)  
- **rc.local** (Sistem lama)  

Dengan begitu, pengaturan CPU kamu akan otomatis diterapkan saat sistem menyala.

---

### 🧩 Contoh
Atur semua CPU ke mode performa dan simpan permanen:
```bash
mycpu
# → Pilih menu 1
# → Masukkan governor: performance
# → Konfirmasi persistensi: y
```

---

### 📄 Lisensi
Lisensi MIT — bebas digunakan, dimodifikasi, dan didistribusikan.

---

### 💬 Author
Created by **Edoll**  
💻 For Linux & Android performance enthusiasts.
