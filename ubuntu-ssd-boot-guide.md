# Ubuntu Server NVMe SSD Boot Guide for Raspberry Pi 5

## Prerequisites

- Raspberry Pi 5 with NVMe shield installed
- Crucial P310 1TB PCIe Gen4 NVMe SSD (2280 M.2)
- MicroSD card (16GB minimum) for initial setup
- Computer with SD card reader
- Stable internet connection
- Quality 5V/5A power supply (essential for P310)
- Heatsink for the P310 (recommended due to heat generation)

## Step-by-Step Instructions

### Phase 1: Preparation and Firmware Update

#### Step 1: Prepare SD Card with Ubuntu Server

1. **Download Raspberry Pi Imager** from https://rpi.org/imager
2. **Flash Ubuntu Server 24.04 LTS** (64-bit) for Raspberry Pi to your SD card
   - Select "Ubuntu Server 24.04.x LTS (64-bit)" from the OS list
3. **Configure before flashing** (using Imager's gear icon):
   - Enable SSH with password or key
   - Set username/password (e.g., ubuntu/yourpassword)
   - Configure WiFi if needed
4. **Insert SD card** into Pi and boot

#### Step 2: Initial Setup and Updates

1. **Boot from SD card** and log in
2. **Update system**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
3. **Update firmware** (CRITICAL):

   **For Ubuntu Server:**

   ```bash
   # Update bootloader/EEPROM firmware
   sudo apt install rpi-eeprom
   sudo rpi-eeprom-update -a
   sudo reboot

   # If above doesn't work, manually update:
   sudo rpi-eeprom-update -d -a
   sudo reboot
   ```

4. **Verify NVMe detection**:

   ```bash
   # First, check if NVMe tools are installed
   lsblk

   # Install NVMe utilities if needed
   sudo apt install nvme-cli

   # Then list NVMe devices
   sudo nvme list

   # Alternative: use lspci to see PCIe devices
   lspci | grep -i nvme

   # Check kernel recognition
   dmesg | grep -i nvme
   ```

   Your SSD should appear as `/dev/nvme0n1` in lsblk output

### Phase 2: Configure Boot Settings

#### Step 3: Configure config.txt for NVMe Support

1. **Edit boot config**:
   ```bash
   sudo nano /boot/firmware/config.txt
   ```
2. **Add these lines** at the end:

   ```ini
   # Enable PCIe for NVMe
   dtparam=pciex1

   # Force PCIe Gen 3 for P310 (it's a Gen4 drive but Gen3 is more stable)
   dtparam=pciex1_gen=3

   # NVMe overlay (redundant but explicit)
   dtoverlay=nvme

   # Crucial P310 specific optimizations
   # Disable ASPM for better stability
   dtparam=pcie_aspm=off

   # Ensure 64-bit mode
   arm_64bit=1

   # Memory settings for better NVMe performance
   gpu_mem=64
   ```

#### Step 4: Configure Kernel Parameters

1. **Edit cmdline.txt**:
   ```bash
   sudo nano /boot/firmware/cmdline.txt
   ```
2. **Add these parameters** to the existing line (don't create new lines):

   ```
   pci=pcie_bus_safe nvme_core.default_ps_max_latency_us=0 pcie_aspm=off
   ```

   Example final line:

   ```
   console=serial0,115200 console=tty1 root=PARTUUID=12345678-02 rootfstype=ext4 fsck.repair=yes rootwait pci=pcie_bus_safe nvme_core.default_ps_max_latency_us=0 pcie_aspm=off
   ```

   **Note for Crucial P310**: This SSD can be sensitive to power state transitions, so disabling APST and ASPM is crucial.

3. **Reboot and test**:
   ```bash
   sudo reboot
   ```

### Phase 3: Install Ubuntu Server on NVMe SSD

#### Step 5: Partition the NVMe SSD

1. **Identify your SSD**:

   ```bash
   lsblk
   sudo fdisk -l /dev/nvme0n1
   ```

2. **Create GPT partition table and partitions**:

   ```bash
   # Clear any existing partitions
   sudo wipefs -a /dev/nvme0n1

   # Create GPT partition table and partitions
   sudo parted /dev/nvme0n1 --script -- mklabel gpt
   sudo parted /dev/nvme0n1 --script -- mkpart ESP fat32 1MiB 513MiB
   sudo parted /dev/nvme0n1 --script -- set 1 esp on
   sudo parted /dev/nvme0n1 --script -- mkpart primary ext4 513MiB 100%

   # Verify partitions
   sudo parted /dev/nvme0n1 print
   ```

#### Step 6: Format Partitions

1. **Format boot partition** (FAT32):

   ```bash
   sudo mkfs.fat -F 32 /dev/nvme0n1p1
   ```

2. **Format root partition** (ext4):
   ```bash
   sudo mkfs.ext4 /dev/nvme0n1p2
   ```

#### Step 7: Install Ubuntu Server

1. **Download Ubuntu Server 24.04 LTS** for ARM64:

   ```bash
   cd /tmp
   # Use stable release instead of daily builds
   wget https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.1-preinstalled-server-arm64+raspi.img.xz
   ```

2. **Extract the image**:

   ```bash
   xz -d ubuntu-24.04.1-preinstalled-server-arm64+raspi.img.xz
   ```

3. **Mount the Ubuntu image**:

   ```bash
   sudo mkdir -p /mnt/ubuntu-img

   # Verify the image file exists
   if [ ! -f "ubuntu-24.04.1-preinstalled-server-arm64+raspi.img" ]; then
       echo "Error: Image file not found in current directory"
       echo "Current directory: $(pwd)"
       echo "Available files:"
       ls -la *.img 2>/dev/null || echo "No .img files found"
       exit 1
   fi

   # Check if loop0 is already in use and clean up if needed
   sudo losetup -d /dev/loop0 2>/dev/null || true

   # Find next available loop device automatically
   LOOP_DEVICE=$(sudo losetup -f)
   echo "Using loop device: $LOOP_DEVICE"

   # Verify the loop device exists
   if [ ! -e "$LOOP_DEVICE" ]; then
       echo "Error: Loop device $LOOP_DEVICE does not exist"
       echo "Available loop devices:"
       ls -la /dev/loop* 2>/dev/null || echo "No loop devices found"
       exit 1
   fi

   # Set up the loop device with partition support
   sudo losetup -P "$LOOP_DEVICE" ubuntu-24.04.1-preinstalled-server-arm64+raspi.img

   # Verify partitions were created
   sleep 2
   ls -la "${LOOP_DEVICE}"* || {
       echo "Error: Partitions not created on $LOOP_DEVICE"
       sudo losetup -d "$LOOP_DEVICE"
       exit 1
   }

   # Mount the partitions
   sudo mount "${LOOP_DEVICE}p2" /mnt/ubuntu-img

   # Create the boot/firmware directory structure if it doesn't exist
   sudo mkdir -p /mnt/ubuntu-img/boot/firmware

   # Mount the boot partition
   sudo mount "${LOOP_DEVICE}p1" /mnt/ubuntu-img/boot/firmware

   # Verify mounts
   echo "Mounted filesystems:"
   mount | grep "/mnt/ubuntu-img"

   echo "Successfully mounted Ubuntu image from $LOOP_DEVICE"
   ```

4. **Mount NVMe partitions**:

   ```bash
   sudo mkdir -p /mnt/nvme-root /mnt/nvme-boot
   sudo mount /dev/nvme0n1p2 /mnt/nvme-root
   sudo mount /dev/nvme0n1p1 /mnt/nvme-boot
   ```

5. **Copy Ubuntu to NVMe**:
   ```bash
   sudo rsync -axHAWX --numeric-ids --info=progress2 /mnt/ubuntu-img/ /mnt/nvme-root/
   sudo rsync -axHAWX --numeric-ids --info=progress2 /mnt/ubuntu-img/boot/firmware/ /mnt/nvme-boot/
   ```

### Phase 4: Configure NVMe Boot

#### Step 8: Update fstab for NVMe

1. **Get UUIDs**:

   ```bash
   sudo blkid /dev/nvme0n1p1
   sudo blkid /dev/nvme0n1p2
   ```

2. **Edit fstab**:

   ```bash
   sudo nano /mnt/nvme-root/etc/fstab
   ```

   **What you need to do:**

   a) **First, get the actual UUIDs from step 1 above**. The output will look like:

   ```
   /dev/nvme0n1p1: UUID="1234-ABCD" TYPE="vfat" PARTUUID="12345678-1234-1234-1234-123456789abc"
   /dev/nvme0n1p2: UUID="12345678-1234-1234-1234-123456789abc" TYPE="ext4" PARTUUID="87654321-4321-4321-4321-cba987654321"
   ```

   b) **Copy the UUID values** (the part in quotes after `UUID=`)

   c) **Replace the entire contents** of the fstab file with these two lines, using YOUR actual UUIDs:

   ```
   UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1
   UUID=1234-ABCD /boot/firmware vfat defaults 0 1
   ```

   **Example with real UUIDs:**

   - If your root partition UUID is `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
   - And your boot partition UUID is `ABCD-1234`
   - Then your fstab should contain:

   ```
   UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890 / ext4 defaults 0 1
   UUID=ABCD-1234 /boot/firmware vfat defaults 0 1
   ```

   d) **Save and exit** nano (Ctrl+X, then Y, then Enter)

#### Step 9: Update Boot Configuration

1. **Edit cmdline.txt on NVMe**:

   ```bash
   sudo nano /mnt/nvme-boot/cmdline.txt
   ```

   Update root parameter to use NVMe UUID:

   ```
   console=serial0,115200 console=tty1 root=UUID=YOUR-ROOT-UUID rootfstype=ext4 fsck.repair=yes rootwait pci=pcie_bus_safe nvme_core.default_ps_max_latency_us=0 pcie_aspm=off
   ```

2. **Update config.txt on NVMe**:
   ```bash
   sudo nano /mnt/nvme-boot/config.txt
   ```
   Ensure it contains the NVMe settings from Step 3.

#### Step 10: Enable NVMe Boot Order

1. **Update bootloader config**:

   ```bash
   sudo rpi-eeprom-config --edit
   ```

   Add or modify these lines:

   ```
   BOOT_ORDER=0xf641
   BOOT_UART=1
   POWER_OFF_ON_HALT=0
   ```

   **Important Notes:**

   - `0xf641` = Boot order: NVMe (6), SD card (4), USB (1), Network (f)
   - Save the file when prompted (usually Ctrl+X, Y, Enter)
   - **A reboot is required** for changes to take effect

   **Alternative boot orders:**

   - `0x641` = NVMe first, SD card second, USB third (no network)
   - `0x6` = NVMe only (will not fall back to SD card)

2. **Apply the changes**:
   ```bash
   # The EEPROM update will be applied on next reboot
   sudo reboot
   ```
3. **Verify the boot order took effect**:

   ```bash
   # After reboot, check current EEPROM config
   sudo rpi-eeprom-config

   # Look for BOOT_ORDER=0xf641 in the output
   # If not present, the change didn't take effect
   ```

4. **Troubleshooting boot order issues**:

   ```bash
   # Check current EEPROM version
   sudo rpi-eeprom-update

   # If EEPROM is too old, update it first:
   sudo rpi-eeprom-update -a
   sudo reboot

   # Then try setting boot order again
   sudo rpi-eeprom-config --edit
   ```

#### Step 11: Clean Up and Prepare for Testing

1. **Unmount everything**:

   ```bash
   sudo umount /mnt/nvme-boot /mnt/nvme-root
   sudo umount /mnt/ubuntu-img/boot/firmware /mnt/ubuntu-img

   # Clean up loop device (use the same variable or find it)
   LOOP_DEVICE=$(losetup -j ubuntu-24.04.1-preinstalled-server-arm64+raspi.img | cut -d: -f1)
   if [ -n "$LOOP_DEVICE" ]; then
       sudo losetup -d $LOOP_DEVICE
       echo "Cleaned up loop device: $LOOP_DEVICE"
   fi
   ```

### Phase 5: Test and Troubleshoot

#### Step 12: First Boot Test

1. **Remove SD card** and power cycle
2. **Monitor boot process** via HDMI or SSH
3. **If boot fails**, insert SD card and check:
   - Boot order in EEPROM: `sudo rpi-eeprom-config`
   - NVMe detection: `lsblk` and `sudo nvme list`
   - Boot configuration files

#### Step 13: Post-Boot Configuration

1. **First login** - Ubuntu Server 24.04 Login Info:

   **Method 1: If you configured credentials in Raspberry Pi Imager:**

   - Username: Whatever you set during imaging (e.g., `ubuntu`)
   - Password: Whatever you set during imaging

   **Method 2: If you used default imaging (no custom config):**

   - **Ubuntu 24.04**: No default password! You MUST:
     - Connect keyboard/monitor directly to Pi
     - Follow first-boot setup wizard to create user account
     - OR use cloud-init configuration

   **Method 3: Emergency access:**

   - Boot with keyboard/monitor connected
   - Press Ctrl+Alt+F2 for console
   - Create user: `sudo adduser yourusername`
   - Add to sudo: `sudo usermod -aG sudo yourusername`

   **For SSH access:**

   - SSH is disabled by default on first boot
   - Enable it: `sudo systemctl enable --now ssh`

2. **Change password** when prompted (if using method 1)
3. **Update system**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
4. **Verify performance**:
   ```bash
   sudo hdparm -t /dev/nvme0n1
   ```

## Troubleshooting Common Issues

### Crucial P310 Specific Issues

- **High temperatures**: P310 can run hot - ensure adequate cooling
- **Power state issues**: The nvme_core.default_ps_max_latency_us=0 parameter is essential
- **PCIe Gen4 instability**: Force Gen3 mode for better compatibility
- **Firmware**: Check if P310 firmware is latest (use nvme-cli after boot)

### SSD Not Detected

- Check physical connections
- Verify power supply (5V/5A minimum)
- Try different SSD
- Update firmware again

### Boot Hangs at Kernel

- For P310: Try `dtparam=pciex1_gen=2` (drop to Gen2) in config.txt
- Disable APST: `nvme_core.default_ps_max_latency_us=0`
- Add `pcie_aspm=off` to cmdline.txt

### Random Freezes

- Check power supply quality (P310 can draw significant power)
- Add `arm_freq=1800` to config.txt (reduce frequency)
- Ensure proper cooling - P310 needs heatsink
- Monitor temperature: `cat /sys/class/thermal/thermal_zone*/temp`

### Boot Order Issues

- Verify EEPROM boot order: `BOOT_ORDER=0xf641`
- Check if bootloader is latest version
- Try `BOOT_ORDER=0xf461` (SD card fallback)

### Login Issues After NVMe Boot

**Problem**: NVMe boots successfully but you don't know the login credentials.

**Solution**: Copy your working SD card credentials to the NVMe installation:

1. **Boot from SD card** (where you can login successfully)

2. **Mount your NVMe partitions**:

   ```bash
   sudo mkdir -p /mnt/nvme-root
   sudo mount /dev/nvme0n1p2 /mnt/nvme-root
   ```

3. **Copy your user account from SD card to NVMe**:

   ```bash
   # Copy user accounts and passwords
   sudo cp /etc/passwd /mnt/nvme-root/etc/passwd
   sudo cp /etc/shadow /mnt/nvme-root/etc/shadow
   sudo cp /etc/group /mnt/nvme-root/etc/group
   sudo cp /etc/gshadow /mnt/nvme-root/etc/gshadow

   # Copy your home directory
   sudo cp -r /home/* /mnt/nvme-root/home/ 2>/dev/null || true

   # Copy SSH configuration (if you use SSH keys)
   sudo cp -r /etc/ssh/ssh_host_* /mnt/nvme-root/etc/ssh/ 2>/dev/null || true
   ```

4. **Set proper permissions**:

   ```bash
   # Fix ownership for copied home directories
   sudo chown -R 1000:1000 /mnt/nvme-root/home/* 2>/dev/null || true

   # Set proper permissions for security files
   sudo chmod 600 /mnt/nvme-root/etc/shadow
   sudo chmod 600 /mnt/nvme-root/etc/gshadow
   sudo chmod 644 /mnt/nvme-root/etc/passwd
   sudo chmod 644 /mnt/nvme-root/etc/group
   ```

5. **Unmount and reboot**:

   ```bash
   sudo umount /mnt/nvme-root
   sudo reboot
   ```

6. **Boot from NVMe** - your SD card credentials should now work!

## Success Verification

✅ Pi boots directly from NVMe SSD without SD card  
✅ No kernel panics or timeouts  
✅ Full Ubuntu Server functionality  
✅ Good I/O performance (>400MB/s typical)

## Notes

- Keep an SD card handy for troubleshooting
- Some SSDs work better than others with Pi 5
- Firmware updates can fix compatibility issues
- Always use quality power supply (official Pi 5 PSU recommended)
