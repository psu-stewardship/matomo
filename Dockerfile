FROM matomo:3.13-apache
ADD plugins/ /var/www/html/plugins
ADD initialize.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/initialize.sh
CMD ["/usr/local/bin/initialize.sh"]
