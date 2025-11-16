# Running Ubuntu Server in Docker Containers for Production Workloads

## Overview

This guide covers best practices for running Ubuntu servers in Docker containers for production environments. It focuses on Docker-in-Docker patterns, security considerations, networking, persistence, and migration strategies.

## 1. Docker-in-Docker (DinD) Patterns

### What is Docker-in-Docker?

Docker-in-Docker (DinD) allows running Docker containers inside a Docker container, creating nested container environments. This is commonly used in CI/CD pipelines and development environments.

### Implementation Patterns

#### Using Docker-in-Docker Image
```dockerfile
FROM docker:dind

# Install Ubuntu base and tools
RUN apk add --no-cache ubuntu-base bash

# Start Docker daemon
CMD ["dockerd", "--host", "tcp://0.0.0.0:2376", "--tls=false"]
```

#### Running DinD Container
```bash
docker run -d --privileged --name dind \
  -p 2376:2376 \
  -v /var/lib/docker \
  docker:dind
```

#### Connecting from Host Container
```bash
export DOCKER_HOST=tcp://dind:2376
docker run hello-world
```

### Security Considerations

- **Privileged Mode Required**: DinD containers must run with `--privileged` flag, granting full host access
- **Host Volume Mounting**: Mount `/var/lib/docker` for persistence
- **TLS Configuration**: Always use TLS in production with client certificates
- **Resource Limits**: Implement CPU and memory limits to prevent host exhaustion

### Production Best Practices

- Use `docker:dind` base image instead of privileged Ubuntu containers
- Implement proper TLS authentication
- Mount Docker socket only when necessary (less secure than DinD)
- Use Docker Compose for multi-container DinD setups

## 2. Privileged Containers and Security Implications

### What are Privileged Containers?

Privileged containers bypass Docker's security mechanisms and gain access to the host system's kernel capabilities.

### When to Use Privileged Mode

- Docker-in-Docker scenarios
- Hardware device access (GPU, USB devices)
- Network interface manipulation
- Kernel module loading

### Security Risks

#### High-Risk Capabilities
- **CAP_SYS_ADMIN**: Allows mounting filesystems, changing namespaces
- **CAP_NET_ADMIN**: Network configuration and firewall manipulation
- **CAP_SYS_PTRACE**: Process debugging and memory access
- **Full Host Access**: Can escape container boundaries

#### Attack Vectors
- Container breakout exploits
- Host kernel compromise
- Privilege escalation
- Data exfiltration

### Mitigation Strategies

#### Least Privilege Principle
```dockerfile
# Instead of --privileged, use specific capabilities
RUN --cap-add=NET_ADMIN --cap-add=SYS_PTRACE

# Drop unnecessary capabilities
RUN --cap-drop=ALL --cap-add=NET_BIND_SERVICE
```

#### Seccomp Profiles
```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {
      "names": ["accept", "bind", "listen"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

#### AppArmor/SELinux Integration
```dockerfile
# Use custom security profiles
LABEL security.apparmor.profile="docker-nginx"
```

### Alternatives to Privileged Mode

- **Device Mounting**: `--device=/dev/device`
- **Bind Mounts**: Mount specific host directories
- **User Namespaces**: Map container users to host users
- **Sysctls**: Modify specific kernel parameters

## 3. Networking and Port Forwarding for Nested Container Setups

### Docker Networking Modes

#### Bridge Network (Default)
```bash
docker run -d --name ubuntu-server \
  --network bridge \
  -p 8080:80 \
  ubuntu:20.04
```

#### Host Network
```bash
docker run -d --name ubuntu-server \
  --network host \
  ubuntu:20.04
```

#### Macvlan Network
```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=eth0 macvlan-net

docker run -d --name ubuntu-server \
  --network macvlan-net \
  ubuntu:20.04
```

### Nested Container Networking

#### Port Forwarding in Nested Setups
```dockerfile
# Outer container (privileged)
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y docker.io

# Inner container networking
EXPOSE 80 443
CMD ["docker", "run", "-d", "-p", "80:80", "nginx"]
```

#### Service Discovery
```yaml
# docker-compose.yml for nested services
version: '3.8'
services:
  proxy:
    image: nginx
    networks:
      - frontend
    depends_on:
      - app

  app:
    image: ubuntu:20.04
    networks:
      - frontend
      - backend

