FROM archlinux:base-devel
LABEL maintainer="64372469+DaedalusHyperboreus@users.noreply.github.com"

ENV AUR_EXTRA_PACKAGES "steamcmd"
ENV BUILD_USER         build
ENV EXTRA_PACKAGES     "man mc xorg-xauth"
ENV PIKAUR_CACHEDIR    "/var/cache/pikaur"
ENV USERNAME           "gamer"

WORKDIR /workdir

# Add the config directory to the container.
COPY config/* config/

# fetch GamerOS package list
RUN curl -L https://github.com/gamer-os/gamer-os/raw/master/manifest -o /tmp/manifest

RUN echo -e "[multilib]\nInclude = /etc/pacman.d/mirrorlist\n\n[chaotic-aur]\nServer = https://de-2-mirror.chaotic.cx/\$repo/\$arch" >> /etc/pacman.conf

RUN pacman --noconfirm -Syyu && \
    pacman --noconfirm -S arch-install-scripts pyalpm sudo reflector python-commonmark wget && \
    pacman --noconfirm -S --needed git

# create build user
RUN useradd ${BUILD_USER} -G wheel -m && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# create GamerOS user
RUN groupadd -r autologin && \
    useradd -m ${USERNAME} -G autologin,wheel && \
    echo "${USERNAME}:${USERNAME}" | chpasswd

# add trust for chaotic-aur
RUN pacman-key --init && \
    pacman-key --keyserver hkp://keyserver.ubuntu.com -r 3056513887B78AEB 8A9E14A07010F7E3 && \
    pacman-key --lsign-key 3056513887B78AEB && \
    pacman-key --lsign-key 8A9E14A07010F7E3

# fetch current mirror list
RUN reflector --verbose --latest 20 --country "Germany" --sort rate --save /etc/pacman.d/mirrorlist

# build pikaur
RUN su - ${BUILD_USER} -c "git clone https://aur.archlinux.org/pikaur.git /tmp/pikaur" && \
    su - ${BUILD_USER} -c "cd /tmp/pikaur && makepkg -f" && \
    pacman --noconfirm -U /tmp/pikaur/pikaur-*.pkg.tar.zst

# add a fake systemd-run script to workaround pikaur requirement.
RUN echo -e '#!/bin/bash\nif [[ "$1" == "--version" ]]; then echo 'fake 244 version'; fi\nmkdir -p ${PIKAUR_CACHEDIR}\n' > /usr/bin/systemd-run && \
    chmod +x /usr/bin/systemd-run

# build pikaur packages
RUN su ${BUILD_USER} -c "source /tmp/manifest && pikaur --noconfirm -Sw \${AUR_PACKAGES} --cachedir \${PIKAUR_CACHEDIR} && pikaur --noconfirm -Sw \${AUR_EXTRA_PACKAGES} --cachedir \${PIKAUR_CACHEDIR} && sudo mv /home/\${BUILD_USER}/.cache/pikaur/pkg/* \${PIKAUR_CACHEDIR}"

# update package databases
RUN pacman --noconfirm -Syy

# install packages
RUN source /tmp/manifest && \
    pacman --noconfirm -S ${PACKAGES} && \
    pacman --noconfirm -S ${EXTRA_PACKAGES}

# install AUR & extra packages
RUN pacman --noconfirm -U ${PIKAUR_CACHEDIR}/*

# set up SSH
RUN ssh-keygen -A && \
    sed -i "s/^.*PasswordAuthentication.*$/PasswordAuthentication no/" /etc/ssh/sshd_config \
    && sed -i "s/^.*X11Forwarding.*$/X11Forwarding yes/" /etc/ssh/sshd_config \
    && sed -i "s/^.*X11UseLocalhost.*$/X11UseLocalhost no/" /etc/ssh/sshd_config && \
    install -D -m 600 -o root /workdir/config/authorized_keys.list /root/.ssh/authorized_keys && \
    install -D -m 600 -o ${USERNAME} /workdir/config/authorized_keys.list /home/${USERNAME}/.ssh/authorized_keys

# run steamcmd to let it fetch the latest update
RUN su - ${USERNAME} -c "steamcmd -h"

# Add the devel directory to the container.
COPY devel/* devel/

# start SSH server
EXPOSE 2222
CMD ["/usr/sbin/sshd","-D","-p 2222"]
