<p align="left">
  <img src="logo.png" width="350">
</p>

# AmlogicKitchen

**A universal firmware kitchen for working with Amlogic, Rockchip, and AllWinner images (Linux x86\_64 only).**

---

### 🛠️ Features

**✅ Rockchip Support**

* Unpack and repack Rockchip firmware images.

**✅ Amlogic Support**

* Unpack and repack Amlogic firmware images.
* Generate Amlogic images from supported flashable ZIPs.
* Dump ROMs via mask ROM mode (Only for legacy chips).

**✅ AllWinner Support**

* Unpack and repack AllWinner firmware images.

**✅ Common Features**

* Unpack and repack partitions.
* Handle `boot`, `recovery`, `logo`, and `dtb` images.
* Unpack and repack super images.
* Sign ROMs with custom keys.

---

### ⚠️ Disclaimer

This project is intended for educational purposes. Use at your own risk.

* The developer is not liable for any **device damage**, **data loss**, **legal issues**, or **injuries**.
* By using this tool, you accept full responsibility for its usage and consequences.

---

### 🔧 Installation

Clone the repository:

```bash
git clone https://github.com/althafvly/AmlogicKitchen AmlogicKitchen
cd AmlogicKitchen

```

Enable 32-bit support and install required dependencies:

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install libc6:i386 libstdc++6:i386 libgcc1:i386 device-tree-compiler \
python3 7zip android-sdk-libsparse-utils brotli
```

---

### 📖 Usage

The kitchen works in **3 levels** — each level goes deeper into the firmware:

* **Level 1** — Splits the firmware image into individual partitions (boot, system, vendor, etc.)
* **Level 2** — Extracts partition filesystems so you can add/remove files
* **Level 3** — Extracts deep components like boot ramdisk, splash logo, and device tree

> **Tip:** You must unpack in order (Level 1 → 2 → 3) and repack in reverse (Level 3 → 2 → 1).

---

#### 🔷 Amlogic — Unpack & Repack

**Unpack:**

```bash
# 1. Place your firmware .img file in the in/ folder
cp firmware.img in/

# 2. Run the unpack script — it will prompt you to select a level (1, 2, or 3)
sudo bash amlunpack.sh
# → Select level 1: splits firmware into level1/ partitions
# → Select level 2: extracts system/vendor/product filesystems into level2/
# → Select level 3: extracts boot, recovery, logo, DTB into level3/
```

**Make your modifications:**

```
level2/system/   — Add or remove system apps, modify framework files
level2/vendor/   — Modify vendor HAL, drivers, build.prop
level2/product/  — Modify product apps and overlays
level3/boot/     — Edit ramdisk (init scripts, fstab, etc.)
level3/logo/     — Replace boot splash screen images
level3/devtree/  — Edit device tree source (.dts) files
```

**Repack:**

```bash
# Repack in reverse order (3 → 2 → 1)
sudo bash amlpack.sh
# → Select level 3: repacks boot, logo, DTB back into level1/
# → Select level 2: rebuilds partition images and super partition
# → Select level 1: packs everything into out/<name>.img
```

---

#### 🟢 Rockchip — Unpack & Repack

**Unpack:**

```bash
cp firmware.img in/

sudo bash rkunpack.sh
# → Level 1: splits firmware using rkImageMaker + afptool → level1/Image/
# → Level 2: extracts partition filesystems → level2/
# → Level 3: extracts boot/recovery ramdisk, resource.img → level3/
```

**Repack:**

```bash
sudo bash rkpack.sh
# → Level 3: repacks resource.img and boot images
# → Level 2: rebuilds partition images and super partition
# → Level 1: packs firmware with your chip model (e.g. RK322A, RK3588) → out/<name>.img
```

> **Note:** When repacking Level 1, you will be asked to select your chip model from a list (e.g., `RK3568`, `RK3588`, `RK330C`).

---

#### 🟡 AllWinner — Unpack & Repack

**Unpack:**

```bash
cp firmware.img in/