networks:
  frontend:
  backend:
```

### Advanced Networking Patterns

#### Overlay Networks
```bash
# Create overlay network for swarm
docker network create -d overlay my-overlay-net

# Use in stack deployment
docker stack deploy -c docker-compose.yml my-stack
```

#### IPv6 Support
```bash
docker run -d --name ubuntu-server \
  --ip6 2001:db8::1 \
  ubuntu:20.04
```

## 4. Volume Mounting and Persistence for Containerized Servers

### Volume Types

#### Named Volumes
```bash
# Create persistent volume
docker volume create ubuntu-data

# Use in container
docker run -d --name ubuntu-server \
  -v ubuntu-data:/data \
  ubuntu:20.04
```

#### Bind Mounts
```bash
docker run -d --name ubuntu-server \
  -v /host/data:/container/data \
  ubuntu:20.04
```

#### tmpfs Mounts
```bash
docker run -d --name ubuntu-server \
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  ubuntu:20.04
```

### Ubuntu Server Persistence Patterns

#### Configuration Persistence
```dockerfile
FROM ubuntu:20.04

# Persistent configuration volume
VOLUME ["/etc/ubuntu-server", "/var/log"]

# Copy default configs
COPY config/ /etc/ubuntu-server/

CMD ["/usr/sbin/ubuntu-server"]
```

#### Database Persistence
```yaml
version: '3.8'
services:
  ubuntu-postgres:
    image: ubuntu:20.04
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}

volumes:
  postgres_data:
```

#### Log Persistence
```dockerfile
FROM ubuntu:20.04

# Create log directory
RUN mkdir -p /var/log/ubuntu-server

# Persistent logging volume
VOLUME ["/var/log/ubuntu-server"]

# Configure log rotation
RUN apt-get install -y logrotate
COPY logrotate.conf /etc/logrotate.d/ubuntu-server

CMD ["/usr/sbin/ubuntu-server"]
```

### Backup and Recovery

#### Volume Backup
```bash
# Backup named volume
docker run --rm -v ubuntu_data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/backup.tar.gz -C /data .
```

#### Volume Restore
```bash
# Restore from backup
docker run --rm -v ubuntu_data:/data -v $(pwd):/backup \
  ubuntu tar xzf /backup/backup.tar.gz -C /data
```

## 5. Ubuntu Container Best Practices for Production Deployment

### Base Image Selection

#### Official Ubuntu Images
```dockerfile
# Use specific version for reproducibility
FROM ubuntu:20.04

# Use slim variant for smaller size
FROM ubuntu:20.04-slim
```

#### Custom Base Images
```dockerfile
FROM ubuntu:20.04

# Update package index
RUN apt-get update && apt-get upgrade -y

