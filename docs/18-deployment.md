# Deployment

## NATS cluster
```bash
# nats-server.conf
port: 4222
jetstream {
  store_dir: /var/lib/nats
  max_file: 10G
}
cluster {
  name: cosmo-cluster
  listen: 0.0.0.0:6222
  routes: [nats://nats-2:6222, nats://nats-3:6222]
}
```

## Docker Compose
```yaml
services:
  nats:
    image: nats:latest
    command: -js -c /etc/nats/nats-server.conf
    volumes:
      - ./nats.conf:/etc/nats/nats-server.conf
      - nats-data:/var/lib/nats

  worker:
    build: .
    environment:
      NATS_URL: nats://nats:4222
    command: bundle exec cosmo -C config/cosmo.yml -c 20 jobs
    deploy:
      replicas: 3
```

## systemd
```ini
# /etc/systemd/system/cosmo.service
[Unit]
Description=Cosmo Background Processor
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/myapp
Environment=RAILS_ENV=production
Environment=NATS_URL=nats://localhost:4222
ExecStart=/usr/local/bin/bundle exec cosmo -C config/cosmo.yml -c 20 jobs
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cosmo

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable cosmo && sudo systemctl start cosmo
```
