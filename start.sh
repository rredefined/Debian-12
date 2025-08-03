#!/bin/bash
set -e

# Configuration variables
DISK="/data/vm.raw"
IMG="/opt/qemu/debian.img"
SEED="/opt/qemu/seed.iso"
PORT_SSH=2221
PORT_VNC=6080
USERNAME="root"
PASSWORD="root"
QEMU_PIDFILE="/var/run/qemu.pid"
LOG_FILE="/var/log/vm-startup.log"

# Log function for better debugging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Initialize log file
mkdir -p /var/log
> $LOG_FILE

# Check if required files exist
if [ ! -f "$IMG" ] || [ ! -f "$SEED" ]; then
    log "Error: Required files ($IMG or $SEED) are missing"
    exit 1
fi

# Check if KVM is available
if [ -e /dev/kvm ]; then
    KVM="-enable-kvm -cpu host"
    log "Using KVM acceleration"
else
    log "⚠️ KVM not available, falling back to software emulation"
    KVM=""
fi

# Get public IP (fallback to localhost if failed)
IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "localhost")
log "Detected IP: $IP"

# Create VM disk if it doesn't exist
if [ ! -f "$DISK" ]; then
    log "Creating VM disk..."
    if ! qemu-img convert -f qcow2 -O raw "$IMG" "$DISK"; then
        log "Error: Failed to convert disk image"
        exit 1
    fi
    if ! qemu-img resize "$DISK" 50G; then
        log "Error: Failed to resize disk"
        exit 1
    fi
    log "VM disk created successfully"
fi

# Start SSH server in container
log "Starting SSH server..."
mkdir -p /var/run/sshd
/usr/sbin/sshd -o "PasswordAuthentication yes" -o "PermitRootLogin yes" || {
    log "Error: Failed to start SSH server"
    exit 1
}

# Start noVNC
log "Starting noVNC on port $PORT_VNC..."
websockify --web=/novnc $PORT_VNC localhost:5900 &
WEBSOCKIFY_PID=$!
sleep 2
if ! ps -p $WEBSOCKIFY_PID > /dev/null; then
    log "Error: Failed to start websockify"
    exit 1
fi

# Clean up previous PID file if exists
[ -f "$QEMU_PIDFILE" ] && rm "$QEMU_PIDFILE"

# Start QEMU in background with proper networking
log "Starting QEMU VM..."
qemu-system-x86_64 \
    $KVM \
    -smp 2 \
    -m 2048 \
    -drive file="$DISK",format=raw,if=virtio \
    -drive file="$SEED",format=raw,if=virtio,readonly=on \
    -smbios type=1,serial=ds=nocloud \
    -netdev user,id=net0,hostfwd=tcp::${PORT_SSH}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -vnc :0 \
    -daemonize \
    -pidfile "$QEMU_PIDFILE" \
    -display none \
    -serial file:/var/log/qemu-serial.log

# Verify QEMU started
sleep 5  # Increased wait time for VM to boot
if [ ! -f "$QEMU_PIDFILE" ]; then
    log "Error: QEMU failed to start (no PID file)"
    exit 1
fi

QEMU_PID=$(cat "$QEMU_PIDFILE")
if ! ps -p "$QEMU_PID" > /dev/null; then
    log "Error: QEMU process not running"
    exit 1
fi

# Wait for SSH to be available
log "Waiting for SSH on port $PORT_SSH..."
for i in {1..60}; do
    if nc -z localhost $PORT_SSH; then
        log "✅ VM is ready!"
        # Verify SSH actually accepts connections
        if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT_SSH $USERNAME@localhost true; then
            log "SSH authentication successful"
            break
        else
            log "SSH port open but authentication failed"
        fi
    fi
    log "⏳ Waiting for SSH... (Attempt $i/60)"
    sleep 2
done

# Print connection details
echo "================================================"
echo " 🖥️  VNC:  http://${IP}:${PORT_VNC}/vnc.html" | tee -a $LOG_FILE
echo " 🔐 SSH:  ssh ${USERNAME}@${IP} -p ${PORT_SSH}" | tee -a $LOG_FILE
echo " 🧾 Login: ${USERNAME} / ${PASSWORD}" | tee -a $LOG_FILE
echo "================================================"

# Keep container running
tail -f /dev/null
