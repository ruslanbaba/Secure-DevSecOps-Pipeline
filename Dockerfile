# Multi-stage Docker build for security and performance
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Create non-root user for build stage
RUN addgroup -g 1001 -S nodejs && \
    adduser -S appuser -u 1001 -G nodejs

# Copy package files
COPY package*.json ./

# Install dependencies with security optimizations
RUN npm ci --only=production --no-audit --no-fund && \
    npm cache clean --force

# Copy source code
COPY --chown=appuser:nodejs . .

# Build application
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Install security updates
RUN apk update && \
    apk upgrade && \
    apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S appuser -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Copy built application from builder stage
COPY --from=builder --chown=appuser:nodejs /app/dist ./dist
COPY --from=builder --chown=appuser:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:nodejs /app/package*.json ./

# Create non-writable directory structure
RUN mkdir -p /app/logs /app/tmp && \
    chown -R appuser:nodejs /app && \
    chmod -R 755 /app && \
    chmod 1777 /app/tmp

# Security configurations
RUN rm -rf /tmp/* /var/tmp/* && \
    find /app -name "*.md" -delete && \
    find /app -name "*.txt" -delete || true

# Switch to non-root user
USER appuser

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000
ENV LOG_LEVEL=info

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD node healthcheck.js || exit 1

# Expose port
EXPOSE 3000

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Start application
CMD ["node", "dist/index.js"]

# Security labels
LABEL maintainer="DevSecOps Team <devsecops@company.com>"
LABEL version="1.0.0"
LABEL description="Secure containerized application"
LABEL security.scan="required"
LABEL compliance.framework="CIS-Docker"