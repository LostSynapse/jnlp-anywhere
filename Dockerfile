FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

ARG VERSION=dev
ENV JNLP_ANYWHERE_VERSION=${VERSION}

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    && wget -O /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
    && wget -P /etc/apt/sources.list.d \
       https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/jammy/xpra.sources \
    && apt-get update && apt-get install -y \
    xpra \
    xpra-html5 \
    xserver-xorg-video-dummy \
    openjdk-8-jre \
    python3-xlib \
    xkb-data \
    libx11-6 \
    libx11-dev \
    libxkbfile1 \
    xmlstarlet \
    ncurses-bin \
    dbus \
    && rm -rf /var/lib/apt/lists/*

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libX11.so.6
ENV XPRA_ZEROCOPY=0
ENV XPRA_OPENGL=0
ENV TERM=xterm-256color

RUN ldconfig

RUN useradd -m -s /bin/bash xpra-user \
    && mkdir -p /app /etc/xpra /run/dbus /etc/xdg/menus /run/user/1000/xpra /run/xpra \
    && touch /etc/xpra/password \
    && chmod 700 /run/user/1000/xpra \
    && chmod 775 /run/xpra \
    && chown -R xpra-user:xpra-user /app /etc/xpra /run/dbus /etc/xdg/menus /run/user/1000/xpra /run/xpra

RUN echo '<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN" "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd"><Menu><Name>Debian</Name></Menu>' \
    > /etc/xdg/menus/debian-menu.menu     

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER xpra-user

EXPOSE 14500

ENTRYPOINT ["/entrypoint.sh"]
