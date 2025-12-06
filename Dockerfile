# Build stage
FROM golang:1.25-bookworm AS builder

WORKDIR /src

COPY . .

WORKDIR /src/app

RUN GOOS=linux GOARCH=amd64 go build -o todo-app main.go
# Runtime stage
FROM debian:bookworm-slim

# Create non-root user
RUN useradd -m -u 1000 appuser

WORKDIR /app

# Copy binary from builder with correct ownership
COPY --from=builder --chown=appuser:appuser /src/app/todo-app .
COPY --from=builder --chown=appuser:appuser /src/app/index.html .

# Switch to non-root user
USER appuser

EXPOSE 8080

CMD ["./todo-app"]