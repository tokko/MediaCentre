FROM resin/raspberrypi2-buildpack-deps

EXPOSE 9091

WORKDIR /root

RUN 	apt-get update && apt-get install -y python transmission-daemon && \
	service transmission-daemon stop

VOLUME /var/lib/transmission-daemon /etc/transmission-daemon

COPY hold_server.py xbmc-upd.sh transmission.sh /root/
COPY settings.json /etc/transmission-daemon

RUN 	chown -R debian-transmission:debian-transmission /var/lib/transmission-daemon && \
	chown -R debian-transmission:debian-transmission /etc/transmission-daemon && \
	chown -R debian-transmission:debian-transmission /root

CMD /root/transmission.sh

