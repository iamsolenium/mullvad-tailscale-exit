FROM archlinux:base

RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm --needed \
        mullvad-vpn-daemon \
        curl \
        iproute2 \
        nftables \
        ca-certificates \
    && pacman -Scc --noconfirm

RUN mkdir -p \
    /etc/mullvad-vpn \
    /var/cache/mullvad-vpn \
    /var/log/mullvad-vpn

CMD ["/usr/bin/mullvad-daemon", "-vv", "--disable-stdout-timestamps"]