sudo bash awunpack.sh
# → Level 1: splits firmware using imgrepacker/OpenixCard → level1/
# → Level 2: extracts partition filesystems → level2/
# → Level 3: extracts boot/recovery and boot-resource → level3/
```

**Repack:**

```bash
sudo bash awpack.sh
# → Level 3: repacks boot images and boot-resource.fex
# → Level 2: rebuilds partition images and super partition
# → Level 1: packs firmware → out/<name>.img
```

---

#### 📥 Amlogic ROM Dump (via USB)

Dumps the ROM directly from an Amlogic device connected in mask ROM mode (USB Burning Tool mode). **Only works with legacy Amlogic chips.**

```bash
# 1. Connect your Amlogic device to PC in mask ROM mode
# 2. Run the dump script
sudo bash amldump.sh
# → Enter bootloader size (default: 4194304) and DTB size (default: 262144)
# → Partitions are auto-detected from DTB and dumped to dump/
```

---

#### 📦 Convert Dump to Amlogic Image

Converts dumped partition files (from `amldump.sh`) into a flashable Amlogic firmware image.

```bash
# Make sure dump/ folder contains the dumped partition .img files
# Also copy DDR.USB, UBOOT.USB, aml_sdc_burn.UBOOT, meson1.PARTITION,
# and platform.conf to level1/ when prompted

sudo bash dump_to_aml.sh
# → Copies partitions, auto-repacks boot/recovery/logo/DTB
# → Generates image.cfg automatically
# → Outputs flashable image to out/<name>.img
```

---

#### 📱 Convert Flashable ZIP to Amlogic Image

Converts a TWRP/CWM flashable ZIP into an Amlogic firmware `.img` file.

```bash
# 1. Place the flashable .zip file in the in/ folder
cp rom.zip in/

# 2. Run the conversion script
sudo bash pack_zip_to_aml.sh
# → Decompresses brotli, converts sparse data to images
# → Copy DDR.USB, UBOOT.USB, aml_sdc_burn.UBOOT, meson1.PARTITION,
#   and platform.conf to level1/ when prompted
# → Outputs flashable image to out/<name>.img
```

---

#### 🔑 Re-sign ROM with AOSP Keys

Re-signs all APK and JAR files in the extracted partitions using AOSP test keys or your own custom keys.

```bash
# Make sure level2/ is populated (unpack Level 2 first)

# Option A: Use default AOSP keys
sudo bash resign.sh

# Option B: Use custom keys — place your keys in custom_keys/ folder
mkdir custom_keys
cp your_platform.x509.pem your_platform.pk8 ... custom_keys/
sudo bash resign.sh
```

---

#### 🧹 Cleanup

Removes all working directories to start fresh.

```bash
sudo bash clean.sh
# → Deletes level1/, level2/, level3/, and tmp/
```

---

### 📌 Notes

* DTB compile/decompile may throw some warnings—these can be safely ignored in most cases.
* Compatibility is limited to certain firmwares, devices, and chipsets. Not all images may work.
* Tested primarily on **Linux (Ubuntu)**. While it *might* work on other platforms, full functionality is not guaranteed.
* Most binaries are compiled for **Linux x86\_64** only.

---

### 🙏 Credits

Special thanks to the contributors and original authors of the tools integrated into this kitchen:

* **Vortex** – Base kitchen (vtx\_kitchen)
* **unix3dgforce, blackeange, xiaoxindada** – ImgExtractor
* **osm0sis** – Android Image Kitchen (AIK)
* **LineageOS** – Super image tools, Amlogic DTB/unpack tools
* **xpirt** – `img2sdat`, `sdat2img`
* **Roger Shimizu** – `android-sdk-libsparse-utils`
* **erfanoabdi** – ROM Resigner
* **RedScorpioXDA** – imgRePacker
* **YuzukiTsuru** – OpenixCard
* **Guoxin Pu** – ampack

*And everyone else who contributed—thank you!*

---

### 🐞 Report Issues

Encounter a bug or need help? [Open an issue](https://github.com/xKern/AmlogicKitchen/issues/new)