# Install essential tools
RUN apt-get install -y \
    curl \
    wget \
    vim \
    htop \
    && rm -rf /var/lib/apt/lists/*
```

### Security Hardening

#### Non-Root User
```dockerfile
FROM ubuntu:20.04

# Create non-root user
RUN useradd -m -s /bin/bash ubuntu-user

# Switch to non-root user
USER ubuntu-user

CMD ["/usr/sbin/ubuntu-server"]
```

#### Package Management
```dockerfile
FROM ubuntu:20.04

# Update and install packages in single layer
RUN apt-get update && apt-get install -y \
    package1 \
    package2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

#### Vulnerability Scanning
```bash
# Use Trivy for vulnerability scanning
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image ubuntu:20.04
```

### Performance Optimization

#### Multi-Stage Builds
```dockerfile
# Build stage
FROM ubuntu:20.04 AS builder
RUN apt-get update && apt-get install -y build-essential
COPY source/ /src/
RUN make -C /src

# Production stage
FROM ubuntu:20.04-slim
COPY --from=builder /src/app /usr/bin/app
CMD ["/usr/bin/app"]
```

#### Layer Caching
```dockerfile
FROM ubuntu:20.04

# Install dependencies first (changes less frequently)
COPY requirements.txt /tmp/
RUN apt-get update && apt-get install -y $(cat /tmp/requirements.txt)

# Copy source code (changes more frequently)
COPY . /app
```

### Monitoring and Logging

#### Health Checks
```dockerfile
FROM ubuntu:20.04

COPY healthcheck.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/healthcheck.sh

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh
```

#### Logging Configuration
```dockerfile
FROM ubuntu:20.04

# Configure syslog
RUN apt-get install -y rsyslog
COPY rsyslog.conf /etc/rsyslog.conf

# Use JSON logging format
ENV LOG_FORMAT=json

CMD ["/usr/sbin/rsyslogd", "-n"]
```

## 6. Migration Strategies for Containerized Environments

### Assessment Phase

#### Application Inventory
```bash
# List all running processes
ps aux

# Identify dependencies
ldd /usr/bin/application

# Check network connections
netstat -tulpn
```

#### Compatibility Analysis
```bash
# Test container compatibility
docker run --rm -v $(pwd):/app ubuntu:20.04 \
  /bin/bash -c "apt-get update && apt-get install -y dependencies"
```

### Migration Approaches

#### Lift and Shift
```dockerfile
FROM ubuntu:20.04

# Install existing application dependencies
RUN apt-get update && apt-get install -y \
    apache2 \
    php \
    mysql-client

# Copy application files
COPY . /var/www/html

EXPOSE 80
CMD ["apache2ctl", "-D", "FOREGROUND"]
```

#### Refactor for Containers
```dockerfile
FROM ubuntu:20.04

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    php-cli \
    && rm -rf /var/lib/apt/lists/*

# Use environment variables for configuration
ENV DB_HOST=database
ENV DB_PORT=3306

COPY app/ /app
WORKDIR /app

CMD ["php", "index.php"]
```

### Database Migration

#### Export/Import Strategy
```bash
# Export from source
mysqldump -u root -p database > backup.sql

# Import to containerized database
docker exec -i mysql-container mysql -u root -p database < backup.sql
```

#### Change Data Capture
```bash
# Use tools like Debezium for real-time sync
docker run --rm -it debezium/connect \
  --config-file /path/to/connect.properties
```

### Orchestration Migration

#### Docker Compose Migration
```yaml
version: '3.8'
services:
  web:
    image: ubuntu:20.04
    ports:
      - "80:80"
    volumes:
      - ./config:/etc/app
    depends_on:
      - db

  db:
    image: mysql:8.0
    volumes:
      - db_data:/var/lib/mysql

volumes:
  db_data:
```

#### Kubernetes Migration
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ubuntu-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ubuntu-server
  template:
    metadata:
      labels:
        app: ubuntu-server
    spec:
      containers:
      - name: ubuntu-server
        image: ubuntu:20.04
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ubuntu-data-pvc
```

### Testing and Validation

#### Functional Testing
```bash
# Test containerized application
docker run --rm -p 8080:80 ubuntu-app
curl http://localhost:8080/health
```

#### Performance Testing
```bash
# Load testing with Apache Bench
ab -n 1000 -c 10 http://localhost:8080/
```

### Rollback Strategies

#### Blue-Green Deployment
```bash
# Deploy new version alongside old
docker tag ubuntu-app:v1 ubuntu-app:v2
docker run -d --name app-v2 ubuntu-app:v2

# Switch load balancer
# If issues, switch back to v1
```

#### Canary Deployment
```bash
# Deploy to subset of servers
kubectl set image deployment/ubuntu-server ubuntu-server=ubuntu-app:v2
kubectl rollout pause deployment/ubuntu-server

# Monitor metrics
# If successful, complete rollout
kubectl rollout resume deployment/ubuntu-server
```

## Sources and References

- [Docker Official Documentation](https://docs.docker.com/)
- [Ubuntu Container Best Practices](https://ubuntu.com/containers/docker)
- [Docker Security Best Practices](https://docs.docker.com/develop/dev-best-practices/security/)
- [Kubernetes Container Migration Guide](https://kubernetes.io/docs/concepts/containers/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

## Production Deployment Checklist

- [ ] Use official Ubuntu base images with specific versions
- [ ] Implement non-root users and minimal privileges
- [ ] Configure proper logging and monitoring
- [ ] Set up health checks and resource limits
- [ ] Use secrets management for sensitive data
- [ ] Implement backup and recovery procedures
- [ ] Test migration in staging environment
- [ ] Monitor performance and security metrics
- [ ] Document runbooks and troubleshooting guides