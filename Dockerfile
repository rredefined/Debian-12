# Use Debian 12 as the base image
FROM debian:12

# Set non-interactive frontend to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for QEMU, noVNC, SSH, and cloud-init
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-system-gui \
    qemu-utils \
    cloud-image-utils \
    genisoimage \
    novnc \
    websockify \
    curl \
    unzip \
    openssh-client \
    openssh-server \
    net-tools \
    netcat-openbsd \
    sudo \
    bash \
    dos2unix \
    procps \
    whois \
    && rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /data /novnc /opt/qemu /cloud-init

# Download Debian 12 cloud image
RUN curl -L https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
    -o /opt/qemu/debian.img

# Create cloud-init metadata
RUN echo "instance-id: debian-vm\nlocal-hostname: debian-vm" > /cloud-init/meta-data

# Create cloud-init user-data with guaranteed SSH access
RUN printf "#cloud-config\n\
users:\n\
  - name: root\n\
    plain_text_passwd: root\n\
    lock_passwd: false\n\
    sudo: ALL=(ALL) NOPASSWD:ALL\n\
chpasswd:\n\
  list: |\n\
    root:root\n\
  expire: false\n\
ssh_pwauth: true\n\
runcmd:\n\
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n\
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n\
  - systemctl restart ssh\n\
  - mkdir -p /var/log\n\
  - echo 'SSH successfully configured for password access' > /var/log/cloud-init.log\n" > /cloud-init/user-data

# Create cloud-init ISO
RUN genisoimage -output /opt/qemu/seed.iso -volid cidata -joliet -rock /cloud-init/user-data /cloud-init/meta-data

# Setup noVNC
RUN curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.3.0.zip -o /tmp/novnc.zip && \
    unzip /tmp/novnc.zip -d /tmp && \
    mv /tmp/noVNC-1.3.0/* /novnc && \
    rm -rf /tmp/novnc.zip /tmp/noVNC-1.3.0

# Copy start.sh into the image
COPY start.sh /start.sh

# Ensure start.sh has Unix line endings and is executable
RUN dos2unix /start.sh && chmod +x /start.sh && /bin/bash -n /start.sh

# Expose ports for noVNC (6080) and SSH (2221)
EXPOSE 6080 2221

# Mount volume for VM disk
VOLUME /data

# Start the system with start.sh
CMD ["/bin/bash", "/start.sh"]
